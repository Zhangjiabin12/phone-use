#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""phone-hub —— 36.102 上的**安卓终端农场服务**

解决四件事：
  1) 有哪些终端在线（adb devices）+ 型号/系统/版本
  2) 每台终端"服务是否就绪"（root / Portal / pu.jar / 无障碍 / 屏幕 / Wi-Fi）
  3) 每台的**占用状态**：idle（空闲）/ busy（被租用）/ offline，带租约(TTL)与占用者
  4) 每台的**能力集**与版本（phone-use 版本、pu.jar 哈希、skill 版本）

对外：
  · HTTP API  :8901（GET / , /devices, /devices/<serial>, /skill ; POST .../lease|release|probe|exec）
  · CLI       : phone-hub ls | show <serial> | lease <serial> --owner X --ttl 600 | release <serial>
                | exec <serial> -- <phone-use 参数...> | probe <serial> | serve
用法示例（AI 侧）：
  curl -s 127.0.0.1:8901/devices | jq '.devices[] | {serial,state,capabilities}'
  phone-hub lease 463fd7bf1220 --owner ai --ttl 900
  phone-hub exec 463fd7bf1220 -- wifi-connect 928wpa2-psk wpa2 12345678 --mac none
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PHONE_HUB_PORT", "8901"))
SCAN_INTERVAL = int(os.environ.get("PHONE_HUB_SCAN", "15"))
PROBE_TTL = int(os.environ.get("PHONE_HUB_PROBE_TTL", "600"))
TTL_DEFAULT = int(os.environ.get("PHONE_HUB_TTL", "900"))          # 租约默认有效期
IDLE_RECLAIM = int(os.environ.get("PHONE_HUB_IDLE_RECLAIM", "600"))  # 无心跳且无动作 → 收回
STILL_RECLAIM = int(os.environ.get("PHONE_HUB_STILL_RECLAIM", "900"))  # 屏幕长时间无变化 → 收回
HEARTBEAT_GRACE = int(os.environ.get("PHONE_HUB_HB_GRACE", "90"))   # 心跳新鲜度阈值（判定"人在/agent 在"）
# 心跳还在、但设备长时间没有任何动作 → 判定任务挂死（典型：LLM 服务器挂了/网络卡住，进程没死心跳照跳）
STALL_AFTER = int(os.environ.get("PHONE_HUB_STALL_AFTER", "120"))       # 多久无动作算"疑似卡死"（展示用）
STALL_RECLAIM = int(os.environ.get("PHONE_HUB_STALL_RECLAIM", "300"))   # 多久无动作就强制收回
OFFLINE_PRUNE = int(os.environ.get("PHONE_HUB_OFFLINE_PRUNE", "86400"))  # 离线多久后从列表删除（老化清理）
PHONE_USE = os.environ.get("PHONE_USE_BIN", "/usr/local/share/phone-use/phone-use.py")
SKILL_PATH = "/usr/local/share/phone-use/SKILL.md"
JAR_PATH = "/opt/phone-use-jar/pu.jar"
VERSION = "1.0"
LOCK = threading.RLock()
DEVICES = {}
PRUNED = []          # 老化删除记录（离线太久被清理的终端）


def sh(cmd, timeout=90):
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=timeout,
                           stdin=subprocess.DEVNULL, text=True)
        return p.returncode, (p.stdout or ""), (p.stderr or "")
    except Exception as e:
        return 1, "", str(e)


def adb(serial, *args, timeout=60):
    return sh(["adb", "-s", serial] + list(args), timeout=timeout)


def jar_sha1():
    try:
        return hashlib.sha1(open(JAR_PATH, "rb").read()).hexdigest()[:12]
    except Exception:
        return None


def phone_use_version():
    try:
        txt = open(PHONE_USE, encoding="utf-8").read()
        m = re.search(r'"""phone-use[^\n]*', txt)
        return "4" if "原语工具集" in txt else "3"
    except Exception:
        return None


