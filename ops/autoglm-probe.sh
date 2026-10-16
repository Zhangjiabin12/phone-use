#!/bin/bash
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
mkdir -p /opt/autoglm && cd /opt/autoglm
if [ ! -d Open-AutoGLM/.git ]; then
  rm -rf Open-AutoGLM
  git clone --depth 1 https://github.com/zai-org/Open-AutoGLM.git 2>&1 | tail -2
fi
cd Open-AutoGLM || exit 1
echo "== 顶层结构 =="
ls -1 | head -25
echo
echo "== 目录 =="
find . -maxdepth 2 -type d -not -path './.git*' | sort | head -20
echo
echo "== 入口与依赖 =="
ls -1 *.py *.txt *.md 2>/dev/null | head -15
echo "--- requirements.txt ---"; head -25 requirements.txt 2>/dev/null
echo
echo "== 怎么配模型（找 base_url / api_key / model）=="
grep -rInE 'base_url|OPENAI|api_key|MODEL|model_name' --include='*.py' --include='*.md' --include='*.yaml' --include='*.json' . 2>/dev/null | grep -v '\.git/' | head -20
echo
echo "== 怎么下发动作（找 adb / tap / swipe）=="
grep -rInE 'adb shell|input tap|input swipe|def tap|def swipe|screencap' --include='*.py' . 2>/dev/null | grep -v '\.git/' | head -16
echo
echo "== 有没有现成的配置模板 =="
find . -name '*.example' -o -name '*config*' -o -name '.env*' | grep -v '\.git/' | head -10
