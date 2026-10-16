#!/bin/bash
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
cd /opt/autoglm
[ -d madeagents-mobileuse/.git ] || { rm -rf madeagents-mobileuse; git clone --depth 1 https://github.com/MadeAgents/mobile-use.git madeagents-mobileuse 2>&1 | tail -2; }
cd madeagents-mobileuse || { echo "克隆失败"; exit 1; }
echo "=== 1) 结构 ==="
ls -1 | head -18
find . -maxdepth 2 -type d -not -path './.git*' | sort | head -16
echo "--- 依赖 ---"; sed -n '1,30p' requirements.txt 2>/dev/null | head -30
echo
echo "=== 2) 它要求什么模型（关键：能不能用我们的 deepseek-flash）==="
grep -rniE "gpt-4|gpt-4o|gemini|claude|qwen|api_key|base_url|OPENAI" --include='*.md' --include='*.py' --include='*.yaml' --include='*.yml' --include='*.toml' --include='*.sh' . 2>/dev/null | grep -v '\.git/' | head -18
echo
echo "=== 3) 脑子：提示词在哪、长什么样 ==="
grep -rln "You are\|system_prompt\|SYSTEM_PROMPT\|prompt" --include='*.py' --include='*.txt' --include='*.md' . 2>/dev/null | grep -v '\.git/' | head -10
for f in $(grep -rl "You are" --include='*.py' --include='*.txt' . 2>/dev/null | grep -v '\.git/' | head -3); do
  echo "--- $f ---"; sed -n '1,45p' "$f"
done
echo
echo "=== 4) 动作格式（决定 deepseek-flash 能不能被解析）==="
grep -rnE "class Action|Action\(|json.loads|parse_action|tool_call|functions=|response_format" --include='*.py' . 2>/dev/null | grep -v '\.git/' | head -14
echo
echo "=== 5) 循环（分层反思）==="
grep -rnE "class .*Agent|def run|while |max_step|reflect|plan" --include='*.py' . 2>/dev/null | grep -v '\.git/' | head -16
echo
echo "=== 6) 输入文字/截图/是否需要额外 App ==="
grep -rniE "adbkeyboard|ADB Keyboard|input text|screencap|uiautomator|androidworld|emulator" --include='*.py' --include='*.md' --include='*.yaml' . 2>/dev/null | grep -v '\.git/' | head -14
echo
echo "=== 7) README 开头（安装与运行门槛）==="
sed -n '1,40p' README.md 2>/dev/null