def probe(serial):
    """探测一台终端的环境与能力（较重，按 TTL 缓存）"""
    d = {"serial": serial}
    rc, o, _ = adb(serial, "shell", "getprop", "ro.product.model")
    d["model"] = o.strip() or None
    for key, prop in (("android", "ro.build.version.release"), ("sdk", "ro.build.version.sdk"),
                      ("miui", "ro.miui.ui.version.name"), ("incremental", "ro.build.version.incremental")):
        rc, o, _ = adb(serial, "shell", "getprop", prop)
        d[key] = o.strip() or None
    rc, o, _ = adb(serial, "shell", "su", "-c", "id", timeout=10)
    d["root"] = o.strip().startswith("uid=0")
    rc, o, _ = adb(serial, "shell", "pm", "list", "packages")
    d["portal_app"] = "com.mobilerun.portal" in o
    d["captive_portal_login"] = "com.android.captiveportallogin" in o
    rc, o, _ = adb(serial, "shell", "dumpsys", "power")
    m = re.search(r"mWakefulness=(\w+)", o)
    d["screen"] = m.group(1) if m else None
    # 显示器真实开关（熄屏时 screencap 会返回全黑帧，靠这个判"为什么没画面"）
    rc, o, _ = adb(serial, "shell", "dumpsys", "display")
    mm = re.search(r"mState=(\w+)", o)
    d["screen_display_on"] = (mm.group(1) == "ON") if mm else None
    # 真实分辨率：墙上点画面的坐标映射必须按它算（否则点偏 —— 之前用压缩图宽*2 就是错的）
    rc, o, _ = adb(serial, "shell", "wm", "size")
    mm = re.search(r"(?:Override|Physical) size:\s*(\d+)x(\d+)", o)
    if mm:
        d["screen_w"], d["screen_h"] = int(mm.group(1)), int(mm.group(2))
    rc, o, _ = adb(serial, "shell", "dumpsys", "battery")
    m = re.search(r"level: (\d+)", o)
    d["battery"] = int(m.group(1)) if m else None
    rc, o, _ = adb(serial, "shell", "cmd", "wifi", "status")
    m = re.search(r'Wifi is connected to "([^"]+)"', o)
    d["wifi_ssid"] = m.group(1) if m else None
    d["wifi_enabled"] = "Wifi is enabled" in o or d["wifi_ssid"] is not None
    m = re.search(r"MAC: ([0-9a-f:]+)", o)
    d["wifi_mac"] = m.group(1) if m else None
    rc, o, _ = adb(serial, "shell", "ip", "-4", "addr", "show", "wlan0")
    m = re.search(r"inet (\d+\.\d+\.\d+\.\d+)", o)
    d["wifi_ip"] = m.group(1) if m else None
    rc, o, _ = adb(serial, "shell", "cmd", "wifi", "help")
    d["cmd_wifi_connect"] = "connect-network" in o
    # 真测一次连网权限（无人值守必需），测完立刻删掉临时配置
    d["wifi_cmd_ok"] = False
    d["wifi_cmd_error"] = None
    if d["cmd_wifi_connect"]:
        probe_ssid = "phone-hub-probe"
        rc, o2, e2 = adb(serial, "shell", "cmd", "wifi", "connect-network", probe_ssid, "open", timeout=40)
        out = o2 + e2
        d["wifi_cmd_ok"] = "Connection initiated" in out
        if not d["wifi_cmd_ok"]:
            d["wifi_cmd_error"] = (out.strip().splitlines()[-1][:160] if out.strip() else "无输出")
        rc3, nets, _ = adb(serial, "shell", "cmd", "wifi", "list-networks")
        for line in nets.splitlines():
            if probe_ssid in line:
                mm = re.match(r"\s*(\d+)", line)
                if mm:
                    adb(serial, "shell", "cmd", "wifi", "forget-network", mm.group(1))
    else:
        d["wifi_cmd_error"] = "系统没有 cmd wifi connect-network 命令"
    # —— 接入体检用的便宜检查（决定"能不能用/为什么不能用"）——
    rc, o, _ = adb(serial, "shell", "settings", "get", "global", "development_settings_enabled")
    d["dev_options"] = o.strip() == "1"
    rc, o, _ = adb(serial, "shell", "settings", "get", "global", "adb_enabled")
    d["usb_debug"] = o.strip() == "1"
    rc, o, _ = adb(serial, "shell", "settings", "get", "global", "stay_on_while_plugged_in")
    d["stay_awake"] = o.strip() not in ("", "0", "null")
    rc, o, _ = adb(serial, "shell", "date", "+%s")
    try:
        d["time_skew_s"] = abs(int(o.strip()) - int(time.time()))
    except Exception:
        d["time_skew_s"] = None
    rc, o, e = adb(serial, "shell", "input", "tap", "1", "1", timeout=30)
    msg = o + e
    d["input_inject"] = rc == 0 and "INJECT_EVENTS" not in msg and "Injecting to another" not in msg
    rc, o, _ = adb(serial, "shell", "dumpsys", "window")
    d["screen_locked"] = "mDreamingLockscreen=true" in o or "mShowingLockscreen=true" in o
    # jar 就绪（无障碍节点注入）：真跑一次极简命令
    rc, o, e = sh(["adb", "-s", serial, "shell",
                   "uiautomator runtest /data/local/tmp/pu.jar -c com.dsh.phoneuse.PhoneUseTest#testRun"],
                  timeout=120)
    d["jar_ready"] = "OK (1 test)" in (o + e) or "Tests run" in (o + e)
    caps = ["read-ui", "screenshot", "shell"]
    if d["jar_ready"]:
        caps += ["node-click", "settext", "scroll", "global-action", "http-from-phone"]
    if d.get("wifi_cmd_ok"):                       # 只有真测通过才给"能连网"能力（无人值守必需）
        caps += ["join-open", "join-psk", "lock-bssid", "mac-policy"]
    if d["captive_portal_login"]:
        caps += ["portal-ui"]
    if (d.get("android") in ("12", "11", "10")) or d["miui"]:
        caps += ["1x-ui"]
    if d["root"]:
        caps += ["su", "supplicant-config", "input-inject", "coordinate-gesture", "keyevent",
                 "install-apk"]
        d["backend"] = "root-input"
    elif d.get("input_inject"):
        caps += ["input-inject", "coordinate-gesture", "keyevent"]   # P2：系统允许坐标注入（免 root）
        d["backend"] = "input"
    else:
        d["backend"] = "jar-node-action"
    d["capabilities"] = caps
    d["versions"] = {"phone_use": phone_use_version(), "pu_jar_sha1": jar_sha1(),
                     "hub": VERSION, "skill": "phone-use-wlan/2026-10-16"}
    d["probed_at"] = time.time()
    return d


