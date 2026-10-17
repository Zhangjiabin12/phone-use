#!/bin/bash
echo "== K20 现在的屏幕状态 =="
adb -s 57ada8 shell "dumpsys power | grep -E 'mWakefulness=|Display Power'" 2>&1 | head -3
adb -s 57ada8 exec-out screencap -p > /tmp/k20_now.png 2>/dev/null
echo "  截图字节: $(stat -c%s /tmp/k20_now.png 2>/dev/null)"

echo
echo "== 给 /api/click 加自动唤醒：屏黑/休眠时先发 key wakeup 再点 =="
python3 - <<'PY'
import ast
p='/usr/local/share/phone-wall/phone-wall.py'
s=open(p,encoding='utf-8').read()
if 'AUTO_WAKE' in s:
    print("  已有 AUTO_WAKE")
else:
    anchor = '''                argv = ["tap", str(body["x"]), str(body["y"])] if dev.get("root") \\\n                    else ["click-xy", str(body["x"]), str(body["y"])]'''
    assert anchor in s, "click 锚点未找到"
    add = '''                # AUTO_WAKE：屏幕黑着时点击不会有任何反应，先唤醒
                try:
                    if (dev.get("screen_display_on") is False) or (dev.get("screen") and dev.get("screen") != "Awake"):
                        hub("POST", "/devices/%s/exec" % serial,
                            {"args": ["key", "wakeup"], "owner": "wall", "force": True}, timeout=60)
                except Exception:
                    pass
'''
    s = s.replace(anchor, add + anchor, 1)
    open(p,'w',encoding='utf-8').write(s)
    ast.parse(s); print("  已加自动唤醒")
PY
systemctl restart phone-wall; sleep 3
echo "  wall=$(systemctl is-active phone-wall)  /api/devices=http$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8910/api/devices)"
echo -n "  K20 点击复测: "; curl -s -m 90 -X POST -H 'Content-Type: application/json' -d '{"serial":"57ada8","x":540,"y":1200}' http://127.0.0.1:8910/api/click | head -c 200; echo
sleep 1
adb -s 57ada8 exec-out screencap -p > /tmp/k20_after2.png 2>/dev/null
echo "  点击后截图字节: $(stat -c%s /tmp/k20_after2.png 2>/dev/null)"
