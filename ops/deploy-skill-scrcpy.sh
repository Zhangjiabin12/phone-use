#!/bin/bash
# 1) 部署 runbook（portal 协议优先）
cp -f /tmp/SKILL-phone-use-wlan.md /usr/local/share/phone-use/SKILL.md
echo "runbook: $(wc -c < /usr/local/share/phone-use/SKILL.md) 字节"
curl -s http://127.0.0.1:8901/skill | python3 -c "import json,sys;t=json.load(sys.stdin)['skill'];print('  hub 供出的 runbook 含 C0 协议优先:', 'C0' in t)"
echo
# 2) 后台尝试装 ws-scrcpy（把 scrcpy 的 H.264 搬进浏览器的现成开源项目）
echo "node/npm: $(node -v 2>/dev/null) / $(npm -v 2>/dev/null)"
cat > /tmp/ws-scrcpy-install.sh <<'EOF'
set -x
cd /opt
rm -rf ws-scrcpy
git clone --depth 1 https://github.com/NetrisTV/ws-scrcpy.git 2>&1 | tail -3
cd /opt/ws-scrcpy
npm install --no-audit --no-fund 2>&1 | tail -5
npm run dist 2>&1 | tail -5
ls -l dist 2>/dev/null | head -5
echo "WS_SCRCPY_INSTALL_DONE rc=$?"
EOF
nohup bash /tmp/ws-scrcpy-install.sh > /tmp/ws-scrcpy.log 2>&1 &
echo "ws-scrcpy 安装已在后台启动（日志 /tmp/ws-scrcpy.log）"
