#!/bin/bash
S=CTV0221202007036
echo "== 华为当前状态 =="
ANDROID_SERIAL=$S timeout 60 phone-use wifi | head -c 300; echo
ANDROID_SERIAL=$S timeout 120 phone-use probe | head -c 260; echo
echo
echo "== 决定性验证：协议式门户认证（不碰界面，直接 POST 到门户机）=="
ANDROID_SERIAL=$S timeout 180 phone-use jar portal-login zjb 123456 2>&1 | tail -6
sleep 6
echo
echo "== 认证后复核 =="
ANDROID_SERIAL=$S timeout 120 phone-use probe | head -c 260; echo
ANDROID_SERIAL=$S timeout 120 phone-use http http://www.qq.com/ 2>&1 | head -c 240; echo
