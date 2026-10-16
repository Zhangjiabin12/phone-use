#!/bin/bash
# 把 Qwen Code 装成手机 agent 的「脑子」（phonebot 非 root，项目级配置，底层只读）
# 用法：以 root 执行；前提是 /opt/phone-use/base 已就位（见 ops/install-frozen-base.sh）
set -e
PU=/opt/phone-use/pu
QURL=https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen-standalone.sh

echo "== 1) 建 phonebot（非 root、无 sudo；物理只读底层的关键）=="
id phonebot >/dev/null 2>&1 || useradd -m -s /bin/bash phonebot
usermod -aG plugdev phonebot 2>/dev/null || true

echo "== 2) 以 phonebot 身份装 Qwen Code（官方 standalone 安装器）=="
sudo -iu phonebot bash -lc "command -v qwen >/dev/null || curl -fsSL '$QURL' | bash"
sudo -u phonebot bash -lc 'qwen --version' | sed 's/^/  qwen /'

echo "== 3) 项目级目录（.qwen 放在工作目录 → 项目级，不是用户级）=="
mkdir -p "$PU"/{.qwen/agents,logs}
cp -f /opt/phone-use/base/AGENT-PROMPT.md "$PU/.qwen/system.md"          # 系统提示词
[ -f "$PU/.qwen/agents/wlan-runner.md" ] || cp -f "$(dirname "$0")/qwen-agents/wlan-runner.md" "$PU/.qwen/agents/" 2>/dev/null || true
# settings 模板（key 需自行填入）
if [ ! -f "$PU/.qwen/settings.json" ]; then
  cp -f "$(dirname "$0")/qwen-project-settings.template.json" "$PU/.qwen/settings.json" 2>/dev/null || \
  cat > "$PU/.qwen/settings.json" <<'JSON'
{
  "env": { "OPENAI_API_KEY": "<填网关 key>",
           "OPENAI_BASE_URL": "http://131.255.36.100:30001/v1",
           "OPENAI_MODEL": "deepseek-flash" },
  "mcpServers": { "phone-hub": { "command": "/usr/bin/python3",
      "args": ["/usr/local/share/phone-hub/phone-hub-mcp.py"],
      "env": {"PHONE_HUB_BASE": "http://127.0.0.1:8901"}, "trust": true } },
  "model": { "visionModel": "deepseek-flash", "visionModelFallback": "glm-5.3-flash" },
  "memory": { "enableAutoSkill": true, "enableManagedAutoMemory": true, "enableManagedAutoDream": true }
}
JSON
fi

echo "== 4) 权限：pu/work 归 phonebot；base 保持 root 只读 =="
chown -R phonebot:phonebot "$PU" /opt/phone-use/work
chmod 600 "$PU/.qwen/settings.json"
chown -R root:root /opt/phone-use/base && chmod -R a-w /opt/phone-use/base

echo "== 5) 视觉能力补丁（models.dev 的表把 deepseek-flash 记成不支持图像；实测能看图）=="
/opt/phone-use/tools/fix-vision-registry.sh || true

echo "== 6) 标准入口 pu-run =="
install -m 755 "$(dirname "$0")/pu-run" /usr/local/bin/pu-run

echo
echo "装完自检："
echo -n "  phonebot 无 sudo: "; sudo -u phonebot bash -lc 'sudo -n true 2>&1 | head -1'
echo -n "  改不了原件: "; sudo -u phonebot bash -lc 'echo x >> /opt/phone-use/base/SKILL.md' 2>&1 | head -1
echo -n "  qwen 可用: "; sudo -iu phonebot bash -lc 'qwen --version'
echo    "  入口示例: pu-run \"连 test-portal2 做 portal 认证，账号 zjb 密码 123456\" --timeout 900"
