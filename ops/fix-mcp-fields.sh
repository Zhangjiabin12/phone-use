#!/bin/bash
set -u
echo "== 1) 修 phone_task 的字段读取（result 优先，缺失则取平铺字段）=="
python3 - <<'PY'
import ast
p='/usr/local/share/phone-hub/phone-hub-mcp.py'
s=open(p,encoding='utf-8').read()
old = '''            res = st.get("result") or {}
            return {"ok": bool(res.get("ok")), "job": jid, "status": st.get("status"),
                    "verdict": res.get("verdict"), "serial": res.get("serial"),
                    "delegated": res.get("delegated"), "steps": res.get("steps"),
                    "elapsed": res.get("elapsed"), "trace": res.get("trace"),
                    "answer": str(res.get("answer"))[-4000:]}'''
new = '''            res = st.get("result")
            if not isinstance(res, dict):
                # 作业对象可能把结果平铺在同一层
                res = {"ok": st.get("ok"), "verdict": st.get("verdict"), "serial": st.get("serial"),
                       "delegated": st.get("delegated"), "steps": st.get("steps"),
                       "elapsed": st.get("elapsed") or st.get("elapsed_s"),
                       "trace": st.get("trace"), "answer": st.get("answer")}
            v = res.get("verdict")
            ok = res.get("ok")
            if ok is None and isinstance(v, str):
                ok = v in ("PASS", "ANSWER")
            return {"ok": bool(ok), "job": jid, "status": st.get("status"),
                    "verdict": v, "serial": res.get("serial"), "delegated": res.get("delegated"),
                    "steps": res.get("steps"), "elapsed": res.get("elapsed") or res.get("elapsed_s"),
                    "trace": res.get("trace"), "answer": str(res.get("answer"))[-4000:]}'''
assert old in s, "锚点未找到"
s=s.replace(old,new,1)
open(p,'w',encoding='utf-8').write(s)
ast.parse(s); print("  已修，语法 OK")
PY

echo "== 2) 后台复验（小任务，不阻塞）=="
cat > /tmp/mcp-verify2.sh <<'EOS'
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
        print('MCP_RESULT ok=%s job=%s status=%s verdict=%s serial=%s steps=%s elapsed=%s trace=%s' % (
            txt.get('ok'),txt.get('job'),txt.get('status'),txt.get('verdict'),txt.get('serial'),
            txt.get('steps'),txt.get('elapsed'),bool(txt.get('trace'))))
        print('MCP_ANSWER', str(txt.get('answer'))[-260:].replace(chr(10),' | '))
    else:
        print('MCP_RESULT', str(txt)[:300])
" > /tmp/mcp-verify2.out 2>&1
echo MCP_VERIFY2_DONE >> /tmp/mcp-verify2.out
EOS
chmod +x /tmp/mcp-verify2.sh
nohup bash /tmp/mcp-verify2.sh >/dev/null 2>&1 &
echo "  已后台启动（/tmp/mcp-verify2.out）"

echo "== 3) 顺带确认异步作业平铺字段（取最近一个已完成作业看结构）=="
curl -s -m 15 http://127.0.0.1:8902/tasks/job001 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  作业键:', sorted(d.keys()))
print('  result 段是否存在:', isinstance(d.get('result'), dict))
print('  平铺: verdict=%s serial=%s steps=%s elapsed_s=%s trace=%s' % (d.get('verdict'),d.get('serial'),d.get('steps'),d.get('elapsed_s'),bool(d.get('trace'))))
" 2>/dev/null || echo "  (作业已过期)"
