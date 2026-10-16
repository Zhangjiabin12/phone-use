#!/bin/bash
set -u
echo "== 1) job_view 补齐契约字段（serial/delegated/trace/elapsed）=="
python3 - <<'PY'
import ast
p='/usr/local/share/phone-agent/phone-agent.py'
s=open(p,encoding='utf-8').read()
i=s.find('def job_view(j):')
print("  job_view 原文:")
print("   ", s[i:i+420].replace("\n","\n    ")[:420])
if 'CONTRACT' in s[i:i+600]:
    print("  已是新版")
else:
    # 在 job_view 的 return 字典里插入契约字段
    j=s.find('return {', i)
    k=s.find('}', j)
    seg=s[j:k]
    add = (''',
            "ok": (j.get("result") or {}).get("ok"),
            "serial": (j.get("result") or {}).get("serial"),
            "delegated": (j.get("result") or {}).get("delegated"),
            "steps": (j.get("result") or {}).get("steps"),
            "elapsed": (j.get("result") or {}).get("elapsed") or (j.get("result") or {}).get("elapsed_s"),
            "trace": (j.get("result") or {}).get("trace")''')
    s = s[:k] + add + s[k:]
    open(p,'w',encoding='utf-8').write(s)
    ast.parse(s); print("  已插入契约字段，语法 OK")
PY
systemctl restart phone-agent; sleep 4
echo "  phone-agent=$(systemctl is-active phone-agent)"

echo
echo "== 2) 后台复验 MCP phone_task（小任务，不阻塞）=="
rm -f /tmp/mcp-verify3.out
cat > /tmp/mcp-verify3.sh <<'EOS'
#!/bin/bash
{ echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
  echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"phone_task","arguments":{"text":"一句话：现在几台手机在线？不要做别的。","timeout_s":300,"max_steps":6}}}'
} | timeout 400 python3 /usr/local/share/phone-hub/phone-hub-mcp.py 2>/dev/null | python3 -c "
import json,sys
for line in sys.stdin:
    line=line.strip()
    if not line.startswith('{'): continue
    try: d=json.loads(line)
    except Exception: continue
    if d.get('id')!=3: continue
    c=d.get('result',{}).get('content') or []
    first=c[0] if c else {}
    txt=first.get('text') if isinstance(first,dict) else str(first)
    if isinstance(txt,str):
        try: txt=json.loads(txt)
        except Exception: pass
    if isinstance(txt,dict):
        print('MCP_RESULT ok=%s job=%s status=%s verdict=%s serial=%s delegated=%s steps=%s elapsed=%s trace=%s' % (
            txt.get('ok'),txt.get('job'),txt.get('status'),txt.get('verdict'),txt.get('serial'),
            txt.get('delegated'),txt.get('steps'),txt.get('elapsed'),bool(txt.get('trace'))))
        print('MCP_ANSWER', str(txt.get('answer'))[-240:].replace(chr(10),' | '))
    else:
        print('MCP_RESULT', str(txt)[:300])
" > /tmp/mcp-verify3.out 2>&1
echo MCP_VERIFY3_DONE >> /tmp/mcp-verify3.out
EOS
chmod +x /tmp/mcp-verify3.sh
nohup bash /tmp/mcp-verify3.sh >/dev/null 2>&1 &
echo "  已后台启动（/tmp/mcp-verify3.out）"
