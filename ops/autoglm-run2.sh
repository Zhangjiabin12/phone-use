#!/bin/bash
exec > /tmp/autoglm-run2.log 2>&1
set -x
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
DEV=57ada8
echo "=== 1) 装 ADBKeyboard（框架要求，仅装在这一台做验证）==="
[ -f /tmp/ADBKeyboard.apk ] || curl -fL --max-time 120 -o /tmp/ADBKeyboard.apk \
  https://github.com/senzhk/ADBKeyBoard/raw/master/ADBKeyboard.apk
ls -l /tmp/ADBKeyboard.apk
adb -s $DEV install -r /tmp/ADBKeyboard.apk 2>&1 | tail -2
echo "=== 2) 启用该输入法（shell 就能做，无需手点）==="
adb -s $DEV shell ime enable com.android.adbkeyboard/.AdbIME 2>&1 | tail -1
adb -s $DEV shell ime set com.android.adbkeyboard/.AdbIME 2>&1 | tail -1
adb -s $DEV shell settings get secure default_input_method
set +x

echo
echo "=== 3) 跑任务（Open-AutoGLM + deepseek-flash + K20）==="
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
cd /opt/autoglm/Open-AutoGLM
export PHONE_AGENT_BASE_URL=http://131.255.36.100:30001/v1 PHONE_AGENT_MODEL=deepseek-flash \
       PHONE_AGENT_API_KEY="$KEY" PHONE_AGENT_DEVICE_ID=$DEV PHONE_AGENT_DEVICE_TYPE=adb \
       PHONE_AGENT_LANG=cn PHONE_AGENT_MAX_STEPS=10
timeout 480 /opt/autoglm/venv/bin/python main.py "打开设置，进入 WLAN 页面，告诉我当前连接的是哪个 WiFi" 2>&1 | tail -70
echo "AUTOGLM2_DONE"
