#!/usr/bin/env python3
"""验证：phone-use 的 stdout 只剩结论，机读行与轨迹走 stderr；8902 的 answer 也只含结论"""
import json
import subprocess
import urllib.request

# 1) 直接跑入口，分离 stdout/stderr
pr = subprocess.run(["phone-use", "一句话：现在几台手机可用？不要做别的。"],
                    capture_output=True, text=True, timeout=600)
print("=== 入口 stdout（应只有结论）===")
print(pr.stdout.strip()[:600])
print("=== 入口 stderr（应有 PU_RESULT/轨迹/步数）===")
for ln in pr.stderr.strip().splitlines()[:6]:
    print("  ", ln[:160])

# 2) 走 HTTP
body = json.dumps({"text": "一句话：现在几台手机可用？不要做别的。"}).encode()
req = urllib.request.Request("http://127.0.0.1:8902/task", data=body,
                             headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=600) as r:
    d = json.loads(r.read())
print("=== 8902 /task ===")
print("verdict=%s steps=%s elapsed=%s trace=%s" % (d.get("verdict"), d.get("steps"), d.get("elapsed"), bool(d.get("trace"))))
print("answer:")
print((d.get("answer") or "")[:600])