def scan_once(force_probe=False):
    rc, o, _ = sh(["adb", "devices", "-l"])
    seen = {}
    for line in o.splitlines()[1:]:
        p = line.split()
        if len(p) >= 2 and p[1] == "device":
            seen[p[0]] = line.strip()
    todo = []
    with LOCK:
        for serial, desc in seen.items():
            dev = DEVICES.get(serial)
            if dev is None:
                dev = {"serial": serial, "created_at": time.time()}
                DEVICES[serial] = dev
            dev["last_seen"] = time.time()
            dev["adb_desc"] = desc
            if force_probe or not dev.get("probed_at") or time.time() - dev["probed_at"] > PROBE_TTL:
                todo.append(serial)
        for serial, dev in DEVICES.items():
            dev["state"] = "offline" if serial not in seen else lease_state(dev)
        # 老化清理：离线超过 OFFLINE_PRUNE 的终端直接从列表删掉（手机墙也不再显示）
        now = time.time()
        for serial in [s for s, d in DEVICES.items()
                       if d.get("state") == "offline" and now - d.get("last_seen", now) > OFFLINE_PRUNE]:
            dev = DEVICES.pop(serial)
            PRUNED.append({"serial": serial, "model": dev.get("model"),
                           "last_seen": dev.get("last_seen"), "at": now})
    # 并行探测（20 台时首轮才不至于串行几分钟）
    if todo:
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=min(6, len(todo))) as ex:
            results = list(ex.map(lambda s: (s, safe_probe(s)), todo))
        with LOCK:
            for serial, res in results:
                if serial in DEVICES:
                    DEVICES[serial].update(res)
    return seen


def safe_probe(serial):
    try:
        return probe(serial)
    except Exception as e:
        return {"probe_error": str(e), "probed_at": time.time()}


def lease_state(dev):
    lease = dev.get("lease")
    if lease and lease.get("until", 0) > time.time():
        return "busy"
    if lease:
        dev["lease"] = None
    return "idle"


def scanner_loop():
    while True:
        try:
            scan_once()
        except Exception:
            pass
        time.sleep(SCAN_INTERVAL)


