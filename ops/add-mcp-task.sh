#!/bin/bash
set -u
echo "===== A) 摘掉异步调用里多余的 body 参数 ====="
python3 - <<'PY'
import ast
p='/usr/local/share/phone-agent/phone-agent.py'
s=open(p,encoding='utf-8').read()
n0=s.count(', body=body')
s=s.replace(', body=body)',' )').replace(', body=body','')
open(p,'w',encoding='utf-8').write(s)
ast.parse(s)
print("  移除 %d 处 body=body" % n0)
PY
systemctl restart phone-agent; sleep 4
echo "  phone-agent=$(systemctl is-active phone-agent)"
echo
echo "== 异步复测 =="
RESP=$(curl -s -m 30 -X POST -H 'Content-Type: application/json' -d '{"text":"一句话：几台手机可用？","max_steps":8}' http://127.0.0.1:8902/tasks 2>/dev/null)
JOB=$(echo "$RESP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('id') or '')" 2>/dev/null)
echo "  提交: $(echo "$RESP" | head -c 120)"
for i in $(seq 1 24); do
  sleep 5
  R=$(curl -s -m 15 http://127.0.0.1:8902/tasks/$JOB 2>/dev/null)
  ST=$(echo "$R" | python3 -c "import json,sys;print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
  case "$ST" in done|failed|cancelled)
    echo "$R" | python3 -c "
import json,sys
d=json.load(sys.stdin); r=(d.get('result') or d)
print('  最终 status=%s verdict=%s steps=%s elapsed=%s serial=%s delegated=%s' % (d.get('status'),r.get('verdict'),r.get('steps'),r.get('elapsed'),r.get('serial'),r.get('delegated')))
print('  keys=%s' % sorted(r.keys()))
print('  answer 片段:', str(r.get('answer'))[-160:].replace(chr(10),' | '))
"; break;;
  *) [ $i -le 2 ] && echo "  轮询$i status=$ST";;
  esac
done

echo
echo "===== B) 本机 MCP 增加 phone_task（走异步作业，契约与 URL 一致）====="
python3 - <<'PY'
import ast
p='/usr/local/share/phone-hub/phone-hub-mcp.py'
s=open(p,encoding='utf-8').read()
if 'phone_task' in s:
    print("  已存在")
else:
    s=s.replace('def main():', '''def phone_task(args):
    """给一句话任务：提交到 8902 的异步作业接口，轮询到结束或超时；返回契约与 HTTP 接口一致"""
    text = args.get("text") or ""
    dev = args.get("device") or "auto"
    timeout_s = int(args.get("timeout_s") or 600)
    body = {"text": text, "device": dev}
    if args.get("max_steps"):
        body["max_steps"] = args["max_steps"]
    r = http("POST", "/tasks", body, base=AGENT_BASE, timeout=60)
    jid = r.get("id") or r.get("job_id")
    if not jid:
        return {"ok": False, "verdict": "ERROR", "answer": "提交失败：%s" % str(r)[:200]}
    import time as _t
    t0 = _t.time()
    while _t.time() - t0 < timeout_s:
        _t.sleep(5)
        st = http("GET", "/tasks/%s" % jid, base=AGENT_BASE, timeout=30)
        if st.get("status") in ("done", "failed", "cancelled"):
            res = st.get("result") or {}
            return {"ok": bool(res.get("ok")), "job": jid, "status": st.get("status"),
                    "verdict": res.get("verdict"), "serial": res.get("serial"),
                    "delegated": res.get("delegated"), "steps": res.get("steps"),
                    "elapsed": res.get("elapsed"), "trace": res.get("trace"),
                    "answer": str(res.get("answer"))[-4000:]}
    return {"ok": True, "job": jid, "status": "running",
            "answer": "等待 %ss 仍未结束；查进度 GET /tasks/%s，放弃 POST /tasks/%s/cancel" % (timeout_s, jid, jid)}


def main():''', 1)
    # 工具注册：找到 TOOLS 列表并追加
    s=s.replace('''    {"name": "phone_skill",''', '''    {"name": "phone_task",
     "description": "给一句话任务（连网/认证/取证等）。提交异步作业并等待结束；返回 verdict(PASS/FAIL/ANSWER/TIMEOUT/BLOCKED)、serial、steps、elapsed、trace 与答复原文。",
     "inputSchema": {"type": "object", "properties": {
        "text": {"type": "string", "description": "任务语句"},
        "device": {"type": "string", "description": "终端 serial，默认 auto"},
        "max_steps": {"type": "integer", "description": "最多工具调用步数"},
        "timeout_s": {"type": "integer", "description": "等待上限（秒），默认 600"}},
        "required": ["text"]}},
    {"name": "phone_skill",''', 1)
    s=s.replace('def call_tool(name, args):', '''def call_tool(name, args):
    if name == "phone_task":
        return phone_task(args)''', 1)
    # http() 支持 base 参数
    s=s.replace('def http(method, path, body=None, timeout=600):',
                'AGENT_BASE = os.environ.get("PHONE_AGENT_BASE", "http://127.0.0.1:8902")\n\n\ndef http(method, path, body=None, timeout=600, base=None):')
    s=s.replace('HUB + path', '(base or HUB) + path')
    open(p,'w',encoding='utf-8').write(s)
    ast.parse(s)
    print("  已加 phone_task 工具")
PY
python3 -c "import ast;ast.parse(open('/usr/local/share/phone-hub/phone-hub-mcp.py').read());print('  MCP 语法 OK')"

echo
echo "== MCP 工具面（stdio JSON-RPC）+ phone_task 实测 =="
{ echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
  echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"phone_task","arguments":{"text":"一句话：现在几台手机可用？不要做别的。","timeout_s":420}}}'
} | timeout 500 python3 /usr/local/share/phone-hub/phone-hub-mcp.py 2>/dev/null | python3 -c "
import json,sys
for line in sys.stdin:
    line=line.strip()
    if not line.startswith('{'): continue
    try: d=json.loads(line)
    except Exception: continue
    i=d.get('id')
    if i==2:
        print('  工具面:', [t['name'] for t in d['result']['tools']])
    if i==3:
        c=d['result']['content'][0]['text']
        try:
            r=json.loads(c)
            print('  phone_task → job=%s status=%s verdict=%s serial=%s steps=%s elapsed=%s' % (r.get('job'),r.get('status'),r.get('verdict'),r.get('serial'),r.get('steps'),r.get('elapsed')))
            print('  答复片段:', str(r.get('answer'))[-200:].replace(chr(10),' | '))
        except Exception:
            print('  phone_task 原始返回:', c[:300])
"
