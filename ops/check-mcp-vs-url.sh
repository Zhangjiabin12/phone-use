#!/bin/bash
echo "== A) .60 上的 phone-mcp 在不在、从 102 能不能到 =="
timeout 6 bash -c 'cat < /dev/null > /dev/tcp/126.255.255.60/8006' 2>/dev/null && echo "  TCP 126.255.255.60:8006 可达" || echo "  TCP 126.255.255.60:8006 不可达（从 102）"
timeout 8 curl -s -o /dev/null -w "  HTTP :8006 → %{http_code}\n" http://126.255.255.60:8006/ 2>/dev/null || echo "  HTTP :8006 无响应"
if timeout 12 ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@126.255.255.60 'systemctl is-active phone-mcp; ls -d /opt/phone-mcp 2>/dev/null' 2>/dev/null; then :; else echo "  （102 → .60 的 ssh 不通或未授权，无法直查）"; fi

echo
echo "== B) 8902 同步 /task 与异步 /tasks 的判语是否一致（同一只读任务）=="
T='一句话：现在几台手机可用？不要做别的。'
echo "  --- 同步 POST /task ---"
curl -s -m 300 -X POST -H 'Content-Type: application/json' -d "{\"text\":\"$T\"}" http://127.0.0.1:8902/task 2>/dev/null | python3 -c "
import json,sys
t=sys.stdin.read()
try:
    r=(json.loads(t).get('result') or json.loads(t))
    print('    verdict=%s serial=%s delegated=%s keys=%s' % (r.get('verdict'), r.get('serial'), r.get('delegated'), sorted(r.keys())))
except Exception: print('    ✗', t[:200])
"
echo "  --- 异步 POST /tasks + 轮询 ---"
JOB=$(curl -s -m 30 -X POST -H 'Content-Type: application/json' -d "{\"text\":\"$T\"}" http://127.0.0.1:8902/tasks 2>/dev/null | python3 -c "
import json,sys
try: print(json.load(sys.stdin).get('job') or '')
except Exception: print('')
")
echo "    job=$JOB"
if [ -n "$JOB" ]; then
  for i in $(seq 1 40); do
    sleep 6
    R=$(curl -s -m 15 http://127.0.0.1:8902/tasks/$JOB 2>/dev/null)
    echo "$R" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin); print('    status=%s verdict=%s steps=%s elapsed=%s keys=%s' % (d.get('status'), d.get('verdict'), d.get('steps'), d.get('elapsed'), sorted(d.keys())))
except Exception as e: print('    (解析失败)', sys.stdin)
" 2>/dev/null | tail -1
    echo "$R" | grep -q '"status": *"done"\|"status":"done"' && break
  done
  echo "    --- 作业返回的答复原文（截断）---"
  curl -s -m 15 http://127.0.0.1:8902/tasks/$JOB | python3 -c "
import json,sys
d=json.load(sys.stdin); a=str(d.get('answer') or d.get('result') or '')
print('   ', a[-300:].replace(chr(10),' | '))
"
fi
