#!/bin/bash
echo "== ws-scrcpy 安装状态 =="
tail -5 /tmp/ws-scrcpy2.log 2>/dev/null
echo "  node_modules: $(ls /opt/ws-scrcpy/node_modules 2>/dev/null | wc -l)  dist: $(ls /opt/ws-scrcpy/dist 2>/dev/null | wc -l)"
pgrep -f finish-scrcpy.sh >/dev/null && echo "  安装脚本: 还在跑" || echo "  安装脚本: 已结束"
echo
if [ "$(ls /opt/ws-scrcpy/dist 2>/dev/null | wc -l)" -gt 0 ]; then
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
  echo "  服务: $(systemctl is-active ws-scrcpy)"
  ss -ltnp | grep 8000 | awk '{print "  监听 "$4}'
  curl -s -m 8 -o /dev/null -w "  HTTP :8000 → %{http_code}\n" http://127.0.0.1:8000/
  journalctl -u ws-scrcpy -n 8 --no-pager | tail -8
else
  echo "== 还没构建完，继续等（npm 走代理中） =="
fi
