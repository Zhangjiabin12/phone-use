#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""phone-use — 安卓手机操作原语（一条命令一个动作，只打印原始事实）

后端自动选择（谁可用用谁）：
  · 动作：手机已 root → `su -c input …`（最稳）；否则走 mobilerun Portal 的无障碍手势
  · 读界面：Portal(`device ui`) → 退化为 `uiautomator dump`
命令：
  ui | find <子串> | tap-text <子串> | tap x y | swipe x1 y1 x2 y2 | text <文本>
  press <back|home|enter|...> | start <包名> | shot <文件> | state | apps [n] | wifi
  wifi-join <SSID> [密码] [bssid]     连网并回报成功/失败 + 证据
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

VENV = os.environ.get("PHONE_USE_VENV", "/opt/droidrun-venv")
DROIDRUN = os.path.join(VENV, "bin", "droidrun")
SERIAL = os.environ.get("ANDROID_SERIAL") or None
NOISE = re.compile(r"FutureWarning|cli_shim|has been renamed|^⚠")
_CACHE = {}

KEYCODES = {"back": 4, "home": 3, "enter": 66, "app_switch": 187, "menu": 82,
            "volume_up": 24, "volume_down": 25, "power": 26, "del": 67, "tab": 61,
            "up": 19, "down": 20, "left": 21, "right": 22, "escape": 111}


def sh(cmd, timeout=90):
    p = subprocess.run(cmd, capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)
    return p.returncode, p.stdout.decode(errors="ignore"), p.stderr.decode(errors="ignore")


def adb(*args, timeout=60):
    return sh(["adb"] + (["-s", SERIAL] if SERIAL else []) + list(args), timeout=timeout)


def resolve_serial():
    global SERIAL
    if SERIAL:
        return SERIAL
    rc, out, _ = sh(["adb", "devices"])
    for line in out.splitlines()[1:]:
        p = line.split()
        if len(p) >= 2 and p[1] == "device":
            SERIAL = p[0]
            return SERIAL
    raise SystemExit("没有已授权的 adb 设备")


def is_root():
    if "root" in _CACHE:
        return _CACHE["root"]
    try:
        rc, out, _ = adb("shell", "su", "-c", "id", timeout=10)
        ok = out.strip().startswith("uid=0")
    except Exception:
        ok = False
    _CACHE["root"] = ok
    return ok


def droidrun(*args, timeout=90):
    cmd = [DROIDRUN, *args]
    if SERIAL:
        cmd += ["--device", SERIAL]
    rc, out, err = sh(cmd, timeout=timeout)
    txt = "\n".join(l for l in (out + err).splitlines() if not NOISE.search(l))
    return rc, txt


def portal_ok():
    if "portal" in _CACHE:
        return _CACHE["portal"]
    try:
        rc, out = droidrun("ping", timeout=40)
        ok = "accessible" in out
    except Exception:
        ok = False
    _CACHE["portal"] = ok
    return ok


