#!/bin/bash
exec > /tmp/ws-node16.log 2>&1
set -x
export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
SYS_NODE=$(node -v); echo "系统 node（不动它）: $SYS_NODE"

echo "== 1) 便携版 Node 16 到 /opt/node16（不动系统 node）=="
mkdir -p /opt/node16
if [ ! -x /opt/node16/bin/node ]; then
  curl -fL --retry 3 --max-time 600 -o /tmp/node16.tar.xz \
    https://nodejs.org/dist/v16.20.2/node-v16.20.2-linux-x64.tar.xz
  ls -l /tmp/node16.tar.xz
  tar -xJf /tmp/node16.tar.xz -C /opt/node16 --strip-components=1
fi
/opt/node16/bin/node -v; /opt/node16/bin/npm -v
echo "  系统 node 仍是: $(node -v)"

echo "== 2) 看正确构建脚本 =="
python3 - <<'PY'
import json
d=json.load(open('/opt/ws-scrcpy/package.json'))
print('  name=%s version=%s' % (d.get('name'), d.get('version')))
for k,v in d.get('scripts',{}).items(): print('   %-14s %s' % (k,v))
print('  engines:', d.get('engines'))
PY

echo "== 3) 用 Node16 重装依赖并构建 =="
cd /opt/ws-scrcpy
export PATH=/opt/node16/bin:$PATH
rm -rf node_modules
npm install --no-audit --no-fund 2>&1 | tail -6
for cmd in build:prod build dist; do
  python3 -c "import json,sys;sys.exit(0 if '$cmd' in json.load(open('package.json')).get('scripts',{}) else 1)" || continue
  echo "--- npm run $cmd"
  timeout 1200 npm run "$cmd" 2>&1 | tail -12
  n=$(ls dist 2>/dev/null | wc -l); echo "--- dist=$n"
  [ "$n" -gt 0 ] && break
done
ls dist 2>/dev/null | head -8
[ "$(ls dist 2>/dev/null | wc -l)" -gt 0 ] || { echo "构建仍未产出 dist"; echo WS_NODE16_FAIL; exit 1; }

echo "== 4) 服务（显式用 /opt/node16/bin/node）=="
cat > /etc/systemd/system/ws-scrcpy.service <<'UNIT'
[Unit]
Description=ws-scrcpy —— 浏览器里的 scrcpy（H.264，用便携 Node16，不影响系统 Node）
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/ws-scrcpy
ExecStart=/opt/node16/bin/node dist/index.js
Restart=always
RestartSec=3
Environment=WS_SCRCPY_PORT=8000
Environment=PATH=/opt/node16/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable ws-scrcpy >/dev/null 2>&1
systemctl restart ws-scrcpy; sleep 10
echo "  服务: $(systemctl is-active ws-scrcpy)"
ss -ltnp | grep 8000 | awk '{print "  监听 "$4}'
curl -s -m 8 -o /dev/null -w "  HTTP :8000 → %{http_code}\n" http://127.0.0.1:8000/
journalctl -u ws-scrcpy -n 12 --no-pager | tail -12
echo "  系统 node 依旧: $(node -v)"
echo WS_NODE16_DONE
