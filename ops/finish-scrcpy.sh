#!/bin/bash
# 代理已可用，用它把 ws-scrcpy 装完并起服务
exec > /tmp/ws-scrcpy2.log 2>&1
set -x
export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890 all_proxy=socks5://127.0.0.1:7890
cd /opt/ws-scrcpy
echo "npm proxy=$(npm config get proxy)"
npm install --no-audit --no-fund 2>&1 | tail -6
npm run dist 2>&1 | tail -8
ls dist 2>/dev/null | head -6
[ "$(ls dist 2>/dev/null | wc -l)" -gt 0 ] || exit 1

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
systemctl is-active ws-scrcpy
ss -ltnp | grep 8000 | awk '{print "  监听 "$4}'
curl -s -m 8 -o /dev/null -w "  HTTP :8000 → %{http_code}\n" http://127.0.0.1:8000/
journalctl -u ws-scrcpy -n 10 --no-pager | tail -10
echo WS_SCRCPY_DONE
