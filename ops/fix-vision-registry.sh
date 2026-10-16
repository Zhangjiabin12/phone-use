#!/bin/bash
# models.dev 的模型能力表可能缺 modalities.image（实测 deepseek-flash 能看图），刷新后重打补丁
for HB in /home/phonebot; do
  F=$HB/.qwen/model-registry.json
  [ -f "$F" ] || continue
  python3 - "$F" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding='utf-8'))
m = d.setdefault('models', {})
changed = []
for name in ('deepseek-flash', 'glm-5.3-flash', 'qwen-3.8-27b'):
    if name in m and not ((m[name].get('modalities') or {}).get('image')):
        m[name] = {**m[name], 'modalities': {**(m[name].get('modalities') or {}), 'image': True}}
        changed.append(name)
json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print("  已补视觉能力:", changed or "（本来就对）")
PY
  chown phonebot:phonebot "$F"
done
