#!/bin/bash
BASE=/opt/phone-use/base
TS=$(date +%s)
echo "== 1) 复制到 work/copies 再改（遵守我们自己的规矩）=="
cp -f $BASE/phone-look /opt/phone-use/work/copies/phone-look.$TS
NEW=/opt/phone-use/work/copies/phone-look.$TS
python3 - "$NEW" <<'PY'
import ast, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = '''    k = os.environ.get("PHONE_LOOK_KEY") or os.environ.get("PHONE_AGENT_API_KEY")'''
new = '''    # 取值顺序：显式指定 > agent 传下来的 OPENAI_API_KEY > BU 网关 key 文件
    k = (os.environ.get("PHONE_LOOK_KEY") or os.environ.get("PHONE_AGENT_API_KEY")
         or os.environ.get("OPENAI_API_KEY"))'''
if old in s:
    s = s.replace(old, new, 1)
s = s.replace('os.environ.get("PHONE_LOOK_BASE", DEFAULT_BASE)',
              'os.environ.get("PHONE_LOOK_BASE") or os.environ.get("OPENAI_BASE_URL") or DEFAULT_BASE')
open(p, 'w', encoding='utf-8').write(s)
ast.parse(s)
print("  副本已改，语法 OK；含 OPENAI_API_KEY:", "OPENAI_API_KEY" in s)
PY

echo "== 2) 提升到 base + 重算指纹 =="
cp -f "$NEW" $BASE/phone-look && chmod 555 $BASE/phone-look
( cd $BASE && sha256sum * > /opt/phone-use/base.sha256 )
echo "  指纹: $(grep phone-look $BASE/../base.sha256 | cut -c1-16)  文件: $(ls -l $BASE/phone-look | awk '{print $1}')"
phone-use state >/dev/null 2>&1 && echo "  守卫: OK" || echo "  守卫: 失败"

echo "== 3) 以 mp 复测（qwen 会把 settings.json 的 env 传给子进程）=="
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
sudo -u mp bash -lc "OPENAI_API_KEY='$KEY' OPENAI_BASE_URL=http://131.255.36.100:30001/v1 phone-look CTV0221202007036 '一句话：现在是什么页面？' 2>&1 | head -5"
echo "--- 顺便：mp 直接跑（不给 key，应该仍 401，验证取值链）---"
sudo -u mp bash -lc "phone-look CTV0221202007036 '一句话：什么页面' 2>&1 | head -2"
