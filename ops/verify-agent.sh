#!/bin/bash
# 真跑一单，验证 agent 端到端可用（含自主选机）
nohup phone-agent '随便挑一台空闲的手机，报告它的型号、安卓版本、当前连接的 WiFi 名称与 IP、电量，并截一张图；最后用一句话给结论' \
  > /tmp/agent-verify.log 2>&1 &
echo "started pid=$!"
sleep 5
echo "== 租约是否被它拿住（证明租约链路通）=="
curl -s http://127.0.0.1:8901/devices | python3 -c "
import json,sys
for d in json.load(sys.stdin)['devices']:
    l=d.get('lease') or {}
    if l: print('  %-16s 被 %s 占用，剩余 %ss' % (d['serial'], l.get('owner'), l.get('remaining_s')))
"
