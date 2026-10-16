#!/bin/bash
exec > /tmp/pu-run2.log 2>&1
rm -f /tmp/pu-run2.done
PU=/opt/phone-use/pu
TS=$(date +%Y%m%d-%H%M%S)
echo "===== 0) 试三种喂 prompt 的方式（各 90s 上限）====="
for form in positional stdin promptflag; do
  case $form in
    positional) CMD="qwen '回复OK两个字' --approval-mode yolo" ;;
    stdin)      CMD="echo '回复OK两个字' | qwen --approval-mode yolo" ;;
    promptflag) CMD="qwen --prompt '回复OK两个字' --approval-mode yolo" ;;
  esac
  echo "--- 方式: $form ---"
  sudo -iu phonebot bash -lc "cd $PU && timeout 90 $CMD" 2>&1 | tail -4
  echo "   (退出码 $?)"
done

echo
echo "===== ① 视觉验证单 ====="
cat > /tmp/p1.txt <<'TXT'
用一句话回答：这台手机（serial CTV0221202007036）现在屏幕上是什么页面？顶部状态栏有哪些图标？只说你确实看到的，不要猜。若看不到图像就直接说看不到。
TXT
sudo -iu phonebot bash -lc "cd $PU && timeout 600 qwen --prompt \"\$(cat /tmp/p1.txt)\" --approval-mode yolo --json-file $PU/logs/look-$TS.json" 2>&1 | tail -18

echo
echo "===== ② portal 真单 ====="
cat > /tmp/p2.txt <<'TXT'
连 test-portal2 做 portal 认证，账号 zjb 密码 123456；完成后必须确认能上外网。先读 /opt/phone-use/base/SKILL.md；只用 phone-use / phone-look；给出证据（SSID/BSSID/IP/门户返回码/probe 结果/截图路径）。
TXT
sudo -iu phonebot bash -lc "cd $PU && timeout 1200 qwen --prompt \"\$(cat /tmp/p2.txt)\" --approval-mode yolo --json-file $PU/logs/portal-$TS.json" 2>&1 | tail -50

echo
echo "===== ③ 轨迹（工具调用与命令）====="
for f in $PU/logs/look-$TS.json $PU/logs/portal-$TS.json; do
  [ -f "$f" ] || { echo "  (无 $(basename $f))"; continue; }
  python3 - "$f" <<'PY'
import json, sys, re, collections
cmds, tools = [], collections.Counter()
for line in open(sys.argv[1], encoding='utf-8', errors='ignore'):
    line = line.strip()
    if not line.startswith('{'): continue
    try: s = json.dumps(json.loads(line), ensure_ascii=False)
    except Exception: continue
    cmds += re.findall(r'"(?:command|cmd)"\s*:\s*"([^"]{0,150})"', s)
    tools.update(re.findall(r'"name"\s*:\s*"([a-zA-Z_]{3,40})"', s))
print("   工具计数:", dict(tools.most_common(6)))
for c in cmds[:10]: print("     $", c[:140])
pl = [c for c in cmds if 'phone-look' in c]
print("   ★phone-look:", pl[:2] if pl else "（未调用）")
PY
done
echo PU_RUN2_DONE > /tmp/pu-run2.done
