#!/bin/bash
exec > /tmp/qwen-proj.log 2>&1
set -x
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890

echo "=== 0) qwen 装好了吗 ==="
command -v qwen || npm i -g @qwen-code/qwen-code 2>&1 | tail -3
qwen --version 2>&1 | head -2

echo
echo "=== 1) 建 pu 项目目录（项目级 .qwen，从这里进无头）==="
PU=/opt/phone-use/pu
mkdir -p "$PU"/{.qwen/agents,logs}
cp -f /opt/phone-use/base/AGENT-PROMPT.md "$PU/.qwen/system.md"          # 系统提示词（项目级）
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
cat > "$PU/.qwen/settings.json" <<JSON
{
  "env": {
    "OPENAI_API_KEY": "$KEY",
    "OPENAI_BASE_URL": "http://131.255.36.100:30001/v1",
    "OPENAI_MODEL": "deepseek-flash"
  }
}
JSON
cat > "$PU/.qwen/agents/wlan-runner.md" <<'AGENT'
---
name: wlan-runner
description: 专门跑一条 WLAN 用例：读 runbook → 选机 → 连网/认证 → 取证 → 给结论
tools: [run_shell_command, read_file, write_file, replace, glob, search_file_content]
---
你是 WLAN 用例执行子 agent。开工前先 `cat /opt/phone-use/base/SKILL.md` 的「怎么看/怎么点」一节；
只用 phone-use / phone-look；判定按 runbook 的成功判据；最后输出 RESULT: PASS|FAIL + 证据块。
AGENT
cat > "$PU/README.md" <<'MD'
# pu —— 手机 WLAN agent 的工作目录（Qwen Code 项目级）

无头入口（就在本目录跑，`.qwen/` 是项目级配置）：
```bash
sudo -iu phonebot
cd /opt/phone-use/pu
qwen -p "连 test-portal2 做 portal 认证，账号 zjb 密码 123456" --approval-mode yolo
```
- `.qwen/system.md`   ：系统提示词（项目级，= 底层 AGENT-PROMPT.md）
- `.qwen/settings.json`：项目级模型配置（OpenAI 兼容 → deepseek-flash）
- `.qwen/agents/`     ：子 agent（wlan-runner）
- `logs/`             ：每次无头运行的输出留档

边界：手机动作只用 `phone-use` / `phone-look`；底层 `/opt/phone-use/base/**` 只读，要改复制到 `/opt/phone-use/work/copies/`。
MD
# 用户级配置让位（避免与项目级混淆）
HOME_DIR=$(getent passwd phonebot | cut -d: -f6)
[ -d "$HOME_DIR/.qwen" ] && mv -f "$HOME_DIR/.qwen" "$HOME_DIR/.qwen.bak.$(date +%s)"
chown -R phonebot:phonebot "$PU"
chmod 600 "$PU/.qwen/settings.json"
echo "  项目结构:"; find "$PU" -maxdepth 3 -printf '    %M %u:%g %p\n' | head -12

echo
echo "=== 2) 无头冒烟测试：从 pu 目录进，验证它能读环境+用我们的命令 ==="
sudo -iu phonebot bash -lc "cd $PU && timeout 420 qwen -p '只做两件事：(1) 运行 curl -s http://127.0.0.1:8901/devices 并用一句话列出每台设备的 serial/backend/usable；(2) 运行 phone-look CTV0221202007036 \"一句话：现在是什么页面？\" 并复述结论。不要做别的。' --approval-mode yolo 2>&1 | tail -30"
echo QWEN_PROJ_DONE