FIXES = {
    "usb_debug": "开发者选项→打开『USB 调试』（设置→我的设备→全部参数→连点 MIUI 版本 7 次可开开发者选项）",
    "dev_options": "同上：先开发者选项，再 USB 调试",
    "no_backend": "既无 root、pu.jar 又不就绪 → 免 root 只能走节点动作：检查 /opt/phone-use-jar/pu.jar 与 uiautomator",
    "no_wifi_cmd": "不能自动连网（无人值守跑不了）→ 给这台 root，或换一台能自动连网的机器；人工连网不符合要求",
    "offline": "重新插拔线/换 USB 口（直插主机）→ `adb kill-server` 重试；USB 用途改『传输文件』",
    "unauthorized": "手机上点『允许 USB 调试』并勾选『一律允许』；没弹窗则开发者选项→撤销 USB 调试授权后重插",
    "low_battery": "插上电源（<15% 会休眠/降频，导致用例半途失败）",
    "time_skew": "设置→日期与时间→自动设置（时间不同步会导致 1X/门户认证失败）",
    "screen_locked": "`adb shell wm dismiss-keyguard` 解锁 + `svc power stayon true` 常亮",
}


def blockers_of(dev):
    """为什么这台"用不了"——给 hub 的调用方直接看结论与修法"""
    b = []
    if dev.get("state") == "offline":
        b.append({"id": "offline", "msg": "adb 里是 offline（线/口/USB 用途问题）", "fix": FIXES["offline"]})
        return b
    if dev.get("adb_state") and dev["adb_state"] != "device":
        b.append({"id": dev["adb_state"], "msg": "adb 状态=%s" % dev["adb_state"],
                  "fix": FIXES.get(dev["adb_state"], FIXES["offline"])})
    if dev.get("usb_debug") is False:
        b.append({"id": "usb_debug", "msg": "USB 调试未开", "fix": FIXES["usb_debug"]})
    if not dev.get("jar_ready") and not dev.get("root") and not dev.get("input_inject"):
        b.append({"id": "no_backend", "msg": "没有可用动作后端（无 root、不能坐标注入、pu.jar 也没就绪）", "fix": FIXES["no_backend"]})
    if dev.get("state") != "offline" and dev.get("wifi_cmd_ok") is False:
        b.append({"id": "no_wifi_cmd", "msg": "不能自动连网：%s" % (dev.get("wifi_cmd_error") or "系统不允许"),
                  "fix": FIXES["no_wifi_cmd"]})
    bat = dev.get("battery")
    if isinstance(bat, int) and bat < 15:
        b.append({"id": "low_battery", "msg": "电量 %d%%" % bat, "fix": FIXES["low_battery"]})
    if isinstance(dev.get("time_skew_s"), int) and dev["time_skew_s"] > 30:
        b.append({"id": "time_skew", "msg": "时间与 102 相差 %ds" % dev["time_skew_s"], "fix": FIXES["time_skew"]})
    if dev.get("screen_locked"):
        b.append({"id": "screen_locked", "msg": "屏幕锁屏", "fix": FIXES["screen_locked"]})
    return b


def public(dev):
    keep = ("serial", "state", "model", "android", "sdk", "miui", "root", "backend", "battery",
            "screen", "wifi_ssid", "wifi_ip", "wifi_mac", "wifi_enabled", "portal_app", "jar_ready",
            "capabilities", "versions", "lease", "last_seen", "probed_at", "adb_desc",
            "dev_options", "usb_debug", "stay_awake", "input_inject", "time_skew_s", "screen_locked", "screen_display_on", "screen_w", "screen_h",
            "cmd_wifi_connect", "wifi_cmd_ok", "wifi_cmd_error")
    d = {k: dev.get(k) for k in keep}
    if dev.get("state") == "offline":
        d["capabilities"] = []
    d["online_for_s"] = int(time.time() - dev.get("last_seen", time.time()))
    # STF 语义对齐（方便以后接 STF / 写前端，零迁移）
    d["stf_state"] = {"idle": "available", "busy": "using", "offline": "absent"}.get(d["state"], d["state"])
    d["present"] = d["state"] != "offline"
    d["ready"] = bool(d.get("jar_ready") or d.get("root") or d.get("input_inject"))
    d["unattended_ready"] = bool(d["present"] and d["ready"] and d.get("wifi_cmd_ok"))
    d["using"] = d["state"] == "busy"
    d["owner"] = (d.get("lease") or {}).get("owner")
    bl = blockers_of(dev)
    d["blockers"] = bl
    la = lease_alive(dev)
    d["lease_alive"] = la
    if la and d.get("lease"):
        d["lease"]["remaining_s"] = int(max(0, d["lease"].get("until", 0) - time.time()))
        d["lease"]["idle_s"] = la["idle_s"]
        d["lease"]["alive"] = la["alive"]
    d["last_reclaim"] = dev.get("last_reclaim")
    # 无人值守口径：动作后端 + 自动连网 都要有（不能自动连网 → 判不可用）
    d["usable"] = d["unattended_ready"] and not any(
        x["id"] in ("offline", "unauthorized", "usb_debug", "no_backend", "no_wifi_cmd") for x in bl)
    d["doctor_hint"] = "POST /devices/%s/doctor 或 102 上 `phone-doctor %s`（逐项体检+修法）" % (
        d.get("serial"), d.get("serial"))
    return d


