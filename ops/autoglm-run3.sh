#!/bin/bash
exec > /tmp/autoglm-run3.log 2>&1
set -x
DEV=CTV0221202007036        # 华为：允许 adb 装 + 允许坐标注入
echo "=== 1) 华为装上 ADBKeyboard ==="
adb -s $DEV push /tmp/ADBKeyboard.apk /data/local/tmp/ 2>&1 | tail -1
adb -s $DEV install -r /tmp/ADBKeyboard.apk 2>&1 | tail -2
adb -s $DEV shell pm list packages | grep -i adbkeyboard
echo "=== 2) 启用输入法 ==="
adb -s $DEV shell ime enable com.android.adbkeyboard/.AdbIME 2>&1 | tail -1
adb -s $DEV shell ime set com.android.adbkeyboard/.AdbIME 2>&1 | tail -1
adb -s $DEV shell settings get secure default_input_method
set +x

echo
echo "=== 3) 用华为跑 Open-AutoGLM（deepseek-flash）==="
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
cd /opt/autoglm/Open-AutoGLM
export PHONE_AGENT_BASE_URL=http://131.255.36.100:30001/v1 PHONE_AGENT_MODEL=deepseek-flash \
       PHONE_AGENT_API_KEY="$KEY" PHONE_AGENT_DEVICE_ID=$DEV PHONE_AGENT_DEVICE_TYPE=adb \
       PHONE_AGENT_LANG=cn PHONE_AGENT_MAX_STEPS=8
timeout 600 /opt/autoglm/venv/bin/python main.py "打开设置，进入 WLAN 页面，告诉我当前连接的是哪个 WiFi" 2>&1 | tail -80
echo "AUTOGLM3_DONE"
