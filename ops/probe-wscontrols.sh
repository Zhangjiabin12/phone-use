#!/bin/bash
echo "== ws-scrcpy 文档列表 =="
ls /opt/ws-scrcpy/docs 2>/dev/null | head -8
echo
echo "== 文档里提 URL/hash 参数与控制条的地方 =="
grep -rniE "hash|url.?param|controls|noControl|hideControl|fitToScreen|player=" /opt/ws-scrcpy/docs 2>/dev/null | head -12
echo
echo "== dist 里控制条相关标识 =="
grep -rhoE "noControls|hideControls|showControls|[a-zA-Z]{0,12}Control[a-zA-Z]{0,12}" /opt/ws-scrcpy/dist 2>/dev/null | sort | uniq -c | sort -rn | head -14
echo
echo "== 页面模板里是否已有参数开关（查 app.js/index.html 片段）=="
grep -rhoE ".{60}(controls|Control).{60}" /opt/ws-scrcpy/dist/index.html 2>/dev/null | head -5
ls /opt/ws-scrcpy/dist | head -10
