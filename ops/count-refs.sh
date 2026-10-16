#!/bin/bash
echo "== 引用了 phone-use 的文件与次数 =="
for f in /opt/phone-use/base/* /usr/local/share/phone-hub/*.py /usr/local/share/phone-use/* /usr/local/bin/phone-* /opt/phone-use/pu/.qwen/system.md /opt/phone-use/pu/.qwen/settings.json; do
  [ -f "$f" ] || continue
  n=$(grep -c 'phone-use' "$f" 2>/dev/null || echo 0)
  [ "$n" -gt 0 ] && printf "  %-56s %s 处\n" "$f" "$n"
done
echo
echo "== 原语调用样式（决定要替换成 phone-hand 的写法）=="
grep -rhoE 'phone-use [a-z][a-z-]*' /opt/phone-use/base /usr/local/share/phone-hub /opt/phone-use/pu/.qwen 2>/dev/null | sort | uniq -c | sort -rn | head -14
echo
echo "== 入口现状 =="
ls -l /usr/local/bin/phone-use /usr/local/bin/phone-look /usr/local/bin/pu-run 2>/dev/null | sed 's/^/  /'
echo
echo "== hub 的 exec 接口（手机墙/agent 实际调用路径）=="
grep -n 'phone-use\|argv' /usr/local/share/phone-hub/phone-hub.py 2>/dev/null | head -6
echo
echo "== MCP 工具面里提到 phone-use 的地方 =="
grep -n 'phone-use' /usr/local/share/phone-hub/phone-hub-mcp.py 2>/dev/null | head -6
