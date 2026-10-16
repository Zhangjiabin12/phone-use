#!/bin/bash
PU=/opt/phone-use/pu; HB=/home/phonebot
echo "=== 1) 现状：项目级 / 用户级的 memory 组开关 ==="
python3 - <<'PY'
import json, os
for p in ('/opt/phone-use/pu/.qwen/settings.json', '/home/phonebot/.qwen/settings.json'):
    print("---", p, "---")
    if not os.path.exists(p):
        print("   （不存在）"); continue
    d = json.load(open(p, encoding='utf-8'))
    mem = d.get('memory')
    if mem is None:
        print("   没有 memory 组 → 三项走默认（默认是开还是关要看实现）")
    else:
        for k in ('enableAutoSkill', 'enableManagedAutoMemory', 'enableManagedAutoDream'):
            print("   %-28s = %s" % (k, mem.get(k, '(未设)')))
    print("   顶层键:", list(d.keys()))
PY

echo
echo "=== 2) 已生成的产物（auto-skill / 自动记忆落盘在哪）==="
for d in $HB/.qwen $PU/.qwen; do
  echo "--- $d ---"
  find "$d" -maxdepth 2 -type d 2>/dev/null | sed 's/^/   dir: /' | head -12
  for sub in skills memories agent-memory auto-skill; do
    [ -e "$d/$sub" ] && echo "   ★ 存在: $d/$sub ($(ls -1 $d/$sub 2>/dev/null | wc -l) 项)"
  done
done
echo "--- 最近 24h 在 .qwen 下被写过的文件（除注册表/项目外）---"
find $HB/.qwen $PU/.qwen -type f -newermt '-24 hours' 2>/dev/null | grep -vE 'model-registry|projects/|extensions/|extension-store|logs/|settings.json' | head -12 | sed 's/^/   /'

echo
echo "=== 3) 按你的口径写死关闭（项目级 + 用户级）==="
python3 - <<'PY'
import json, os, shutil, time
targets = ['/opt/phone-use/pu/.qwen/settings.json', '/home/phonebot/.qwen/settings.json']
for p in targets:
    if not os.path.exists(p):
        # 用户级没有就创建一个最小 settings
        os.makedirs(os.path.dirname(p), exist_ok=True)
        d = {}
    else:
        shutil.copy2(p, p + '.bak-' + time.strftime('%Y%m%d-%H%M%S'))
        d = json.load(open(p, encoding='utf-8'))
    mem = d.setdefault('memory', {})
    mem['enableAutoSkill'] = False
    mem['enableManagedAutoMemory'] = False
    mem['enableManagedAutoDream'] = False
    json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    print("   已写:", p, "→", {k: mem[k] for k in ('enableAutoSkill','enableManagedAutoMemory','enableManagedAutoDream')})
PY
chown -R phonebot:phonebot $PU/.qwen $HB/.qwen 2>/dev/null
chmod 600 $PU/.qwen/settings.json $HB/.qwen/settings.json 2>/dev/null

echo
echo "=== 4) 复核 + 顺带确认轨迹开关（上一轮发现 --output-format json 才是有效的）==="
python3 - <<'PY'
import json
for p in ('/opt/phone-use/pu/.qwen/settings.json', '/home/phonebot/.qwen/settings.json'):
    d = json.load(open(p, encoding='utf-8'))
    print("  ", p, "memory =", d.get('memory'))
PY
echo "  （轨迹留痕用 --output-format json，已验证能产出事件流；--json-file 无效）"