# ---------------- 读 ----------------
ELEM_RE = re.compile(r"^\s*(\d+)\.\s*([\w.]+):\s*(.*?)\s*-\s*\((\d+),(\d+),(\d+),(\d+)\)\s*$")
BOUNDS_RE = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def _norm(x1, y1, x2, y2, rid, text, cls):
    return {"id": rid, "text": text, "cls": cls, "bounds": [x1, y1, x2, y2],
            "center": [(x1 + x2) // 2, (y1 + y2) // 2]}


def ui_tree():
    if portal_ok():
        rc, out = droidrun("device", "ui")
        els = []
        for line in out.splitlines():
            m = ELEM_RE.match(line)
            if not m:
                continue
            _, cls, mid, x1, y1, x2, y2 = m.groups()
            parts = re.findall(r'"([^"]*)"', mid)
            rid = parts[0] if parts else ""
            text = parts[1] if len(parts) > 1 else ""
            els.append(_norm(int(x1), int(y1), int(x2), int(y2), rid, text, cls))
        if els:
            return els
    # 退化：uiautomator dump
    adb("shell", "rm", "-f", "/sdcard/ui.xml")
    adb("shell", "uiautomator", "dump", "/sdcard/ui.xml", timeout=60)
    rc, xml, _ = adb("exec-out", "cat", "/sdcard/ui.xml", timeout=60)
    els = []
    if xml:
        try:
            root = ET.fromstring(xml)
            for n in root.iter("node"):
                b = BOUNDS_RE.match(n.get("bounds", ""))
                if not b:
                    continue
                x1, y1, x2, y2 = map(int, b.groups())
                els.append(_norm(x1, y1, x2, y2, n.get("resource-id", ""),
                                 n.get("text", "") or n.get("content-desc", ""), n.get("class", "")))
        except Exception:
            pass
    return els


def find(needle):
    n = needle.lower()
    return [e for e in ui_tree() if n in e["text"].lower() or n in e["id"].lower()]


def phone_state():
    if portal_ok():
        rc, out = droidrun("device", "ui")
        lines = [l for l in out.splitlines() if l.startswith(("**", "•"))]
        return "\n".join(lines[:5])
    rc, out, _ = adb("shell", "dumpsys window")
    m = re.search(r"mCurrentFocus=Window\{[^}]*\s([^\s}]+)", out)
    return "焦点: %s" % (m.group(1) if m else "?")


def screenshot(dst):
    if portal_ok():
        rc, out = droidrun("device", "screenshot")
        m = re.search(r"(/\S+\.png)", out)
        if m:
            shutil.copy(m.group(1), dst)
            print("saved %s (%d bytes)" % (dst, os.path.getsize(dst)))
            return True
    rc, png, _ = adb("exec-out", "screencap", "-p", timeout=60)
    if not png:
        return False
    open(dst, "wb").write(png)
    print("saved %s (%d bytes)" % (dst, os.path.getsize(dst)))
    return True


def wifi():
    rc, out, _ = adb("shell", "cmd", "wifi", "status")
    d = {}
    m = re.search(r'Wifi is connected to "?([^"\n]+)"?', out)
    d["ssid_display"] = m.group(1) if m else None
    for k, pat in (("bssid", r"BSSID: ([0-9a-f:]+)"), ("mac", r"MAC: ([0-9a-f:]+)"),
                   ("ip", r"IP: /([0-9.]+)"), ("freq", r"Frequency: (\d+)"),
                   ("rssi", r"RSSI: (-?\d+)")):
        m = re.search(pat, out)
        d[k] = m.group(1) if m else None
    return d


# ---------------- 动 ----------------
def tap(x, y):
    x, y = int(x), int(y)
    if is_root():
        rc, out, err = adb("shell", "su", "-c", "input tap %d %d" % (x, y))
        print("tap(%d,%d) via root rc=%d %s" % (x, y, rc, err.strip()[:80]))
        return rc == 0
    rc, out = droidrun("device", "tap", str(x), str(y))
    print("tap(%d,%d) via Portal rc=%d %s" % (x, y, rc, out.strip()[:80]))
    return rc == 0


def tap_text(needle):
    hits = find(needle)
    if not hits:
        print("没找到含 %r 的元素" % needle)
        return False
    e = hits[0]
    print("命中: %r bounds=%s center=%s" % (e["text"], e["bounds"], e["center"]))
    return tap(*e["center"])


def swipe(x1, y1, x2, y2, ms=300):
    if is_root():
        rc, out, err = adb("shell", "su", "-c", "input swipe %d %d %d %d %d" % (x1, y1, x2, y2, ms))
        print("swipe via root rc=%d" % rc)
        return rc == 0
    rc, out = droidrun("device", "swipe", str(x1), str(y1), str(x2), str(y2))
    print("swipe via Portal rc=%d %s" % (rc, out.strip()[:80]))
    return rc == 0


def type_text(t):
    if is_root():
        rc, out, err = adb("shell", "su", "-c", "input text '%s'" % t.replace("'", "").replace(" ", "%s"))
        print("text via root rc=%d %s" % (rc, err.strip()[:80]))
        return rc == 0
    rc, out = droidrun("device", "type", t)
    print("text via Portal rc=%d %s" % (rc, out.strip()[:80]))
    return rc == 0


def press(k):
    k = k.lower()
    if is_root():
        code = KEYCODES.get(k, k)
        rc, out, err = adb("shell", "su", "-c", "input keyevent %s" % code)
        print("press %s(%s) via root rc=%d" % (k, code, rc))
        return rc == 0
    rc, out = droidrun("device", "press", k)
    print("press %s via Portal rc=%d %s" % (k, rc, out.strip()[:80]))
    return rc == 0


def start_app(pkg):
    rc, out, err = adb("shell", "monkey", "-p", pkg, "-c", "android.intent.category.LAUNCHER", "1")
    print("start %s rc=%d" % (pkg, rc))
    return rc == 0


# ---------------- 用例 ----------------
def wifi_join(ssid, psk=None, bssid=None, wait=30):
    print("== 目标: %s%s%s ==" % (ssid, "（带密码）" if psk else "（开放）",
                                  " 锁定 BSSID " + bssid if bssid else ""))
    print("连接前:", json.dumps(wifi(), ensure_ascii=False))
    if is_root():
        auth = "wpa2" if psk else "open"
        cmd = "cmd wifi connect-network '%s' %s" % (ssid, auth)
        if psk:
            cmd += " '%s'" % psk
        if bssid:
            cmd += " -b %s" % bssid
        rc, out, err = adb("shell", "su", "-c", cmd, timeout=60)
        print("root 直连: rc=%d %s" % (rc, (out + err).strip()[:160]))
    else:
        adb("shell", "am", "start", "-a", "android.settings.WIFI_SETTINGS")
        time.sleep(5)
        el = None
        prev = None
        for _ in range(8):
            hits = [e for e in ui_tree() if ssid.lower() in e["text"].lower()]
            if hits:
                if prev == hits[0]["bounds"]:
                    el = hits[0]
                    break
                prev = hits[0]["bounds"]
            time.sleep(1.2)
        if el is None:
            print("FAIL WLAN 页面找不到 %r" % ssid)
            screenshot("/tmp/wifi-join-fail.png")
            return 2
        print("命中元素 %r bounds=%s" % (el["text"], el["bounds"]))
        tap(*el["center"])
        time.sleep(4)
        els = ui_tree()
        fields = [e for e in els if "EditText" in e["cls"]]
        btns = [e for e in els if e["text"] in ("连接", "确定", "保存")]
        if psk and fields:
            tap(*fields[-1]["center"]); time.sleep(1)
            type_text(psk); time.sleep(1)
            if btns:
                tap(*btns[-1]["center"])
        elif btns:
            tap(*btns[0]["center"])
    for _ in range(wait):
        time.sleep(1)
        w = wifi()
        if ssid.lower() in (w.get("ssid_display") or "").lower():
            print("PASS 已连上: %s" % json.dumps(w, ensure_ascii=False))
            return 0
    print("FAIL 超时未连上；当前: %s" % json.dumps(wifi(), ensure_ascii=False))
    screenshot("/tmp/wifi-join-fail.png")
    print("失败现场: /tmp/wifi-join-fail.png")
    return 4


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    cmd = sys.argv[1]
    resolve_serial()
    if cmd == "ui":
        for e in ui_tree():
            print("%-30s id=%-40s bounds=%s" % (e["text"][:30], e["id"][:40], e["bounds"]))
        return 0
    if cmd == "find":
        hits = find(sys.argv[2])
        for e in hits:
            print("%-30s id=%-40s bounds=%s center=%s" % (e["text"][:30], e["id"][:40], e["bounds"], e["center"]))
        if not hits:
            print("没找到含 %r 的元素" % sys.argv[2])
            return 2
        return 0
    if cmd == "tap-text":
        return 0 if tap_text(sys.argv[2]) else 1
    if cmd == "tap":
        return 0 if tap(sys.argv[2], sys.argv[3]) else 1
    if cmd == "swipe":
        return 0 if swipe(int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])) else 1
    if cmd == "text":
        return 0 if type_text(sys.argv[2]) else 1
    if cmd == "press":
        return 0 if press(sys.argv[2]) else 1
    if cmd == "start":
        return 0 if start_app(sys.argv[2]) else 1
    if cmd == "shot":
        return 0 if screenshot(sys.argv[2]) else 1
    if cmd == "state":
        print("root=%s portal=%s" % (is_root(), portal_ok()))
        print(phone_state())
        return 0
    if cmd == "wifi":
        print(json.dumps(wifi(), ensure_ascii=False))
        return 0
    if cmd == "wifi-join":
        return wifi_join(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None,
                         sys.argv[4] if len(sys.argv) > 4 else None)
    if cmd == "apps":
        if portal_ok():
            rc, out = droidrun("device", "apps")
            print("\n".join(out.splitlines()[:int(sys.argv[2]) if len(sys.argv) > 2 else 10]))
        else:
            rc, out, _ = adb("shell", "pm", "list", "packages", "-3")
            print(out)
        return 0
    print("未知命令:", cmd)
    return 1


if __name__ == "__main__":
    sys.exit(main())
