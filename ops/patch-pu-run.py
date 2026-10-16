import re
p = '/usr/local/bin/pu-run'
s = open(p, encoding='utf-8').read()

# 1) 提示词文件放到 pu 目录（phonebot 可读），并显式放开权限；stderr 留档
s = s.replace('P=$(mktemp /tmp/pu-task-XXXX.txt); printf \'%s\' "$TASK" > "$P"',
              'P=$PU/.task-$TS.txt; printf \'%s\' "$TASK" > "$P"; chmod 644 "$P"; ERR=$PU/logs/run-$TS.err')
s = s.replace('--approval-mode yolo --output-format json" > "$JSONL" 2>/dev/null',
              '--approval-mode yolo --output-format json" > "$JSONL" 2>"$ERR"')

# 2) 解析器：JSONL 里若掺了非 JSON 文本，也把 stderr 摘要打出来便于定位
s = s.replace('print("  事件类型:", dict(kinds))',
              'print("  事件类型:", dict(kinds))\nprint("  轨迹字节:", __import__("os").path.getsize(src))')
open(p, 'w', encoding='utf-8').write(s)
print("  已修：提示词文件权限 + stderr 留档 + 轨迹字节数")