def summary():
    with LOCK:
        ds = [public(d) for d in DEVICES.values()]
    return {"hub_version": VERSION, "time": time.time(), "count": len(ds),
            "online": sum(1 for d in ds if d["state"] != "offline"),
            "idle": sum(1 for d in ds if d["state"] == "idle"),
            "busy": sum(1 for d in ds if d["state"] == "busy"),
            "offline": sum(1 for d in ds if d["state"] == "offline"),
            "usable": sum(1 for d in ds if d.get("usable")),
            "pruned": len(PRUNED),
            "jar_ready": sum(1 for d in ds if d.get("jar_ready"))}


def do_lease(serial, owner, ttl, renew=False):
    """占一台终端。硬闸：别人持有效租约时拒绝（409 语义），返回谁占用到几点。"""
    with LOCK:
        dev = DEVICES.get(serial)
        if not dev:
            return None, "设备不存在"
        if dev.get("state") == "offline":
            return None, "设备离线"
        now = time.time()
        cur = dev.get("lease")
        if cur and cur.get("until", 0) > now and cur.get("owner") != owner:
            return None, "已被 %s 占用（剩余 %ds，最后活动 %ds 前）" % (
                cur.get("owner"), int(cur["until"] - now), int(now - cur.get("last_active", now)))
        if renew and cur and cur.get("owner") != owner:
            return None, "不是你的租约（当前 %s）" % (cur or {}).get("owner")
        dev["lease"] = {"owner": owner, "until": now + (ttl or TTL_DEFAULT), "since": now,
                        "last_active": now, "last_heartbeat": now, "renew_count":
                        (cur.get("renew_count", 0) + 1 if cur and cur.get("owner") == owner else 1)}
        dev["state"] = "busy"
        return public(dev), None


def do_heartbeat(serial, owner):
    """持租者心跳：证明"人还在 / agent 还活着"。心跳停了就会按空闲规则被收回。"""
    with LOCK:
        dev = DEVICES.get(serial)
        if not dev:
            return None, "设备不存在"
        cur = dev.get("lease")
        if not cur or cur.get("owner") != owner:
            return None, "没有你的租约（先 lease；当前 %s）" % ((cur or {}).get("owner") or "无")
        now = time.time()
        cur["last_heartbeat"] = now
        # 注意：心跳**不算设备活动**！否则"心跳在跳但设备卡死"就永远检测不出来。
        # 判断任务是否真在干活只看 last_active（由 do_exec 更新）。
        cur["until"] = max(cur["until"], now + TTL_DEFAULT)
        return public(dev), None


def do_reclaim(serial, reason="手动收回", owner=None, force=False):
    """释放/收回终端。
    · 带 owner：只能释放自己的租约（别人拿着 → 拒绝，提示用 reclaim/force）
    · 不带 owner 或 force=True：强制收回（管理/页面「强制收回」用这条）
    """
    with LOCK:
        dev = DEVICES.get(serial)
        if not dev:
            return None, "设备不存在"
        cur = dev.get("lease")
        if cur and cur.get("until", 0) > time.time() and owner and not force \
                and cur.get("owner") != owner:
            return None, "不是你的租约（当前 %s 占用，剩余 %ds）→ 用 /reclaim 强制收回" % (
                cur.get("owner"), int(cur["until"] - time.time()))
        if cur:
            dev["last_reclaim"] = {"at": time.time(), "owner": cur.get("owner"), "reason": reason}
        dev["lease"] = None
        dev["state"] = lease_state(dev)
        return public(dev), None


def lease_holder(dev):
    """当前有效租约的持有人（没有则 None）"""
    cur = dev.get("lease")
    if cur and cur.get("until", 0) > time.time():
        return cur
    if cur:
        dev["lease"] = None
    return None


