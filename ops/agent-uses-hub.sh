#!/bin/bash
echo "=== 1) agent 侧：怎么问 8901 ==="
grep -n 'HUB\|devices_list\|/devices' /usr/local/share/phone-agent/phone-agent.py 2>/dev/null | grep -vE '^\s*#' | head -14
echo
echo "=== 2) agent 侧：挑终端的判据 ==="
sed -n '/def choose_device\|def pick_device\|def select_device/,/^def /p' /usr/local/share/phone-agent/phone-agent.py 2>/dev/null | head -30
echo
echo "=== 3) 工具说明里给 LLM 的原话（devices_list）==="
python3 - <<'PY'
import re
p='/usr/local/share/phone-agent/phone-agent.py'
try:
    t=open(p,encoding='utf-8').read()
except Exception as e:
    print('  读不到:',e); raise SystemExit
m=re.search(r'"devices_list".*?\}', t, re.S)
print('  ',(m.group(0)[:600] if m else '未找到 devices_list 定义'))
PY
echo
echo "=== 4) hub 侧：/devices 给出的判定字段 ==="
curl -s http://127.0.0.1:8901/devices | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  概览:', {k:d[k] for k in ('online','idle','busy','usable','count') if k in d})
for x in d['devices']:
    print('  %-16s usable=%-5s 可用(无人值守)=%-5s backend=%-16s 能连网=%-5s busy=%-5s blockers=%s' % (
        x['serial'], x['usable'], x.get('unattended_ready'), x['backend'], x.get('wifi_cmd_ok'),
        x['state']=='busy', [b['id'] for b in x['blockers']] or '无'))
"
echo
echo "=== 5) runbook（8901 的 /skill 供出）里对 agent 的强制要求 ==="
curl -s http://127.0.0.1:8901/skill | python3 -c "
import json,sys,re
t=json.load(sys.stdin)['skill']
for kw in ('usable','不能自动连网','必须先','blockers','体检'):
    for m in re.finditer(r'.{0,70}'+kw+r'.{0,90}', t):
        print('  …'+m.group(0).replace(chr(10),' ')+'…'); break
"
