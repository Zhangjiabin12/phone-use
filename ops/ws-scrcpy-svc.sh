#!/bin/bash
echo "== 安装进度 =="
tail -6 /tmp/ws-scrcpy.log
echo "  node_modules: $(ls /opt/ws-scrcpy/node_modules 2>/dev/null | wc -l) 个包"
echo "  dist: $(ls /opt/ws-scrcpy/dist 2>/dev/null | wc -l) 个文件"
echo "  安装脚本还在跑? $(pgrep -f ws-scrcpy-install.sh >/dev/null && echo 是 || echo 否)"
echo
if [ -d /opt/ws-scrcpy/dist ] && [ "$(ls /opt/ws-scrcpy/dist 2>/dev/null | wc -l)" -gt 0 ]; then
  echo "== 构建已完成，建 systemd 服务 =="
  cat > /etc/systemd/system/ws-scrcpy.service <<'UNIT'
[Unit]
Description=ws-scrcpy —— 浏览器里的 scrcpy（H.264 视频流 + 触控/按键转发）
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/ws-scrcpy
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=3
Environment=WS_SCRCPY_PORT=8000
Environment=ADB_PATH=adb

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload; systemctl enable ws-scrcpy >/dev/null 2>&1
  systemctl restart ws-scrcpy; sleep 6
  systemctl is-active ws-scrcpy
  journalctl -u ws-scrcpy -n 8 --no-pager | tail -8
  curl -s -m 8 -o /dev/null -w "  HTTP :8000 → %{http_code}\n" http://127.0.0.1:8000/
else
  echo "== 还在安装/构建中，先不动服务 =="
fi
