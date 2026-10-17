#!/bin/bash
echo "== 耗时 =="
echo -n "  hub  /devices      : "; curl -s -o /dev/null -w "%{time_total}s http=%{http_code}\n" -m 200 http://127.0.0.1:8901/devices
echo -n "  hub  /devices/57ada8: "; curl -s -o /dev/null -w "%{time_total}s http=%{http_code}\n" -m 200 http://127.0.0.1:8901/devices/57ada8
echo -n "  wall /api/devices  : "; curl -s -o /dev/null -w "%{time_total}s http=%{http_code}\n" -m 200 http://127.0.0.1:8910/api/devices
echo
echo "== wall 调 hub 的超时参数 =="
grep -n 'hub("GET", "/devices' /usr/local/share/phone-wall/phone-wall.py | head -5
echo
echo "== wall 的 /api/devices 处理 =="
grep -n 'api/devices' -A 6 /usr/local/share/phone-wall/phone-wall.py | head -12
