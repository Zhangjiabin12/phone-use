#!/bin/bash
echo "== A) 大屏不再搬动卡片节点（避免重排）：改为克隆 =="
python3 - <<'PY'
p='/usr/local/share/phone-wall/wall-page.html'
s=open(p,encoding='utf-8').read()
if 'KEEP_ORDER_CLONE' in s:
    print("  已修")
else:
    old1 = '  wrap.appendChild(col);'
    new1 = '  wrap.appendChild(col.cloneNode(true));  /* KEEP_ORDER_CLONE：克隆，不动原卡片，避免顺序跳动 */'
    assert old1 in s, "锚点1未找到"
    s = s.replace(old1, new1, 1)
    old2 = '    onClose: () => { holder.replaceWith(col); }'
    new2 = '    onClose: () => { /* 克隆模式：无需还原 */ }'
    assert old2 in s, "锚点2未找到"
    s = s.replace(old2, new2, 1)
    open(p,'w',encoding='utf-8').write(s)
    print("  已改为克隆模式")
PY
systemctl restart phone-wall; sleep 3; echo "  wall=$(systemctl is-active phone-wall)"

echo
echo "== B) K20 触摸到底有没有生效：拉通知栏（swipe 顶部→中）前后截图对比 =="
adb -s 57ada8 exec-out screencap -p > /tmp/k20_before.png 2>/dev/null
python3 - <<'PY'
import json, urllib.request
body = json.dumps({"serial":"57ada8","x1":540,"y1":30,"x2":540,"y2":900,"ms":300}).encode()
req = urllib.request.Request("http://127.0.0.1:8910/api/swipe", data=body, headers={"Content-Type":"application/json"})
with urllib.request.urlopen(req, timeout=90) as r:
    print("  swipe:", r.read().decode()[:160])
PY
sleep 2
adb -s 57ada8 exec-out screencap -p > /tmp/k20_after.png 2>/dev/null
echo -n "  before md5/size: "; md5sum /tmp/k20_before.png 2>/dev/null | cut -c1-12; stat -c%s /tmp/k20_before.png 2>/dev/null
echo -n "  after  md5/size: "; md5sum /tmp/k20_after.png 2>/dev/null | cut -c1-12; stat -c%s /tmp/k20_after.png 2>/dev/null
echo -n "  当前前台窗口: "; adb -s 57ada8 shell "dumpsys window | grep -E 'mCurrentFocus'" 2>&1 | head -1
