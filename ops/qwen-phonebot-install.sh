#!/bin/bash
# 给 phonebot 装 Qwen Code，并做最小权限验收（无 sudo、改不了原件、能跑我们的原语）
exec > /tmp/qwen-phonebot.log 2>&1
rm -f /tmp/qwen-phonebot.done
set -x
URL=https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen-standalone.sh

echo "=== 1) 先验收 phonebot 的权限边界（关键：不能提权）==="
id phonebot
echo -n "  sudo 可用? "; sudo -u phonebot bash -lc 'command -v sudo && sudo -n true 2>&1 | head -1' || echo "(没有 sudo 或不可用)"
echo -n "  能否读 root 私有的 bu.env: "; sudo -u phonebot bash -lc 'head -c 1 /opt/webui-mcp/bu/bu.env 2>&1 | head -1'
echo -n "  能否写 base（应被拒）: "; sudo -u phonebot bash -lc 'echo x >> /opt/phone-use/base/SKILL.md' 2>&1 | head -1

echo
echo "=== 2) 以 phonebot 身份装 Qwen Code（官方 standalone 安装器）==="
sudo -iu phonebot bash -lc "curl -fsSL '$URL' | bash" 2>&1 | tail -8
echo -n "  装好没: "; sudo -u phonebot bash -lc 'command -v qwen || ls ~/.local/bin/qwen 2>/dev/null || echo 未找到'
echo -n "  版本: "; sudo -u phonebot bash -lc 'qwen --version 2>&1 | head -1'

echo
echo "=== 3) 把 pu 项目目录与 work 交给 phonebot（项目级配置）==="
PU=/opt/phone-use/pu
chown -R phonebot:phonebot "$PU" /opt/phone-use/work
chmod 600 "$PU/.qwen/settings.json"
# phonebot 自己的环境（key 从项目配置来；这里给直跑 phone-look 兜底 + adb server 指向）
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
HB=$(getent passwd phonebot | cut -d: -f6)
cat > "$HB/.bashrc.qwen" <<RC
export OPENAI_BASE_URL=http://131.255.36.100:30001/v1
export OPENAI_MODEL=deepseek-flash
export OPENAI_API_KEY='$KEY'
export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037
RC
chmod 600 "$HB/.bashrc.qwen"
grep -q bashrc.qwen "$HB/.bashrc" || echo '[ -f ~/.bashrc.qwen ] && . ~/.bashrc.qwen' >> "$HB/.bashrc"
chown phonebot:phonebot "$HB/.bashrc" "$HB/.bashrc.qwen"
echo "  $(ls -ld $PU | awk '{print $1,$3":"$4,$9}')"

echo
echo "=== 4) 权限与能力复验（phonebot）==="
echo -n "  phone-hand state: "; sudo -iu phonebot bash -lc 'ANDROID_SERIAL=CTV0221202007036 phone-hand state 2>&1 | head -c 120'; echo
echo -n "  adb devices(经 TCP server): "; sudo -iu phonebot bash -lc 'adb devices 2>&1 | head -3' | tr '\n' ' '; echo
echo -n "  phone-look（眼睛）: "; sudo -iu phonebot bash -lc 'phone-look CTV0221202007036 "一句话：什么页面" 2>&1 | head -3' | tr '\n' ' '; echo
echo -n "  写 base（应仍被拒）: "; sudo -u phonebot bash -lc 'echo x >> /opt/phone-use/base/SKILL.md' 2>&1 | head -1
echo -n "  写 work（应成功）: "; sudo -iu phonebot bash -lc 'echo ok > /opt/phone-use/work/notes/.p && echo 成功'; rm -f /opt/phone-use/work/notes/.p
echo -n "  sudo -i 提权（应失败）: "; sudo -u phonebot bash -lc 'sudo -i id 2>&1 | head -1'

echo
echo "=== 5) 项目级无头冒烟（phonebot 身份，从 pu 目录进）==="
sudo -iu phonebot bash -lc "cd $PU && timeout 420 qwen -p '(1) 运行 curl -s http://127.0.0.1:8901/devices 并用一句话列出每台 serial/backend/usable；(2) 运行 phone-look CTV0221202007036 \"一句话：现在是什么页面？\" 并复述结论。不做别的。' --approval-mode yolo 2>&1 | tail -25"
echo QWEN_PHONEBOT_DONE > /tmp/qwen-phonebot.done
