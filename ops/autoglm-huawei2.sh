#!/bin/bash
exec > /tmp/autoglm-hw2.log 2>&1
DEV=CTV0221202007036
echo "=== A) 它到底怎么检查的（找源码）==="
cd /opt/autoglm/Open-AutoGLM
grep -rn "ADB Keyboard" . 2>/dev/null | grep -v '\.git/' | head -5
grep -rln "adbkeyboard\|AdbIME" . 2>/dev/null | grep -v '\.git/' | head -8
python3 - <<'PY'
import subprocess
r = subprocess.run(["grep", "-rn", "-A12", "Checking ADB Keyboard", "/opt/autoglm/Open-AutoGLM"],
                   capture_output=True, text=True)
print(r.stdout[:1500] or "  (没找到该字符串)")
PY

echo
echo "=== B) 判断验证：导出 ANDROID_SERIAL 让它只盯华为，再跑 ==="
export ANDROID_SERIAL=$DEV
echo "  ANDROID_SERIAL=$ANDROID_SERIAL"
echo -n "  裸 adb 现在指向: "; adb shell getprop ro.product.model 2>&1 | tr -d '\r'
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
export PHONE_AGENT_BASE_URL=http://131.255.36.100:30001/v1 PHONE_AGENT_MODEL=deepseek-flash \
       PHONE_AGENT_API_KEY="$KEY" PHONE_AGENT_DEVICE_ID=$DEV PHONE_AGENT_DEVICE_TYPE=adb \
       PHONE_AGENT_LANG=cn PHONE_AGENT_MAX_STEPS=8
timeout 780 /opt/autoglm/venv/bin/python main.py "打开设置，进入 WLAN 页面，告诉我当前连接的是哪个 WiFi" 2>&1 | tail -80
echo "AUTOGLM_HW2_DONE"
