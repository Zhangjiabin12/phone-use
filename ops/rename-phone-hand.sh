#!/bin/bash
# 改名与合并：原语 phone-use → phone-hand；入口 phone-use = 给任务（含留档）；删除 pu-run
set -u
BASE=/opt/phone-use/base
PU=/opt/phone-use/pu
TS=$(date +%Y%m%d-%H%M%S)
echo "===== A) 冻结层改名（复制→改→提升→重算 sha256）====="
# 1) 原语脚本改名
cp -f $BASE/phone-use.py /opt/phone-use/work/copies/phone-hand.py.$TS
NEW=/opt/phone-use/work/copies/phone-hand.py.$TS
python3 - "$NEW" <<'PY'
import ast, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = s.replace('phone-use — 安卓真机的**原语工具集**', 'phone-hand — 安卓真机的**原语工具集**')
open(p, 'w', encoding='utf-8').write(s)
ast.parse(s); print("  phone-hand.py 语法 OK")
PY

# 2) 文档与 phone-look 里的原语调用统一改名（不做兼容，直接替换）
for f in $BASE/SKILL.md $BASE/AGENT-PROMPT.md $BASE/phone-look; do
  cp -f "$f" "/opt/phone-use/work/copies/$(basename $f).$TS"
  python3 - "/opt/phone-use/work/copies/$(basename $f).$TS" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
# 原语调用样式 phone-use <动词> → phone-hand <动词>；其它提及 phone-use（指入口）保留
verbs = r'(state|wifi|list|scan|probe|failure|backend|ui|find|click-text|click-desc|click-id|click-xy|settext|scroll|scroll-up|global|tap|swipe|key|input|shot|pull|http|httpfile|shell|wifi-connect|wifi-forget|jar|tap\b)'
s2 = re.sub(r'phone-use\s+(' + verbs + r')', r'phone-hand \1', s)
# phone-look 内部调用是 subprocess 里的 "phone-use" → phone-hand
s2 = s2.replace('"phone-hand", "shot"', '"phone-hand", "shot"').replace('"phone-hand", "pull"', '"phone-hand", "pull"')
open(p, 'w', encoding='utf-8').write(s2)
n = s2.count('phone-hand')
print("  %-22s → phone-hand 出现 %d 次" % (p.split('/')[-1], n))
PY
done

echo "  提升到 base："
mv -f "$NEW" $BASE/phone-hand.py
cp -f /opt/phone-use/work/copies/SKILL.md.$TS       $BASE/SKILL.md
cp -f /opt/phone-use/work/copies/AGENT-PROMPT.md.$TS $BASE/AGENT-PROMPT.md
cp -f /opt/phone-use/work/copies/phone-look.$TS      $BASE/phone-look
rm -f $BASE/phone-use.py
chown -R root:root $BASE; chmod -R a-w $BASE; chmod 555 $BASE/*.py $BASE/phone-look 2>/dev/null
( cd $BASE && sha256sum * > /opt/phone-use/base.sha256 )
echo "  base 文件: $(ls -1 $BASE | tr '\n' ' ')"

echo
echo "===== B) 入口：phone-hand（原语，带守卫）+ phone-use（给任务，含留档）====="
cat > /usr/local/bin/phone-hand <<'H'
#!/bin/bash
BASE=/opt/phone-use/base
if [ -f /opt/phone-use/base.sha256 ]; then
  ( cd "$BASE" && sha256sum -c /opt/phone-use/base.sha256 --status 2>/dev/null ) || {
    echo "❌ 底层被改动：$BASE 与清单不符。" >&2; exit 90; }
fi
exec python3 "$BASE/phone-hand.py" "$@"
H
chmod 755 /usr/local/bin/phone-hand

# phone-use = 给任务（把 pu-run 的能力并进来，默认留档）
sed -e 's/^# pu-run .*$/# phone-use — 给一句话任务（内部用 Qwen Code 跑；默认留全轨迹）/' \
    -e 's/pu-run/phone-use/g' /usr/local/bin/pu-run > /usr/local/bin/phone-use
chmod 755 /usr/local/bin/phone-use
rm -f /usr/local/bin/pu-run

echo
echo "===== C) 其它引用面（hub / MCP / 手机墙）====="
python3 - <<'PY'
import re
edits = []
for p in ('/usr/local/share/phone-hub/phone-hub.py',
          '/usr/local/share/phone-hub/phone-hub-mcp.py',
          '/usr/local/share/phone-wall/phone-wall.py'):
    try:
        s = open(p, encoding='utf-8').read()
    except Exception as e:
        print("  跳过", p, e); continue
    n0 = len(re.findall(r'"phone-use"|\bphone-use\b', s))
    # 只替换"调用原语"的写法：phone-use <动词> 或 "phone-use"
    s2 = re.sub(r'"phone-use"', '"phone-hand"', s)
    s2 = re.sub(r'\bphone-use\s+(state|wifi|probe|failure|scan|ui|find|tap|swipe|key|input|shot|pull|shell|jar|click-xy|click-text|settext|scroll|global)\b', r'phone-hand \1', s2)
    if s2 != s:
        open(p, 'w', encoding='utf-8').write(s2)
        edits.append((p.split('/')[-1], n0))
print("  已改:", edits or "（无需改）")
PY
for u in phone-hub phone-wall; do systemctl restart $u; sleep 2; printf "  %-11s %s\n" $u "$(systemctl is-active $u)"; done

echo
echo "===== D) 验证 ====="
echo -n "  守卫: "; phone-hand state >/dev/null 2>&1 && echo OK || echo FAIL
echo -n "  原语(phone-hand wifi @华为): "; ANDROID_SERIAL=CTV0221202007036 phone-hand wifi 2>&1 | head -c 150; echo
echo -n "  入口(phone-use 给任务): "; phone-use "运行 curl -s http://127.0.0.1:8901/devices，一句话列出每台 serial/usable。不要做别的。" --timeout 300 2>&1 | tail -8
echo -n "  旧名字是否已无: "; command -v pu-run >/dev/null && echo "pu-run 还在!" || echo "pu-run 已删 ✓"
echo -n "  旧写法 phone-hand wifi 的现行为: "; ANDROID_SERIAL=CTV0221202007036 phone-hand wifi 2>&1 | head -3 | tr '\n' ' '; echo
