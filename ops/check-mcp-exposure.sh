#!/bin/bash
echo "== 1) phone-hub-mcp.py 的传输方式与工具面 =="
grep -nE 'FastMCP|mcp\.run|stdio|sse|streamable|transport|host=|port=|@mcp\.tool|def ' /usr/local/share/phone-hub/phone-hub-mcp.py 2>/dev/null | head -20
echo
echo "== 2) 有没有对外监听的 MCP 端点 =="
ss -ltnp 2>/dev/null | grep -E 'LISTEN' | awk '{print "  "$4"  "$6}' | grep -vE '127.0.0.53|:22 ' | head -20
echo
echo "== 3) hub 自身是否提供 /mcp 路由 =="
curl -s -m 6 -o /dev/null -w "  hub /mcp → %{http_code}\n" http://127.0.0.1:8901/mcp
curl -s -m 6 http://127.0.0.1:8901/ | python3 -c "import json,sys;d=json.load(sys.stdin);print('  hub 端点:', list(d.keys()))" 2>/dev/null
echo
echo "== 4) qwen 侧接入方式（stdio，本机拉起）=="
python3 -c "
import json;d=json.load(open('/opt/phone-use/pu/.qwen/settings.json',encoding='utf-8'))
print('  mcpServers:', json.dumps(d.get('mcpServers'), ensure_ascii=False)[:300])"
echo
echo "== 5) 其它机器上的手机 MCP（memory 提到 .60:8006）=="
timeout 8 curl -s -o /dev/null -w "  126.255.255.60:8006 → %{http_code}\n" http://126.255.255.60:8006/ 2>/dev/null || echo "  126.255.255.60:8006 不可达"
echo
echo "== 6) bu 的 MCP 形态（对照）=="
grep -nE 'FastMCP|mcp\.run|transport|host|port' /opt/webui-mcp/bu/bu-mcp.py 2>/dev/null | head -8
