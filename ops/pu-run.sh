#!/bin/bash
# 1→2→3：验证视觉修复 → 跑 portal 真单 → 留结构化轨迹
exec > /tmp/pu-run.log 2>&1
rm -f /tmp/pu-run.done
PU=/opt/phone-use/pu
TS=$(date +%Y%m%d-%H%M%S)

cat > /tmp/prompt-look.txt <<'TXT'
用一句话回答：这台手机（serial CTV0221202007036）现在屏幕上是什么页面？顶部状态栏有哪些图标？
只说你确实看到的内容，不要猜。如果你看不到图像，请直接说"看不到图像"。
TXT

cat > /tmp/prompt-portal.txt <<'TXT'
连 test-portal2 做 portal 认证，账号 zjb 密码 123456；完成后必须确认能上外网。
要求：先读 /opt/phone-use/base/SKILL.md；只用 phone-use / phone-look；给出证据（SSID/BSSID/IP/门户返回码/probe 结果/截图路径）。
TXT

echo "############ ① 视觉验证单（看图描述屏幕）############"
sudo -iu phonebot bash -lc "cd $PU && PROMPT=\$(cat /tmp/prompt-look.txt) && timeout 600 qwen \"\$PROMPT\" --approval-mode yolo --json-file $PU/logs/run-look-$TS.json" 2>&1 | tail -20

echo
echo "############ ② portal 真单 ############"
sudo -iu phonebot bash -lc "cd $PU && PROMPT=\$(cat /tmp/prompt-portal.txt) && timeout 1200 qwen \"\$PROMPT\" --approval-mode yolo --json-file $PU/logs/run-portal-$TS.json" 2>&1 | tail -55

echo
echo "############ ③ 轨迹统计（它到底调了什么）############"
for f in $PU/logs/run-look-$TS.json $PU/logs/run-portal-$TS.json; do
  [ -f "$f" ] || { echo "  (无 $f)"; continue; }
  echo "  --- $(basename $f) ($(stat -c%s $f) 字节) ---"
  python3 - "$f" <<'PY'
import json, sys, re, collections
p = sys.argv[1]
cmds, tools = [], collections.Counter()
for line in open(p, encoding='utf-8', errors='ignore'):
    line = line.strip()
    if not line.startswith('{'): continue
    try: e = json.loads(line)
    except Exception: continue
    s = json.dumps(e, ensure_ascii=False)
    for m in re.findall(r'"(?:command|cmd)"\s*:\s*"([^"]{0,160})"', s):
        cmds.append(m)
    for t in re.findall(r'"name"\s*:\s*"([a-zA-Z_]{3,40})"', s):
        tools[t] += 1
print("   工具调用计数:", dict(tools.most_common(8)))
print("   命令样本（前 12 条）:")
for c in cmds[:12]:
    print("     -", c[:150])
pl = [c for c in cmds if 'phone-look' in c]
print("   ★ phone-look 相关命令:", pl[:3] if pl else "（没有）")
PY
done
echo PU_RUN_DONE > /tmp/pu-run.done