def lease_alive(dev):
    """活性判定：心跳新鲜 / 最近有动作 / 屏幕在变 —— 任一成立就算"有人在用"
    另外单独给出 no_action_s（设备多久没被真正操作过）与 stalled（心跳在但没动作 = 疑似挂死）"""
    cur = lease_holder(dev)
    if not cur:
        return None
    now = time.time()
    hb_age = now - cur.get("last_heartbeat", 0)
    act_age = now - cur.get("last_active", 0)
    screen_age = now - dev.get("screen_changed_at", 0)
    alive = (hb_age <= HEARTBEAT_GRACE) or (act_age <= IDLE_RECLAIM / 2)
    inflight = dev.get("exec_inflight", 0)
    stalled = (hb_age <= HEARTBEAT_GRACE) and (act_age > STALL_AFTER) and not inflight
    return {"owner": cur["owner"], "heartbeat_age_s": int(hb_age), "idle_s": int(act_age),
            "no_action_s": int(act_age), "stalled": stalled, "exec_inflight": inflight,
            "will_reclaim_in_s": max(0, int(STALL_RECLAIM - act_age)) if stalled else None,
            "screen_changed_s": int(screen_age) if dev.get("screen_changed_at") else None,
            "alive": alive, "renew_count": cur.get("renew_count", 1)}


def screen_hash(serial):
    """屏幕指纹（用于判断"页面是不是一直没动"）"""
    rc, out, _ = sh(["adb", "-s", serial, "exec-out", "screencap", "-p"], timeout=30, binary=True)
    if rc != 0 or not out:
        return None
    return hashlib.md5(out).hexdigest()


def reaper_loop():
    """定期巡逻：TTL 过期 / 无心跳无动作 / 屏幕长期不动 → 自动收回终端（免得占用后没人释放）"""
    last_hash_check = {}
    while True:
        time.sleep(10)
        try:
            with LOCK:
                now = time.time()
                devs = list(DEVICES.values())
            for dev in devs:
                cur = lease_holder(dev)
                if not cur:
                    continue
                serial = dev["serial"]
                if cur["until"] <= now:
                    do_reclaim(serial, "租约到期（TTL）")
                    continue
                idle = now - cur.get("last_active", now)
                hb = now - cur.get("last_heartbeat", now)
                if idle > IDLE_RECLAIM and hb > IDLE_RECLAIM:
                    do_reclaim(serial, "无心跳且无动作 %ds（agent 可能已死/页面已关）" % int(idle))
                    continue
                # 关键：心跳还在，但设备长期没有动作 → LLM 服务器挂了/任务挂死（进程与心跳都正常）
                if dev.get("exec_inflight"):
                    continue      # 有动作正在执行（长动作），不能判卡死
                if idle > STALL_RECLAIM and hb <= HEARTBEAT_GRACE:
                    do_reclaim(serial, "心跳仍在但设备 %ds 无任何动作（LLM 卡住或任务挂死）" % int(idle))
                    continue
                # 屏幕指纹：只在"最近没动作"时采样，避免持续占用资源
                if idle > 120 and now - last_hash_check.get(serial, 0) > 60:
                    last_hash_check[serial] = now
                    h = screen_hash(serial)
                    if h:
                        with LOCK:
                            if dev.get("screen_hash") != h:
                                dev["screen_hash"] = h
                                dev["screen_changed_at"] = now
                            elif now - dev.get("screen_changed_at", now) > STILL_RECLAIM:
                                pass  # 下一轮由下面的判定收回
                        sc_age = now - dev.get("screen_changed_at", now)
                        if sc_age > STILL_RECLAIM:
                            do_reclaim(serial, "屏幕 %ds 无变化且无动作（僵尸占用）" % int(sc_age))
        except Exception:
            pass


def do_exec(serial, args, owner=None, force=False, timeout=600):
    """执行原语。**硬闸**：别人持有效租约时拒绝；同 owner 放行；force 可强占。"""
    with LOCK:
        dev = DEVICES.get(serial)
    if not dev:
        return {"rc": 3, "stdout": "", "stderr": "设备不存在", "blocked": True}
    cur = lease_holder(dev)
    if cur and not force and (owner or "anonymous") != cur["owner"]:
        return {"rc": 409, "stdout": "", "blocked": True,
                "stderr": "终端被 %s 占用（剩余 %ds，最后活动 %ds 前）→ 等它释放、用同一 owner、"
                          "或 POST /devices/%s/reclaim 收回" % (
                              cur["owner"], int(cur["until"] - time.time()),
                              int(time.time() - cur.get("last_active", time.time())), serial)}
    with LOCK:
        if cur and (owner or "anonymous") == cur["owner"]:
            cur["last_active"] = time.time()
        dev["last_action_at"] = time.time()
        dev["exec_inflight"] = dev.get("exec_inflight", 0) + 1   # 长动作进行中：巡逻不要判它卡死
    env = dict(os.environ, ANDROID_SERIAL=serial)
    try:
        p = subprocess.run([sys.executable, PHONE_USE] + args, capture_output=True,
                           text=True, timeout=timeout, env=env)
        res = {"rc": p.returncode, "stdout": p.stdout[-20000:], "stderr": p.stderr[-2000:]}
    except subprocess.TimeoutExpired:
        res = {"rc": 124, "stdout": "", "stderr": "超时"}
    finally:
        with LOCK:
            dev["exec_inflight"] = max(0, dev.get("exec_inflight", 1) - 1)
            if cur and (owner or "anonymous") == cur["owner"]:
                cur["last_active"] = time.time()
    return res


