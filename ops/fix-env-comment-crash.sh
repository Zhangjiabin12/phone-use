#!/bin/bash
# 修复 phone-agent 崩溃循环：① 配置去掉行内注释 ② 代码侧防御（容忍行内注释）
set -uo pipefail
echo "== 修前状态 =="
for u in phone-hub phone-agent phone-wall; do printf "  %-12s %s\n" "$u" "$(systemctl is-active $u 2>/dev/null)"; done
echo "  最近崩溃原因:"; journalctl -u phone-agent -n 6 --no-pager 2>/dev/null | grep -iE 'valueerror|traceback|int\(\)' | tail -2 | sed 's/^/    /'

echo
echo "== ① 配置：去掉行内注释 =="
cp -f /tmp/farm.env /usr/local/share/phone-farm/farm.env
echo "  仍含行内注释的行数: $(grep -cE '^[A-Z_]+=.*#' /usr/local/share/phone-farm/farm.env)"

echo
echo "== ② 代码：环境变量读取容忍行内注释（phone-agent / phone-hub）=="
python3 - <<'PY'
import re
HELPER = '''

def _clean_env(v, default=None):
    """取值时去掉行内注释与空白（systemd EnvironmentFile 不会去掉 # 后的内容）"""
    if v is None:
        return default
    v = str(v).split("#", 1)[0].strip()
    return v if v != "" else default


def _envint(name, default):
    """读整数环境变量；容忍 '1200 # 注释' 这种写法"""
    return int(_clean_env(os.environ.get(name), default))
'''
for path in ("/usr/local/share/phone-agent/phone-agent.py", "/usr/local/share/phone-hub/phone-hub.py"):
    s = open(path, encoding="utf-8").read()
    orig = s
    if "_envint(" not in s:
        lines = s.split("\n")
        idx = max([i for i, l in enumerate(lines) if l.startswith(("import ", "from "))] or [0])
        lines.insert(idx + 1, HELPER)
        s = "\n".join(lines)
    # int(os.environ.get(...))  →  _envint(...)
    s = re.sub(r"int\(os\.environ\.get\(([^()]*)\)\)", r"_envint(\1)", s)
    # 字符串型：os.environ.get("X", "默认") → _clean_env(os.environ.get("X"), "默认")
    s = re.sub(r'(?<!_clean_env\()os\.environ\.get\((\"[A-Z_]+\",\s*\"[^\"]*\")\)', r"_clean_env(os.environ.get(\1))", s)
    if s != orig:
        open(path, "w", encoding="utf-8").write(s)
    import ast
    ast.parse(s)
    print("  %-42s 已改，语法 OK；剩余裸 int(os.environ.get()：%d" % (
        path.split("/")[-1], len(re.findall(r"int\(os\.environ\.get\(", s))))
PY

echo
echo "== 重启并验证 =="
systemctl daemon-reload
for u in phone-hub phone-agent phone-wall; do systemctl restart $u; done
sleep 10
for u in phone-hub phone-agent phone-wall; do printf "  %-12s %s\n" "$u" "$(systemctl is-active $u 2>/dev/null)"; done
echo "  agent /health: $(curl -s -m 8 http://127.0.0.1:8902/health)"
echo "  生效的 DEADLINE（应为纯数字）:"
systemctl show phone-agent -p Environment 2>/dev/null | tr ' ' '\n' | grep -E 'DEADLINE|MAX_STEPS' | sed 's/^/    /'
echo "  有没有再崩:"; journalctl -u phone-agent --since '30 seconds ago' --no-pager 2>/dev/null | grep -ciE 'valueerror|traceback' | sed 's/^/    报错行数=/'
