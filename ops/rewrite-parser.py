import re

p = '/usr/local/bin/phone-use'
s = open(p, encoding='utf-8').read()

start = s.find("python3 - \"$JSONL\" \"$MD\" <<'PY'")
assert start >= 0, "找不到解析器起点"
end_marker = "\nPY\n"
end = s.find(end_marker, start)
assert end > start, "找不到解析器终点"

NEW = '''python3 - "$JSONL" "$MD" <<'PY'
import json, sys, collections, os, time

src, out = sys.argv[1], sys.argv[2]
raw = open(src, encoding='utf-8', errors='ignore').read().strip()
lines = []
if raw:
    try:
        d = json.loads(raw)
        lines = d if isinstance(d, list) else [d]
    except Exception:
        for ln in raw.splitlines():
            ln = ln.strip()
            if ln.startswith('{'):
                try:
                    lines.append(json.loads(ln))
                except Exception:
                    pass

kinds = collections.Counter(x.get('type') or x.get('subtype') or '?' for x in lines)
tools, cmds, texts = [], [], []


def walk(o):
    if isinstance(o, dict):
        n = o.get('name') or o.get('tool_name') or o.get('toolName')
        if isinstance(n, str) and n not in ('', 'system'):
            inp = o.get('input') or o.get('args') or o.get('arguments') or {}
            if isinstance(inp, dict):
                tools.append((n, json.dumps(inp, ensure_ascii=False)[:200]))
                c = inp.get('command') or inp.get('cmd')
                if isinstance(c, str):
                    cmds.append(c)
        for k in ('text', 'content', 'message', 'result'):
            v = o.get(k)
            if isinstance(v, str) and len(v) > 20:
                texts.append(v)
            elif isinstance(v, list):
                for part in v:
                    if isinstance(part, dict) and isinstance(part.get('text'), str) and len(part['text']) > 20:
                        texts.append(part['text'])
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)


walk(lines)
final = (texts[-1] if texts else '').strip()
txt_all = '\\n'.join(texts)
verdict = 'PASS' if 'RESULT: PASS' in txt_all else ('FAIL' if 'RESULT: FAIL' in txt_all else 'ANSWER')
elapsed = int(time.time() - int(os.environ.get('T0', '0') or 0))

# 人读摘要（给复盘用）
with open(out, 'w', encoding='utf-8') as f:
    f.write('# 运行摘要\\n\\n结论判语: %s\\n步数: %d\\n耗时: %ds\\n轨迹: %s\\n\\n## 工具调用（%d）\\n' % (
        verdict, len(tools), elapsed, src, len(tools)))
    for i, (n, a) in enumerate(tools, 1):
        f.write('%2d. %s  %s\\n' % (i, n, a))
    f.write('\\n## 结论\\n\\n%s\\n' % (final or '(无)'))

# 机读行与轨迹摘要 → stderr（不污染人读输出）
print('PU_RESULT ' + json.dumps({'verdict': verdict, 'steps': len(tools), 'elapsed': elapsed,
                                 'trace': src, 'summary': out}, ensure_ascii=False), file=sys.stderr)
print('步数: %d   耗时: %ds' % (len(tools), elapsed), file=sys.stderr)
print('轨迹: %s' % src, file=sys.stderr)
print('摘要: %s' % out, file=sys.stderr)

# stdout 只给结论
print(final if final else '(本次未产出结论，详情见上方轨迹文件)', flush=True)
PY'''

s = s[:start] + NEW + s[end + len(end_marker):]
open(p, 'w', encoding='utf-8').write(s)

# 语法检查：抽出 heredoc 内容做 ast.parse
m = re.search(r"python3 - \"\$JSONL\" \"\$MD\" <<'PY'\n(.*?)\nPY", s, re.S)
import ast
ast.parse(m.group(1))
print("解析器已整段重写，Python 语法 OK")
