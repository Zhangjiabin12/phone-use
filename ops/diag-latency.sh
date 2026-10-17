#!/bin/bash
echo "== 耗时 =="
echo -n "  hub  /devices : "; curl -s -o /dev/null -w "%{time_total}s http=%{http_code}\n" -m 180 http://127.0.0.1:8901/devices
echo -n "  wall /api/devices : "; curl -s -o /dev/null -w "%{time_total}s http=%{http_code}\n" -m 180 http://127.0.0.1:8910/api/devices

echo
echo "== wall 里对 hub /devices 的超时设置 =="
grep -n 'hub("GET", "/devices' /usr/local/share/phone-wall/phone-wall.py | head -4

echo
echo "== 把 wall 的超时放宽到 180s，并给 hub 的 /devices 加 5 秒内存缓存 =="
python3 - <<'PY'
import ast, re
p='/usr/local/share/phone-wall/phone-wall.py'
s=open(p,encoding='utf-8').read()
s2=re.sub(r'hub\("GET", "/devices"([^)]*?)timeout=\d+', lambda m: 'hub("GET", "/devices"%s timeouts=180' % m.group(1), s)
PY
