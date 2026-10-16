#!/bin/bash
echo "== 1) 是否有监听 =="
ss -ltnp 2>/dev/null | grep -E '8903' || echo "  8903 无监听"
echo
echo "== 2) 服务日志 =="
journalctl -u phone-mcp -n 20 --no-pager | tail -12
echo
echo "== 3) FastMCP 4.1 的 run() 签名与可用 transport =="
/opt/phone-mcp/venv/bin/python - <<'PY'
import inspect, fastmcp
print("  fastmcp", fastmcp.__version__)
print("  run 签名:", inspect.signature(fastmcp.FastMCP.run))
try:
    from fastmcp.server.server import Transport
    print("  Transport 取值:", list(getattr(Transport, "__args__", [])))
except Exception as e:
    print("  (Transport 枚举取不到)", e)
PY
