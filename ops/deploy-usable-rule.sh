#!/bin/bash
# 部署：agent 工具描述 + runbook 硬规则
cp -f /tmp/phone-agent.py /usr/local/share/phone-agent/phone-agent.py
cp -f /tmp/SKILL-phone-use-wlan.md /usr/local/share/phone-use/SKILL.md
python3 -c "import ast; ast.parse(open('/usr/local/share/phone-agent/phone-agent.py').read()); print('语法 OK')"
echo -n "  agent 里的判据句数: "; grep -c '挑终端必须以' /usr/local/share/phone-agent/phone-agent.py
echo -n "  runbook 硬规则: "; grep -c '硬规则（挑终端）' /usr/local/share/phone-use/SKILL.md
systemctl restart phone-agent; sleep 4
echo "  phone-agent: $(systemctl is-active phone-agent)"
python3 - <<'PY'
import json,urllib.request
t=json.load(urllib.request.urlopen('http://127.0.0.1:8901/skill'))['skill']
print('  8901 供出的 runbook 含硬规则:', '硬规则（挑终端）' in t)
PY
