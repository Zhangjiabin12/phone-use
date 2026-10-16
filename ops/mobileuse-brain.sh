#!/bin/bash
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
cd /opt/autoglm
[ -d mobile-use/.git ] || { rm -rf mobile-use; git clone --depth 1 https://github.com/mnotgod96/mobile-use.git 2>&1 | tail -2; }
cd mobile-use || exit 1
echo "=== 1) 仓库结构 ==="
ls -1 | head -20
echo "--- 子目录 ---"; find . -maxdepth 2 -type d -not -path './.git*' | sort | head -18
echo "--- 依赖 ---"; sed -n '1,25p' requirements.txt 2>/dev/null; ls pyproject.toml setup.py 2>/dev/null

echo
echo "=== 2) 它的“脑子”＝系统提示词在哪 ==="
grep -rln "You are\|system_prompt\|SYSTEM_PROMPT" --include='*.py' --include='*.md' --include='*.txt' . 2>/dev/null | grep -v '\.git/' | head -8
for f in $(grep -rl "You are an\|You are a" --include='*.py' . 2>/dev/null | grep -v '\.git/' | head -2); do
  echo "--- $f（前 40 行）---"; sed -n '1,40p' "$f"
done

echo
echo "=== 3) 动作格式：JSON / 函数调用 / ReAct ==="
grep -rnE "json_schema|tools=|function_call|tool_choice|<\||Action:|action_type" --include='*.py' . 2>/dev/null | grep -v '\.git/' | head -12

echo
echo "=== 4) 循环与步数 ==="
grep -rnE "max_steps|while True|for step|def run\(|def step\(" --include='*.py' . 2>/dev/null | grep -v '\.git/' | head -12

echo
echo "=== 5) 模型配置（能不能指任意 OpenAI 兼容端点）==="
grep -rnE "base_url|api_key|model_name|MODEL|ChatOpenAI|openai\.|genai|google" --include='*.py' --include='*.md' . 2>/dev/null | grep -v '\.git/' | head -14

echo
echo "=== 6) 要不要 ADBKeyboard / 怎么输入文字 / 怎么截图 ==="
grep -rniE "adbkeyboard|ADB Keyboard" . 2>/dev/null | grep -v '\.git/' | head -5
grep -rnE "input text|uiautomator dump|screencap|dump_hierarchy|device\.tap|swipe" --include='*.py' . 2>/dev/null | grep -v '\.git/' | head -12

echo
echo "=== 7) README 用法（前 30 行）==="
sed -n '1,30p' README.md 2>/dev/null