# ---------------- HTTP ----------------

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/") or "/"
        q = self.path.split("?", 1)[1] if "?" in self.path else ""
        if path == "/":
            return self._send(summary())
        if path in ("/devices", "/api/v1/devices"):
            with LOCK:
                return self._send({"devices": [public(d) for d in DEVICES.values()]})
        if path == "/api/v1/user/devices":
            owner = None
            m = re.search(r"owner=([^&]+)", q)
            if m:
                owner = m.group(1)
            with LOCK:
                ds = [public(d) for d in DEVICES.values()
                      if d.get("lease") and (owner is None or d["lease"].get("owner") == owner)]
            return self._send({"devices": ds})
        if path == "/skill":
            try:
                return self._send({"skill": open(SKILL_PATH, encoding="utf-8").read()})
            except Exception as e:
                return self._send({"error": str(e)}, 404)
        m = re.match(r"^/(?:api/v1/)?devices/([^/]+)$", path)
        if m:
            with LOCK:
                dev = DEVICES.get(m.group(1))
                if not dev:
                    return self._send({"error": "设备不存在"}, 404)
                return self._send(public(dev))
        return self._send({"error": "未知路径",
                           "hint": "/ /devices /api/v1/devices /api/v1/user/devices /devices/<serial> /skill"}, 404)

    def do_DELETE(self):
        """STF 风格释放：DELETE /api/v1/user/devices/<serial>"""
        path = self.path.split("?")[0].rstrip("/")
        m = re.match(r"^/(?:api/v1/)?user/devices/([^/]+)$", path)
        if not m:
            return self._send({"error": "未知路径"}, 404)
        dev, err = do_reclaim(m.group(1), "STF 风格释放")
        return self._send({"ok": dev is not None, "device": dev, "error": err})

    def do_POST(self):
        path = self.path.split("?")[0].rstrip("/")
        n = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            body = {}
        # STF 风格占用：POST /api/v1/user/devices/<serial>
        m0 = re.match(r"^/(?:api/v1/)?user/devices/([^/]+)$", path)
        if m0:
            dev, err = do_lease(m0.group(1), body.get("owner", "anonymous"),
                                int(body.get("ttl", TTL_DEFAULT)), renew=bool(body.get("renew")))
            return self._send({"ok": dev is not None, "device": dev, "error": err},
                              200 if dev else 409)
        m = re.match(r"^/(?:api/v1/)?devices/([^/]+)/(lease|release|probe|exec|doctor|heartbeat|reclaim)$", path)
        if not m:
            return self._send({"error": "未知路径"}, 404)
        serial, action = m.groups()
        if action == "doctor":
            rc, o, e = sh(["/usr/bin/python3", "/usr/local/share/phone-hub/phone-doctor.py",
                           "--json", serial], timeout=600)
            try:
                return self._send(json.loads(o))
            except Exception:
                return self._send({"ok": False, "error": (e or o)[-500:]}, 500)
        if action == "heartbeat":
            dev, err = do_heartbeat(serial, body.get("owner", "anonymous"))
            return self._send({"ok": dev is not None, "device": dev, "error": err},
                              200 if dev else 409)
        if action == "reclaim":
            dev, err = do_reclaim(serial, body.get("reason", "手动收回"))
            return self._send({"ok": dev is not None, "device": dev, "error": err})
        if action == "lease":
            dev, err = do_lease(serial, body.get("owner", "anonymous"),
                                int(body.get("ttl", TTL_DEFAULT)), renew=bool(body.get("renew")))
            return self._send({"ok": dev is not None, "device": dev, "error": err},
                              200 if dev else 409)
        if action == "release":
            dev, err = do_reclaim(serial, body.get("reason", "主动释放"),
                                  owner=body.get("owner"), force=bool(body.get("force")))
            return self._send({"ok": dev is not None, "device": dev, "error": err},
                              200 if dev else 409)
        if action == "probe":
            with LOCK:
                dev = DEVICES.get(serial)
            if not dev:
                return self._send({"error": "设备不存在"}, 404)
            try:
                with LOCK:
                    dev.update(probe(serial))
            except Exception as e:
                return self._send({"ok": False, "error": str(e)}, 500)
            return self._send({"ok": True, "device": public(dev)})
        if action == "exec":
            res = do_exec(serial, body.get("args", []), owner=body.get("owner"),
                          force=bool(body.get("force")),
                          timeout=int(body.get("timeout_s", 600)))
            code = 409 if res.get("blocked") else 200
            return self._send(res, code)
        return self._send({"error": "?"}, 400)


