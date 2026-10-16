#!/bin/bash
set -u
echo "== 1) 恢复被改坏的 phone-agent.py（用仓库版）=="
cp -f /usr/local/share/phone-agent/phone-agent.py /tmp/phone-agent.broken.py 2>/dev/null || true
cp -f /tmp/phone-agent.py /usr/local/share/phone-agent/phone-agent.py
python3 -c "import ast;ast.parse(open('/usr/local/share/phone-agent/phone-agent.py').read());print('  恢复后语法 OK')"

echo "== 2) 精确替换 job_view 的 return（整段替换，不猜括号）=="
python3 - <<'PY'
import ast
p='/usr/local/share/phone-agent/phone-agent.py'
s=open(p,encoding='utf-8').read()
old = '''def job_view(j):
    return {"id": j["id"], "status": j["status"], "text": j["text"][:200], "device": j["device"],
            "devices": j["devices"], "created": j["created"], "started": j["started"],
            "finished": j["finished"],
            "elapsed_s": round((j["finished"] or time.time()) - (j["started"] or j["created"]), 1),
            "verdict": (j["result"] or {}).get("verdict"),
            "steps": (j["result"] or {}).get("steps"),
            "answer": ((j["result"] or {}).get("answer") or "")[:1500]}'''
new = '''def job_view(j):
    r = j.get("result") or {}
    return {"id": j["id"], "status": j["status"], "text": j["text"][:200], "device": j["device"],
            "devices": j["devices"], "created": j["created"], "started": j["started"],
            "finished": j["finished"],
            "elapsed_s": round((j["finished"] or time.time()) - (j["started"] or j["created"]), 1),
            "ok": r.get("ok"),
            "verdict": r.get("verdict"),
            "serial": r.get("serial"),
            "delegated": r.get("delegated"),
            "steps": r.get("steps"),
            "elapsed": r.get("elapsed") if r.get("elapsed") is not None else r.get("elapsed_s"),
            "trace": r.get("trace"),
            "answer": (r.get("answer") or "")[:1500]}'''
assert old in s, "job_view 锚点未找到"
s=s.replace(old,new,1)
open(p,'w',encoding='utf-8').write(s)
ast.parse(s); print("  已精确替换，语法 OK")
PY
systemctl restart phone-agent; sleep 5
echo "  phone-agent=$(systemctl is-active phone-agent)"
journalctl -u phone-agent -n 3 --no-pager | tail -2

echo
echo "== 3) 后台复验（异步 URL 与 MCP 各一条小任务，都不阻塞）=="
rm -f /tmp/verify4.out
cat > /tmp/verify4.sh <<'EOS'
#!/bin/bash
{
echo "--- 异步 URL ---"
R=$(curl -s -m 30 -X POST -H 'Content-Type: application/json' -d '{"text":"一句话：几台手机在线？不要做别的。","max_steps":6}' http://127.0.0.1:8902/tasks)
JID=$(echo "$R" | python3 -c "import json,sys;print(json.load(sys.stdin).get('id') or '')")
echo "提交 id=$JID"
for i in $(seq 1 40); do
  sleep 5
  V=$(curl -s -m 15 http://127.0.0.1:8902/tasks/$JID)
  ST=$(echo "$V" | python3 -c "import json,sys;print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
  case "$ST" in done|failed|cancelled)
    echo "$V" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('URL_RESULT status=%s ok=%s verdict=%s serial=%s delegated=%s steps=%s elapsed=%s trace=%s' % (
  d.get('status'),d.get('ok'),d.get('verdict'),d.get('serial'),d.get('delegated'),d.get('steps'),d.get('elapsed'),bool(d.get('trace'))))
"; break;;
  esac
done
echo "--- MCP phone_task ---"
{ echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
  echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"phone_task","arguments":{"text":"一句话：几台手机在线？不要做别的。","timeout_s":300,"max_steps":6}}}'
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
    t=first.get('text') if isinstance(first,dict) else str(first)
    if isinstance(t,str):
        try: t=json.loads(t)
        except Exception: pass
    if isinstance(t,dict):
        print('MCP_RESULT ok=%s status=%s verdict=%s serial=%s delegated=%s steps=%s elapsed=%s trace=%s' % (
          t.get('ok'),t.get('status'),t.get('verdict'),t.get('serial'),t.get('delegated'),t.get('steps'),t.get('elapsed'),bool(t.get('trace'))))
    else:
        print('MCP_RESULT', str(t)[:200])
"
echo VERIFY4_DONE
} > /tmp/verify4.out 2>&1
EOS
chmod +x /tmp/verify4.sh
nohup bash /tmp/verify4.sh >/dev/null 2>&1 &
echo "  已后台启动（/tmp/verify4.out）"
