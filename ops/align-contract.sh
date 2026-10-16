#!/bin/bash
# 统一契约：字段对齐(serial/delegated/steps/elapsed/trace) + 判语统一(PASS/FAIL/ANSWER/TIMEOUT/BLOCKED) + max_steps 透传
# 三条路都改：phone-use 入口 / 8902 URL(同步+异步) / 本机 stdio MCP(新增 phone_task)
set -u
echo "===== A) 入口 phone-use：加 --max-steps，并输出机读结果行 PU_RESULT ====="
python3 - <<'PY'
p='/usr/local/bin/phone-use'
s=open(p,encoding='utf-8').read()
if 'PU_RESULT' not in s:
    s=s.replace('U=phonebot; TO=900; TASK=""; RAW=0; DEV=""','U=phonebot; TO=900; TASK=""; RAW=0; DEV=""; MAXS=""; T0=$(date +%s)')
    s=s.replace('    --device) DEV="$2"; shift 2;;','    --device) DEV="$2"; shift 2;;\n    --max-steps) MAXS="$2"; shift 2;;')
    s=s.replace('--approval-mode yolo --output-format json" > "$JSONL" 2>"$ERR"',
                '--approval-mode yolo ${MAXS:+--max-tool-calls $MAXS} --output-format json" > "$JSONL" 2>"$ERR"')
    # 解析器末尾追加机读结果行（steps=工具调用数、elapsed=秒）
    s=s.replace('''print("  事件类型:", dict(kinds))''',
'''print("  事件类型:", dict(kinds))
_el = int(__import__("time").time() - int(__import__("os").environ.get("T0", "0") or 0))
_v = "PASS" if "RESULT: PASS" in (open(src, encoding="utf-8", errors="ignore").read()) else (
     "FAIL" if "RESULT: FAIL" in (open(src, encoding="utf-8", errors="ignore").read()) else "ANSWER")
print("PU_RESULT " + json.dumps({"verdict": _v, "steps": len(tools), "elapsed": _el,
                                 "trace": src, "summary": out}, ensure_ascii=False))''')
    # 把 T0 传进 python
    s=s.replace('python3 - "$JSONL" "$MD" <<\'PY\'','export T0\npython3 - "$JSONL" "$MD" <<\'PY\'')
    open(p,'w',encoding='utf-8').write(s)
    print("  入口已改")
else:
    print("  入口已是新版")
PY
bash -n /usr/local/bin/phone-use && echo "  入口语法 OK"

echo
echo "===== B) 8902：委派返回对齐字段 + max_steps 透传（同步与异步共用 run_task，天然一致）====="
python3 - <<'PY'
import ast
p='/usr/local/share/phone-agent/phone-agent.py'
s=open(p,encoding='utf-8').read()
if 'PU_RESULT' in s:
    print("  已是新版")
else:
    # B1) 委派函数：解析 PU_RESULT、带 steps/elapsed/trace、支持 max_steps
    s=s.replace('''def delegate_to_phone_use(text, device="auto", timeout=None):''',
'''def delegate_to_phone_use(text, device="auto", timeout=None, max_steps=None):''')
    s=s.replace('''        cmd = ["phone-use", text]
        if ser:
            cmd += ["--device", ser]''',
'''        cmd = ["phone-use", text]
        if ser:
            cmd += ["--device", ser]
        ms = max_steps or os.environ.get("PHONE_AGENT_MAX_STEPS") or ""
        if str(ms).strip():
            cmd += ["--max-steps", str(ms).strip()]''')
    s=s.replace('''    if re.search(r"RESULT:\\s*PASS", out):
        v = "PASS"
    elif re.search(r"RESULT:\\s*FAIL", out):
        v = "FAIL"
    else:
        v = "ANSWER"
    return {"ok": v in ("PASS", "ANSWER"), "verdict": v, "serial": ser,
            "answer": out[-6000:], "delegated": "phone-use"}''',
'''    steps = elapsed = trace = None
    m = re.search(r"PU_RESULT (\\{.*\\})", out)
    if m:
        try:
            d = json.loads(m.group(1))
            v = d.get("verdict") or "ANSWER"
            steps, elapsed, trace = d.get("steps"), d.get("elapsed"), d.get("trace")
        except Exception:
            v = "ANSWER"
    elif re.search(r"RESULT:\\s*PASS", out):
        v = "PASS"
    elif re.search(r"RESULT:\\s*FAIL", out):
        v = "FAIL"
    else:
        v = "ANSWER"
    if v not in ("PASS", "FAIL", "ANSWER", "TIMEOUT", "BLOCKED"):
        v = "ANSWER"
    return {"ok": v in ("PASS", "ANSWER"), "verdict": v, "serial": ser,
            "delegated": "phone-use", "steps": steps, "elapsed": elapsed,
            "trace": trace, "answer": out[-6000:]}''')
    # B2) 委派分支接受 max_steps
    s=s.replace('return delegate_to_phone_use(text, device=device, timeout=None)',
                'return delegate_to_phone_use(text, device=device, timeout=None,\n                                     max_steps=(body or {}).get("max_steps"))')
    # B3) run_task 签名与 POST 解析（把 body 传进来）
    s=s.replace('def run_task(text, device="auto", devices=None, cancel=None, job=None):',
                'def run_task(text, device="auto", devices=None, cancel=None, job=None, body=None):')
    s=s.replace('j["result"] = run_task(text, device, devices=devices, cancel=j["cancel"], job=j)',
                'j["result"] = run_task(text, device, devices=devices, cancel=j["cancel"], job=j, body=body)')
    open(p,'w',encoding='utf-8').write(s)
    ast.parse(s)
    print("  已改（若异步提交处未传 body，下面脚本会再补）")
PY

# 找到异步/同步提交处，确保把请求体透传进 run_task
python3 - <<'PY'
import ast, re
p='/usr/local/share/phone-agent/phone-agent.py'
s=open(p,encoding='utf-8').read()
# 异步提交：threading.Thread(target=..., args=(text, device ...)) 形态；找出调用点
for m in re.finditer(r'run_task\([^)]*\)', s):
    print("  调用点:", m.group(0)[:120])
open(p,'w',encoding='utf-8').write(s)
PY
python3 -c "import ast;ast.parse(open('/usr/local/share/phone-agent/phone-agent.py').read());print('  phone-agent 语法 OK')"
systemctl restart phone-agent; sleep 4
echo "  phone-agent=$(systemctl is-active phone-agent)"
echo "  （若委派未生效，下一步验证会显示缺字段，我再补线程参数）"
