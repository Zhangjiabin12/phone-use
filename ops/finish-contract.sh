#!/bin/bash
set -u
echo "===== A) 异步作业补齐契约字段（serial/delegated/trace/elapsed）====="
python3 - <<'PY'
import ast
p='/usr/local/share/phone-agent/phone-agent.py'
s=open(p,encoding='utf-8').read()
if 'CONTRACT_KEYS' in s:
    print("  已补")
else:
    s=s.replace('j["result"] = run_task(text, device, devices=devices, cancel=j["cancel"], job=j )',
                'j["result"] = run_task(text, device, devices=devices, cancel=j["cancel"], job=j )')
    # 在赋值之后合并字段
    anchor = 'j["result"] = run_task('
    i = s.find(anchor)
    if i >= 0:
        j = s.find('\n', i)
        ins = ('\n            CONTRACT_KEYS = ("ok", "verdict", "serial", "delegated", "steps", "elapsed", "trace")\n'
               '            for _k in CONTRACT_KEYS:\n'
               '                if isinstance(j.get("result"), dict) and j["result"].get(_k) is not None:\n'
               '                    j[_k] = j["result"][_k]')
        s = s[:j] + ins + s[j:]
        open(p,'w',encoding='utf-8').write(s)
        ast.parse(s); print("  已在异步完成处合并契约字段")
    else:
        print("  锚点未找到")
PY
python3 -c "import ast;ast.parse(open('/usr/local/share/phone-agent/phone-agent.py').read());print('  语法 OK')"
systemctl restart phone-agent; sleep 4
echo "  phone-agent=$(systemctl is-active phone-agent)"

echo
echo "===== B) 把 MCP 的 phone_task 验证丢到后台（不阻塞）====="
cat > /tmp/mcp-verify.sh <<'EOS'
#!/bin/bash
{ echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
  echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"phone_task","arguments":{"text":"一句话：现在几台手机可用？不要做别的。","timeout_s":420}}}'
} | timeout 500 python3 /usr/local/share/phone-hub/phone-hub-mcp.py 2>/dev/null | python3 -c "
import json,sys
for line in sys.stdin:
    line=line.strip()
    if not line.startswith('{'): continue
    try: d=json.loads(line)
    except Exception: continue
    if d.get('id')!=3: continue
    c=d.get('result',{}).get('content') or []
    txt=''
    if c:
        first=c[0]
        txt=first.get('text') if isinstance(first,dict) else str(first)
    print('MCP_CONTENT_TYPE', type(txt).__name__)
    print('MCP_RAW', str(txt)[:800])
" > /tmp/mcp-verify.out 2>&1
echo "MCP_VERIFY_DONE" >> /tmp/mcp-verify.out
EOS
chmod +x /tmp/mcp-verify.sh
nohup bash /tmp/mcp-verify.sh >/dev/null 2>&1 &
echo "  已在后台启动（结果写 /tmp/mcp-verify.out）"

echo
echo "===== C) 同步接口复核（契约字段）====="
curl -s -m 120 -X POST -H 'Content-Type: application/json' -d '{"text":"一句话：当前哪些终端空闲？不要做别的。"}' \
  http://127.0.0.1:8902/task 2>/dev/null | python3 -c "
import json,sys
t=sys.stdin.read()
try:
    d=json.loads(t); r=(d.get('result') or d)
    print('  同步 → verdict=%s ok=%s serial=%s steps=%s elapsed=%s trace=%s' % (r.get('verdict'),r.get('ok'),r.get('serial'),r.get('steps'),r.get('elapsed'),bool(r.get('trace'))))
except Exception: print('  ✗', t[:200])
"
