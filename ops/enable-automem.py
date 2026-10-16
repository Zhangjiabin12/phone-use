import json, os, shutil, time
targets = ['/opt/phone-use/pu/.qwen/settings.json', '/home/phonebot/.qwen/settings.json']
for p in targets:
    if not os.path.exists(p):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        d = {}
    else:
        shutil.copy2(p, p + '.bak-' + time.strftime('%Y%m%d-%H%M%S'))
        d = json.load(open(p, encoding='utf-8'))
    mem = d.setdefault('memory', {})
    mem['enableAutoSkill'] = True
    mem['enableManagedAutoMemory'] = True
    mem['enableManagedAutoDream'] = True
    json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    print("  已开:", p, "->", {k: mem[k] for k in ('enableAutoSkill', 'enableManagedAutoMemory', 'enableManagedAutoDream')})
print("  复核:")
for p in targets:
    d = json.load(open(p, encoding='utf-8'))
    print("   ", p, "memory =", d.get('memory'))
