#!/bin/bash
cp -f /tmp/phone-hub.py /usr/local/share/phone-hub/phone-hub.py
cp -f /tmp/phone-wall-svc.py /usr/local/share/phone-wall/phone-wall.py
cp -f /tmp/wall-page.html /usr/local/share/phone-wall/wall-page.html
cp -f /tmp/phone-use-v4.py /usr/local/share/phone-use/phone-use.py
python3 - <<'EOF'
import ast
for f in ('/usr/local/share/phone-hub/phone-hub.py','/usr/local/share/phone-wall/phone-wall.py','/usr/local/share/phone-use/phone-use.py'):
    ast.parse(open(f).read())
print('语法 OK')
EOF
systemctl restart phone-hub; sleep 55
systemctl restart phone-wall; sleep 3
systemctl is-active phone-hub phone-agent phone-wall | tr '\n' ' '; echo

echo
echo "== 分辨率（墙上坐标映射要用的）=="
curl -s http://127.0.0.1:8901/devices | python3 -c "
import json,sys
for d in json.load(sys.stdin)['devices']:
    print('  %-16s %-13s 屏幕 %sx%s  屏幕开着=%s' % (d['serial'], d['model'], d.get('screen_w'), d.get('screen_h'), d.get('screen_display_on')))"

echo
echo "== 系统按键接口实测（华为）=="
for k in back home app_switch notifications; do
  printf '  %-14s → ' "$k"
  curl -s -m 60 -X POST -H 'Content-Type: application/json' -d "{\"serial\":\"CTV0221202007036\",\"key\":\"$k\"}" \
    http://127.0.0.1:8910/api/key | head -c 160; echo
done

echo
echo "== scan 解析（华为格式）修复验证 =="
ANDROID_SERIAL=CTV0221202007036 timeout 90 phone-hand scan | python3 -c "
import json,sys
r=json.load(sys.stdin)['results']
print('  扫到 %d 个；前 3：' % len(r), [(x['ssid'] or '(隐藏)', x['freq_mhz'], x['rssi']) for x in r[:3]])"
