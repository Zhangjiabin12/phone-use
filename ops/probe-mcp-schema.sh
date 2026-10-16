#!/bin/bash
SET=/home/phonebot/.qwen/settings.json
echo "== 加一个 http 型 MCP 看它写进 settings.json 的结构 =="
sudo -iu phonebot bash -lc 'qwen mcp add phone-use-net http://127.0.0.1:8903/mcp -t http -s user --trust' 2>&1 | tail -3
echo "--- settings.json 里的 mcpServers ---"
python3 -c "
import json
d=json.load(open('$SET',encoding='utf-8'))
print(json.dumps(d.get('mcpServers'), ensure_ascii=False, indent=2))
"
echo "== 移除验证用的条目，恢复原状 =="
sudo -iu phonebot bash -lc 'qwen mcp remove phone-use-net' 2>&1 | tail -2
python3 -c "
import json
d=json.load(open('$SET',encoding='utf-8'))
print(json.dumps(d.get('mcpServers'), ensure_ascii=False, indent=2))
"
echo "== qwen mcp list 的显示形式 =="
sudo -iu phonebot bash -lc 'cd /opt/phone-use/pu && qwen mcp list' 2>&1 | head -6
