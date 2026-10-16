#!/bin/bash
exec > /tmp/pu-wrap.log 2>&1
rm -f /tmp/pu-wrap.done
PU=/opt/phone-use/pu
TS=$(date +%Y%m%d-%H%M%S)

echo "===== ① 探 --json-file 的三种用法（各 60s 上限）====="
sudo -iu phonebot bash -lc "cd $PU && timeout 60 qwen '回复OK' --approval-mode yolo --json-file $PU/logs/t1.json >/dev/null 2>&1; ls -l $PU/logs/t1.json 2>/dev/null || echo '  形态1(json-file) 无产出'"
sudo -iu phonebot bash -lc "cd $PU && timeout 60 qwen '回复OK' --approval-mode yolo --json-fd 3 3>$PU/logs/t2.json >/dev/null 2>&1; ls -l $PU/logs/t2.json 2>/dev/null || echo '  形态2(json-fd) 无产出'"
sudo -iu phonebot bash -lc "cd $PU && timeout 60 qwen '回复OK' --approval-mode yolo --output-format json > $PU/logs/t3.json 2>/dev/null; head -c 200 $PU/logs/t3.json; echo"
echo "  有没有落到别处: $(find / -name 'look-*.json' -o -name 'portal-*.json' 2>/dev/null | head -3 | tr '\n' ' ')"

echo
echo "===== ② 标准入口 pu-run（自动留 stdout + 事件轨迹）====="
cat > /usr/local/bin/pu-run <<'WRAP'
#!/bin/bash
# pu-run "任务文本" [--timeout 秒] [--user phonebot]
# 统一入口：从 pu 项目目录、以 phonebot、无头跑，stdout 与事件轨迹都留档
PU=/opt/phone-use/pu
U=phonebot; TO=900; TASK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TO="$2"; shift 2;;
    --user) U="$2"; shift 2;;
    *) TASK="$TASK $1"; shift;;
  esac
done
[ -z "$TASK" ] && { echo "用法: pu-run \"一句话任务\" [--timeout 900]"; exit 2; }
TS=$(date +%Y%m%d-%H%M%S); LOG=$PU/logs/run-$TS.log; JSON=$PU/logs/run-$TS.json
printf '%s' "$TASK" > /tmp/pu-task-$TS.txt
echo "任务: $TASK"
echo "日志: $LOG"
sudo -iu "$U" bash -lc "cd $PU && timeout $TO qwen --prompt \"\$(cat /tmp/pu-task-$TS.txt)\" --approval-mode yolo --output-format json > $JSON 2>/dev/null; cd $PU && timeout $TO qwen --prompt \"\$(cat /tmp/pu-task-$TS.txt)\" --approval-mode yolo" 2>&1 | tee "$LOG" | tail -40
rm -f /tmp/pu-task-$TS.txt
echo "--- 轨迹文件: $JSON ($(stat -c%s $JSON 2>/dev/null || echo 0) 字节) ---"
WRAP
chmod 755 /usr/local/bin/pu-run

echo
echo "===== ③ 把 agent 发现的两条坑写进 SKILL（复制→改→提升→重算指纹）====="
BASE=/opt/phone-use/base
cp -f $BASE/SKILL.md /opt/phone-use/work/copies/SKILL.md.$TS
cat >> /opt/phone-use/work/copies/SKILL.md.$TS <<'ADD'

### 五之补：实测踩坑（2026-10-16，agent 自己发现并记录）
1. **残留会话会让 `probe` 假报"未被拦截"**：开局若残留上次的 L2 连接，`probe` 可能显示 `portal_intercepted=false`，
   但手机真实拉网页会 DNS 失败 —— **判据要看真实内容**（163.com/neverssl 返回真实 HTML），不能只看 probe。
2. **`jar portal-login` 可能被 permit 名单短路**：它先探 `1.1.1.1`，若该地址在门户 permit 名单里被放行返回 301，
   就判"无需认证"而**根本不发登录请求**。此时要**重置客户端身份**触发真正的门户挑战：
   `wifi-forget <ssid>` → `wifi-connect <ssid> open --bssid <MAC> --mac none` → `captive_portal_flag` 变 true → 再 `portal-login`。
3. **MIUI 忽略 `--mac auto`**（MAC 不变）→ 换会话只能靠 forget + 重连（锁定 BSSID 更稳）。
4. `phone_exec` **会自动占用**终端：不要再显式 `lease_device` 后再 `phone_exec`（会 409）。
ADD
cp -f /opt/phone-use/work/copies/SKILL.md.$TS $BASE/SKILL.md
chmod 444 $BASE/SKILL.md
( cd $BASE && sha256sum * > /opt/phone-use/base.sha256 )
phone-use state >/dev/null 2>&1 && echo "  守卫 OK（新指纹已生效）" || echo "  守卫 失败"
grep -c "实测踩坑" $BASE/SKILL.md | sed 's/^/  SKILL 含新坑: /'

echo
echo "===== ④ 幂等脚本：models.dev 刷新后重打视觉补丁 ====="
mkdir -p /opt/phone-use/tools
cat > /opt/phone-use/tools/fix-vision-registry.sh <<'FIX'
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
FIX
chmod 755 /opt/phone-use/tools/fix-vision-registry.sh
/opt/phone-use/tools/fix-vision-registry.sh
echo "  （可放进部署流程：models.dev 刷新后跑一次）"
echo PU_WRAP_DONE > /tmp/pu-wrap.done
