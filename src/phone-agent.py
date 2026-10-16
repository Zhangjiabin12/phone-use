#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""phone-agent —— 跑在 36.102 上的**手机 agent，也是唯一的调用总入口**

上层（人 / 平台 / 手机墙）只给它"一句话 + 可选的终端范围"，其余全由它现场决定：
  · 单台任务 → 自己组合原语（phone_exec）完成
  · 多台/所有终端 → 自己调 run_devices 扇出并行（不用上层另写批量命令）

结构 = LLM(函数调用) + 通用原语工具 + runbook：
  · 工具只有 6 个，schema 极小且不变：
      devices_list() / phone_exec(serial, argv) / run_devices(text, devices) /
      phone_skill() / lease_device / release_device
    —— "连哪种认证"完全不进 schema，AI 现场判断（避免工具定义写死导致调用失败）
  · runbook（怎么做怎么连：开放/PSK/1X/门户 + 成功判据 + MIUI 坑）来自 phone-hub 的 /skill
  · LLM 端点复用 BU 的配置（/opt/webui-mcp/bu/bu.env：deepseek-flash + 131.255.36.100:30001/v1）

用法（这就是全部入口）：
  phone-agent "连 928wpa2-psk，密码 12345678，用设备 MAC"
  phone-agent "两台一起连 928wpa2-psk，密码 12345678"          # agent 自己扇出
  phone-agent serve            # HTTP :8902  POST /task {"text":"...","device":"auto"|"devices":["all"]}
