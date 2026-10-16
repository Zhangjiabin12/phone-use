#!/bin/bash
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
IMG=${1:-/tmp/k20_report_57ada8.png}
[ -f "$IMG" ] || { echo "  截图不存在: $IMG"; exit 1; }
echo "  用图: $IMG ($(stat -c%s "$IMG") 字节)"
python3 /tmp/vision_test.py http://131.255.36.100:30001/v1 "$KEY" "$IMG"