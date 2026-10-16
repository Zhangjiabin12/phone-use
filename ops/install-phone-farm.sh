#!/bin/bash
# 安装/更新 phone-farm 统一入口与配置，并让各单元读取同一个配置文件
set -e
mkdir -p /usr/local/share/phone-farm
cp -f /tmp/farm.env /usr/local/share/phone-farm/farm.env
install -m 755 /tmp/phone-farm /usr/local/bin/phone-farm

# 各单元加一行 EnvironmentFile（放在最前，后面的显式 Environment= 仍可覆盖单项）
for u in phone-hub phone-agent phone-wall ws-scrcpy mihomo; do
  f=/etc/systemd/system/$u.service
  [ -f "$f" ] || continue
  if ! grep -q 'phone-farm/farm.env' "$f"; then
    python3 - "$f" <<'PY'
import sys,re
p=sys.argv[1]; t=open(p).read()
t=t.replace('[Service]\n','[Service]\nEnvironmentFile=-/usr/local/share/phone-farm/farm.env\n',1)
open(p,'w').write(t)
PY
  fi
done
systemctl daemon-reload
for u in phone-hub phone-agent phone-wall ws-scrcpy mihomo; do systemctl restart $u 2>/dev/null || true; done
sleep 6
echo "=== 验证 phone-farm ==="
phone-farm ports
echo
phone-farm status
echo
echo "=== 日志入口验证（hub 最近 3 行）==="
phone-farm logs hub -n 3 --no-pager | tail -3
