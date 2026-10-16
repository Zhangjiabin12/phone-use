#!/bin/bash
# 装标准入口 pu-run：一次运行 + JSONL 全轨迹 + 自动人读摘要
cat > /usr/local/bin/pu-run <<'WRAP'
#!/bin/bash
# pu-run "一句话任务" [--timeout 秒] [--user phonebot] [--raw]
# 从 pu 项目目录、以 phonebot、无头跑；一次运行同时留：
#   logs/run-<ts>.jsonl  ← 全事件轨迹（qwen --output-format json）
#   logs/run-<ts>.md     ← 自动生成的人读摘要（工具调用序列 + 最终结论）
PU=/opt/phone-use/pu
U=phonebot; TO=900; TASK=""; RAW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TO="$2"; shift 2;;
    --user) U="$2"; shift 2;;
    --raw) RAW=1; shift;;
    *) TASK="$TASK $1"; shift;;
  esac
done
[ -z "${TASK// }" ] && { echo '用法: pu-run "一句话任务" [--timeout 900] [--user phonebot] [--raw]'; exit 2; }
TS=$(date +%Y%m%d-%H%M%S)
JSONL=$PU/logs/run-$TS.jsonl; MD=$PU/logs/run-$TS.md
P=$(mktemp /tmp/pu-task-XXXX.txt); printf '%s' "$TASK" > "$P"
echo "任务 :$TASK"
echo "轨迹 :$JSONL"
sudo -iu "$U" bash -lc "cd $PU && timeout $TO qwen --prompt \"\$(cat $P)\" --approval-mode yolo --output-format json" > "$JSONL" 2>/dev/null
RC=$?
rm -f "$P"
python3 - "$JSONL" "$MD" <<'PY'
import json, sys, collections, re
src, out = sys.argv[1], sys.argv[2]
lines = []
for ln in open(src, encoding='utf-8', errors='ignore'):
    ln = ln.strip()
    if ln.startswith('{'):
        try: lines.append(json.loads(ln))
        except Exception: pass
kinds = collections.Counter(x.get('type') or x.get('subtype') or '?' for x in lines)
tools, cmds, texts = [], [], []
def walk(o):
    if isinstance(o, dict):
        n = o.get('name') or o.get('tool_name') or o.get('toolName')
        if isinstance(n, str) and n not in ('', 'system'):
            inp = o.get('input') or o.get('args') or o.get('arguments') or {}
            if isinstance(inp, dict):
                tools.append((n, json.dumps(inp, ensure_ascii=False)[:160]))
                c = inp.get('command') or inp.get('cmd')
                if isinstance(c, str): cmds.append(c)
        for k in ('text', 'content', 'message', 'result'):
            v = o.get(k)
            if isinstance(v, str) and len(v) > 40: texts.append(v)
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(lines)
# 最终结论：取最后一段较长的文本
final = texts[-1] if texts else ''
with open(out, 'w', encoding='utf-8') as f:
    f.write("# pu-run 摘要\n\n事件类型分布: %s\n\n## 工具调用序列（%d 次）\n" % (dict(kinds), len(tools)))
    for i, (n, a) in enumerate(tools, 1): f.write("%2d. %s  %s\n" % (i, n, a))
    if cmds:
        f.write("\n## 关键命令（%d 条）\n" % len(cmds))
        for c in cmds: f.write("- `%s`\n" % c[:160])
    f.write("\n## 最终结论\n\n%s\n" % (final or '(未捕获到文本结论)'))
print("  事件类型:", dict(kinds))
print("  工具调用:", len(tools), " 关键命令:", len(cmds))
print("\n----- 工具调用序列（前 20）-----")
for i, (n, a) in enumerate(tools[:20], 1): print("  %2d. %-22s %s" % (i, n, a[:120]))
print("\n----- 最终结论（前 25 行）-----")
for l in (final or '(无)').splitlines()[:25]: print("  " + l)
PY
echo "人读摘要: $MD"
[ "$RAW" = 1 ] && { echo "----- 原始事件（尾 5 行）-----"; tail -5 "$JSONL"; }
exit $RC
WRAP
chmod 755 /usr/local/bin/pu-run
echo "  已安装: $(wc -l < /usr/local/bin/pu-run) 行"
echo
echo "=== 实测（一条小任务，验证轨迹+摘要）==="
pu-run "运行 curl -s http://127.0.0.1:8901/devices，用一句话列出每台设备的 serial 和 usable。不要做别的。" --timeout 300 2>&1 | tail -30
