#!/bin/bash
echo "================ 最终验收 ================"
echo "== 1) 命名与入口 =="
for c in phone-use phone-hand phone-look; do printf "  %-11s %s\n" "$c" "$(command -v $c || echo 缺失)"; done
echo -n "  pu-run（应无）: "; command -v pu-run >/dev/null && echo 还在 || echo 已删✓
echo -n "  旧原语脚本（应无）: "; ls /opt/phone-use/base/phone-use.py /usr/local/share/phone-use/phone-use.py 2>/dev/null | tr '\n' ' '; echo

echo
echo "== 2) 旧写法残留审计（全机相关目录）=="
hits=$(grep -rnE 'phone-use +(state|wifi|list|scan|probe|failure|backend|ui|find|click-[a-z]+|settext|scroll|global|tap|swipe|key|input|shot|pull|http|shell|jar|wifi-connect|wifi-forget)' \
  /opt/phone-use/base /opt/phone-use/tools /usr/local/share/phone-hub /usr/local/share/phone-wall /usr/local/share/phone-use /usr/local/share/phone-agent /usr/local/bin /etc/systemd/system 2>/dev/null | grep -v '\.old' | wc -l)
echo "  残留处数: $hits  $([ "$hits" = 0 ] && echo '✓ 干净' || echo '✗ 需清')"

echo
echo "== 3) 冻结层与守卫 =="
echo "  base: $(ls -1 /opt/phone-use/base | tr '\n' ' ')"
echo -n "  守卫(phone-hand state): "; phone-hand state >/dev/null 2>&1 && echo OK✓ || echo FAIL
echo -n "  篡改检测: "; chmod u+w /opt/phone-use/base/ONBOARD.md; echo "# x" >> /opt/phone-use/base/ONBOARD.md; phone-hand state >/dev/null 2>&1; rc=$?; python3 - <<'PY'
p='/opt/phone-use/base/ONBOARD.md'
out=[l for l in open(p,encoding='utf-8').read().splitlines() if l.strip()!='# x']
open(p,'w',encoding='utf-8').write("\n".join(out)+"\n")
PY
chmod a-w /opt/phone-use/base/ONBOARD.md; ( cd /opt/phone-use/base && sha256sum * > /opt/phone-use/base.sha256 )
echo "退出码=$rc $([ $rc -eq 90 ] && echo '✓ 守卫按预期拒绝' || echo '✗')"

echo
echo "== 4) 三个入口是否共用同一颗脑子 =="
echo "  (a) CLI: phone-use 一句话"
phone-use "运行 curl -s http://127.0.0.1:8901/devices，一句话说出几台可用。" --timeout 300 2>&1 | grep -E '事件类型|工具调用:|usable' | head -3 | sed 's/^/       /'
echo "  (b) HTTP 8902:"
curl -s -m 420 -X POST -H 'Content-Type: application/json' -d '{"text":"一句话：当前几台手机 usable？"}' http://127.0.0.1:8902/task 2>/dev/null | python3 -c "
import json,sys
t=sys.stdin.read()
try:
    r=(json.loads(t).get('result') or json.loads(t)); print('      verdict=%s serial=%s delegated=%s' % (r.get('verdict'),r.get('serial'),r.get('delegated')))
except Exception: print('      ✗', t[:120])
"
echo "  (c) 手机墙 8910:"
curl -s -m 420 -X POST -H 'Content-Type: application/json' -d '{"text":"一句话：几台手机在线？"}' http://127.0.0.1:8910/api/task 2>/dev/null | python3 -c "
import json,sys
t=sys.stdin.read()
try:
    r=json.loads(t); print('      ok=%s verdict=%s serial=%s' % (r.get('ok'),r.get('verdict'),r.get('serial')))
except Exception: print('      ✗', t[:120])
"

echo
echo "== 5) 服务与端口 =="
for u in phone-hub phone-agent phone-wall ws-scrcpy mihomo; do printf "  %-12s %s\n" "$u" "$(systemctl is-active $u 2>/dev/null)"; done
for p in 8901 8902 8910 8000; do printf "  :%s → %s\n" "$p" "$(curl -s -m 6 -o /dev/null -w '%{http_code}' http://127.0.0.1:$p/ 2>/dev/null)"; done
echo -n "  设备: "; curl -s -m 10 http://127.0.0.1:8901/devices | python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print('%d 台，可用 %d' % (len(d), sum(1 for x in d if x['usable'])))"
echo
echo "=== 验收结束 ==="
