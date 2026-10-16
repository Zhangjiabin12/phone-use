#!/bin/bash
HB=$(getent passwd phonebot | cut -d: -f6)
Q=$(sudo -u phonebot bash -lc 'readlink -f $(command -v qwen)')
echo "=== A) qwen 安装体在哪、是不是单文件 bundle ==="
echo "  qwen -> $Q"; ls -l "$Q" | sed 's/^/  /'
QD=$(dirname "$Q"); ls -1 "$QD/../" 2>/dev/null | head -8 | sed 's/^/  /'

echo
echo "=== B) qwen 里跟图像/视觉有关的判定（按模型名认能力？）==="
for f in "$Q" $(ls "$QD"/../lib/*.js 2>/dev/null | head -3) $(ls "$QD"/../*.js 2>/dev/null | head -3); do
  [ -f "$f" ] || continue
  echo "  --- $(basename $f) ---"
  grep -o "supportsVision\|isVisionModel\|vision[A-Za-z]*\|image_url\|input_image\|multimodal\|modalities\|imageInput\|canReadImages" "$f" 2>/dev/null | sort | uniq -c | sort -rn | head -8
done

echo
echo "=== C) 是否有'模型名 → 视觉能力'的名单（deepseek-flash 会不在名单里？）==="
grep -rho "qwen-vl[a-z0-9.\-]*\|gpt-4o[a-z0-9.\-]*\|claude-3[a-z0-9.\-]*\|deepseek[a-z0-9.\-]*" "$Q" 2>/dev/null | sort -u | head -20

echo
echo "=== D) 上次那单的会话日志：phone-look 到底怎么被调的、报什么错 ==="
find "$HB/.qwen" "$PU/.qwen" -name '*.json' -newermt '-2 hours' 2>/dev/null | head -5 | sed 's/^/  /'
LOG=$(ls -t "$HB"/.qwen/tmp/*/chats/*.json 2>/dev/null | head -1)
echo "  最近会话: $LOG"
if [ -n "$LOG" ]; then
  python3 - "$LOG" <<'PY'
import json, sys, re
d = json.load(open(sys.argv[1], encoding='utf-8'))
msgs = d if isinstance(d, list) else d.get('messages') or d.get('history') or []
hits = 0
for m in msgs:
    s = json.dumps(m, ensure_ascii=False)
    if 'phone-look' in s or 'phone_look' in s:
        hits += 1
        print("  --- 第 %d 条含 phone-look ---" % hits)
        for mm in re.findall(r'.{0,120}phone-look.{0,220}', s):
            print("   ", mm.replace('\\n', ' | ')[:340])
        if hits >= 4:
            break
print("  含 phone-look 的条目数:", hits)
PY
fi

echo
echo "=== E) 直接复现：以 phonebot + qwen 的运行环境手跑 phone-look（带/不带 ANDROID_SERIAL）==="
echo -n "  带 serial 参数: "; sudo -iu phonebot bash -lc 'phone-look CTV0221202007036 "一句话：什么页面" 2>&1 | head -2' | tr '\n' ' '; echo
echo -n "  设备上有图吗: "; adb -s CTV0221202007036 shell ls -l /sdcard/phone-look.png 2>&1 | tail -1
