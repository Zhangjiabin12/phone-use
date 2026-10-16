#!/bin/bash
# phone-use 服务端部署（幂等，可反复执行）
#
# 在仓库根目录执行：
#   scp src/*.py deploy/*.env deploy/phone-farm deploy/install-all.sh \
#       deploy/install-frozen-base.sh deploy/units/*.service \
#       docs/SKILL-phone-use-wlan.md docs/ONBOARD.md docs/AGENT-PROMPT.md src/phone-look.py \
#       tools/pu-node.py root@<host>:/tmp/
#   ssh root@<host> bash /tmp/install-all.sh
#
# 部署内容：服务代码、systemd 单元、统一入口 CLI、启动器。
# 底层冻结与校验清单由 deploy/install-frozen-base.sh 完成；任务主体由 deploy/install-qwen-agent.sh 完成。
set -e

echo "== 1) 目录 =="
mkdir -p /usr/local/share/phone-hub /usr/local/share/phone-agent /usr/local/share/phone-wall \
         /usr/local/share/phone-use /usr/local/share/phone-farm /opt/phone-use-jar \
         /opt/phone-use/base /opt/phone-use/work/{copies,adapt,notes}

echo "== 2) 服务代码 =="
cp -f /tmp/phone-hub.py       /usr/local/share/phone-hub/phone-hub.py
cp -f /tmp/phone-hub-mcp.py   /usr/local/share/phone-hub/phone-hub-mcp.py
cp -f /tmp/phone-doctor.py    /usr/local/share/phone-hub/phone-doctor.py
cp -f /tmp/phone-agent.py     /usr/local/share/phone-agent/phone-agent.py
cp -f /tmp/phone-wall.py      /usr/local/share/phone-wall/phone-wall.py
[ -f /tmp/wall-page.html ] && cp -f /tmp/wall-page.html /usr/local/share/phone-wall/wall-page.html
cp -f /tmp/pu-node.py         /opt/phone-use-jar/pu-node.py
[ -f /tmp/agent.env ] && cp -f /tmp/agent.env /usr/local/share/phone-agent/agent.env
[ -f /tmp/hub.env ]   && cp -f /tmp/hub.env   /usr/local/share/phone-hub/hub.env
[ -f /tmp/farm.env ]  && cp -f /tmp/farm.env  /usr/local/share/phone-farm/farm.env
chmod +x /usr/local/share/phone-hub/phone-hub-mcp.py /usr/local/share/phone-agent/phone-agent.py \
         /usr/local/share/phone-wall/phone-wall.py /opt/phone-use-jar/pu-node.py
chmod 600 /usr/local/share/phone-agent/agent.env 2>/dev/null || true

echo "== 3) 底层文件（只读 + 校验清单由 install-frozen-base.sh 处理）=="
for f in phone-hand.py phone-look SKILL.md ONBOARD.md AGENT-PROMPT.md; do
  [ -f "/tmp/$f" ] && cp -f "/tmp/$f" "/opt/phone-use/base/$f"
done
[ -f /tmp/SKILL-phone-use-wlan.md ] && cp -f /tmp/SKILL-phone-use-wlan.md /opt/phone-use/base/SKILL.md
[ -f /tmp/AGENT-PROMPT.md ]         && cp -f /tmp/AGENT-PROMPT.md         /opt/phone-use/base/AGENT-PROMPT.md
[ -f /tmp/phone-look.py ]           && cp -f /tmp/phone-look.py           /opt/phone-use/base/phone-look
# hub 供出的任务手册与接入清单（与底层保持同一份内容）
cp -f /opt/phone-use/base/SKILL.md  /usr/local/share/phone-use/SKILL.md
cp -f /opt/phone-use/base/ONBOARD.md /usr/local/share/phone-use/ONBOARD.md 2>/dev/null || true
rm -rf /usr/local/share/phone-use/__pycache__

echo "== 4) 启动器 =="
# 原语入口：带校验
cat > /usr/local/bin/phone-hand <<'H'
#!/bin/bash
BASE=/opt/phone-use/base
if [ -f /opt/phone-use/base.sha256 ]; then
  ( cd "$BASE" && sha256sum -c /opt/phone-use/base.sha256 --status 2>/dev/null ) || {
    echo "底层文件校验失败：$BASE 与 base.sha256 不一致，拒绝执行。" >&2; exit 90; }
fi
exec python3 "$BASE/phone-hand.py" "$@"
H
# 屏幕识别入口：带校验
cat > /usr/local/bin/phone-look <<'H'
#!/bin/bash
BASE=/opt/phone-use/base
if [ -f /opt/phone-use/base.sha256 ]; then
  ( cd "$BASE" && sha256sum -c /opt/phone-use/base.sha256 --status 2>/dev/null ) || {
    echo "底层文件校验失败：$BASE 与 base.sha256 不一致，拒绝执行。" >&2; exit 90; }
fi
exec python3 "$BASE/phone-look" "$@"
H
# 任务入口
[ -f /tmp/phone-use ] && install -m 755 /tmp/phone-use /usr/local/bin/phone-use
chmod 755 /usr/local/bin/phone-hand /usr/local/bin/phone-look
# 服务侧命令
for pair in "phone-hub.py:phone-hub" "phone-doctor.py:phone-doctor" "phone-agent.py:phone-agent"; do
  src=${pair%%:*}; dst=${pair##*:}
  case $dst in
    phone-hub)     ln -sf /usr/local/share/phone-hub/$src     /usr/local/bin/$dst ;;
    phone-doctor)  ln -sf /usr/local/share/phone-hub/$src     /usr/local/bin/$dst ;;
    phone-agent)   ln -sf /usr/local/share/phone-agent/$src   /usr/local/bin/$dst ;;
  esac
done

echo "== 5) systemd 单元 =="
for u in phone-hub phone-agent phone-wall; do
  [ -f /tmp/$u.service ] && cp -f /tmp/$u.service /etc/systemd/system/$u.service
  f=/etc/systemd/system/$u.service
  [ -f "$f" ] && { grep -q 'phone-farm/farm.env' "$f" || \
    sed -i 's#^\[Service\]#[Service]\nEnvironmentFile=-/usr/local/share/phone-farm/farm.env#' "$f"; }
done
[ -f /tmp/phone-farm ] && install -m 755 /tmp/phone-farm /usr/local/bin/phone-farm
systemctl daemon-reload
for u in phone-hub phone-agent phone-wall; do systemctl enable $u >/dev/null 2>&1 || true; done

echo "== 6) 重启 =="
systemctl restart phone-hub; sleep 6
systemctl restart phone-agent phone-wall; sleep 3

echo "== 7) 自检 =="
systemctl is-active phone-hub phone-agent phone-wall | tr '\n' ' '; echo
curl -s -m 10 http://127.0.0.1:8901/ ; echo
curl -s -m 15 http://127.0.0.1:8902/health; echo
curl -s -m 10 -o /dev/null -w "  phone-wall(8910) http=%{http_code}\n" http://127.0.0.1:8910/
phone-hand state >/dev/null 2>&1 && echo "  phone-hand 可用" || echo "  phone-hand 不可用"
phone-use logs >/dev/null 2>&1 && echo "  phone-use 可用"  || echo "  phone-use 待装任务主体"