"""
import json
import os
import re
import sys
import threading
import time
import urllib.request

HUB = os.environ.get("PHONE_HUB_BASE", "http://127.0.0.1:8901")
PORT = int(os.environ.get("PHONE_AGENT_PORT", "8902"))
BU_ENV = os.environ.get("PHONE_AGENT_ENV", "/opt/webui-mcp/bu/bu.env")
MAX_STEPS = int(os.environ.get("PHONE_AGENT_MAX_STEPS", "24"))
LOG = os.environ.get("PHONE_AGENT_LOG", "/var/log/phone-agent.log")
LLM_TIMEOUT = int(os.environ.get("PHONE_AGENT_LLM_TIMEOUT", "120"))      # 单次 LLM 调用超时（LLM 挂住不会拖死）
LLM_RETRY = int(os.environ.get("PHONE_AGENT_LLM_RETRY", "2"))
DEADLINE = int(os.environ.get("PHONE_AGENT_DEADLINE", "1200"))           # 单任务总时限（秒），到点收口释放
QUEUE_WAIT = int(os.environ.get("PHONE_AGENT_QUEUE_WAIT", "600"))        # 同一台被占时，排队等多久（0=不排队）


def log(msg):
    line = "[%s] %s" % (time.strftime("%H:%M:%S"), msg)
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass
    if os.environ.get("PHONE_AGENT_VERBOSE"):
        print(line, file=sys.stderr, flush=True)


def load_llm_conf():
    cfg = {"model": os.environ.get("PHONE_AGENT_MODEL", "deepseek-flash"),
           "base": os.environ.get("PHONE_AGENT_BASE_URL", ""),
           "key": os.environ.get("PHONE_AGENT_API_KEY", "")}
    if (not cfg["base"] or not cfg["key"]) and os.path.exists(BU_ENV):
        for line in open(BU_ENV, encoding="utf-8", errors="ignore"):
            line = line.strip()
            if line.startswith("BU_LLM_MODEL="):
                cfg["model"] = cfg["model"] or line.split("=", 1)[1]
                cfg["model"] = line.split("=", 1)[1]
            elif line.startswith("BU_LLM_BASE_URL="):
                cfg["base"] = line.split("=", 1)[1]
            elif line.startswith("BU_LLM_API_KEY="):
                cfg["key"] = line.split("=", 1)[1]
    return cfg


def http(method, path, body=None, timeout=900):
    req = urllib.request.Request(HUB + path,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 method=method, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


# ---------------- 工具（= 给 LLM 的函数） ----------------

TOOLS = [
    {"type": "function", "function": {
        "name": "devices_list",
        "description": "列出所有安卓终端：serial、stf_state(available/using/absent)、是否 root、动作后端、能力集、当前 Wi-Fi；每台还带 usable（无人值守是否可用）与 blockers（不可用原因+修法）——挑终端必须以 usable=true 且 stf_state=available 为准，别自己猜；usable=false 的不要派活，把 blockers 报给用户。",
        "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {
        "name": "phone_exec",
        "description": ("在指定终端上执行一条 phone-use 原语，返回 JSON 事实。原语："
                        "state / wifi / list / scan [关键字] / probe [url] / failure [ssid] / backend / "
                        "ui [过滤] / find <子串> / click-text|click-desc|click-id <子串> [--self] / "
                        "click-xy <x> <y> / settext [--id 元素id] <文本> / scroll [n] / scroll-up [n] / "
                        "global <home|back|recents|notifications> / tap <x> <y> / swipe x1 y1 x2 y2 [ms] / "
                        "key <home|back|enter|...> / input <文本> / shot <设备路径> / pull <设备路径> <本地路径> / "
                        "http <url> / httpfile <url> <设备路径> / shell <命令> / "
                        "wifi-connect <ssid> open|owe|wpa2|wpa3 [密码] [--bssid MAC] [--mac none|auto] / "
                        "wifi-forget <ssid|netid> / wifi-forget-all / wifi-radio on|off / jar <pu.jar 命令>"),
        "parameters": {"type": "object", "properties": {
            "serial": {"type": "string", "description": "终端 serial（省略则用唯一在线终端）"},
            "argv": {"type": "array", "items": {"type": "string"}, "description": "原语参数数组"},
            "timeout_s": {"type": "integer", "default": 600}},
            "required": ["argv"]}}},
    {"type": "function", "function": {
        "name": "run_devices",
        "description": ("【多台并行】把同一句话下发到多台终端，每台各自租用/执行/释放，最后汇总。"
                        "凡是'两台一起'『所有终端都』这类需求都用它，不要自己一台台串行做。"
                        "text 里可用 {serial} {model} 占位。"),
        "parameters": {"type": "object", "properties": {
            "text": {"type": "string", "description": "要每台各自完成的完整任务描述"},
            "devices": {"type": "array", "items": {"type": "string"},
                        "description": "serial 列表；省略 = 所有在线终端"},
            "parallel": {"type": "integer", "default": 4}},
            "required": ["text"]}}},
    {"type": "function", "function": {
        "name": "phone_skill",
        "description": "取「怎么做怎么连」的 runbook（开放/PSK/1X/门户四条路线、成功判据、MIUI 已知坑、机型差异）。动手前先读。",
        "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {
        "name": "lease_device",
        "description": "占用一台终端（TTL 秒），避免并发抢同一台。",
        "parameters": {"type": "object", "properties": {"serial": {"type": "string"},
                                                        "ttl_s": {"type": "integer", "default": 900}},
                       "required": ["serial"]}}},
    {"type": "function", "function": {
        "name": "release_device",
        "description": "释放终端占用。",
        "parameters": {"type": "object", "properties": {"serial": {"type": "string"}},
                       "required": ["serial"]}}},
]


def hub_call(method, path, body=None, timeout=60):
    """带 owner 的 hub 调用：phone_exec 必须带 owner，否则会被自己刚拿的租约挡住（硬闸）"""
    if body is None:
        body = {}
    if isinstance(body, dict) and "owner" not in body:
        body["owner"] = CURRENT_OWNER[0]
    req = urllib.request.Request(HUB + path,
                                 data=json.dumps(body).encode() if method != "GET" else None,
                                 method=method, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


CURRENT_OWNER = ["phone-agent"]


class LeaseCtx:
    """一次任务自己的租约上下文（必须每任务独立：否则并发任务会互相释放租约）"""

    def __init__(self, owner):
        self.owner = owner
        self.held = set()
        self.stops = {}


def ensure_lease(ctx, serial):
    """硬闸下的自保：动手前确保这台是我的租约（不占就没人保护，可能被别人抢走）"""
    owner = ctx.owner or "phone-agent"
    try:
        d = http("GET", "/devices/%s" % serial, timeout=20)
    except Exception as e:
        return False, "hub 查询失败: %s" % e
    cur = d.get("lease")
    if cur and cur.get("owner") == owner:
        ctx.held.add(serial)
        return True, None
    if cur and cur.get("until", 0) > time.time():
        return False, "终端 %s 被 %s 占用（剩余 %ds，最后活动 %ds 前）；换一台空闲的，或让上层 reclaim" % (
            serial, cur["owner"], int(cur["until"] - time.time()),
            int(time.time() - cur.get("last_active", time.time())))
    try:
        r = http("POST", "/devices/%s/lease" % serial, {"owner": owner, "ttl": 1800,
                                                        "renew": True}, timeout=20)
    except Exception as e:
        return False, "占用失败: %s" % e
    if not r.get("ok"):
        return False, r.get("error") or "占用被拒"
    ctx.held.add(serial)
    if serial not in ctx.stops:
        import threading as _th
        ev = _th.Event()
        ctx.stops[serial] = ev
        _th.Thread(target=heartbeat_loop, args=(serial, ev, ctx), daemon=True).start()
    return True, None


def heartbeat_loop(serial, stop, ctx=None):
    """任务期间持续心跳（每 30s）：agent 活着就一直续期；agent 崩了心跳停 → hub 按空闲超时自动收回"""
    owner = (ctx.owner if ctx else CURRENT_OWNER[0])
    while not stop.is_set():
        try:
            http("POST", "/devices/%s/heartbeat" % serial, {"owner": owner}, timeout=15)
        except Exception:
            pass
        stop.wait(30)


def release_ctx(ctx):
    """收口：停心跳 + 释放本任务占过的终端（只释放自己的）"""
    for ev in list(ctx.stops.values()):
        ev.set()
    ctx.stops.clear()
    for s in list(ctx.held):
        try:
            http("POST", "/devices/%s/release" % s,
                 {"owner": ctx.owner, "reason": "agent 任务结束"}, timeout=15)
        except Exception:
            pass
    ctx.held.clear()


def exec_tool(name, args, ctx):
    owner = ctx.owner                 # 硬闸下必须带上自己的身份，否则被自己的租约挡住
    if name == "devices_list":
        return http("GET", "/devices", timeout=40)
    if name == "phone_exec":
        serial = args.get("serial")
        if not serial:
            ds = [d for d in http("GET", "/devices", timeout=40)["devices"] if d["present"]]
            if len(ds) != 1:
                return {"error": "需要指定 serial（在线 %d 台）" % len(ds),
                        "devices": [d["serial"] for d in ds]}
            serial = ds[0]["serial"]
        ok, err = ensure_lease(ctx, serial)
        if not ok:
            return {"blocked": True, "error": err}
        res = http("POST", "/devices/%s/exec" % serial, {"args": args["argv"], "owner": ctx.owner},
                   timeout=int(args.get("timeout_s", 600)) + 60)
        return {"serial": serial, "rc": res.get("rc"),
                "stdout": (res.get("stdout") or "").strip()[-8000:],
                "stderr": (res.get("stderr") or "").strip()[-800:]}
    if name == "run_devices":
        r = fanout(args["text"], args.get("devices") or ["all"],
                   int(args.get("parallel", 4)), owner)
        # 给模型一个精简汇总（避免把子 agent 的全过程灌进来）
        return {"ok": r["ok"], "count": r["count"], "pass": r["pass"], "fail": r["fail"],
                "results": [{"serial": x["serial"], "model": x.get("model"),
                             "verdict": x.get("verdict"), "steps": x.get("steps"),
                             "answer": (x.get("answer") or "")[:600]} for x in r["results"]]}
    if name == "phone_skill":
        return http("GET", "/skill", timeout=40).get("skill", "")
    if name == "lease_device":
        return http("POST", "/devices/%s/lease" % args["serial"],
                    {"owner": owner, "ttl": int(args.get("ttl_s", 900))}, timeout=40)
    if name == "release_device":
        return http("POST", "/devices/%s/release" % args["serial"], {}, timeout=40)
    return {"error": "未知工具 %s" % name}


# ---------------- LLM ----------------

def chat(cfg, messages, tools=True):
    """调用 LLM：短超时 + 有限重试。
    为什么重要：LLM 服务器挂住时，不能让 agent 无限等待把手机租约占死；
    超时/重试都失败就让本次任务收口（释放终端、报 LLM 不可用）。"""
    body = {"model": cfg["model"], "messages": messages, "temperature": 0.2}
    if tools:
        body["tools"] = TOOLS
        body["tool_choice"] = "auto"
    last = None
    for attempt in range(LLM_RETRY + 1):
        try:
            req = urllib.request.Request(cfg["base"].rstrip("/") + "/chat/completions",
                                         data=json.dumps(body).encode(),
                                         headers={"Content-Type": "application/json",
                                                  "Authorization": "Bearer " + cfg["key"]})
            with urllib.request.urlopen(req, timeout=LLM_TIMEOUT) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            last = e
            log("LLM 调用失败（第 %d 次/%d）：%s" % (attempt + 1, LLM_RETRY + 1, e))
            time.sleep(2 * (attempt + 1))
    raise RuntimeError("LLM 不可用（已重试 %d 次，超时 %ds）：%s" % (LLM_RETRY, LLM_TIMEOUT, last))


def system_prompt(cfg):
    try:
        skill = http("GET", "/skill", timeout=30).get("skill", "")
    except Exception as e:
        skill = "（runbook 取不到：%s）" % e
    try:
        devs = http("GET", "/devices", timeout=30)["devices"]
        devtxt = "\n".join("- %s  %s  backend=%s  root=%s  capabilities=%s  wifi=%s" % (
            d["serial"], d["model"], d.get("backend"), d.get("root"),
            ",".join(d.get("capabilities") or []), d.get("wifi_ssid")) for d in devs)
    except Exception as e:
        devtxt = "（设备列表取不到：%s）" % e
    return f"""你是跑在测试机 131.255.36.102 上的**手机 agent**，负责把"连某个 WiFi 并完成（或不完成）认证"这类需求落地。

