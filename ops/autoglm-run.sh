#!/bin/bash
# Open-AutoGLM 轻量视觉 agent 试跑（独立 venv，不影响现有服务）
exec > /tmp/autoglm-run.log 2>&1
set -x
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
cd /opt/autoglm/Open-AutoGLM

echo "=== 1) 独立 venv 安装（只装 openai + Pillow）==="
[ -x /opt/autoglm/venv/bin/python ] || python3 -m venv /opt/autoglm/venv
/opt/autoglm/venv/bin/pip install -q --upgrade pip 2>&1 | tail -1
/opt/autoglm/venv/bin/pip install -q -r requirements.txt 2>&1 | tail -3
/opt/autoglm/venv/bin/python -c "import openai, PIL; print('openai', openai.__version__, '| Pillow', PIL.__version__)"

echo
echo "=== 2) CLI 用法 ==="
/opt/autoglm/venv/bin/python main.py --help 2>&1 | head -30
set +x

echo
echo "=== 3) 指向我们的网关 + K20（root，动作层最省事）跑一句 ==="
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
export PHONE_AGENT_BASE_URL=http://131.255.36.100:30001/v1
export PHONE_AGENT_MODEL=deepseek-flash
export PHONE_AGENT_API_KEY="$KEY"
export PHONE_AGENT_DEVICE_ID=57ada8
export PHONE_AGENT_DEVICE_TYPE=adb
export PHONE_AGENT_LANG=cn
export PHONE_AGENT_MAX_STEPS=10
echo "  模型=$PHONE_AGENT_MODEL  设备=$PHONE_AGENT_DEVICE_ID  key长度=${#KEY}"
timeout 420 /opt/autoglm/venv/bin/python main.py "打开设置，进入 WLAN 页面，告诉我当前连接的是哪个 WiFi" 2>&1 | tail -60
echo "AUTOGLM_RUN_DONE rc=$?"
