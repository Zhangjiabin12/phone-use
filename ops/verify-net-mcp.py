#!/usr/bin/env python3
"""验证网络 MCP：tools/list + 一条 phone_task（经 8903）"""
import json
import sys
import urllib.request

URL = "http://127.0.0.1:8903/mcp"


def rpc(payload, sid=None, timeout=60):
    h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    if sid:
        h["Mcp-Session-Id"] = sid
    req = urllib.request.Request(URL, data=json.dumps(payload).encode(), headers=h)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.headers.get("Mcp-Session-Id"), r.read().decode("utf-8", "replace")


def parse(body):
    txt = body.split("data: ", 1)[-1] if "data: " in body else body
    for line in reversed(txt.strip().splitlines()):
        line = line.strip()
        if line.startswith("{"):
            return json.loads(line)
    return {}


sid, _ = rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                         "clientInfo": {"name": "verify", "version": "1"}}})
rpc({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid=sid)
_, b = rpc({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, sid=sid)
tools = [t["name"] for t in parse(b)["result"]["tools"]]
print("TOOLS", tools)

with open("/tmp/mcpnet.out", "w", encoding="utf-8") as f:
    f.write("TOOLS %s\n" % tools)
    f.flush()
    try:
        _, b = rpc({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                    "params": {"name": "phone_task",
                               "arguments": {"text": "一句话：现在几台手机在线？不要做别的。",
                                             "timeout_s": 300, "max_steps": 6}}}, sid=sid, timeout=400)
        d = parse(b)
        c = d.get("result", {}).get("content") or [{}]
        t = c[0].get("text") if isinstance(c[0], dict) else str(c[0])
        if isinstance(t, str):
            try:
                t = json.loads(t)
            except Exception:
                pass
        f.write("PHONE_TASK %s\n" % json.dumps(t, ensure_ascii=False)[:600])
    except Exception as e:
        f.write("PHONE_TASK_ERR %s %s\n" % (type(e).__name__, str(e)[:200]))
    f.write("MCPNET_DONE\n")
print("DONE")
