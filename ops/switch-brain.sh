#!/bin/bash
# 把 8902（phone-agent）与手机墙的派任务切成新脑子；并做旧名字残留审计
set -u
echo "===== 0) 旧名字残留审计（应只剩"入口"用法）====="
echo "-- 仍在调原语的旧写法（phone-use <动词>）--"
grep -rnE 'phone-use +(state|wifi|list|scan|probe|failure|backend|ui|find|click-[a-z]+|settext|scroll|global|tap|swipe|key|input|shot|pull|http|shell|jar|wifi-connect|wifi-forget)' \
  /opt/phone-use/base /usr/local/share/phone-hub /usr/local/share/phone-wall /usr/local/share/phone-use /usr/local/bin /etc/systemd/system /opt/phone-use/tools 2>/dev/null | grep -v '\.old' | head -10
echo "-- 仍指向旧可执行文件路径的 --"
grep -rn 'phone-use\.py\|/usr/local/share/phone-use/phone-use' /usr/local/share/phone-hub /usr/local/share/phone-wall /usr/local/bin /opt/phone-use/tools 2>/dev/null | grep -v '\.old' | head -10
echo "  （以上无输出 = 干净）"

echo
echo "===== 1) 给入口 phone-use 加 --device 支持 ====="
python3 - <<'PY'
p = '/usr/local/bin/phone-use'
s = open(p, encoding='utf-8').read()
if '--device' not in s:
    s = s.replace('U=phonebot; TO=900; TASK=""; RAW=0', 'U=phonebot; TO=900; TASK=""; RAW=0; DEV=""')
    s = s.replace('    --user) U="$2"; shift 2;;', '    --user) U="$2"; shift 2;;\n    --device) DEV="$2"; shift 2;;')
    s = s.replace('P=$PU/.task-$TS.txt; printf \'%s\' "$TASK" > "$P"; chmod 644 "$P"; ERR=$PU/logs/run-$TS.err',
                  'P=$PU/.task-$TS.txt; { [ -n "$DEV" ] && printf \'只操作这一台终端：%s。\\n\' "$DEV"; printf \'%s\' "$TASK"; } > "$P"; chmod 644 "$P"; ERR=$PU/logs/run-$TS.err')
    s = s.replace('sudo -iu "$U" bash -lc "cd $PU && timeout $TO qwen',
                  'sudo -iu "$U" bash -lc "cd $PU && ${DEV:+export ANDROID_SERIAL=$DEV;} timeout $TO qwen')
    open(p, 'w', encoding='utf-8').write(s)
    print("  已加 --device（会导出 ANDROID_SERIAL 并在任务里点名该终端）")
else:
    print("  （已支持）")
PY
bash -n /usr/local/bin/phone-use && echo "  入口脚本语法 OK"

echo
echo "===== 2) phone-agent(8902) 退化为"新脑子的 HTTP 门面" ====="
python3 - <<'PY'
import ast, re
p = '/usr/local/share/phone-agent/phone-agent.py'
s = open(p, encoding='utf-8').read()
if 'DELEGATE_TO_PHONE_USE' in s:
    print("  （已改过，跳过）")
else:
    helper = '''

# ===== DELEGATE_TO_PHONE_USE：本服务退化为新脑子（phone-use 入口 = Qwen Code）的 HTTP 门面 =====
def _pick_free_device():
    try:
        for d in http("GET", "/devices", timeout=30).get("devices", []):
            if d.get("usable") and d.get("state") == "idle":
                return d["serial"]
    except Exception:
        pass
    return None


def delegate_to_phone_use(text, device="auto", timeout=None):
    ser = device if device and device not in ("auto", "", None) else _pick_free_device()
    owner = "phone-agent:%s" % (ser or "auto")
    leased = False
    if ser:
        try:
            http("POST", "/devices/%s/lease" % ser, {"owner": owner, "ttl": 1800}, timeout=30)
            leased = True
        except Exception as e:
            return {"ok": False, "verdict": "BLOCKED", "serial": ser,
                    "answer": "终端不可用或被占用：%s" % str(e)[:200]}
    try:
        cmd = ["phone-use", text]
        if ser:
            cmd += ["--device", ser]
        pr = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout or DEADLINE)
        out = (pr.stdout or "") + (("\\n[stderr]\\n" + pr.stderr[-800:]) if pr.returncode else "")
    except subprocess.TimeoutExpired:
        out = "任务超时（%ss）" % (timeout or DEADLINE)
        if leased:
            try: http("POST", "/devices/%s/release" % ser, {"owner": owner}, timeout=15)
            except Exception: pass
        return {"ok": False, "verdict": "TIMEOUT", "answer": out, "serial": ser}
    finally:
        if leased:
            try: http("POST", "/devices/%s/release" % ser, {"owner": owner}, timeout=15)
            except Exception: pass
    if re.search(r"RESULT:\\s*PASS", out):
        v = "PASS"
    elif re.search(r"RESULT:\\s*FAIL", out):
        v = "FAIL"
    else:
        v = "ANSWER"
    return {"ok": v in ("PASS", "ANSWER"), "verdict": v, "serial": ser,
            "answer": out[-6000:], "delegated": "phone-use"}
'''
    s = s.replace('\ndef run_task(', helper + '\n\ndef run_task(', 1)
    s = s.replace('def run_task(', 'def run_task(', 1)
    # 在 run_task 开头插入委派分支
    m = re.search(r'def run_task\(([^)]*)\):\n', s)
    body_start = m.end()
    indent = '    '
    s = s[:body_start] + indent + 'if os.environ.get("PHONE_AGENT_DELEGATE", "1") == "1":\n' + \
        indent + '    return delegate_to_phone_use(text, device=device, timeout=None)\n' + s[body_start:]
    open(p, 'w', encoding='utf-8').write(s)
    ast.parse(s)
    print("  已插入委派分支，语法 OK")
PY
python3 -c "import ast;ast.parse(open('/usr/local/share/phone-agent/phone-agent.py').read());print('  phone-agent 语法 OK')"
systemctl restart phone-agent; sleep 4
echo "  phone-agent=$(systemctl is-active phone-agent)"

echo
echo "===== 3) 验证：8902 收一句话 → 委派新脑子 → 返回结论 ====="
curl -s -m 420 -X POST -H 'Content-Type: application/json' \
  -d '{"text":"运行 curl -s http://127.0.0.1:8901/devices，一句话列出三台 serial 和 usable。不要做别的。"}' \
  http://127.0.0.1:8902/task 2>/dev/null | python3 -c "
import json,sys
t=sys.stdin.read()
try:
    d=json.loads(t); r=d.get('result') or d
    print('  verdict=%s  serial=%s  delegated=%s' % (r.get('verdict'), r.get('serial'), r.get('delegated')))
    print('  结论片段:', str(r.get('answer'))[-300:].replace(chr(10),' | '))
except Exception as e:
    print('  解析失败:', t[:300])
"

echo
echo "===== 4) 验证：手机墙派任务端到端 ====="
curl -s -m 420 -X POST -H 'Content-Type: application/json' -d '{"text":"一句话：现在有几台手机在线？"}' \
  http://127.0.0.1:8910/api/task 2>/dev/null | head -c 400; echo
echo DONE_ALL