def serve():
    threading.Thread(target=scanner_loop, daemon=True).start()
    threading.Thread(target=reaper_loop, daemon=True).start()
    time.sleep(1)
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(json.dumps({"phone_hub": "listening", "port": PORT, "version": VERSION}, ensure_ascii=False))
    sys.stdout.flush()
    srv.serve_forever()


# ---------------- CLI ----------------

def cli():
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd = a[0]

    def opt(name, default=None):
        if name in a:
            i = a.index(name)
            if i + 1 < len(a):
                return a[i + 1]
        return default

    if cmd == "serve":
        serve()
        return 0
    if cmd == "refresh":
        scan_once(force_probe=True)
        print(json.dumps(summary(), ensure_ascii=False))
        return 0
    if cmd in ("ls", "list"):
        scan_once(force_probe=("-p" in a))
        with LOCK:
            rows = [public(d) for d in DEVICES.values()]
        if "--json" in a:
            print(json.dumps({"devices": rows}, ensure_ascii=False, indent=2))
            return 0
        print("%-16s %-8s %-12s %-6s %-5s %-6s %-8s %s" %
              ("serial", "state", "model", "AND", "root", "jar", "wifi", "capabilities"))
        for d in rows:
            print("%-16s %-8s %-12s %-6s %-5s %-6s %-8s %s" %
                  (d["serial"], d["state"], (d.get("model") or "?")[:12], d.get("android") or "?",
                   "Y" if d.get("root") else "-", "Y" if d.get("jar_ready") else "-",
                   (d.get("wifi_ssid") or "-")[:8], ",".join(d.get("capabilities") or [])[:70]))
        print("\n" + json.dumps(summary(), ensure_ascii=False))
        return 0
    if cmd == "show":
        scan_once()
        with LOCK:
            dev = DEVICES.get(a[1])
        print(json.dumps(public(dev) if dev else {"error": "设备不存在"}, ensure_ascii=False, indent=2))
        return 0
    if cmd == "probe":
        dev = probe(a[1])
        print(json.dumps(dev, ensure_ascii=False, indent=2))
        return 0
    if cmd == "exec":
        if "--" not in a:
            print("用法: phone-hub exec <serial> [--owner X] [--force] -- <phone-use 参数...>")
            return 2
        i = a.index("--")
        res = do_exec(a[1], a[i + 1:], owner=opt("--owner", "cli"), force=("--force" in a))
        if res.get("blocked"):
            print(json.dumps({"blocked": True, "reason": res["stderr"]}, ensure_ascii=False))
            return 3
        print(res["stdout"] or res["stderr"])
        return res["rc"]
    if cmd in ("lease", "release", "heartbeat", "reclaim"):
        import urllib.request
        base = "http://127.0.0.1:%d" % PORT
        if cmd == "lease":
            body = json.dumps({"owner": opt("--owner", "cli"), "ttl": int(opt("--ttl", TTL_DEFAULT)),
                               "renew": ("--renew" in a)}).encode()
        elif cmd == "heartbeat":
            body = json.dumps({"owner": opt("--owner", "cli")}).encode()
        elif cmd == "reclaim":
            body = json.dumps({"reason": opt("--reason", "CLI 收回")}).encode()
        else:
            body = b"{}"
        req = urllib.request.Request("%s/devices/%s/%s" % (base, a[1], cmd), data=body,
                                     headers={"Content-Type": "application/json"})
        try:
            print(urllib.request.urlopen(req, timeout=10).read().decode())
        except Exception as e:
            print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))
        return 0
    print("未知命令:", cmd)
    return 2


if __name__ == "__main__":
    sys.exit(cli())
