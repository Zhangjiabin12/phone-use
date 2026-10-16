#!/bin/bash
# AutoGLM 适配包：① 解析容错 ② adb 拦截层（我们的原语优先，失败回退它自带的 adb）
set -e
cd /opt/autoglm/Open-AutoGLM

echo "=== ① 解析层容错（改 phone_agent/actions/handler.py）==="
python3 - <<'PY'
p = '/opt/autoglm/Open-AutoGLM/phone_agent/actions/handler.py'
s = open(p, encoding='utf-8').read()
if 'ADAPT_SANITIZE' not in s:
    old = """    try:
        response = response.strip()
        if response.startswith('do(action="Type"'):"""
    new = """    try:
        response = response.strip()
        # ADAPT_SANITIZE: 容忍模型把 </answer>/``` 与动作写在同一行（deepseek-flash 常见）
        import re as _re
        response = _re.split(r"</?answer>|</?think>|```", response)[0].strip()
        if response.startswith('do(action="Type"'):"""
    assert old in s, "锚点未找到"
    s = s.replace(old, new, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print("  ✓ 已加解析容错（ADAPT_SANITIZE）")
else:
    print("  = 已有容错，跳过")
import ast; ast.parse(open(p, encoding='utf-8').read()); print("  ✓ 语法 OK")
PY

echo
echo "=== ② adb 拦截层：/opt/autoglm/shim/adb ==="
mkdir -p /opt/autoglm/shim
cat > /opt/autoglm/shim/adb <<'SHIM'
#!/bin/bash
# 先我们的 phone-use 原语（P1 root / P2 input / P3 jar 自动回退），失败再放行给真 adb
# 只拦坐标/按键/文字这类"注入"动作；其余（push/pull/shell 读信息/ime/pm）一律透传
REAL_ADB=/usr/bin/adb
args=("$@")
serial="${ANDROID_SERIAL:-}"
rest=()
i=0
while [ $i -lt ${#args[@]} ]; do
  if [ "${args[$i]}" = "-s" ]; then serial="${args[$((i+1))]}"; i=$((i+2)); continue; fi
  rest+=("${args[$i]}"); i=$((i+1))
done
[ ${#rest[@]} -ge 3 ] && [ "${rest[0]}" = "shell" ] || exec "$REAL_ADB" "${args[@]}"
cmd=("${rest[@]:1}")
case "${cmd[0]}" in
  input)
    sub="${cmd[1]:-}"
    case "$sub" in
      tap)
        if ANDROID_SERIAL="$serial" timeout 60 phone-use tap "${cmd[2]}" "${cmd[3]}" 2>/dev/null | grep -q '"ok": *true'; then
          echo "phone-use: tap ${cmd[2]} ${cmd[3]} ok"; exit 0
        fi ;;
      swipe)
        if ANDROID_SERIAL="$serial" timeout 60 phone-use swipe "${cmd[2]}" "${cmd[3]}" "${cmd[4]}" "${cmd[5]}" "${cmd[6]:-300}" 2>/dev/null | grep -q '"ok": *true'; then
          echo "phone-use: swipe ok"; exit 0
        fi ;;
      keyevent)
        if ANDROID_SERIAL="$serial" timeout 60 phone-use key "${cmd[2]}" 2>/dev/null | grep -q '"ok": *true'; then
          echo "phone-use: key ${cmd[2]} ok"; exit 0
        fi ;;
      text)
        txt="${cmd[*]:2}"
        if ANDROID_SERIAL="$serial" timeout 60 phone-use input "$txt" 2>/dev/null | grep -q '"ok": *true'; then
          echo "phone-use: input ok"; exit 0
        fi ;;
    esac ;;
esac
exec "$REAL_ADB" "${args[@]}"
SHIM
chmod 755 /opt/autoglm/shim/adb
echo "  ✓ shim 已建（$(wc -l < /opt/autoglm/shim/adb) 行）"

echo
echo "=== ③ 验证 shim：先我们的原语，失败才回退 ==="
export ANDROID_SERIAL=CTV0221202007036
echo -n "  经 shim 点一下(540,600): "; PATH=/opt/autoglm/shim:$PATH adb shell input tap 540 600
echo -n "  经 shim 读型号(应透传给真 adb): "; PATH=/opt/autoglm/shim:$PATH adb shell getprop ro.product.model | tr -d '\r'
echo
echo "=== ④ 用它跑一单（PATH 里带上 shim + ANDROID_SERIAL）==="
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
export PATH=/opt/autoglm/shim:$PATH
export PHONE_AGENT_BASE_URL=http://131.255.36.100:30001/v1 PHONE_AGENT_MODEL=deepseek-flash \
       PHONE_AGENT_API_KEY="$KEY" PHONE_AGENT_DEVICE_ID=$ANDROID_SERIAL PHONE_AGENT_DEVICE_TYPE=adb \
       PHONE_AGENT_LANG=cn PHONE_AGENT_MAX_STEPS=10
echo "5. Checking ADB Keyboard..." >/dev/null
cd /opt/autoglm/Open-AutoGLM
timeout 780 /opt/autoglm/venv/bin/python main.py "打开设置，进入 WLAN 页面，告诉我当前连接的是哪个 WiFi" 2>&1 | tail -70
echo "ADAPT_RUN_DONE"
