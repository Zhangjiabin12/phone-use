#!/bin/bash
set -u
echo "== 补 import subprocess =="
python3 - <<'PY'
p='/usr/local/share/phone-agent/phone-agent.py'
s=open(p,encoding='utf-8').read()
if '\nimport subprocess\n' not in s:
    s=s.replace('import re\n','import re\nimport subprocess\n',1)
    open(p,'w',encoding='utf-8').write(s)
import ast; ast.parse(s); print("  已补，语法 OK")
PY
systemctl restart phone-agent; sleep 4
echo "  phone-agent=$(systemctl is-active phone-agent)"

echo
echo "== 复测 1：8902 收一句话 → 委派新脑子 =="
curl -s -m 420 -X POST -H 'Content-Type: application/json' \
  -d '{"text":"运行 curl -s http://127.0.0.1:8901/devices，一句话列出三台 serial 和 usable。别的不要做。"}' \
  http://127.0.0.1:8902/task > /tmp/t8902.json 2>/dev/null
python3 - <<'PY'
import json
t=open('/tmp/t8902.json',encoding='utf-8').read()
try:
    d=json.loads(t); r=d.get('result') or d
    print("  verdict=%s serial=%s delegated=%s" % (r.get('verdict'), r.get('serial'), r.get('delegated')))
    print("  结论片段:", str(r.get('answer'))[-260:].replace(chr(10),' | '))
except Exception as e:
    print("  解析失败:", t[:300])
PY

echo
echo "== 复测 2：手机墙派任务 =="
curl -s -m 420 -X POST -H 'Content-Type: application/json' -d '{"text":"一句话：现在有几台手机在线、都可用吗？"}' \
  http://127.0.0.1:8910/api/task > /tmp/twall.json 2>/dev/null
head -c 500 /tmp/twall.json; echo

echo
echo "== 复测 3：显式指定终端的委派（--device 生效）=="
curl -s -m 420 -X POST -H 'Content-Type: application/json' -d '{"text":"一句话：这台机器现在什么页面？","device":"CTV0221202007036"}' \
  http://127.0.0.1:8902/task 2>/dev/null | python3 -c "
import json,sys
t=sys.stdin.read()
try:
    r=(json.loads(t).get('result') or json.loads(t))
    print('  serial=%s verdict=%s' % (r.get('serial'), r.get('verdict')))
    print('  结论片段:', str(r.get('answer'))[-220:].replace(chr(10),' | '))
except Exception as e: print('  解析失败:', t[:200])
"
echo SWITCH_DONE
