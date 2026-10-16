#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""phone-look —— 手机"眼睛"：截图 → 交给视觉模型 → 回文本结论（可选给坐标）

为什么要它：coding agent（Aider/Qwen Code/crush）的工具输出都是**文本**，
模型看不到图。所以把"看图"封成一条命令：agent 只要会敲命令、读文本，
就能"看见"手机现在是什么界面、该点哪里。

用法：
  phone-look <serial> "这是什么页面？"                # 文本结论
  phone-look <serial> --coord "WLAN 列表第一项"       # 额外要求给出可点坐标 [x,y]
  phone-look <serial> --json "..."                   # 机器可读输出
选项/环境：
  PHONE_LOOK_MODEL   默认 deepseek-flash
  PHONE_LOOK_BASE    默认 http://131.255.36.100:30001/v1
  PHONE_LOOK_KEY     默认读 /opt/webui-mcp/bu/bu.env 的 BU_LLM_API_KEY
  PHONE_LOOK_KEEP=1  保留本地截图（默认留在 /tmp/phone-look-<serial>.png）
"""
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

BU_ENV = "/opt/webui-mcp/bu/bu.env"
DEFAULT_BASE = "http://131.255.36.100:30001/v1"
DEFAULT_MODEL = "deepseek-flash"


def sh(args, timeout=120, serial=None):
    env = dict(os.environ)
    if serial:
        env["ANDROID_SERIAL"] = serial
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                       env=env, stdin=subprocess.DEVNULL)
    return p.returncode, p.stdout, p.stderr


def _proj_base():
    """端点也回退读项目级配置"""
    try:
        import json as _json
        for cand in ("/opt/phone-use/pu/.qwen/settings.json",
                     os.path.expanduser("~/.qwen/settings.json")):
            if os.path.exists(cand):
                b = ((_json.load(open(cand, encoding="utf-8")).get("env") or {})
                     .get("OPENAI_BASE_URL"))
                if b:
                    return str(b).strip()
    except Exception:
        pass
    return None


def bu_key():
    # 取值顺序：显式指定 > agent 传下来的 OPENAI_API_KEY > BU 网关 key 文件
    k = (os.environ.get("PHONE_LOOK_KEY") or os.environ.get("PHONE_AGENT_API_KEY")
         or os.environ.get("OPENAI_API_KEY"))
    if k:
        return k.strip()
    try:
        for line in open(BU_ENV, encoding="utf-8", errors="ignore"):
            if line.startswith("BU_LLM_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    except Exception:
        pass
    # 回退：读项目级 .qwen/settings.json 的 env（phonebot 可读，600）
    try:
        import json as _json
        for cand in ("/opt/phone-use/pu/.qwen/settings.json",
                     os.path.expanduser("~/.qwen/settings.json")):
            if os.path.exists(cand):
                k = ((_json.load(open(cand, encoding="utf-8")).get("env") or {})
                     .get("OPENAI_API_KEY"))
                if k:
                    return str(k).strip()
    except Exception:
        pass
    return ""


def device_size(serial):
    rc, out, _ = sh(["phone-use", "state"], timeout=90, serial=serial)
    try:
        d = json.loads(out.strip().splitlines()[-1])
        w = (d.get("screen") or {}).get("w") or d.get("screen_w")
        h = (d.get("screen") or {}).get("h") or d.get("screen_h")
        if w and h:
            return int(w), int(h)
    except Exception:
        pass
    rc, out, _ = sh(["adb", "-s", serial, "shell", "wm", "size"], timeout=60)
    m = re.search(r"(?:Override|Physical) size:\s*(\d+)x(\d+)", out)
    return (int(m.group(1)), int(m.group(2))) if m else (1080, 2340)


def look(serial, question, want_coord=False, keep=False, timeout=300):
    """截图 → 模型读图 → 文本结论"""
    w, h = device_size(serial)
    dev_png = "/sdcard/phone-look.png"
    local = "/tmp/phone-look-%s.png" % serial
    rc, out, err = sh(["phone-hand", "shot", dev_png], timeout=120, serial=serial)
    if rc != 0:
        return {"ok": False, "error": "截图失败: %s" % (err or out)[:200]}
    rc, out, err = sh(["phone-hand", "pull", dev_png, local], timeout=120, serial=serial)
    if rc != 0 or not os.path.exists(local):
        return {"ok": False, "error": "取回截图失败: %s" % (err or out)[:200]}

    ask = ("这是一张安卓手机截图（分辨率 %dx%d）。请用中文回答：\n%s\n" % (w, h, question))
    if want_coord:
        ask += ("\n另外，请给出要点击的**屏幕绝对坐标**（基于 %dx%d）："
                "最后一行固定输出 TAP=x,y；若无需点击则输出 TAP=none。" % (w, h))
    ask += "\n要求：只描述你确实看到的内容，不要猜；看不清就说看不清。"

    b64 = base64.b64encode(open(local, "rb").read()).decode()
    body = {"model": os.environ.get("PHONE_LOOK_MODEL", DEFAULT_MODEL),
            "max_tokens": 900, "temperature": 0,
            "messages": [{"role": "user", "content": [
                {"type": "text", "text": ask},
                {"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}}]}]}
    _base = (os.environ.get("PHONE_LOOK_BASE") or os.environ.get("OPENAI_BASE_URL")
             or _proj_base() or DEFAULT_BASE).rstrip("/")
    req = urllib.request.Request(
        _base + "/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + bu_key(), "Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            resp = json.loads(r.read().decode())
    except Exception as e:
        return {"ok": False, "error": "模型调用失败: %s" % str(e)[:200]}
    msg = (resp.get("choices") or [{}])[0].get("message", {}) or {}
    text = (msg.get("content") or "").strip()
    if not text:
        text = (msg.get("reasoning") or "").strip()      # deepseek-flash 是推理模型
    tap = None
    m = re.search(r"TAP\s*=\s*(\d+)\s*,\s*(\d+)", text)
    if m:
        tap = [int(m.group(1)), int(m.group(2))]
    if not keep:
        try:
            os.remove(local)
        except Exception:
            pass
    return {"ok": True, "serial": serial, "screen": [w, h], "question": question,
            "answer": text, "tap": tap, "screenshot": (local if keep else None),
            "seconds": round(time.time() - t0, 1),
            "usage": resp.get("usage", {})}


def main():
    args = [a for a in sys.argv[1:]]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    serial = args.pop(0)
    as_json = "--json" in args
    want_coord = "--coord" in args
    keep = os.environ.get("PHONE_LOOK_KEEP") == "1" or "--keep" in args
    args = [a for a in args if a not in ("--json", "--coord", "--keep")]
    question = " ".join(args) or "现在是什么页面？有没有需要处理的弹窗？"
    r = look(serial, question, want_coord=want_coord, keep=keep)
    if as_json:
        print(json.dumps(r, ensure_ascii=False))
    elif r.get("ok"):
        print("【看】%s  (%dx%d, %.1fs)" % (serial, r["screen"][0], r["screen"][1], r["seconds"]))
        print(r["answer"])
        if r.get("tap"):
            print("建议点击: phone-hand tap %d %d" % (r["tap"][0], r["tap"][1]))
    else:
        print("【看】失败: %s" % r.get("error"))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
