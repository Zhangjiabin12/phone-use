#!/bin/bash
exec > /tmp/qwen-setup.log 2>&1
set -x
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890

echo "=== 1) 装 Qwen Code（全局 npm，走代理）==="
npm i -g @qwen-code/qwen-code 2>&1 | tail -4
command -v qwen && qwen --version 2>&1 | head -2

echo
echo "=== 2) 建 phonebot（非 root，物理只读的关键）==="
id phonebot >/dev/null 2>&1 || useradd -m -s /bin/bash phonebot
usermod -aG plugdev phonebot 2>/dev/null || true
mkdir -p /opt/phone-use/work/{copies,adapt,notes,.qwen}
chown -R phonebot:phonebot /opt/phone-use/work
echo "  用户: $(id phonebot)"
echo "  base 权限（phonebot 只读）: $(stat -c '%A %U:%G' /opt/phone-use/base)"

echo
echo "=== 3) phonebot 能不能用我们的原语 + 能不能碰 adb ==="
sudo -u phonebot bash -lc 'ANDROID_SERIAL=CTV0221202007036 phone-hand state 2>&1 | head -c 160' ; echo
echo -n "  phonebot 直接 adb devices: "; sudo -u phonebot bash -lc 'adb devices 2>&1 | head -3' | tr '\n' ' '; echo
echo -n "  phonebot 走 root 的 adb server（TCP）: "
sudo -u phonebot bash -lc 'export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037; adb devices 2>&1 | head -4' | tr '\n' ' '; echo
echo -n "  phonebot 能否写 base（应被拒）: "
sudo -u phonebot bash -lc 'echo x >> /opt/phone-use/base/SKILL.md' 2>&1 | head -1
echo -n "  phonebot 能否写 work（应成功）: "
sudo -u phonebot bash -lc 'echo ok > /opt/phone-use/work/notes/.probe && echo 成功'
rm -f /opt/phone-use/work/notes/.probe

echo
echo "=== 4) Qwen Code 配置：环境变量 + system.md（系统提示词）==="
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
HOME_DIR=$(getent passwd phonebot | cut -d: -f6)
mkdir -p "$HOME_DIR/.qwen"
cp -f /opt/phone-use/base/AGENT-PROMPT.md "$HOME_DIR/.qwen/system.md"
cat > "$HOME_DIR/.qwen/settings.json" <<JSON
{
  "env": {
    "OPENAI_API_KEY": "$KEY",
    "OPENAI_BASE_URL": "http://131.255.36.100:30001/v1",
    "OPENAI_MODEL": "deepseek-flash"
  }
}
JSON
chown -R phonebot:phonebot "$HOME_DIR/.qwen"
chmod 600 "$HOME_DIR/.qwen/settings.json"
echo "  system.md: $(wc -c < "$HOME_DIR/.qwen/system.md") 字节（= AGENT-PROMPT.md）"
echo "  settings.json 键: $(python3 -c "import json;print(list(json.load(open('$HOME_DIR/.qwen/settings.json'))['env'].keys()))")"

cat > "$HOME_DIR/.bashrc.qwen" <<'RC'
export OPENAI_BASE_URL=http://131.255.36.100:30001/v1
export OPENAI_MODEL=deepseek-flash
export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037
RC
grep -q 'bashrc.qwen' "$HOME_DIR/.bashrc" || echo '[ -f ~/.bashrc.qwen ] && . ~/.bashrc.qwen' >> "$HOME_DIR/.bashrc"
chown phonebot:phonebot "$HOME_DIR/.bashrc" "$HOME_DIR/.bashrc.qwen"

echo
echo "=== 5) 无头模式冒烟测试（一句话，看它能否读到我们的环境）==="
sudo -iu phonebot bash -lc 'cd /opt/phone-use/work && timeout 300 qwen -p "只做一件事：运行 curl -s http://127.0.0.1:8901/devices 并把结果里每台设备的 serial/backend/usable 列出来。不要做别的。" 2>&1 | tail -25'
echo QWEN_SETUP_DONE
