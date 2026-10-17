#!/bin/bash
echo "== A) 两台设备的输入能力与屏幕状态 =="
for s in 57ada8 CTV0221202007036; do
  echo "--- $s ---"
  adb -s $s shell "dumpsys power | grep -E 'mWakefulness|mHoldingDisplay' " 2>&1 | head -2
  adb -s $s shell "dumpsys window | grep -E 'mDreamingLockscreen|mShowingLockscreen|isStatusBarKeyguard'" 2>&1 | head -2
  echo -n "  input --help 有 swipe/tap? "; adb -s $s shell "input" 2>&1 | head -2 | tr '\n' ' '; echo
done

echo
echo "== B) 直接用原语试 K20 的 tap / swipe =="
echo -n "  K20 tap:    "; ANDROID_SERIAL=57ada8 phone-hand tap 540 1200 2>&1 | head -3 | tr '\n' ' '; echo
echo -n "  K20 swipe:  "; ANDROID_SERIAL=57ada8 phone-hand swipe 540 1600 540 800 300 2>&1 | head -3 | tr '\n' ' '; echo
echo -n "  K20 直接 adb input swipe: "; adb -s 57ada8 shell "input swipe 540 1600 540 800 300" 2>&1 | head -2 | tr '\n' ' '; echo
echo -n "  K20 su input swipe:       "; adb -s 57ada8 shell "su -c 'input swipe 540 1600 540 800 300'" 2>&1 | head -2 | tr '\n' ' '; echo
echo -n "  CTV tap（对照）: "; ANDROID_SERIAL=CTV0221202007036 phone-hand tap 540 1200 2>&1 | head -2 | tr '\n' ' '; echo

echo
echo "== C) 手机墙 /api/click 的实现（走哪个后端、传什么）=="
grep -n "api/click" -A 12 /usr/local/share/phone-wall/phone-wall.py | head -20