当前在线终端：
{devtxt}

你的工具（只有这几个，全部通过 phone_exec 暴露原语）：
- devices_list()：设备清单与能力
- phone_exec(serial, argv)：在终端上跑 phone-use 原语（**你所有的动作都通过它**）
- phone_skill()：取 runbook（怎么连、成功判据、坑）
- lease_device / release_device：占用与释放

工作纪律（很重要）：
0. **你是唯一的调用总入口**：上层（人/平台/手机墙）只会给你一句话 + 可选的终端范围，所有动作都由你决定。
   · **只涉及一台（哪怕上层指定了 serial）→ 直接用 phone_exec 自己串起来做完**，不要调 run_devices（那会多起一个子 agent，浪费步数）
   · **"两台一起"『所有终端都』『同时』→ 才调 `run_devices(text, devices)` 扇出并行**
1. **先读 runbook**（phone_skill），按里面的路线做；不要凭印象发明命令。
1.5 **硬闸与占用**：hub 已启用租约硬闸——别人持有效租约时，`phone_exec` 会被拒（会告诉你被谁占用、剩多久）。
   你自己动手前会**自动占用**该终端并持续心跳；任务结束会**自动释放**。
   · 看到被占用：**先去 devices_list 换一台空闲的**；同一台确实非跑不可时，才向上层报告并要求
     `POST /devices/<serial>/reclaim`（收回会打断对方任务，别擅自做）。
   · 长任务期间不要停心跳（你就正常调工具即可，心跳是自动的）。
