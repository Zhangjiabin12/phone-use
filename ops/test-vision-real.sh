#!/bin/bash
# 用真手机截图实测 deepseek-flash 的视觉能力（这是"看图点击"的前提）
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
BASE=http://131.255.36.100:30001/v1
IMG=${1:-/tmp/k20_report_57ada8.png}
[ -f "$IMG" ] || { echo "  截图不存在: $IMG"; exit 1; }
echo "  用图: $IMG ($(stat -c%s "$IMG") 字节)"

python3 - "$BASE" "$KEY" "$IMG" <<'PY'
import json, sys, urllib.request
import base64 as _b64`nbase, key, img = sys.argv[1], sys.argv[2], sys.argv[3]`nb64 = _b64.b64encode(open(img,"rb").read()).decode()
q = ("这是一张安卓手机的截图。请回答：1) 现在处于什么界面/应用？"
     "2) 屏幕顶部状态栏显示的信号/WiFi 图标有哪些？"
     "3) 如果要打开「设置」，你会在屏幕上点哪个坐标（给出 x,y，屏幕分辨率 1080x2340）？"
     "只输出 JSON: {\"screen\":\"...\",\"status\":\"...\",\"tap\":[x,y],\"why\":\"...\"}")
body = {"model": "deepseek-flash", "max_tokens": 600, "temperature": 0,
        "messages": [{"role": "user", "content": [
            {"type": "text", "text": q},
            {"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}}]}]}
req = urllib.request.Request(base + "/chat/completions", data=json.dumps(body).encode(),
                             headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
t0 = __import__("time").time()
with urllib.request.urlopen(req, timeout=180) as r:
    d = json.loads(r.read().decode())
dt = __import__("time").time() - t0
if "choices" in d:
    c = d["choices"][0]["message"].get("content") or ""
    print("  ✓ 模型回答（%.1fs，%s tokens）:" % (dt, d.get("usage", {}).get("total_tokens")))
    for ln in c.strip().splitlines()[:14]:
        print("    " + ln)
else:
    print("  ✗ 失败:", str(d)[:200])
PY
