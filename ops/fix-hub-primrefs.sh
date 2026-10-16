#!/bin/bash
echo "== 1) hub/wall/MCP 到底怎么调原语的 =="
for f in /usr/local/share/phone-hub/phone-hub.py /usr/local/share/phone-hub/phone-hub-mcp.py /usr/local/share/phone-wall/phone-wall.py /usr/local/share/phone-use/pu-node.py; do
  [ -f "$f" ] || continue
  echo "--- $(basename $f) ---"
  grep -nE 'phone-use|phone-hand|PRIM|PU_CMD|\[.?python3.*phone' "$f" 2>/dev/null | head -6
done

echo
echo "== 2) 把所有仍在调 phone-use 原语的地方改成 phone-hand =="
python3 - <<'PY'
import re, os
targets = ['/usr/local/share/phone-hub/phone-hub.py',
           '/usr/local/share/phone-hub/phone-hub-mcp.py',
           '/usr/local/share/phone-wall/phone-wall.py']
for p in targets:
    if not os.path.exists(p):
        continue
    s = open(p, encoding='utf-8').read()
    orig = s
    # 任何指向原语可执行文件的写法
    s = s.replace('"phone-use"', '"phone-hand"').replace("'phone-use'", "'phone-hand'")
    s = re.sub(r'\bphone-use(?=\s+["\']?(?:state|wifi|list|scan|probe|failure|backend|ui|find|click|settext|scroll|global|tap|swipe|key|input|shot|pull|http|shell|jar|wifi-connect|wifi-forget))',
               'phone-hand', s)
    s = s.replace('/usr/local/bin/phone-use', '/usr/local/bin/phone-hand')
    s = s.replace('/usr/local/share/phone-use/phone-use.py', '/opt/phone-use/base/phone-hand.py')
    if s != orig:
        open(p, 'w', encoding='utf-8').write(s)
        print("  已改:", p)
    else:
        print("  未改（本来就没直接引用）:", p)
PY
echo
echo "== 3) 语法与守卫检查 =="
python3 -c "import ast;[ast.parse(open(p).read()) for p in ['/usr/local/share/phone-hub/phone-hub.py','/usr/local/share/phone-wall/phone-wall.py','/usr/local/share/phone-hub/phone-hub-mcp.py'] ];print('  三个服务语法 OK')"
systemctl restart phone-hub phone-wall; sleep 4
echo "  hub=$(systemctl is-active phone-hub)  wall=$(systemctl is-active phone-wall)"
echo
echo "== 4) 端到端：经 hub 的 exec 调原语（应走 phone-hand，不是派任务）=="
curl -s -m 60 -X POST -H 'Content-Type: application/json' -d '{"args":["wifi"],"owner":"rename-check"}' http://127.0.0.1:8901/devices/57ada8/exec 2>/dev/null | head -c 260; echo
echo
echo "== 5) MCP 工具面仍可用吗 =="
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | timeout 30 python3 /usr/local/share/phone-hub/phone-hub-mcp.py 2>/dev/null | python3 -c "import json,sys;d=json.loads(sys.stdin.readline());print('  MCP 工具:',[t['name'] for t in d['result']['tools']])" 2>/dev/null || echo "  (MCP 自检跳过)"
