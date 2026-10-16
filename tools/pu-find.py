#!/usr/bin/env python3
"""从 pu.jar 的元素树里取节点中心坐标： pu-find.py <text|id|desc> <子串> [第几个]
输出： "x y"  或空（未找到）"""
import re
import subprocess
import sys

mode, needle = sys.argv[1], sys.argv[2]
idx = int(sys.argv[3]) if len(sys.argv) > 3 else 1

out = subprocess.run(["python3", "/opt/phone-use-jar/pu-node.py"],
                     input="ui\n", capture_output=True, text=True,
                     timeout=300).stdout
body = out.split("== 结果 ==", 1)[-1]

pat = {
    "text": r"text=([^|]*?)\s*\|",
    "desc": r"desc=([^|]*?)\s*\|",
    "id": r"id=([^|]*?)\s*\|",
}[mode]

hits = []
for line in body.splitlines():
    if "|" not in line:
        continue
    m = re.search(pat, line)
    if not m:
        continue
    val = (m.group(1) or "").strip()
    if needle.lower() in val.lower():
        b = re.search(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]", line)
        if b:
            x1, y1, x2, y2 = map(int, b.groups())
            hits.append(((x1 + x2) // 2, (y1 + y2) // 2, val, (x2 - x1) * (y2 - y1)))
if not hits:
    sys.exit(0)
hits.sort(key=lambda h: h[3])          # 取最小的（最内层）
x, y, val, _ = hits[min(idx, len(hits)) - 1]
print("%d %d" % (x, y))
