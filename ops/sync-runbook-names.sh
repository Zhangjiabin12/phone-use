#!/bin/bash
echo "== 1) 把 base 的文档同步到 hub 供出的位置（runbook 是 agent 的必读）=="
for f in SKILL.md ONBOARD.md; do
  if [ -f /opt/phone-use/base/$f ]; then
    cp -f /opt/phone-use/base/$f /usr/local/share/phone-use/$f
    printf "  %-12s → /usr/local/share/phone-use/%s  (phone-hand %s 次)\n" "$f" "$f" "$(grep -c phone-hand /usr/local/share/phone-use/$f)"
  fi
done
# 旧的原语副本清掉（避免混淆；hub 已不指向它）
[ -f /usr/local/share/phone-use/phone-use.py ] && mv -f /usr/local/share/phone-use/phone-use.py /usr/local/share/phone-use/phone-use.py.old && echo "  旧副本已改名 phone-use.py.old"

echo
echo "== 2) hub 里读版本号的写法同步（它原来匹配文档字符串 \"\"\"phone-use）=="
python3 - <<'PY'
p='/usr/local/share/phone-hub/phone-hub.py'
s=open(p,encoding='utf-8').read()
if '"""phone-use' in s:
    s=s.replace('"""phone-use','"""phone-hand')
    open(p,'w',encoding='utf-8').write(s)
    print("  已同步版本号匹配")
else:
    print("  （无需改）")
PY
python3 -c "import ast;ast.parse(open('/usr/local/share/phone-hub/phone-hub.py').read());print('  hub 语法 OK')"
systemctl restart phone-hub; sleep 4
echo "  hub=$(systemctl is-active phone-hub)"

echo
echo "== 3) 验证：agent 读到的 runbook 是 phone-hand =="
curl -s -m 10 http://127.0.0.1:8901/skill | python3 -c "
import json,sys
t=json.load(sys.stdin)['skill']
print('  runbook 字节:', len(t))
print('  含 phone-hand:', t.count('phone-hand'), ' 含旧的 phone-use <原语> 写法:', len([l for l in t.splitlines() if 'phone-use ' in l and 'phone-hand' not in l]))
print('  怎么看/怎么点 一节:', '怎么看 / 怎么点' in t)
"
echo
echo "== 4) 三个名字的最终样子 =="
for c in phone-use phone-hand phone-look; do printf "  %-11s %s\n" "$c" "$(command -v $c || echo '缺失')"; done
echo -n "  pu-run: "; command -v pu-run >/dev/null && echo "还在（应已删）" || echo "已删除 ✓"
echo
echo "== 5) 一句话冒烟（phone-use 给任务）=="
phone-use "运行 curl -s http://127.0.0.1:8901/devices 并一句话列出三台 serial。别的不要做。" --timeout 300 2>&1 | tail -10
