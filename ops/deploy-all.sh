#!/bin/bash
# 部署 v4.1（双后端）+ STF 对齐的 hub + MCP
set -e
cp -f /tmp/phone-use-v4.py /usr/local/share/phone-use/phone-use.py
cp -f /tmp/phone-hub.py /usr/local/share/phone-hub/phone-hub.py
cp -f /tmp/phone-hub-mcp.py /usr/local/share/phone-hub/phone-hub-mcp.py
chmod +x /usr/local/share/phone-use/phone-use.py /usr/local/share/phone-hub/phone-hub-mcp.py
rm -rf /usr/local/share/phone-use/__pycache__
systemctl restart phone-hub
sleep 5
echo "== 两台终端的后端与能力集 =="
curl -s -m 20 http://127.0.0.1:8901/api/v1/devices | python3 -c "
import json,sys
for d in json.load(sys.stdin)['devices']:
    print('%-16s %-10s %-12s AND%-3s backend=%-16s jar=%-5s root=%s' % (
        d['serial'], d['stf_state'], (d['model'] or '?')[:12], d['android'], d['backend'], d['jar_ready'], d['root']))
    print('    能力:', ','.join(d['capabilities'])[:150])
    print('    Wi-Fi:', d['wifi_ssid'], d['wifi_ip'])
"
echo
echo "== STF 风格租约：POST/DELETE /api/v1/user/devices/<serial> =="
R=$(adb devices < /dev/null | awk 'NR>1 && $2=="device"{print $1}' | head -1)
curl -s -X POST -H 'Content-Type: application/json' -d '{"owner":"ai","ttl":120}' \
  "http://127.0.0.1:8901/api/v1/user/devices/$R" | python3 -c "import json,sys; d=json.load(sys.stdin); print('  own:', d['ok'], d['device']['stf_state'], d['device']['owner'])"
curl -s "http://127.0.0.1:8901/api/v1/user/devices?owner=ai" | python3 -c "import json,sys; print('  owner=ai 持有:', [d['serial'] for d in json.load(sys.stdin)['devices']])"
curl -s -X DELETE "http://127.0.0.1:8901/api/v1/user/devices/$R" | python3 -c "import json,sys; d=json.load(sys.stdin); print('  release:', d['ok'], d['device']['stf_state'])"
echo
echo "== MCP 自检（initialize / tools/list / tools/call）=="
printf '%s\n%s\n%s\n' \
 '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
 '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
 '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"devices_list","arguments":{}}}' \
 | python3 /usr/local/share/phone-hub/phone-hub-mcp.py | python3 -c "
import json,sys
for line in sys.stdin:
    m=json.loads(line)
    if m.get('id')==1: print('  initialize →', m['result']['serverInfo'])
    if m.get('id')==2: print('  tools:', [t['name'] for t in m['result']['tools']])
    if m.get('id')==3:
        txt=m['result']['content'][0]['text']
        d=json.loads(txt)
        print('  devices_list →', [(x['serial'], x['stf_state'], x['backend']) for x in d['devices']])
"
