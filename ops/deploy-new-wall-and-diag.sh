#!/bin/bash
set -u
echo "===== 1) 部署新版手机墙页面 ====="
BK=/usr/local/share/phone-wall/wall-page.html.bak-$(date +%F-%H%M)
cp -f /usr/local/share/phone-wall/wall-page.html "$BK" && echo "  已备份: $BK"
install -m 644 /tmp/wall-page.html /usr/local/share/phone-wall/wall-page.html
echo "  落位: $(stat -c '%A %U:%G %s' /usr/local/share/phone-wall/wall-page.html)"
systemctl restart phone-wall; sleep 3
echo "  服务: $(systemctl is-active phone-wall)  http=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8910/)"
echo -n "  /screen/57ada8 → "; curl -s -o /dev/null -w "http=%{http_code} type=%{content_type} size=%{size_download}\n" http://127.0.0.1:8910/screen/57ada8

echo
echo "===== 2) K20(57ada8) 为什么不可用：现场字段 ====="
curl -s -m 20 http://127.0.0.1:8901/devices/57ada8 | python3 -c "
import json,sys
d=json.load(sys.stdin)
keys=['serial','present','ready','usable','state','backend','root','cmd_wifi_connect','wifi_cmd_ok','wifi_cmd_error','blockers','unattended_ready','blocker_hint','doctor_hint','wifi_ssid','stf_state','lease','input_inject','su']
for k in keys:
    if k in d: print('  %-20s %s' % (k, json.dumps(d[k], ensure_ascii=False)[:220]))
print('  capabilities:', d.get('capabilities'))
" 2>&1 | head -30

echo
echo "===== 3) 真机侧核对：su 是否还有权限 ====="
echo -n "  adb root? "; adb -s 57ada8 shell id 2>&1 | head -1
echo -n "  su 可用? "; adb -s 57ada8 shell "su -c id" 2>&1 | head -1
echo -n "  cmd wifi 权限? "; adb -s 57ada8 shell cmd wifi status 2>&1 | head -2
echo -n "  connect-network 试跑: "; adb -s 57ada8 shell cmd wifi connect-network __probe__ open 2>&1 | head -2

echo
echo "===== 4) 体检（57ada8）====="
timeout 180 phone-doctor 57ada8 2>&1 | tail -30
