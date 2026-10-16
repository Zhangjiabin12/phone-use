#!/bin/bash
exec > /tmp/ws-build.log 2>&1
set -x
export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
cd /opt/ws-scrcpy
echo "== package.json scripts =="
python3 -c "import json;d=json.load(open('package.json'));[print('  %-18s %s'%(k,v)) for k,v in d.get('scripts',{}).items()]"
echo "== 依赖是否装齐 =="
ls node_modules | wc -l
[ -d node_modules/webpack ] && echo "  webpack ✓" || echo "  webpack ✗"
echo
echo "== 按存在的脚本依次构建 =="
for cmd in build:prod build dist; do
  if python3 -c "import json,sys;sys.exit(0 if '$cmd' in json.load(open('package.json')).get('scripts',{}) else 1)"; then
    echo "--- npm run $cmd"
    timeout 900 npm run "$cmd" 2>&1 | tail -15
    echo "--- dist: $(ls dist 2>/dev/null | wc -l) 个文件"
    [ "$(ls dist 2>/dev/null | wc -l)" -gt 0 ] && break
  fi
done
ls dist 2>/dev/null | head -8
[ "$(ls dist 2>/dev/null | wc -l)" -gt 0 ] || { echo "构建未产出 dist"; exit 1; }

cat > /etc/systemd/system/ws-scrcpy.service <<'UNIT'
[Unit]
Description=ws-scrcpy —— 浏览器里的 scrcpy（H.264 视频流 + 触控/按键）
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/ws-scrcpy
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=3
Environment=WS_SCRCPY_PORT=8000
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable ws-scrcpy >/dev/null 2>&1
systemctl restart ws-scrcpy; sleep 8
echo "服务: $(systemctl is-active ws-scrcpy)"
ss -ltnp | grep 8000 | awk '{print "  监听 "$4}'
curl -s -m 8 -o /dev/null -w "  HTTP :8000 → %{http_code}\n" http://127.0.0.1:8000/
journalctl -u ws-scrcpy -n 8 --no-pager | tail -8
echo WS_BUILD_DONE
