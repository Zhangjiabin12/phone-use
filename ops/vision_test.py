import base64, json, sys, time, urllib.request
base, key, img = sys.argv[1], sys.argv[2], sys.argv[3]
b64 = base64.b64encode(open(img, "rb").read()).decode()
q = ("这是一张安卓手机的截图。请回答："
     "1) 现在处于什么界面/应用？ "
     "2) 屏幕顶部状态栏都有哪些图标（信号/WiFi/电量）？ "
     "3) 如果想打开「设置」，你会在屏幕上点哪里？给出坐标 x,y（屏幕 1080x2340）。 "
     '只输出 JSON：{"screen":"...","status":"...","tap":[x,y],"why":"..."}')
body = {"model": "deepseek-flash", "max_tokens": 800, "temperature": 0,
        "messages": [{"role": "user", "content": [
            {"type": "text", "text": q},
            {"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}}]}]}
req = urllib.request.Request(base + "/chat/completions", data=json.dumps(body).encode(),
                             headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
t0 = time.time()
with urllib.request.urlopen(req, timeout=240) as r:
    d = json.loads(r.read().decode())
dt = time.time() - t0
if "choices" in d:
    c = d["choices"][0]["message"].get("content") or ""
    print("  OK 模型回答（%.1fs，tokens=%s）:" % (dt, d.get("usage", {}).get("total_tokens")))
    for ln in c.strip().splitlines()[:16]:
        print("    " + ln)
else:
    print("  FAIL:", str(d)[:220])