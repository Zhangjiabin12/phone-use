#!/bin/bash
cd /opt/autoglm/madeagents-mobileuse || exit 1
echo "=== A) 默认提示词文件 ==="
ls -1 mobile_use/default_prompts/
echo "--- operator/主 agent 提示词（前 60 行）---"
for f in mobile_use/default_prompts/*.py; do echo "### $f"; sed -n '1,60p' "$f"; echo; done 2>/dev/null | head -90
echo
echo "=== B) 动作格式（schema / 解析）==="
ls -1 mobile_use/schema/ 2>/dev/null
grep -rnE "class .*Action|ActionType|def parse|json|tap|swipe|type" mobile_use/schema/*.py 2>/dev/null | head -25
echo
echo "=== C) 动作怎么落到设备上（重点：要不要 ADBKeyboard、文字怎么输入）==="
grep -rniE "adbkeyboard|ADB Keyboard|input text|type_text|screencap|uiautomator|send_broadcast" mobile_use/environment/*.py mobile_use/environment/**/*.py 2>/dev/null | head -20
echo
echo "=== D) 配置长什么样（能不能指我们的端点）==="
sed -n '1,30p' configs/multiagent_webui.yaml 2>/dev/null
echo "--- pyproject 依赖 ---"
grep -A20 "dependencies" pyproject.toml 2>/dev/null | head -22
