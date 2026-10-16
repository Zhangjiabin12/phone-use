#!/bin/bash
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
cd /opt/autoglm/Open-AutoGLM

echo "=== A) ADBKeyboard 到底卡在哪：装 vs 启用 ==="
DEV=CTV0221202007036
echo -n "  包是否已装: "; adb -s $DEV shell pm list packages | grep -c adbkeyboard
echo -n "  ime list 是否列出: "; adb -s $DEV shell ime list -a -s 2>/dev/null | grep -c 'com.android.adbkeyboard/.AdbIME'
echo -n "  当前默认输入法: "; adb -s $DEV shell settings get secure default_input_method
echo -n "  已启用输入法列表: "; adb -s $DEV shell settings get secure enabled_input_methods
echo "  试着直接写 enabled_input_methods（shell 有 WRITE_SECURE_SETTINGS 才行）:"
adb -s $DEV shell settings put secure enabled_input_methods 'com.android.adbkeyboard/.AdbIME' 2>&1 | tail -2
echo -n "  写后查询: "; adb -s $DEV shell settings get secure enabled_input_methods
echo -n "  带 --user 0 再 enable 一次: "; adb -s $DEV shell ime enable --user 0 com.android.adbkeyboard/.AdbIME 2>&1 | tail -1

echo
echo "=== B) AutoGLM 的检查函数与设备接口（改哪里）==="
grep -rn "ADB Keyboard\|ADBKeyboard\|check_system\|requirements" --include='*.py' . | head -8
echo "--- device_factory.py 的接口 ---"
grep -nE "^class |def [a-z_]+\(|BACKEND|adb|hdc" phone_agent/device_factory.py | head -25
echo "--- adb/device.py 暴露的动作 ---"
grep -nE "^def [a-z_]+\(" phone_agent/adb/device.py | head -30

echo
echo "=== C) mobile-use 探一探 ==="
cd /opt/autoglm
if [ ! -d mobile-use/.git ]; then rm -rf mobile-use; git clone --depth 1 https://github.com/mnotgod96/mobile-use.git 2>&1 | tail -2; fi
cd mobile-use 2>/dev/null && {
  echo "  顶层: $(ls -1 | tr '\n' ' ' | cut -c1-200)"
  echo "  依赖: $(head -12 requirements.txt 2>/dev/null | tr '\n' ' ' | cut -c1-260)"
  echo "  找 ADBKeyboard 依赖: $(grep -ril 'adbkeyboard\|ADB Keyboard' . 2>/dev/null | grep -v '\.git/' | head -5 | tr '\n' ' ')"
  echo "  输入文字怎么做的: $(grep -rnE 'input text|ADB_INPUT|broadcast|settext' --include='*.py' . 2>/dev/null | grep -v '\.git/' | head -6 | cut -c1-400)"
  echo "  模型/端点配置: $(grep -rnE 'base_url|OPENAI_API|MODEL|api_key' --include='*.py' --include='*.md' --include='*.yaml' . 2>/dev/null | grep -v '\.git/' | head -6 | cut -c1-400)"
  echo "  README 用法前 20 行:"; sed -n '1,20p' README.md 2>/dev/null | sed 's/^/    /'
}
