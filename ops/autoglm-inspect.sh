#!/bin/bash
cd /opt/autoglm/Open-AutoGLM
echo "=== 1) 谁在什么时候调用系统检查（判断“每次启动都检验？”）==="
grep -rn "check_system\|Checking ADB Keyboard\|check_requirements\|def check" --include='*.py' . | grep -v '\.git/' | head -12
echo "--- main.py 里的调用点前后 ---"
grep -n "check\|requirements\|sys.exit" main.py | head -12

echo
echo "=== 2) 检查函数的实现（怎么判断 ADBKeyboard 装了没）==="
F=$(grep -rl "ADB Keyboard is not installed" --include='*.py' . | grep -v '\.git/' | head -1)
echo "  文件: $F"
[ -n "$F" ] && grep -n -B6 -A22 "ADB Keyboard is not installed" "$F" | head -60

echo
echo "=== 3) 解析层（要加容错的地方）==="
sed -n '345,395p' phone_agent/actions/handler.py

echo
echo "=== 4) 动作层接口（要接我们原语的地方）==="
grep -nE "^def [a-z_]+\(|^    def [a-z_]+\(" phone_agent/adb/device.py | head -30
echo "--- tap / type_text 的实现 ---"
grep -n -A12 "^def tap" phone_agent/adb/device.py | head -20
grep -n -A14 "def type_text\|def send_text\|def input_text" phone_agent/adb/device.py | head -22
