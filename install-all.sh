#!/bin/bash
# 一键部署/更新 36.102 上的手机农场全家桶（幂等，可反复跑）
# 用法：把本目录的源文件 scp 到 /tmp 后，在 102 上 `bash install-all.sh`
#   scp phone-use-v4.py SKILL-phone-use-wlan.md pu-node.py phone-hub.py phone-hub-mcp.py \
#       phone-agent.py agent.env phone-wall-svc.py \
#       phone-hub.service phone-agent.service phone-wall.service \
#       root@131.255.36.102:/tmp/  &&  ssh root@131.255.36.102 'bash /tmp/install-all.sh'
set -e
echo "== 1) 目录 =="
mkdir -p /usr/local/share/phone-use /usr/local/share/phone-hub /usr/local/share/phone-agent \
         /usr/local/share/phone-wall /opt/phone-use-jar
echo "== 2) 原语与服务代码 =="
cp -f /tmp/phone-use-v4.py     /usr/local/share/phone-use/phone-use.py
cp -f /tmp/SKILL-phone-use-wlan.md /usr/local/share/phone-use/SKILL.md
cp -f /tmp/pu-node.py          /opt/phone-use-jar/pu-node.py
cp -f /tmp/phone-hub.py        /usr/local/share/phone-hub/phone-hub.py
cp -f /tmp/phone-hub-mcp.py    /usr/local/share/phone-hub/phone-hub-mcp.py
cp -f /tmp/phone-doctor.py     /usr/local/share/phone-hub/phone-doctor.py
cp -f /tmp/ONBOARD.md          /usr/local/share/phone-use/ONBOARD.md
cp -f /tmp/phone-agent.py      /usr/local/share/phone-agent/phone-agent.py
[ -f /tmp/agent.env ] && cp -f /tmp/agent.env /usr/local/share/phone-agent/agent.env
cp -f /tmp/phone-wall-svc.py   /usr/local/share/phone-wall/phone-wall.py
cp -f /tmp/wall-page.html      /usr/local/share/phone-wall/wall-page.html
[ -f /tmp/hub.env ] && cp -f /tmp/hub.env /usr/local/share/phone-hub/hub.env
chmod +x /usr/local/share/phone-use/phone-use.py /usr/local/share/phone-hub/phone-hub-mcp.py \
         /usr/local/share/phone-agent/phone-agent.py /usr/local/share/phone-wall/phone-wall.py \
         /opt/phone-use-jar/pu-node.py
chmod 600 /usr/local/share/phone-agent/agent.env 2>/dev/null || true
ln -sf /usr/local/share/phone-use/phone-use.py   /usr/local/bin/phone-use
ln -sf /usr/local/share/phone-hub/phone-hub.py   /usr/local/bin/phone-hub
ln -sf /usr/local/share/phone-hub/phone-doctor.py /usr/local/bin/phone-doctor
ln -sf /usr/local/share/phone-agent/phone-agent.py /usr/local/bin/phone-agent
rm -rf /usr/local/share/phone-use/__pycache__
echo "== 3) systemd 单元 =="
for u in phone-hub phone-agent phone-wall; do cp -f /tmp/$u.service /etc/systemd/system/$u.service; done
systemctl daemon-reload
for u in phone-hub phone-agent phone-wall; do systemctl enable $u >/dev/null 2>&1 || true; done
echo "== 4) 重启 =="
systemctl restart phone-hub; sleep 6      # hub 要先起来（agent/wall 依赖它的 /devices）
systemctl restart phone-agent phone-wall; sleep 3
touch /var/log/phone-agent.log
echo "== 5) 自检 =="
systemctl is-active phone-hub phone-agent phone-wall | tr '\n' ' '; echo
curl -s -m 10 http://127.0.0.1:8901/ ; echo
curl -s -m 15 http://127.0.0.1:8902/health; echo
curl -s -m 10 -o /dev/null -w "  phone-wall(8910) http=%{http_code}\n" http://127.0.0.1:8910/
curl -s -m 10 http://127.0.0.1:8901/skill | python3 -c "import json,sys;print('  runbook %d 字'%len(json.load(sys.stdin)['skill']))"
