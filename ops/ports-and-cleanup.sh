#!/bin/bash
echo "=== A) ws-scrcpy 从 8000 挪到 8920（归入 89xx 有序段）==="
cat > /etc/systemd/system/ws-scrcpy.service <<'UNIT'
[Unit]
Description=ws-scrcpy —— 浏览器里的 scrcpy（H.264，便携 Node16，端口 8920）
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/ws-scrcpy
ExecStart=/opt/node16/bin/node dist/index.js
Restart=always
RestartSec=3
Environment=WS_SCRCPY_PORT=8920
Environment=PATH=/opt/node16/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl stop ws-scrcpy 2>/dev/null; sleep 1
systemctl restart ws-scrcpy; sleep 10
echo "  ws-scrcpy: $(systemctl is-active ws-scrcpy)"
ss -ltnp | grep -E ':(8000|8920)' | awk '{print "  监听 "$4}' || echo "  8920 未监听"

echo
echo "=== B) 清理不需要的服务（8899 旧投屏等）==="
for u in phone-view phone-view2; do
  if systemctl list-unit-files | grep -q "^$u"; then
    systemctl stop $u 2>/dev/null; systemctl disable $u 2>/dev/null
    echo "  已停用 $u"
  fi
done
# 8899 若还有残留进程（非 systemd）也停掉
PIDS=$(ss -ltnp 2>/dev/null | grep ':8899' | grep -oP 'pid=\K[0-9]+' | sort -u)
[ -n "$PIDS" ] && { kill $PIDS 2>/dev/null; echo "  已结束占用 8899 的进程: $PIDS"; } || echo "  8899 已无监听"
# 清掉安装/排查用的临时脚本
rm -f /tmp/mihomo*.log /tmp/ws-*.log /tmp/hw-portal.log /tmp/third-phone.log /tmp/node16.tar.xz /tmp/mihomo.gz 2>/dev/null
echo "  已清理临时文件"

echo
echo "=== C) 端口总表（有序）==="
echo "  ── 89xx 手机农场段 ──"
printf "  %-6s %-14s %s\n" 8901 phone-hub "农场 API（清单/能力/租约/体检/exec）"
printf "  %-6s %-14s %s\n" 8902 phone-agent "一句话总入口（LLM agent）"
printf "  %-6s %-14s %s\n" 8910 phone-wall "手机墙（页面：高清画面+按键+派任务+体检）"
printf "  %-6s %-14s %s\n" 8920 ws-scrcpy "H.264 视频流后端（被 8910 嵌入）"
echo "  ── 其它 ──"
printf "  %-6s %-14s %s\n" 7890 mihomo "出网代理（规则分流）"
echo
echo "=== D) 逐端口探活 ==="
for p in 8901 8902 8910 8920 7890; do
  printf "  :%s → %s\n" "$p" "$(curl -s -m 6 -o /dev/null -w '%{http_code}' http://127.0.0.1:$p/ 2>/dev/null)"
done
echo "  8899（应已关闭）→ $(curl -s -m 4 -o /dev/null -w '%{http_code}' http://127.0.0.1:8899/ 2>/dev/null || echo 关闭)"
echo "=== 系统 node 未动: $(/usr/bin/node -v) / 便携: $(/opt/node16/bin/node -v) ==="
