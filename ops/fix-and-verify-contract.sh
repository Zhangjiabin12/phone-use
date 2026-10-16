#!/bin/bash
echo "== 1) run_task 定义与委派分支现状 =="
grep -n "def run_task" -A 4 /usr/local/share/phone-agent/phone-agent.py | head -12
echo "--- 委派分支 ---"
grep -n "delegate_to_phone_use" /usr/local/share/phone-agent/phone-agent.py | head -6
echo "--- body 出现的行 ---"
grep -n "body" /usr/local/share/phone-agent/phone-agent.py | head -12
echo
echo "== 2) 立即修复：委派分支改用 max_steps 参数，去掉对 body 的引用 =="
python3 - <<'PY'
import ast, re
p='/usr/local/share/phone-agent/phone-agent.py'
s=open(p,encoding='utf-8').read()
s=s.replace('''        return delegate_to_phone_use(text, device=device, timeout=None,
                                     max_steps=(body or {}).get("max_steps"))''',
'''        return delegate_to_phone_use(text, device=device, timeout=None,
                                     max_steps=(max_steps if "max_steps" in dir() else None))''')
# 更稳妥：直接用局部变量名（若不存在则用 None）
s=re.sub(r'max_steps=\(max_steps if "max_steps" in dir\(\) else None\)', 'max_steps=locals().get("max_steps")', s)
open(p,'w',encoding='utf-8').write(s)
ast.parse(s)
print("  已修（改为 locals().get('max_steps')）")
PY
grep -n "delegate_to_phone_use(text" -A 1 /usr/local/share/phone-agent/phone-agent.py | head -6
systemctl restart phone-agent; sleep 4
echo "  phone-agent=$(systemctl is-active phone-agent)"
echo
echo "== 3) 同步接口验证（字段应含 steps/elapsed/trace/delegated/serial）=="
curl -s -m 300 -X POST -H 'Content-Type: application/json' -d '{"text":"一句话：现在几台手机可用？不要做别的。"}' \
  http://127.0.0.1:8902/task 2>/dev/null | python3 -c "
import json,sys
t=sys.stdin.read()
try:
    d=json.loads(t); r=(d.get('result') or d)
    print('  verdict=%s ok=%s serial=%s delegated=%s steps=%s elapsed=%s' % (r.get('verdict'),r.get('ok'),r.get('serial'),r.get('delegated'),r.get('steps'),r.get('elapsed')))
    print('  keys=%s' % sorted(r.keys()))
    print('  trace=%s' % r.get('trace'))
except Exception as e: print('  ✗', t[:200])
"
echo
echo "== 4) 异步接口验证（POST /tasks → GET /tasks/<job>，键名以实测为准）=="
RESP=$(curl -s -m 30 -X POST -H 'Content-Type: application/json' -d '{"text":"一句话：几台手机可用？","max_steps":8}' http://127.0.0.1:8902/tasks 2>/dev/null)
echo "  提交返回: $(echo "$RESP" | head -c 200)"
JOB=$(echo "$RESP" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('job_id') or d.get('job') or d.get('id') or '')" 2>/dev/null)
echo "  job=$JOB"
if [ -n "$JOB" ]; then
  for i in $(seq 1 30); do
    sleep 5
    R=$(curl -s -m 15 http://127.0.0.1:8902/tasks/$JOB 2>/dev/null)
    ST=$(echo "$R" | python3 -c "import json,sys;print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
    echo "    轮询$i status=$ST"
    [ "$ST" = "done" ] || [ "$ST" = "failed" ] || [ "$ST" = "cancelled" ] && { echo "$R" | python3 -c "
import json,sys
d=json.load(sys.stdin); r=(d.get('result') or d)
print('  最终 verdict=%s steps=%s elapsed=%s serial=%s delegated=%s' % (r.get('verdict'),r.get('steps'),r.get('elapsed'),r.get('serial'),r.get('delegated')))
print('  keys=%s' % sorted(r.keys()))
"; break; }
  done
fi
