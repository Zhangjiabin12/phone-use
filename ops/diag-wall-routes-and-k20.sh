#!/bin/bash
set -u
echo "== A) wall 支持哪些路由 =="
grep -nE "p == '/|p.startswith\('/|/screen|/api/" /usr/local/share/phone-wall/phone-wall.py 2>/dev/null | head -18

echo
echo "== B) /screen/<serial> 实测（8s 上限）=="
for path in /screen/57ada8 /screen /snapshot/57ada8 /api/screen/57ada8; do
  printf "  %-22s → " "$path"
  curl -s -m 8 -o /dev/null -w "http=%{http_code} type=%{content_type} size=%{size_download}\n" "http://127.0.0.1:8910$path" 2>/dev/null || echo "超时/失败"
done

echo
echo "== C) K20 现场字段 =="
curl -s -m 20 http://127.0.0.1:8901/devices/57ada8 | python3 -c "
import json,sys
d=json.load(sys.stdin)
for k in ['serial','present','ready','usable','state','backend','root','cmd_wifi_connect','wifi_cmd_ok','wifi_cmd_error','blockers','unattended_ready','wifi_ssid','stf_state','lease']:
    if k in d: print('  %-18s %s' % (k, json.dumps(d[k], ensure_ascii=False)[:200]))
print('  capabilities  :', d.get('capabilities'))
"

echo
echo "== D) 真机侧：root / su / cmd wifi 权限 =="
echo -n "  id:              "; adb -s 57ada8 shell id 2>&1 | head -1
echo -n "  su -c id:        "; adb -s 57ada8 shell "su -c id" 2>&1 | head -1
echo -n "  cmd wifi status: "; adb -s 57ada8 shell "cmd wifi status" 2>&1 | head -1
echo -n "  connect-network: "; adb -s 57ada8 shell "cmd wifi connect-network __probe__ open" 2>&1 | head -1
echo -n "  已保存网络数:    "; adb -s 57ada8 shell "cmd wifi list-networks" 2>&1 | wc -l
