#!/bin/bash
echo "=== A) 部署物 vs 位置（md5）==="
chk(){ [ -f "$2" ] && printf "  %-26s %-52s %s\n" "$1" "$2" "$(md5sum "$2" | cut -c1-12)" || printf "  %-26s %-52s %s\n" "$1" "$2" "缺失!"; }
chk phone-use.py       /usr/local/share/phone-use/phone-use.py
chk phone-hub.py       /usr/local/share/phone-hub/phone-hub.py
chk phone-hub-mcp.py   /usr/local/share/phone-hub/phone-hub-mcp.py
chk phone-doctor.py    /usr/local/share/phone-hub/phone-doctor.py
chk phone-agent.py     /usr/local/share/phone-agent/phone-agent.py
chk phone-wall.py      /usr/local/share/phone-wall/phone-wall.py
chk wall-page.html     /usr/local/share/phone-wall/wall-page.html
chk pu-node.py         /opt/phone-use-jar/pu-node.py
chk pu.jar             /opt/phone-use-jar/pu.jar
chk SKILL.md           /usr/local/share/phone-use/SKILL.md
chk ONBOARD.md         /usr/local/share/phone-use/ONBOARD.md
chk farm.env           /usr/local/share/phone-farm/farm.env
chk hub.env            /usr/local/share/phone-hub/hub.env
chk agent.env          /usr/local/share/phone-agent/agent.env
chk "phone-farm CLI"    /usr/local/bin/phone-farm
chk "phone-doctor CLI"  /usr/local/bin/phone-doctor
for u in phone-hub phone-agent phone-wall ws-scrcpy mihomo; do chk "$u.service" /etc/systemd/system/$u.service; done

echo
echo "=== B) 服务状态 / 开机自启 ==="
for u in phone-hub phone-agent phone-wall ws-scrcpy mihomo phone-view; do
  printf "  %-12s active=%-11s enabled=%s\n" "$u" "$(systemctl is-active $u 2>/dev/null || echo -)" "$(systemctl is-enabled $u 2>/dev/null || echo -)"
done

echo
echo "=== C) 端口与探测 ==="
for p in 8901 8902 8910 8000 7890; do printf "  :%s → %s\n" "$p" "$(curl -s -m 6 -o /dev/null -w '%{http_code}' http://127.0.0.1:$p/ 2>/dev/null)"; done
echo "  agent /health: $(curl -s -m 8 http://127.0.0.1:8902/health)"
echo -n "  设备数: "; curl -s -m 10 http://127.0.0.1:8901/devices | python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print(len(d),'台，可用', sum(1 for x in d if x['usable']))"

echo
echo "=== D) 102 上有、但仓库里没有的东西（复现缺口）==="
for f in /opt/node16/bin/node /opt/ws-scrcpy/dist/index.js /usr/local/bin/mihomo /etc/mihomo/config.yaml /usr/local/share/phone-farm/farm.env; do
  [ -e "$f" ] && echo "  有: $f   $(du -sh "$f" 2>/dev/null | cut -f1)"
done
echo "  ws-scrcpy 单元在仓库里? $(ls /etc/systemd/system/ws-scrcpy.service >/dev/null 2>&1 && echo '机器上有，仓库无')"

echo
echo "=== E) 密钥检查（只看有没有，不打印值）==="
for f in /usr/local/share/phone-agent/agent.env /usr/local/share/phone-farm/farm.env /usr/local/share/phone-hub/hub.env; do
  [ -f "$f" ] && echo "  $f: KEY/TOKEN 行数=$(grep -ciE 'key|token|secret|password' $f)"
done
echo "  agent 里 key 是否已设: $(curl -s -m 8 http://127.0.0.1:8902/health | python3 -c 'import json,sys;print(json.load(sys.stdin).get("key_set"))' 2>/dev/null)"

echo
echo "=== F) 从零复现要跑的命令（仓库路径）==="
echo "  scp src/*.py src/wall/* deploy/*.env deploy/phone-farm deploy/units/*.service docs/SKILL-phone-use-wlan.md docs/ONBOARD.md tools/pu-node.py root@<host>:/tmp/"
echo "  ssh root@<host> bash /tmp/install-all.sh"
echo "  install-all.sh 里引用的 /tmp 文件名:"
grep -oE '/tmp/[A-Za-z0-9._-]+' /usr/local/share/phone-hub/../phone-use/../../../../tmp/install-all.sh 2>/dev/null | sort -u | sed 's/^/    /' || echo "    (本机 /tmp 下无 install-all.sh，见仓库 deploy/install-all.sh)"
