import re
p = '/usr/local/bin/phone-farm'
s = open(p, encoding='utf-8').read()
done = []
if 'PHONE_FARM_PORT_MCP' not in s:
    out = []
    for ln in s.splitlines():
        if '[scrcpy]=${PHONE_FARM_PORT_SCRCPY:-8000}' in ln and 'PHONE_FARM_PORT_MCP' not in ln:
            ln = ln.rstrip()
            # 若行尾是续行反斜杠，插到反斜杠之前
            if ln.endswith('\\'):
                ln = ln[:-1].rstrip() + ' [mcp]=${PHONE_FARM_PORT_MCP:-8903} \\'
            else:
                ln = ln + ' [mcp]=${PHONE_FARM_PORT_MCP:-8903}'
            done.append('PORT')
        out.append(ln)
    s = "\n".join(out) + "\n"
    open(p, 'w', encoding='utf-8').write(s)
print("已补:", done or "（本来就有）")
