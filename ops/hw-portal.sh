#!/bin/bash
S=CTV0221202007036
nohup phone-agent '连 test-portal2 做 portal 认证，账号 zjb 密码 123456；认证完成后确认真的能访问外网，给我结论和证据（SSID/BSSID/IP/门户返回码/截图）' --device $S > /tmp/hw-portal.log 2>&1 &
echo "started pid=$!"
sleep 6
curl -s http://127.0.0.1:8901/devices/$S | python3 -c "
import json,sys
d=json.load(sys.stdin); l=d.get('lease') or {}
print('  占用: owner=%s 剩余=%ss alive=%s' % (l.get('owner'), l.get('remaining_s'), (d.get('lease_alive') or {}).get('alive')))"
