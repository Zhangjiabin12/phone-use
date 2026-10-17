#!/bin/bash
echo "== A) hub 传给原语的解释器路径 =="
grep -n 'PHONE_USE\|PHONE_USE_BIN' /usr/local/share/phone-hub/phone-hub.py | head -4

echo
echo "== B) /api/click 两台对照（同坐标 540,1200）=="
python3 - <<'PY'
import json, urllib.request
for s in ("57ada8", "CTV0221202007036"):
    body = json.dumps({"serial": s, "x": 540, "y": 1200}).encode()
    req = urllib.request.Request("http://127.0.0.1:8910/api/click", data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            d = json.loads(r.read())
        print("  %-16s argv=%s rc=%s out=%s" % (s, d.get("argv"), d.get("rc"), (d.get("stdout") or "")[:100]))
    except Exception as e:
        print("  %-16s 失败 %s %s" % (s, type(e).__name__, str(e)[:100]))
PY

echo
echo "== C) 页面点击的坐标换算逻辑 =="
grep -n "api/click" -B 8 -A 6 /usr/local/share/phone-wall/wall-page.html | head -30

echo
echo "== D) 大屏是否把卡片里的节点搬走（导致重排）=="
grep -n "function openBig" -A 14 /usr/local/share/phone-wall/wall-page.html | head -20