2. 先 devices_list 选终端：优先用 backend=root-input 的（能力全），免 root 机用 jar-node-action。
3. 每次动作后**必须核实事实**（wifi / probe / failure），**绝不相信命令返回值当成功**：
   - 上线成功 = wifi 里 ssid 匹配 + supplicant=COMPLETED + ip 非空
   - 1X 成功 = 同上 + failure 里 level2FailureCode=NONE
   - 门户成功 = probe 里 portal_intercepted=false
4. 遇到不兼容（列表里没有该 SSID、下拉框点不动、中文 SSID 不出现…）要**换招或如实报告**，不要卡在一个动作上重复。
5. 开门户认证页用系统门户登录页（WLAN 页点"登录到网络"），网页元素能被无障碍读到（id 如 widget-login-btn/account/acc_pass/account-login-btn）。
6. 全程占用终端：开始时 lease_device，结束时 release_device。

最终输出（必须）：
- 先一句结论：`RESULT: PASS` 或 `RESULT: FAIL`
- 然后"证据"块：SSID / BSSID / 频点 / RSSI / MAC / IP / 安全类型 / 失败码（有则给）/ 截图路径
- 再给"过程"：实际执行的关键步骤（每一步一条，简洁）
- 失败时给"原因与建议"

runbook 全文：
{skill}
"""


def wait_device_free(serial, cancel=None, timeout=None):
    """同一台手机的第二个任务：**排队等空闲**，而不是立刻被 409 顶回去。
    返回 (True, None) / (False, 原因)"""
    timeout = QUEUE_WAIT if timeout is None else timeout
    if timeout <= 0:
        return True, None
    t0 = time.time()
    while time.time() - t0 < timeout:
        if cancel is not None and cancel.is_set():
            return False, "已取消"
        try:
            d = http("GET", "/devices/%s" % serial, timeout=15)
        except Exception:
            time.sleep(3)
            continue
        cur = d.get("lease")
        if (not cur) or cur.get("until", 0) <= time.time() or cur.get("owner") == CURRENT_OWNER[0]:
            return True, None
        time.sleep(5)
    return False, "排队等了 %ds，%s 仍被占用" % (timeout, serial)


def run_task(text, device="auto", max_steps=MAX_STEPS, owner=None, devices=None,
             cancel=None, job=None):
    # 多台：直接扇出（总入口只认一句话 + 目标集合，不另设命令）
    if devices and list(devices) not in (["auto"], ["all"]) and len(list(devices)) > 1:
        return fanout(text, list(devices), 4, owner)
    if devices and list(devices) == ["all"]:
        return fanout(text, ["all"], 4, owner)
    cfg = load_llm_conf()
    if not cfg["base"] or not cfg["key"]:
        return {"ok": False, "error": "没有可用的模型端点（设 PHONE_AGENT_BASE_URL/API_KEY，或复用 %s）" % BU_ENV}
    # 自己的身份与租约上下文（每任务独立：并发任务不会互相释放）
    CURRENT_OWNER[0] = owner or ("phone-agent:%d" % (int(time.time()) % 1000000))
    ctx = LeaseCtx(CURRENT_OWNER[0])
    if device not in ("auto", "", None):
        if job is not None:
            job["status"] = "queued"
        ok_free, why = wait_device_free(device, cancel)
        if not ok_free:
            return {"ok": False, "verdict": "CANCELLED" if why == "已取消" else "BLOCKED", "error": why}
        if job is not None:
            job["status"] = "running"
        ok, err = ensure_lease(ctx, device)
        if not ok:
            return {"ok": False, "verdict": "BLOCKED", "error": err}

    def finish(res, release=True):
        """收口：停心跳、释放本任务占过的终端（硬闸下必须释放，否则别人用不了）"""
        if release:
            release_ctx(ctx)
        else:
            for ev in list(ctx.stops.values()):
                ev.set()
        return res

    step_hint = "" if device in ("auto", "", None) else "\n注意：本次只能使用终端 %s。" % device
    messages = [{"role": "system", "content": system_prompt(cfg)},
                {"role": "user", "content": text + step_hint}]
    trace = []
    t0 = time.time()
    for i in range(max_steps):
        # 取消 / 总时限：LLM 或人工卡住时也能及时收口释放终端
        if cancel is not None and cancel.is_set():
            return finish({"ok": False, "verdict": "CANCELLED", "answer": "任务被取消（终端已释放）",
                           "trace": trace, "steps": len(trace), "elapsed_s": round(time.time() - t0, 1)})
        if time.time() - t0 > DEADLINE:
            return finish({"ok": False, "verdict": "TIMEOUT",
                           "answer": "超过任务总时限 %ds，已收口释放终端" % DEADLINE,
                           "trace": trace, "steps": len(trace), "elapsed_s": round(time.time() - t0, 1)})
        try:
            r = chat(cfg, messages)
        except Exception as e:
            return finish({"ok": False, "verdict": "LLM_DOWN",
                           "answer": "模型服务不可用，任务中止并释放终端：%s" % e,
                           "trace": trace, "steps": len(trace), "elapsed_s": round(time.time() - t0, 1)})
        msg = (r.get("choices") or [{}])[0].get("message") or {}
        calls = msg.get("tool_calls") or []
        if calls:
            messages.append({"role": "assistant", "content": msg.get("content") or "",
                             "tool_calls": calls})
            for c in calls:
                fn = c.get("function", {})
                name = fn.get("name")
                try:
                    args = json.loads(fn.get("arguments") or "{}")
                except Exception:
                    args = {}
                log("step%d tool %s %s" % (i + 1, name, json.dumps(args, ensure_ascii=False)[:200]))
                try:
                    res = exec_tool(name, args, ctx)
                except Exception as e:
                    res = {"error": str(e)}
                trace.append({"step": i + 1, "tool": name, "args": args,
                              "result": res if name != "phone_skill" else "(runbook %d 字)" % len(str(res))})
                messages.append({"role": "tool", "tool_call_id": c.get("id"),
                                 "content": json.dumps(res, ensure_ascii=False)[:12000]})
            continue
        final = msg.get("content") or ""
        # 有没有做"会改设备状态"的动作（用于区分"回个话"与"干了活却没给结论"）
        mut = ("wifi-connect", "wifi-forget", "wifi-radio", "settext", "click", "tap", "swipe",
               "key", "input", "portal-login", "am start", "svc power", "sendevent")
        changed = any(any(m in " ".join(map(str, t["args"].get("argv", []) or [])) for m in mut)
                      for t in trace if t["tool"] == "phone_exec")
        if re.search(r"RESULT:\s*PASS", final, re.I):
            verdict, ok = "PASS", True
        elif re.search(r"RESULT:\s*FAIL", final, re.I):
            verdict, ok = "FAIL", False
        elif not changed:
            verdict, ok = "ANSWER", True          # 只读/纯问答，不算失败
        else:
            verdict, ok = "UNKNOWN", False        # 改了设备却没给 PASS/FAIL
        return finish({"ok": ok, "verdict": verdict, "answer": final, "changed_device": changed,
                       "steps": len(trace), "trace": trace, "elapsed_s": round(time.time() - t0, 1),
                       "llm": {"model": cfg["model"], "base": cfg["base"]}})
    return finish({"ok": False, "verdict": "TIMEOUT", "answer": "步数用尽未完成", "trace": trace,
                   "steps": len(trace), "elapsed_s": round(time.time() - t0, 1)})


# ---------------- 作业（异步任务：可查状态、可取消） ----------------

JOBS = {}
JOB_SEQ = [0]
JOB_LOCK = threading.Lock()


def submit(text, device="auto", devices=None):
    """异步提交：立刻返回 job_id，后台跑（LLM 挂了也能 cancel 掉释放终端）"""
    with JOB_LOCK:
        JOB_SEQ[0] += 1
        jid = "job%03d" % JOB_SEQ[0]
        j = {"id": jid, "text": text, "device": device, "devices": devices,
             "status": "queued", "created": time.time(), "started": None, "finished": None,
             "result": None, "cancel": threading.Event()}
        JOBS[jid] = j

    def runner():
        j["status"] = "running"
        j["started"] = time.time()
        try:
            j["result"] = run_task(text, device, devices=devices, cancel=j["cancel"], job=j)
        except Exception as e:
            j["result"] = {"ok": False, "verdict": "ERROR", "answer": str(e)}
        j["finished"] = time.time()
        if j["cancel"].is_set():
            j["status"] = "cancelled"
        else:
            j["status"] = "done" if (j["result"] or {}).get("ok") else "failed"

    threading.Thread(target=runner, daemon=True).start()
    return j


def job_view(j):
    return {"id": j["id"], "status": j["status"], "text": j["text"][:200], "device": j["device"],
            "devices": j["devices"], "created": j["created"], "started": j["started"],
            "finished": j["finished"],
            "elapsed_s": round((j["finished"] or time.time()) - (j["started"] or j["created"]), 1),
            "verdict": (j["result"] or {}).get("verdict"),
            "steps": (j["result"] or {}).get("steps"),
            "answer": ((j["result"] or {}).get("answer") or "")[:1500]}


# ---------------- 服务 ----------------

def serve():
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _send(self, obj, code=200):
            b = json.dumps(obj, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)

        def do_GET(self):
            p = self.path.split("?")[0].rstrip("/") or "/"
            if p.startswith("/health"):
                cfg = load_llm_conf()
                with JOB_LOCK:
                    jl = [job_view(j) for j in JOBS.values()][-10:]
                return self._send({"ok": True, "model": cfg["model"], "base": cfg["base"],
                                   "key_set": bool(cfg["key"]),
                                   "busy_jobs": sum(1 for x in jl if x["status"] in ("running", "queued")),
                                   "devices": [d["serial"] for d in http("GET", "/devices", timeout=20)["devices"]]})
            if p == "/tasks":
                with JOB_LOCK:
                    return self._send({"jobs": [job_view(j) for j in JOBS.values()][-50:]})
            m = re.match(r"^/tasks/(job\d+)$", p)
            if m:
                with JOB_LOCK:
                    j = JOBS.get(m.group(1))
                return self._send(job_view(j) if j else {"error": "没有这个作业"}, 200 if j else 404)
            return self._send({"error": "use POST /task (同步) 或 POST /tasks (异步) 或 GET /tasks"}, 404)

        def do_POST(self):
            n = int(self.headers.get("Content-Length") or 0)
            try:
                body = json.loads(self.rfile.read(n) or b"{}")
            except Exception:
                body = {}
            p = self.path.split("?")[0].rstrip("/")
            if p == "/tasks":                      # 异步：立刻拿 job_id
                text = body.get("text") or ""
                if not text:
                    return self._send({"error": "需要 text"}, 400)
                j = submit(text, body.get("device", "auto"), body.get("devices"))
                return self._send(job_view(j), 202)
            m = re.match(r"^/tasks/(job\d+)/cancel$", p)
            if m:
                with JOB_LOCK:
                    j = JOBS.get(m.group(1))
                if not j:
                    return self._send({"error": "没有这个作业"}, 404)
                j["cancel"].set()
                return self._send({"ok": True, "job": job_view(j), "note": "已请求取消；若在等 LLM 会很快收口并释放终端"})
            if p == "/task":                       # 同步（兼容）
                text = body.get("text") or body.get("task") or ""
                if not text:
                    return self._send({"error": "需要 text"}, 400)
                return self._send(run_task(text, body.get("device", "auto"),
                                           int(body.get("max_steps", MAX_STEPS)),
                                           devices=body.get("devices")))
            return self._send({"error": "未知路径"}, 404)

    srv = ThreadingHTTPServer(("0.0.0.0", PORT), H)
    log("phone-agent listening :%d" % PORT)
    print(json.dumps({"phone_agent": "listening", "port": PORT}, ensure_ascii=False))
    sys.stdout.flush()
    srv.serve_forever()


def fanout(text, devices, parallel=4, owner=None):
    """多终端并行：一句话下发到多台（每台各自 lease → 跑 agent → release）
    这就是'两台一起/所有终端都'的实现 —— 上层只需把它当工具用。"""
    owner = owner or "phone-agent-fanout"
    from concurrent.futures import ThreadPoolExecutor
    ds = [d for d in http("GET", "/devices", timeout=40)["devices"] if d["present"]]
    if devices and devices != ["all"] and devices != ["auto"]:
        want = set(devices)
        ds = [d for d in ds if d["serial"] in want]
    if not ds:
        return {"ok": False, "error": "没有匹配的在线终端"}

    def one(d):
        s = d["serial"]
        o = "%s:%s" % (owner, s)          # 每台一个 owner 身份，便于硬闸下排队与心跳续期
        try:
            http("POST", "/devices/%s/lease" % s, {"owner": o, "ttl": 1800}, timeout=30)
        except Exception:
            pass
        # 每台一句：把 {serial} 占位替换掉，方便把终端名写进任务
        t = text.replace("{serial}", s).replace("{model}", d.get("model") or "")
        try:
            r = run_task(t, device=s, owner=o)
        except Exception as e:
            r = {"ok": False, "verdict": "ERROR", "answer": str(e), "trace": []}
        finally:
            try:
                http("POST", "/devices/%s/release" % s, {"owner": o, "reason": "fanout 结束"}, timeout=30)
            except Exception:
                pass
        r["serial"] = s
        r["model"] = d.get("model")
        return r

    with ThreadPoolExecutor(max_workers=max(1, min(parallel, len(ds)))) as ex:
        results = list(ex.map(one, ds))
    return {"ok": all(r.get("ok") for r in results),
            "count": len(results),
            "pass": sum(1 for r in results if r.get("ok")),
            "fail": sum(1 for r in results if not r.get("ok")),
            "results": results}


def main():
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if a[0] == "serve":
        serve()
        return 0
    if a[0] == "health":
        cfg = load_llm_conf()
        print(json.dumps({"model": cfg["model"], "base": cfg["base"], "key_set": bool(cfg["key"])},
                         ensure_ascii=False))
        return 0
    if a[0] == "batch":
        rest = a[1:]
        devs, par = ["all"], 4
        if "--devices" in rest:
            i = rest.index("--devices")
            devs = rest[i + 1].split(",")
            rest = rest[:i] + rest[i + 2:]
        if "--parallel" in rest:
            i = rest.index("--parallel")
            par = int(rest[i + 1])
            rest = rest[:i] + rest[i + 2:]
        res = fanout(" ".join(rest), devs, par)
        if os.environ.get("PHONE_AGENT_JSON"):
            print(json.dumps(res, ensure_ascii=False))
        else:
            print("批量: %d 台，PASS %d / FAIL %d" % (res.get("count", 0), res.get("pass", 0), res.get("fail", 0)))
            for r in res.get("results", []):
                head = (r.get("answer") or "").strip().splitlines()
                first = next((l for l in head if "RESULT" in l), (head[0] if head else ""))
                print("\n=== %s (%s) → %s  [%s 步 / %ss]" % (r["serial"], r.get("model"), r.get("verdict"),
                                                          r.get("steps"), r.get("elapsed_s")))
                print("   " + first.strip()[:150])
        return 0 if res.get("ok") else 1
    device = "auto"
    if "--device" in a:
        device = a[a.index("--device") + 1]
        a = [x for i, x in enumerate(a) if x != "--device" and i != a.index("--device") + 1]
    text = " ".join(a)
    res = run_task(text, device)
    if os.environ.get("PHONE_AGENT_JSON"):
        print(json.dumps(res, ensure_ascii=False))
    else:
        print(res.get("answer") or json.dumps(res, ensure_ascii=False))
        print("\n--- 过程 %d 步 / %.1fs / 模型 %s ---" % (res.get("steps", 0), res.get("elapsed_s", 0),
                                                        (res.get("llm") or {}).get("model")))
        for t in res.get("trace", []):
            r = t["result"]
            if isinstance(r, str):
                brief = r[:120].replace("\n", " ")
            elif isinstance(r, dict):
                brief = (r.get("stdout") or json.dumps(r, ensure_ascii=False))[:120].replace("\n", " ")
            else:
                brief = str(r)[:120].replace("\n", " ")
            print("  %2d. %-14s %-60s → %s" % (t["step"], t["tool"],
                                               json.dumps(t["args"], ensure_ascii=False)[:60], brief))
    return 0 if res.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
