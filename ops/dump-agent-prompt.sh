#!/bin/bash
python3 - <<'PY'
import re, json
p = '/usr/local/share/phone-agent/phone-agent.py'
s = open(p, encoding='utf-8').read()

print("=== 1) 系统提示词（原文）===")
m = re.search(r'(?s)(SYSTEM\w*)\s*=\s*(?:r?)(?:"""|\'\'\')(.*?)(?:"""|\'\'\')', s)
if m:
    print("  [变量 %s，共 %d 字]" % (m.group(1), len(m.group(2))))
    for ln in m.group(2).strip().splitlines():
        print("  | " + ln)
else:
    print("  未找到三引号常量，改用相关行：")
    for i, ln in enumerate(s.splitlines(), 1):
        if re.search(r'(?i)system|prompt', ln):
            print("  %4d: %s" % (i, ln.rstrip()[:150]))

print()
print("=== 2) 工具清单（名称 / 描述 / 参数）===")
# 找 TOOLS 列表里的每个 { "name": ... }
names = re.findall(r'"name":\s*"(\w+)"', s)
descs = re.findall(r'"description":\s*"([^"]{0,300})"', s)
seen = []
for n, d in zip(names, descs):
    if n in seen:
        continue
    seen.append(n)
    print("  · %-16s %s" % (n, d[:170]))
print("  合计 %d 个工具: %s" % (len(seen), ", ".join(seen)))

print()
print("=== 3) 参数 schema（原文片段）===")
mt = re.search(r'(?s)TOOLS\s*=\s*\[(.*?)\n\]', s)
print(mt.group(1)[:1200] if mt else "  未找到 TOOLS 字面量")

print()
print("=== 4) 返回判定（verdict / finish）===")
for i, ln in enumerate(s.splitlines(), 1):
    if re.search(r'PASS|FAIL|BLOCKED|UNKNOWN|TIMEOUT|LLM_DOWN|CANCELLED|def finish|verdict', ln):
        print("  %4d: %s" % (i, ln.rstrip()[:150]))

print()
print("=== 5) 循环与限制 ===")
for i, ln in enumerate(s.splitlines(), 1):
    if re.search(r'while |range\(|MAX_STEPS|DEADLINE|time\.time\(\)|break$', ln):
        print("  %4d: %s" % (i, ln.rstrip()[:140]))
PY
