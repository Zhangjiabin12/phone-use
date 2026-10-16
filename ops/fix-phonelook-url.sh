#!/bin/bash
BASE=/opt/phone-use/base
TS=$(date +%s)
cp -f $BASE/phone-look /opt/phone-use/work/copies/phone-look.$TS
NEW=/opt/phone-use/work/copies/phone-look.$TS
python3 - "$NEW" <<'PY'
import ast, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = '''    req = urllib.request.Request(
        os.environ.get("PHONE_LOOK_BASE") or os.environ.get("OPENAI_BASE_URL") or DEFAULT_BASE.rstrip("/") + "/chat/completions",'''
new = '''    _base = (os.environ.get("PHONE_LOOK_BASE") or os.environ.get("OPENAI_BASE_URL")
             or DEFAULT_BASE).rstrip("/")
    req = urllib.request.Request(
        _base + "/chat/completions",'''
if old in s:
    s = s.replace(old, new, 1)
    print("  已修运算符优先级（URL 拼接）")
else:
    print("  锚点没匹配，打印相关两行以便排查：")
    for i, l in enumerate(s.splitlines(), 1):
        if "PHONE_LOOK_BASE" in l or "chat/completions" in l:
            print("   %4d: %s" % (i, l.rstrip()))
open(p, 'w', encoding='utf-8').write(s)
ast.parse(s)
print("  语法 OK")
PY
cp -f "$NEW" $BASE/phone-look && chmod 555 $BASE/phone-look
( cd $BASE && sha256sum * > /opt/phone-use/base.sha256 )
phone-hand state >/dev/null 2>&1 && echo "  守卫 OK" || echo "  守卫 失败"

KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
echo "== 以 mp 复测（带 key，应成功）=="
sudo -u mp bash -lc "OPENAI_API_KEY='$KEY' OPENAI_BASE_URL=http://131.255.36.100:30001/v1 phone-look CTV0221202007036 '一句话：现在是什么页面？' 2>&1 | head -6"
