#!/bin/bash
echo "== 8902 路由 =="
grep -nE "path *== *['\"]|path\.startswith" /usr/local/share/phone-agent/phone-agent.py | head -14
echo
echo "== 实测各路由 =="
for r in / /health /task /tasks /jobs; do
  printf "  %-9s GET=%s  POST=%s\n" "$r" \
    "$(curl -s -m 6 -o /dev/null -w '%{http_code}' http://127.0.0.1:8902$r)" \
    "$(curl -s -m 6 -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:8902$r)"
done
echo
echo "== 代码里是否还有异步作业实现 =="
grep -nE 'def .*job|JOBS|/tasks|cancel' /usr/local/share/phone-agent/phone-agent.py | head -12
