#!/bin/bash
exec > /tmp/autoglm-hw.log 2>&1
DEV=CTV0221202007036
echo "=== 0) 前置状态确认 ==="
echo -n "  当前默认输入法: "; adb -s $DEV shell settings get secure default_input_method
echo -n "  ADBKeyboard 已启用: "; adb -s $DEV shell settings get secure enabled_input_methods | grep -c adbkeyboard
echo -n "  坐标注入可用(input tap): "; adb -s $DEV shell 'input tap 1 1; echo rc=$?' 2>&1 | tr -d '\r' | tr '\n' ' '; echo

echo
echo "=== 1) 原版 AutoGLM + deepseek-flash 跑一单（华为）==="
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
cd /opt/autoglm/Open-AutoGLM
export PHONE_AGENT_BASE_URL=http://131.255.36.100:30001/v1 \
       PHONE_AGENT_MODEL=deepseek-flash \
       PHONE_AGENT_API_KEY="$KEY" \
       PHONE_AGENT_DEVICE_ID=$DEV \
       PHONE_AGENT_DEVICE_TYPE=adb \
       PHONE_AGENT_LANG=cn \
       PHONE_AGENT_MAX_STEPS=8
timeout 900 /opt/autoglm/venv/bin/python main.py "打开设置，进入 WLAN 页面，告诉我当前连接的是哪个 WiFi" 2>&1 | tail -100
echo "RC=$?"
echo "=== 2) 跑完抓一张现场图 ==="
ANDROID_SERIAL=$DEV phone-hand shot /sdcard/ag_after.png >/dev/null 2>&1
ANDROID_SERIAL=$DEV phone-hand pull /sdcard/ag_after.png /tmp/ag_after.png >/dev/null 2>&1
ls -l /tmp/ag_after.png 2>/dev/null
echo "AUTOGLM_HW_DONE"
