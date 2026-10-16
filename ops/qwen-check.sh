#!/bin/bash
exec > /tmp/qwen-check.log 2>&1
echo "=== 1) qwen 装在哪、谁能跑 ==="
echo -n "  root:      "; command -v qwen || echo "(root 无)"
echo -n "  /usr/local/bin/qwen: "; ls -l /usr/local/bin/qwen 2>/dev/null || echo "(无)"
echo -n "  mp 用户:   "; sudo -u mp bash -lc 'command -v qwen || echo 无' 2>&1 | tail -1
echo -n "  mp 版本:   "; sudo -u mp bash -lc 'qwen --version 2>&1 | head -2' 2>&1 | tr '\n' ' '; echo
echo -n "  phonebot:  "; sudo -u phonebot bash -lc 'command -v qwen || echo 无' 2>&1 | tail -1
echo "  mp 家目录里的相关目录:"; ls -d /home/mp/.qwen /home/mp/.local/bin /home/mp/.npm-global 2>/dev/null | sed 's/^/    /'
echo "  mp 的 node/npm:"; sudo -u mp bash -lc 'node -v; npm -v' 2>&1 | tr '\n' ' '; echo

echo
echo "=== 2) pu 项目目录（项目级 .qwen）==="
PU=/opt/phone-use/pu
mkdir -p "$PU"/{.qwen/agents,logs}
[ -f "$PU/.qwen/system.md" ] || cp -f /opt/phone-use/base/AGENT-PROMPT.md "$PU/.qwen/system.md"
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
cat > "$PU/.qwen/settings.json" <<JSON
{
  "env": {
    "OPENAI_API_KEY": "$KEY",
    "OPENAI_BASE_URL": "http://131.255.36.100:30001/v1",
    "OPENAI_MODEL": "deepseek-flash"
  }
}
JSON
# 让 mp 能用这个项目目录（项目级配置 + 可写的 work）
chown -R mp:mp "$PU" 2>/dev/null
[ -f "$PU/.qwen/settings.json" ] && chmod 600 "$PU/.qwen/settings.json"
mkdir -p /opt/phone-use/work/{copies,adapt,notes}
chown -R mp:mp /opt/phone-use/work 2>/dev/null
echo "  $(ls -ld "$PU" | awk '{print $1,$3":"$4,$9}')"
find "$PU" -maxdepth 2 -printf '    %M %u:%G %p\n' | head -8

echo
echo "=== 3) 项目级无头冒烟（以 mp 跑，从 pu 目录进）==="
sudo -iu mp bash -lc "cd $PU && timeout 420 qwen -p '只做两件事：(1) 运行 curl -s http://127.0.0.1:8901/devices 并用一句话列出每台设备的 serial/backend/usable；(2) 运行 phone-look CTV0221202007036 \"一句话：现在是什么页面？\" 并复述结论。不做别的。' --approval-mode yolo 2>&1 | tail -35"
echo "QWEN_CHECK_DONE"
