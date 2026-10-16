import re, os, subprocess, sys
ROOT = r'E:\dsh_project\远程桌面 36.102'

def run(*a):
    return subprocess.run(a, cwd=ROOT, capture_output=True, text=True)

# 1) 仓库里改名：src/phone-use.py → src/phone-hand.py
if os.path.exists(os.path.join(ROOT, 'src', 'phone-use.py')) and not os.path.exists(os.path.join(ROOT, 'src', 'phone-hand.py')):
    run('git', 'mv', 'src/phone-use.py', 'src/phone-hand.py')
    print('  git mv src/phone-use.py → src/phone-hand.py')
# deploy/pu-run → deploy/phone-use
if os.path.exists(os.path.join(ROOT, 'deploy', 'pu-run')) and not os.path.exists(os.path.join(ROOT, 'deploy', 'phone-use')):
    run('git', 'mv', 'deploy/pu-run', 'deploy/phone-use')
    print('  git mv deploy/pu-run → deploy/phone-use')

# 2) 仓库内所有"原语调用"改写为 phone-hand（与线上同一套正则）
VERBS = (r'(state|wifi|list|scan|probe|failure|backend|ui|find|click-text|click-desc|click-id|click-xy'
         r'|settext|scroll|scroll-up|global|tap|swipe|key|input|shot|pull|http|httpfile|shell|wifi-connect|wifi-forget|jar)')
targets = []
for d, _, fs in os.walk(ROOT):
    if '.git' in d: continue
    for f in fs:
        if f.endswith(('.py', '.md', '.sh', '.html', '.json')):
            targets.append(os.path.join(d, f))
changed = []
for p in targets:
    try:
        s = open(p, encoding='utf-8').read()
    except Exception:
        continue
    o = s
    s = re.sub(r'phone-use\s+' + VERBS + r'\b', r'phone-hand \1', s)
    s = s.replace('"phone-use", "shot"', '"phone-hand", "shot"').replace('"phone-use", "pull"', '"phone-hand", "pull"')
    s = s.replace("'phone-use', 'shot'", "'phone-hand', 'shot'").replace("'phone-use', 'pull'", "'phone-hand', 'pull'")
    if s != o:
        open(p, 'w', encoding='utf-8').write(s)
        changed.append(os.path.relpath(p, ROOT))
print('  文档/脚本改名:', len(changed), '个文件')
for c in changed[:10]:
    print('   -', c)

# 3) README §10 里把入口说明改成新命名
rp = os.path.join(ROOT, 'README.md')
s = open(rp, encoding='utf-8').read()
s = s.replace('''### 入口
```bash
pu-run "连 test-portal2 做 portal 认证，账号 zjb 密码 123456" [--timeout 900]
# 一次运行留三份档：logs/run-<ts>.jsonl（全事件轨迹）/ .md（人读摘要）/ .err（stderr）
```''', '''### 三个名字（对外只有这三个）
```bash
phone-use "连 test-portal2 做 portal 认证，账号 zjb 密码 123456"   # 给任务（默认留全轨迹：logs/run-<ts>.{jsonl,md,err}）
phone-use "…" --device <serial> --timeout 900                     # 指定终端 / 超时
phone-use logs                                                     # 看历史运行
phone-hand wifi | probe | tap X Y | click-text "登录" …            # 原语（AI 的手；带 sha256 守卫）
phone-look <serial> "现在什么页面？"                                # 看（AI 的眼）
```
`pu-run` 这个名字已取消，留档能力并入 `phone-use`；旧写法 `phone-use <原语>` 不再兼容（直接用 `phone-hand <原语>`）。''')
open(rp, 'w', encoding='utf-8').write(s)
print('  README §10 入口说明已更新')
