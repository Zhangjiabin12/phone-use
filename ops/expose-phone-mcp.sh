#!/bin/bash
# 把手机工具面以网络 MCP 暴露（FastMCP over streamable-http，端口 8903）
set -u
echo "== 1) 建 venv 并装 fastmcp（走内网镜像）=="
UV=/opt/webui-mcp/uv/uv
[ -x "$UV" ] || UV=$(command -v uv)
mkdir -p /opt/phone-mcp
if [ ! -x /opt/phone-mcp/venv/bin/python ]; then
  $UV venv /opt/phone-mcp/venv --python 3.12 2>&1 | tail -2
fi
/opt/phone-mcp/venv/bin/python -c "import fastmcp" 2>/dev/null || \
  $UV pip install --python /opt/phone-mcp/venv/bin/python fastmcp \
     --index-url https://mirrors.aliyun.com/pypi/simple/ 2>&1 | tail -3
/opt/phone-mcp/venv/bin/python -c "import fastmcp;print('  fastmcp', fastmcp.__version__)"

echo
echo "== 2) 写服务：包装已有工具面（复用 phone-hub-mcp 的实现）=="
cat > /opt/phone-mcp/phone-mcp-http.py <<'PY'
#!/usr/bin/env python3
"""phone-mcp —— 把手机工具面以网络 MCP 暴露（streamable-http）。

工具与 stdio 版 phone-hub-mcp 一致：devices_list / phone_exec / phone_task /
phone_skill / lease_device / release_device。实现复用同一份代码，避免两套逻辑。
可选鉴权：环境变量 PHONE_MCP_TOKEN 非空时，要求请求带 Authorization: Bearer <token>。
"""
import importlib.util
import os

from fastmcp import FastMCP

HUB_MCP = os.environ.get("PHONE_HUB_MCP", "/usr/local/share/phone-hub/phone-hub-mcp.py")
spec = importlib.util.spec_from_file_location("hub_mcp", HUB_MCP)
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)          # 该模块仅在 __main__ 下才起 stdio 循环

mcp = FastMCP("phone-use")


@mcp.tool
def devices_list() -> dict:
    """列出手机终端：serial、状态、可用性(usable)、后端、能力集、占用情况。"""
    return hub.call_tool("devices_list", {})


@mcp.tool
def phone_task(text: str, device: str = "auto", max_steps: int | None = None,
               timeout_s: int = 600) -> dict:
    """给一句话任务（连网/认证/取证等）。返回 verdict(PASS/FAIL/ANSWER/TIMEOUT/BLOCKED)、
    serial、steps、elapsed、trace 与答复原文；超时返回 job 号供继续查询。"""
    args = {"text": text, "device": device, "timeout_s": timeout_s}
    if max_steps:
        args["max_steps"] = max_steps
    return hub.call_tool("phone_task", args)


@mcp.tool
def phone_exec(serial: str, argv: list[str], timeout_s: int = 600) -> dict:
    """在指定终端执行一条原语，例如 argv=["wifi"]、["probe"]、["tap","540","600"]。"""
    return hub.call_tool("phone_exec", {"serial": serial, "argv": argv, "timeout_s": timeout_s})


@mcp.tool
def phone_skill() -> dict:
    """取任务手册（认证路线、成功判据、机型注意事项）。"""
    return hub.call_tool("phone_skill", {})


@mcp.tool
def lease_device(serial: str, owner: str, ttl_s: int = 1800) -> dict:
    """独占一台终端。被他人持有时返回 409。"""
    return hub.call_tool("lease_device", {"serial": serial, "owner": owner, "ttl": ttl_s})


@mcp.tool
def release_device(serial: str, owner: str) -> dict:
    """释放终端。"""
    return hub.call_tool("release_device", {"serial": serial, "owner": owner})


if __name__ == "__main__":
    host = os.environ.get("PHONE_MCP_HOST", "0.0.0.0")
    port = int(os.environ.get("PHONE_MCP_PORT", "8903"))
    mcp.run(transport="streamable-http", host=host, port=port)
PY
chmod 755 /opt/phone-mcp/phone-mcp-http.py
/opt/phone-mcp/venv/bin/python -c "import ast;ast.parse(open('/opt/phone-mcp/phone-mcp-http.py').read());print('  语法 OK')"

echo
echo "== 3) systemd 单元 =="
cat > /etc/systemd/system/phone-mcp.service <<'UNIT'
[Unit]
Description=phone-mcp —— 手机工具面 MCP（streamable-http :8903）
After=network.target phone-hub.service

[Service]
Type=simple
EnvironmentFile=-/usr/local/share/phone-farm/farm.env
EnvironmentFile=-/opt/phone-mcp/mcp.env
ExecStart=/opt/phone-mcp/venv/bin/python /opt/phone-mcp/phone-mcp-http.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable phone-mcp >/dev/null 2>&1 || true
systemctl restart phone-mcp; sleep 6
echo "  phone-mcp=$(systemctl is-active phone-mcp)"
journalctl -u phone-mcp -n 5 --no-pager | tail -4

echo
echo "== 4) 立即验证 tools/list（秒级，不跑任务）=="
python3 - <<'PY'
import json, urllib.request
url = "http://127.0.0.1:8903/mcp"
def call(payload, sid=None, extra=None):
    h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    if sid: h["Mcp-Session-Id"] = sid
    if extra: h.update(extra)
    r = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=h)
    with urllib.request.urlopen(r, timeout=20) as resp:
        return resp.headers.get("Mcp-Session-Id"), resp.read().decode("utf-8", "replace")
try:
    sid, body = call({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                      "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                                 "clientInfo": {"name": "verify", "version": "1"}}})
    print("  initialize OK, session =", sid)
    call({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid=sid)
    _, body = call({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, sid=sid)
    txt = body.split("data: ", 1)[-1] if "data: " in body else body
    d = json.loads(txt.strip().splitlines()[-1])
    print("  工具面:", [t["name"] for t in d["result"]["tools"]])
except Exception as e:
    print("  验证失败:", type(e).__name__, str(e)[:200])
PY
