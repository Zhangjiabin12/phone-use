import re, sys

# 1) phone-use：stdout 只留「结论」，机读行与轨迹摘要移到 stderr
p = '/usr/local/bin/phone-use'
s = open(p, encoding='utf-8').read()
if 'META_ON_STDERR' in s:
    print("  入口已是新版")
else:
    # 把解析器里的人读输出改写：结论 → stdout；其余 → stderr
    old = '''print("  事件类型:", dict(kinds))'''
    new = '''import sys as _sys
print("PU_RESULT " + json.dumps({"verdict": _v0, "steps": len(tools), "elapsed": _el0,
                                 "trace": src, "summary": out}, ensure_ascii=False), file=_sys.stderr)  # META_ON_STDERR'''
    assert old in s, "入口锚点缺失"
    s = s.replace(old, new, 1)
    # 删掉后续的杂项打印（事件类型/轨迹字节/工具调用列/最终结论标题/人读摘要/PU_RESULT 行）
    s = s.replace('''print("  轨迹字节:", __import__("os").path.getsize(src))''', '''print("轨迹: %s (%d 字节)" % (src, __import__("os").path.getsize(src)), file=_sys.stderr)''')
    s = s.replace('''print("  工具调用:", len(tools), " 关键命令:", len(cmds))''', '''print("工具调用: %d  关键命令: %d" % (len(tools), len(cmds)), file=_sys.stderr)''')
    s = s.replace('''print("\\n----- 工具调用序列（前 20）-----")
for i, (n, a) in enumerate(tools[:20], 1): print("  %2d. %-22s %s" % (i, n, a[:120]))''', '''for i, (n, a) in enumerate(tools[:20], 1): print("  %2d. %-22s %s" % (i, n, a[:120]), file=_sys.stderr)''')
    s = s.replace('''print("\\n----- 最终结论（前 25 行）-----")
for l in (final or '(无)').splitlines()[:25]: print("  " + l)''', '''print(final or '(无结论)', flush=True)''')
    s = s.replace('''print("人读摘要: $MD")''', '''print("人读摘要: $MD", file=_sys.stderr)''')
    s = s.replace('''print("PU_RESULT " + json.dumps({"verdict": _v, "steps": len(tools), "elapsed": _el,
                                 "trace": src, "summary": out}, ensure_ascii=False))''', '''print("", file=_sys.stderr)''')
    # 追加到 stderr 的机读行需要 verdict/elapsed 变量：从 PU_RESULT 段前的计算里取
    s = s.replace('''_el = int(__import__("time").time() - int(__import__("os").environ.get("T0", "0") or 0))
_v = "PASS" if "RESULT: PASS" in (open(src, encoding="utf-8", errors="ignore").read()) else (
     "FAIL" if "RESULT: FAIL" in (open(src, encoding="utf-8", errors="ignore").read()) else "ANSWER")''',
'''_el0 = int(__import__("time").time() - int(__import__("os").environ.get("T0", "0") or 0))
_txt_all = open(src, encoding="utf-8", errors="ignore").read()
_v0 = "PASS" if "RESULT: PASS" in _txt_all else ("FAIL" if "RESULT: FAIL" in _txt_all else "ANSWER")''')
    open(p, 'w', encoding='utf-8').write(s)
    print("  phone-use 已改为：stdout=结论，stderr=机读行+轨迹")

# 2) phone-agent：PU_RESULT 从 stdout+stderr 合并里解析（机读行现在在 stderr）
q = '/usr/local/share/phone-agent/phone-agent.py'
t = open(q, encoding='utf-8').read()
if 'MERGED_OUT_ERR' in t:
    print("  agent 已是新版")
else:
    t = t.replace('''        out = (pr.stdout or "") + (("\\n[stderr]\\n" + pr.stderr[-800:]) if pr.returncode else "")''',
                  '''        out = (pr.stdout or "") + "\\n" + (pr.stderr or "")  # MERGED_OUT_ERR''')
    # answer 只保留 stdout（结论），机读行在 stderr 里不影响人读
    t = t.replace('''            "trace": trace, "answer": out[-6000:]}''',
                  '''            "trace": trace, "answer": (pr.stdout or "")[-6000:] or out[-6000:]}''')
    open(q, 'w', encoding='utf-8').write(t)
    import ast; ast.parse(t)
    print("  agent 已改为合并解析 + answer 只取结论")
PY = None
