#!/bin/bash
echo "=== A) phonebot 能不能直接用 mp 装的 qwen ==="
namei -l /home/mp/.local/bin/qwen 2>/dev/null | sed 's/^/  /'
echo -n "  phonebot 直接跑 mp 的 qwen: "
sudo -u phonebot bash -lc '/home/mp/.local/bin/qwen --version 2>&1 | head -2' | tr '\n' ' '; echo
echo -n "  phonebot 自己的 PATH 里有吗: "; sudo -u phonebot bash -lc 'command -v qwen || echo 无'

echo
echo "=== B) qwen 0.25.2 到底支持哪些定制入口（事实）==="
sudo -u mp bash -lc 'qwen --help 2>&1 | head -45'

echo
echo "=== C) 它认哪个上下文/提示词文件、怎么配 MCP、有没有 skill 机制 ==="
QDIR=$(sudo -u mp bash -lc 'dirname $(readlink -f $(command -v qwen))')
echo "  qwen 安装位置: $QDIR"
sudo -u mp bash -lc 'npm root -g 2>/dev/null; ls ~/.local/share 2>/dev/null | head'
for f in $(sudo -u mp bash -lc 'ls -d ~/.local/lib/node_modules/@qwen-code/qwen-code 2>/dev/null || ls -d ~/.local/share/qwen* 2>/dev/null'); do
  echo "  --- 在 $f 里找关键字 ---"
  grep -rlo "mcpServers" "$f" 2>/dev/null | head -3
  grep -rho "QWEN\.md\|system\.md\|\.qwen/skills\|skills/" "$f" 2>/dev/null | sort -u | head -8
done

echo
echo "=== D) 我们的 system.md 里有没有写这些硬规矩（逐条核对）==="
S=/opt/phone-use/pu/.qwen/system.md
echo "  文件: $S  ($(wc -c < $S) 字节)"
for kw in "只能" "复制" "只读" "phone-look" "phone-use" "click-text" "find" "判定" "PASS" "adapt"; do
  n=$(grep -c "$kw" "$S" 2>/dev/null)
  printf "    %-12s 出现 %s 次\n" "$kw" "$n"
done
echo "  --- 关键几行原文 ---"
grep -n "只读\|复制\|sha256\|phone-look\|禁止直接" "$S" | head -12 | sed 's/^/    /'

echo
echo "=== E) SKILL（怎么看/怎么点/怎么判定）在不在、agent 能不能读到 ==="
ls -l /opt/phone-use/base/SKILL.md | sed 's/^/  /'
grep -c "怎么看 / 怎么点" /opt/phone-use/base/SKILL.md
grep -n "phone-look\|click-text\|click-xy\|portal_intercepted\|level2FailureCode" /opt/phone-use/base/SKILL.md | head -10 | sed 's/^/    /'
echo -n "  agent(mp) 能读吗: "; sudo -u mp bash -lc 'head -1 /opt/phone-use/base/SKILL.md' >/dev/null 2>&1 && echo "✓ 能读" || echo "✗ 读不到"
