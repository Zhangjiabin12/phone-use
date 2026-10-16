#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""phone-hub-mcp —— 把手机原语暴露成 MCP（stdio）

**刻意只暴露 5 个"通用"工具**，schema 极简且几乎不会变（避免"工具定义写死导致调用失败"）：
  1. devices_list()                        有哪些终端、状态、后端、能力集
  2. phone_exec(serial, argv, timeout_s)   在指定终端上跑任意 phone-use 原语（**能力全在这一个工具里**）
  3. phone_skill()                         返回「怎么做怎么连」的 runbook（AI 读它自己决策）
  4. lease_device(serial, owner, ttl_s)    占用一台终端
  5. release_device(serial)                释放

也就是说：MCP 只负责"给我手和眼"，**"连哪种认证"完全不进 schema**，由 AI 现场判断。

跑法（MCP 客户端配置里）：
  command: python3
  args: ["/usr/local/share/phone-hub/phone-hub-mcp.py"]
"""
import json
import os
import subprocess
import sys
import urllib.request

HUB = os.environ.get("PHONE_HUB_BASE", "http://127.0.0.1:8901")
PHONE_USE = os.environ.get("PHONE_USE_BIN", "/opt/phone-use/base/phone-hand.py")
SERVER_INFO = {"name": "phone-hub", "version": "1.0"}

TOOLS = [
    {"name": "devices_list",
     "description": "列出所有安卓终端：serial、state(available/using/absent)、是否 root、动作后端、"
                    "能力集(如 node-click / input-inject / portal-ui / 1x-ui)、当前 Wi-Fi、版本。",
     "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False}},
    {"name": "phone_exec",
     "description": "在指定终端上执行一条 phone-use 原语，返回 JSON。这是唯一需要变通的地方："
                    "原语包括 state/ui/find/click-text/click-desc/click-id/click-xy/settext/scroll/"
                    "scroll-up/global/tap/swipe/key/input/shot/pull/http/httpfile/shell/wifi/"
                    "wifi-connect/wifi-forget/wifi-radio/list/scan/probe/failure/backend/jar。"
                    "怎么用它完成'连 WiFi + 各种认证'见 phone_skill()。",
     "inputSchema": {"type": "object",
                     "properties": {"serial": {"type": "string", "description": "终端 serial；省略则用唯一在线终端"},
                                    "argv": {"type": "array", "items": {"type": "string"},
                                             "description": "原语参数，如 [\"wifi-connect\",\"928wpa2-psk\",\"wpa2\",\"12345678\",\"--mac\",\"none\"]"},
                                    "timeout_s": {"type": "integer", "default": 600}},
                     "required": ["argv"], "additionalProperties": False}},
    {"name": "phone_skill",
     "description": "返回手机 WLAN 认证 runbook（开放/PSK/1X/门户四条路线的做法、成功判据、MIUI 已知坑、"
                    "机型差异）。先读它再动手。",
     "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False}},
    {"name": "lease_device",
     "description": "占用一台终端（TTL 秒），避免多 agent 抢同一台。",
     "inputSchema": {"type": "object", "properties": {"serial": {"type": "string"},
                                                      "owner": {"type": "string"},
                                                      "ttl_s": {"type": "integer", "default": 600}},
                     "required": ["serial"], "additionalProperties": False}},
    {"name": "release_device",
     "description": "释放终端占用。",
     "inputSchema": {"type": "object", "properties": {"serial": {"type": "string"}},
                     "required": ["serial"], "additionalProperties": False}},
]


def http(method, path, body=None, timeout=600):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(HUB + path, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def pick_serial():
    ds = [d for d in http("GET", "/devices", timeout=20)["devices"] if d["present"]]
    if len(ds) == 1:
        return ds[0]["serial"]
    if not ds:
        raise RuntimeError("没有在线终端")
    raise RuntimeError("有多台在线终端，请指定 serial：%s" % ", ".join(d["serial"] for d in ds))


def call_tool(name, args):
    if name == "devices_list":
        d = http("GET", "/devices", timeout=30)
        return json.dumps(d, ensure_ascii=False, indent=2)
    if name == "phone_exec":
        serial = args.get("serial") or pick_serial()
        res = http("POST", "/devices/%s/exec" % serial,
                   {"args": args["argv"]}, timeout=int(args.get("timeout_s", 600)) + 30)
        return json.dumps({"serial": serial, "rc": res.get("rc"),
                           "stdout": res.get("stdout", "").strip(),
                           "stderr": res.get("stderr", "").strip()}, ensure_ascii=False, indent=2)
    if name == "phone_skill":
        return http("GET", "/skill", timeout=30)["skill"]
    if name == "lease_device":
        d = http("POST", "/devices/%s/lease" % args["serial"],
                 {"owner": args.get("owner", "mcp"), "ttl": int(args.get("ttl_s", 600))}, timeout=30)
        return json.dumps(d, ensure_ascii=False)
    if name == "release_device":
        d = http("POST", "/devices/%s/release" % args["serial"], {}, timeout=30)
        return json.dumps(d, ensure_ascii=False)
    raise RuntimeError("未知工具: %s" % name)


def reply(msg_id, result=None, error=None):
    m = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        m["error"] = error
    else:
        m["result"] = result
    sys.stdout.write(json.dumps(m, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            continue
        method, mid = req.get("method"), req.get("id")
        params = req.get("params") or {}
        try:
            if method == "initialize":
                reply(mid, {"protocolVersion": params.get("protocolVersion", "2024-11-05"),
                            "capabilities": {"tools": {}},
                            "serverInfo": SERVER_INFO})
            elif method in ("notifications/initialized", "initialized"):
                continue
            elif method == "tools/list":
                reply(mid, {"tools": TOOLS})
            elif method == "tools/call":
                text = call_tool(params.get("name"), params.get("arguments") or {})
                reply(mid, {"content": [{"type": "text", "text": text}], "isError": False})
            elif method == "ping":
                reply(mid, {})
            else:
                reply(mid, error={"code": -32601, "message": "未知方法 %s" % method})
        except Exception as e:
            reply(mid, error={"code": -32000, "message": str(e)})


if __name__ == "__main__":
    main()
