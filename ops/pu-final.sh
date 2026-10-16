#!/bin/bash
exec > /tmp/pu-final.log 2>&1
rm -f /tmp/pu-final.done
set -x
BASE=/opt/phone-use/base
PU=/opt/phone-use/pu
TS=$(date +%s)

echo "############ ① phone-look：key/端点回退读项目级 .qwen/settings.json ############"
cp -f $BASE/phone-look /opt/phone-use/work/copies/phone-look.$TS
NEW=/opt/phone-use/work/copies/phone-look.$TS
python3 - "$NEW" <<'PY'
import ast, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = '''    except Exception:
        pass
    return ""'''
new = '''    except Exception:
        pass
    # 回退：读项目级 .qwen/settings.json 的 env（phonebot 可读，600）
    try:
        import json as _json
        for cand in ("/opt/phone-use/pu/.qwen/settings.json",
                     os.path.expanduser("~/.qwen/settings.json")):
            if os.path.exists(cand):
                k = ((_json.load(open(cand, encoding="utf-8")).get("env") or {})
                     .get("OPENAI_API_KEY"))
                if k:
                    return str(k).strip()
    except Exception:
        pass
    return ""'''
assert old in s, "key 回退锚点未找到"
s = s.replace(old, new, 1)
old2 = '''    _base = (os.environ.get("PHONE_LOOK_BASE") or os.environ.get("OPENAI_BASE_URL")
             or DEFAULT_BASE).rstrip("/")'''
new2 = '''    _base = (os.environ.get("PHONE_LOOK_BASE") or os.environ.get("OPENAI_BASE_URL")
             or _proj_base() or DEFAULT_BASE).rstrip("/")'''
s = s.replace(old2, new2, 1)
s = s.replace('def bu_key():', '''def _proj_base():
    """端点也回退读项目级配置"""
    try:
        import json as _json
        for cand in ("/opt/phone-use/pu/.qwen/settings.json",
                     os.path.expanduser("~/.qwen/settings.json")):
            if os.path.exists(cand):
                b = ((_json.load(open(cand, encoding="utf-8")).get("env") or {})
                     .get("OPENAI_BASE_URL"))
                if b:
                    return str(b).strip()
    except Exception:
        pass
    return None


def bu_key():''', 1)
open(p, 'w', encoding='utf-8').write(s)
ast.parse(s); print("  ✓ 副本已改（key+端点都回退项目级配置）")
PY
cp -f "$NEW" $BASE/phone-look && chmod 555 $BASE/phone-look
( cd $BASE && sha256sum * > /opt/phone-use/base.sha256 )
echo -n "  以 phonebot 直跑（不给任何 env）: "
sudo -iu phonebot bash -lc 'phone-look CTV0221202007036 "一句话：什么页面" 2>&1 | head -2' | tr '\n' ' '; echo

echo
echo "############ ② 挂 MCP（项目级 settings.json 的 mcpServers）############"
cp -f $PU/.qwen/settings.json $PU/.qwen/settings.json.bak.$TS
python3 - <<'PY'
import json
p = '/opt/phone-use/pu/.qwen/settings.json'
d = json.load(open(p, encoding='utf-8'))
d.setdefault('mcpServers', {})['phone-hub'] = {
    "command": "/usr/bin/python3",
    "args": ["/usr/local/share/phone-hub/phone-hub-mcp.py"],
    "env": {"PHONE_HUB_BASE": "http://127.0.0.1:8901"},
    "trust": True
}
json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print("  mcpServers:", list(d['mcpServers']))
PY
chown phonebot:phonebot $PU/.qwen/settings.json; chmod 600 $PU/.qwen/settings.json
echo -n "  qwen 看到的 MCP: "; sudo -iu phonebot bash -lc "cd $PU && qwen mcp list 2>&1 | head -6" | tr '\n' ' '; echo
echo "  （顺带确认：qwen 没有 skills 子命令，技能以 system.md + 读 SKILL.md 的方式给）"
echo -n "  qwen 子命令: "; sudo -iu phonebot bash -lc 'qwen --help 2>&1 | sed -n "/Commands:/,/^$/p" | tr "\n" " " | cut -c1-200'; echo

echo
echo "############ ③ 跑第一单：portal 认证（phonebot，从 pu 目录，无头）############"
LOG=$PU/logs/portal-$(date +%Y%m%d-%H%M%S).log
sudo -iu phonebot bash -lc "cd $PU && timeout 900 qwen -p '连 test-portal2 做 portal 认证，账号 zjb 密码 123456；完成后必须确认能上外网；给出证据（SSID/BSSID/IP/门户返回/截图）；先读 /opt/phone-use/base/SKILL.md' --approval-mode yolo" > "$LOG" 2>&1
echo "  日志: $LOG ($(wc -l < $LOG) 行)"
tail -45 "$LOG"
echo PU_FINAL_DONE > /tmp/pu-final.done
