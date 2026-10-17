#!/bin/bash
python3 /tmp/add-swipe.py
systemctl restart phone-wall; sleep 3
echo "  wall=$(systemctl is-active phone-wall)"
python3 - <<'PY'
import json, urllib.request
for s in ("57ada8", "CTV0221202007036"):
    body = json.dumps({"serial": s, "x1": 540, "y1": 1600, "x2": 540, "y2": 900, "ms": 280}).encode()
    req = urllib.request.Request("http://127.0.0.1:8910/api/swipe", data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            d = json.loads(r.read())
        print("  %-16s argv=%s rc=%s out=%s" % (s, d.get("argv"), d.get("rc"), (d.get("stdout") or "")[:80]))
    except Exception as e:
        print("  %-16s 失败: %s %s" % (s, type(e).__name__, str(e)[:120]))
PY
