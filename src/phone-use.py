#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""phone-use — 安卓真机的**原语工具集**（给 AI 用；不含任何固定流程）

设计原则（像 browser-use）：
  · 这里只提供"眼睛"和"手"：看界面、点、输、滚、截图、发 HTTP、查/连 Wi-Fi
  · **不做**中文语句解析、不内置"连哪种认证"的流程 —— 怎么做由后台 AI 现场决定
  · 每条命令输出**一行 JSON**（机器可读），AI 直接消费；人类可读摘要放在 stderr 之外不强求

后端（自动选择）：
  · 读界面/点击/输入/滚动/截图/HTTP → 自写 pu.jar（无障碍节点动作，免 root、免装 APK）
  · 上线（开放/PSK）→ `cmd wifi connect-network`
  · 1X/门户 → AI 用本工具的原语自己走 UI（见 skill: phone-use-wlan）

命令（全部可选 --json，默认本就输出 JSON）：
  state                              设备/root/Portal/当前 Wi-Fi
  ui [过滤子串]                       元素树（text/id/desc/bounds/click/edit/scroll）
  find <子串>                         过滤元素
  click-text|click-desc|click-id <子串> [--self]
  click-xy <x> <y>                    按坐标找节点再做无障碍点击（替代被封的坐标手势）
  settext <文本> | settext --id <元素id> <文本>
  scroll [n] | scroll-up [n]          无障碍滚动
  global <home|back|recents|notifications>
  shot <路径>                         截图（设备上生成，用 pull 取回）
  pull <设备路径> <本地路径>
  http <url> | httpfile <url> <设备路径>
  shell <命令>                        以 shell 身份执行
  wifi                                当前连接事实（SSID/BSSID/MAC/IP/频点/RSSI/安全类型/门户标记）
  wifi-connect <ssid> <open|owe|wpa2|wpa3> [密码] [--bssid MAC] [--mac none|auto|persistent]
  wifi-forget <ssid|netid> | wifi-forget-all
  wifi-radio <on|off>
  list                                已保存网络
  scan [关键字]                        扫描结果（含 EAP 企业级）
  probe [url]                         探测是否被门户拦截（默认 http://1.1.1.1/）
  jar <pu.jar 命令行...>               直接下一条 pu.jar 原语（供 AI 兜底/试验）
"""
import json
import os
import re
import subprocess
import sys
import time

SERIAL = os.environ.get("ANDROID_SERIAL") or None
_CACHE = {}
JAR_DRIVER = os.environ.get("PHONE_USE_JAR_DRIVER", "/opt/phone-use-jar/pu-node.py")
ADB = ["adb"] + (["-s", SERIAL] if SERIAL else [])


def run(cmd, timeout=120, text=True):
    p = subprocess.run(cmd, capture_output=True, timeout=timeout,
                       stdin=subprocess.DEVNULL, text=text)
    return p.returncode, (p.stdout or ""), (p.stderr or "")


def adb(*args, timeout=90):
    return run(ADB + list(args), timeout=timeout)


def resolve_serial():
    global SERIAL, ADB
    if SERIAL:
        return SERIAL
    rc, out, _ = run(["adb", "devices"])
    for line in out.splitlines()[1:]:
        p = line.split()
        if len(p) >= 2 and p[1] == "device":
            SERIAL = p[0]
            ADB = ["adb", "-s", SERIAL]
            return SERIAL
    raise SystemExit(json.dumps({"ok": False, "error": "没有已授权的 adb 设备"}, ensure_ascii=False))


def jar(*cmds, timeout=300):
    """把原语喂给手机上的 pu.jar，返回其结果文本。可传多条命令：jar('ui', 'wait 500')"""
    flat = []
    for c in cmds:
        if isinstance(c, (list, tuple)):
            flat.extend(c)
        else:
            flat.append(c)
    p = subprocess.run(["python3", JAR_DRIVER], input="\n".join(flat) + "\n",
                       capture_output=True, text=True, timeout=timeout)
    o = p.stdout or ""
    return o.split("== 结果 ==", 1)[-1] if "== 结果 ==" in o else o


def out(obj):
    print(json.dumps(obj, ensure_ascii=False))


# ---------------- 读 ----------------

def is_root():
    try:
        rc, o, _ = adb("shell", "su", "-c", "id", timeout=10)
        return o.strip().startswith("uid=0")
    except Exception:
        return False


def input_ok():
    """P2 判定：没有 root，但系统允许 adb 直接做坐标注入（`input tap` 能过）—— 华为这类就是"""
    if "input_ok" in _CACHE:
        return _CACHE["input_ok"]
    try:
        rc, o, e = adb("shell", "input", "tap", "1", "1", timeout=30)
        msg = o + e
        ok = rc == 0 and "INJECT_EVENTS" not in msg and "Injecting to another" not in msg
    except Exception:
        ok = False
    _CACHE["input_ok"] = ok
    return ok


def backend():
    """动作后端按优先级回退：P1 root → P2 裸 input → P3 pu.jar 节点动作"""
    if is_root():
        return "root-input"
    if input_ok():
        return "input"
    return "jar-node-action"


def _su(cmd, timeout=60):
    return adb("shell", "su", "-c", cmd, timeout=timeout)


def input_tap(x, y):
    if is_root():
        rc, o, e = _su("input tap %d %d" % (int(x), int(y)))
        return {"ok": rc == 0, "backend": "root-input", "detail": (o + e).strip()[:120]}
    if input_ok():
        rc, o, e = adb("shell", "input", "tap", str(int(x)), str(int(y)))
        return {"ok": rc == 0, "backend": "input", "detail": (o + e).strip()[:120]}
    return dict(click_xy(int(x), int(y)), backend="jar-node-action")


def input_swipe(x1, y1, x2, y2, ms=300):
    if is_root():
        rc, o, e = _su("input swipe %d %d %d %d %d" % (x1, y1, x2, y2, ms))
        return {"ok": rc == 0, "backend": "root-input", "detail": (o + e).strip()[:120]}
    if input_ok():
        rc, o, e = adb("shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(ms))
        return {"ok": rc == 0, "backend": "input", "detail": (o + e).strip()[:120]}
    return {"ok": False, "backend": "jar-node-action",
            "detail": "这台既不能坐标注入、也没有 root → 手势不可用；请用 scroll/click 原语（节点动作）"}


def input_text(text, elem_id=None):
    """有 root 或系统允许坐标注入时可直接 input text；否则对元素做 ACTION_SET_TEXT"""
    if not elem_id and is_root():
        safe = text.replace("'", "").replace(" ", "%s")
        rc, o, e = _su("input text '%s'" % safe)
        return {"ok": rc == 0, "backend": "root-input", "detail": (o + e).strip()[:120]}
    if not elem_id and input_ok():
        safe = text.replace("'", "").replace(" ", "%s").replace("&", "\\&").replace("<", "\\<")
        rc, o, e = adb("shell", "input", "text", safe)
        return {"ok": rc == 0, "backend": "input", "detail": (o + e).strip()[:120]}
    return dict(settext(text, elem_id=elem_id), backend="jar-node-action")


def input_key(name):
    KEY = {"home": 3, "back": 4, "enter": 66, "menu": 82, "app_switch": 187, "power": 26,
           "volume_up": 24, "volume_down": 25, "del": 67, "tab": 61, "up": 19, "down": 20,
           "left": 21, "right": 22, "escape": 111, "wakeup": 224}
    code = KEY.get(name.lower(), name)
    if is_root():
        rc, o, e = _su("input keyevent %s" % code)
        return {"ok": rc == 0, "backend": "root-input", "detail": (o + e).strip()[:120]}
    if input_ok():
        rc, o, e = adb("shell", "input", "keyevent", str(code))
        return {"ok": rc == 0, "backend": "input", "detail": (o + e).strip()[:120]}
    aliases = {"home": "home", "back": "back", "app_switch": "recents", "menu": "recents"}
    if name.lower() in aliases:
        return dict(global_action(aliases[name.lower()]), backend="jar-node-action")
    return {"ok": False, "backend": "jar-node-action",
            "detail": "这台既不能坐标注入、也没有 root；只有 home/back/recents 能用 global（节点动作）"}


def wifi_status():
    d = {"ssid": None, "bssid": None, "mac": None, "ip": None, "prefix": None, "freq_mhz": None,
         "rssi": None, "security_type": None, "supplicant": None, "enabled": None,
         "captive_portal_flag": False}
    rc, o, _ = adb("shell", "cmd", "wifi", "status")
    m = re.search(r'Wifi is connected to "([^"]+)"', o)
    d["ssid"] = m.group(1) if m else None
    if d["ssid"] is None:
        d["state"] = "connected" if "Wifi is connected" in o else (
            "enabled" if "Wifi is enabled" in o else "disabled")
    else:
        d["state"] = "connected"
    for k, pat, cast in (("bssid", r"BSSID: ([0-9a-f:]+)", str), ("mac", r"MAC: ([0-9a-f:]+)", str),
                         ("freq_mhz", r"Frequency: (\d+)", int), ("rssi", r"RSSI: (-?\d+)", int),
                         ("security_type", r"Security type: (\d+)", int),
                         ("supplicant", r"Supplicant state: (\w+)", str)):
        m = re.search(pat, o)
        d[k] = cast(m.group(1)) if m else None
    rc, o2, _ = adb("shell", "ip", "-4", "addr", "show", "wlan0")
    m = re.search(r"inet (\d+\.\d+\.\d+\.\d+)/(\d+)", o2)
    if m:
        d["ip"], d["prefix"] = m.group(1), int(m.group(2))
    rc, o3, _ = adb("shell", "dumpsys", "connectivity")
    d["captive_portal_flag"] = "isCaptivePortal" in o3
    d["validated"] = "VALIDATED" in o3
    # 补偿：小米/中文 SSID 会让 WifiInfo 读不出名字（WifiGbk 特判），但 BSSID 是准的
    # → 用 BSSID 去扫描结果里反查名字，避免"明明连着却显示 ssid=null"
    if d.get("ssid") is None and d.get("bssid"):
        try:
            for r in scan():
                if (r.get("bssid") or "").lower() == d["bssid"].lower() and r.get("ssid"):
                    d["ssid"] = r["ssid"]
                    d["ssid_source"] = "bssid-lookup(扫描结果)"
                    break
        except Exception:
            pass
    if d.get("ssid") is None and d.get("state") == "connected":
        # 不猜：小米/HyperOS 对部分 SSID 读不出名字，但 BSSID/IP/supplicant 都是准的
        d["ssid_note"] = ("系统读不出当前网络的名字（小米对部分 SSID 的限制）；"
                          "BSSID、IP、supplicant 可信，'已连接'这个结论也是准的")
    return d


def failure_reason(ssid=None):
    """从 dumpsys wifi 里取最近一次连接的失败码"""
    rc, o, _ = adb("shell", "dumpsys", "wifi", timeout=90)
    ev = {"level2FailureCode": None, "level2FailureReason": None, "connectionResult": None,
          "mEapMethod": None, "mAuthPhase2Method": None}
    blocks = re.findall(r"startTime=[^\n]*", o)
    for b in reversed(blocks):
        if ssid and ('SSID="%s"' % ssid) not in b:
            continue
        for k in ev:
            m = re.search(k + r"=([A-Za-z0-9_]+)", b)
            if m:
                ev[k] = m.group(1)
        break
    return ev


def probe(url="http://1.1.1.1/"):
    txt = jar("http " + url)
    m = re.search(r"->\s*(\d+)", txt)
    code = int(m.group(1)) if m else 0
    loc = re.search(r"Location:\s*(\S+)", txt)
    location = loc.group(1) if loc else None
    portal = bool(location and ("/portal/" in location or "Login.do" in location or "Auth.do" in location))
    return {"url": url, "code": code, "location": location,
            "portal_intercepted": portal,
            "verdict": "被门户拦截" if portal else ("未被拦截" if code else "无法判定")}


def scan(keyword=None):
    adb("shell", "cmd", "wifi", "start-scan")
    time.sleep(5)
    rc, o, _ = adb("shell", "cmd", "wifi", "list-scan-results")
    rows = []
    for line in o.splitlines()[1:]:
        # 厂商容忍解析：RSSI 有的带括号有的不带；列之间空格数不同（华为/AOSP 输出格式不一样）
        m = re.match(r"\s*([0-9a-fA-F:]{17})\s+(\d+)\s+(-?\d+)(?:\([^)]*\))?\s+([\d.]+)\s+"
                     r"(.*?)\s{2,}(\S+)\s*$", line)
        if not m:
            m2 = re.match(r"\s*([0-9a-fA-F:]{17})\s+(\d+)\s+(-?\d+)(?:\([^)]*\))?\s+(.*?)\s{2,}(\S+)\s*$", line)
            if not m2:
                continue
            bssid, freq, rssi, ssid, flags = m2.groups()
        else:
            bssid, freq, rssi, _age, ssid, flags = m.groups()
        rows.append({"bssid": bssid.lower(), "freq_mhz": int(freq), "rssi": int(rssi),
                     "ssid": ssid.strip(), "flags": flags})
    if keyword:
        rows = [r for r in rows if keyword.lower() in (r["ssid"] or "").lower()
                or keyword.lower() in r["flags"].lower()]
    rows.sort(key=lambda r: -r["rssi"])
    return rows


def saved_networks():
    rc, o, _ = adb("shell", "cmd", "wifi", "list-networks")
    nets = []
    for line in o.splitlines()[1:]:
        m = re.match(r"\s*(\d+)\s+(.+?)\s{2,}([\w-]+)\s*$", line)
        if m:
            nets.append({"netid": int(m.group(1)), "ssid": m.group(2).strip(),
                         "security": m.group(3)})
    return nets


# ---------------- 手 ----------------

def ui_elements():
    """优先 pu.jar 的元素树；jar 不可用（如未部署/旧系统）且有 root 时回退 uiautomator dump"""
    txt = jar("ui")
    els = _parse_jar_tree(txt)
    if els:
        return els
    # 回退：uiautomator dump（Android 全版本可用）
    adb("shell", "rm -f /sdcard/ui.xml")
    adb("shell", "uiautomator", "dump", "/sdcard/ui.xml", timeout=90)
    rc, xml, _ = adb("exec-out", "cat", "/sdcard/ui.xml", timeout=90)
    return _parse_dump(xml)


def _parse_jar_tree(txt):
    els = []
    for line in txt.splitlines():
        if "|" not in line or "[" not in line:
            continue
        m = re.search(r"^(?:click-xy 命中 )?(\w+) \| id=([^|]*) \| text=([^|]*) \| desc=([^|]*) \| "
                      r"click=(\w+) edit=(\w+) focus=(\w+) \| \[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]", line)
        if not m:
            continue
        cls, rid, text, desc, click, edit, focus, x1, y1, x2, y2 = m.groups()
        els.append({"cls": cls, "id": rid.strip(), "text": text.strip(), "desc": desc.strip(),
                    "clickable": click == "true", "editable": edit == "true", "focused": focus == "true",
                    "bounds": [int(x1), int(y1), int(x2), int(y2)],
                    "center": [(int(x1) + int(x2)) // 2, (int(y1) + int(y2)) // 2]})
    return els


def _parse_dump(xml):
    import xml.etree.ElementTree as ET
    els = []
    if not xml:
        return els
    try:
        root = ET.fromstring(xml)
    except Exception:
        return els
    for n in root.iter("node"):
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds", ""))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        els.append({"cls": (n.get("class") or "").split(".")[-1], "id": n.get("resource-id", ""),
                    "text": n.get("text", ""), "desc": n.get("content-desc", ""),
                    "clickable": n.get("clickable") == "true", "editable": n.get("focusable") == "true",
                    "focused": n.get("focused") == "true",
                    "bounds": [x1, y1, x2, y2], "center": [(x1 + x2) // 2, (y1 + y2) // 2]})
    return els


def find_elements(needle):
    n = needle.lower()
    return [e for e in ui_elements()
            if n in (e["text"] or "").lower() or n in (e["id"] or "").lower()
            or n in (e["desc"] or "").lower()]


def jar_click(kind, needle, self_click=False):
    arg = ("!" if self_click else "") + needle
    txt = jar("click-%s %s" % (kind, arg), "wait 600")
    ok = "click ok=true" in txt or "click(self) ok=true" in txt
    line = next((l for l in txt.splitlines() if l.startswith("click")), "")
    return {"ok": ok, "detail": line.strip(), "raw": txt.strip()[:400]}


def click_xy(x, y):
    txt = jar("click-xy %d %d" % (x, y), "wait 600")
    return {"ok": ("click ok=true" in txt or "click(force) ok=true" in txt or "click(self) ok=true" in txt),
            "detail": txt.strip()[:400]}


def settext(text, elem_id=None):
    if elem_id:
        txt = jar("settext-id %s %s" % (elem_id, text))
    else:
        txt = jar("settext %s" % text)
    return {"ok": "settext ok=true" in txt, "detail": txt.strip()[:300]}


def scroll(times=1, up=False):
    txt = jar("%s %d" % ("scroll-up" if up else "scroll", times))
    return {"ok": "scroll ok=true" in txt, "detail": txt.strip()[:300]}


def global_action(name):
    txt = jar("global %s" % name)
    return {"ok": "-> true" in txt, "detail": txt.strip()[:200]}


def shot(dev_path):
    txt = jar("shot %s" % dev_path)
    return {"ok": "shot OK" in txt, "path": dev_path, "detail": txt.strip()[:200]}


def pull(dev_path, local_path):
    rc, o, e = adb("pull", dev_path, local_path, timeout=120)
    return {"ok": rc == 0, "local": local_path, "detail": (o + e).strip()[:200]}


# ---------------- 上线 ----------------

def wifi_connect(ssid, auth, psk=None, bssid=None, mac=None):
    cmd = ["cmd", "wifi", "connect-network", ssid, auth]
    if psk:
        cmd.append(psk)
    if bssid:
        cmd += ["-b", bssid]
    if mac:
        cmd += ["-r", mac]
    rc, o, e = adb("shell", *cmd, timeout=60)
    return {"ok": "Connection initiated" in (o + e), "cmd": " ".join(cmd),
            "detail": (o + e).strip()[:200]}


def wifi_wait(ssid, seconds=30):
    for i in range(seconds):
        time.sleep(1)
        w = wifi_status()
        if (w.get("ssid") or "").lower() == ssid.lower():
            return True, w
    return False, wifi_status()


def wifi_forget(target):
    if str(target).isdigit():
        rc, o, e = adb("shell", "cmd", "wifi", "forget-network", str(target))
        return {"ok": "successful" in (o + e).lower(), "detail": (o + e).strip()[:120]}
    ids = [n["netid"] for n in saved_networks() if n["ssid"] == target]
    res = []
    for i in ids:
        rc, o, e = adb("shell", "cmd", "wifi", "forget-network", str(i))
        res.append({"netid": i, "detail": (o + e).strip()[:80]})
    return {"ok": bool(ids), "forgotten": res}


def wifi_radio(state):
    rc, o, e = adb("shell", "cmd", "wifi", "set-wifi-enabled",
                   "enabled" if state == "on" else "disabled")
    return {"ok": rc == 0, "detail": (o + e).strip()[:120]}


# ---------------- CLI ----------------

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 0
    resolve_serial()
    a = sys.argv[1:]
    cmd, rest = a[0], a[1:]

    def flag(name):
        return name in rest

    def val(name, default=None):
        if name in rest:
            i = rest.index(name)
            if i + 1 < len(rest):
                return rest[i + 1]
        return default

    pos = [x for x in rest if not x.startswith("--") and x not in
           (val("--id"), val("--bssid"), val("--mac"))]
    pos = [p for p in pos if p is not None]

    if cmd == "state":
        out({"serial": SERIAL, "root": is_root(), "wifi": wifi_status(),
             "saved_networks": len(saved_networks()), "device": adb("shell", "getprop",
                                                                   "ro.product.model")[1].strip()})
    elif cmd == "ui":
        els = ui_elements()
        if pos:
            els = [e for e in els if pos[0].lower() in (e["text"] + e["id"] + e["desc"]).lower()]
        out({"count": len(els), "elements": els})
    elif cmd == "find":
        out({"elements": find_elements(pos[0])})
    elif cmd in ("click-text", "click-desc", "click-id"):
        out(jar_click(cmd.split("-")[1], pos[0], self_click=flag("--self")))
    elif cmd == "click-xy":
        out(click_xy(int(pos[0]), int(pos[1])))
    elif cmd == "settext":
        out(settext(" ".join(pos), elem_id=val("--id")))
    elif cmd in ("scroll", "scroll-up"):
        out(scroll(int(pos[0]) if pos else 1, up=(cmd == "scroll-up")))
    elif cmd == "global":
        out(global_action(pos[0]))
    elif cmd == "tap":
        out(input_tap(int(pos[0]), int(pos[1])))
    elif cmd == "swipe":
        out(input_swipe(int(pos[0]), int(pos[1]), int(pos[2]), int(pos[3]),
                        int(pos[4]) if len(pos) > 4 else 300))
    elif cmd == "key":
        out(input_key(pos[0]))
    elif cmd == "input":
        out(input_text(" ".join(pos)))
    elif cmd == "backend":
        caps = ["read-ui", "screenshot"]
        if is_root():
            caps += ["root-input", "coordinate-gesture", "keyevent", "ime-text", "su",
                     "supplicant-config", "install-apk"]
        else:
            caps += ["node-click", "settext", "scroll", "global-action"]
        out({"backend": backend(), "root": is_root(), "capabilities": caps})
    elif cmd == "shot":
        out(shot(pos[0]))
    elif cmd == "pull":
        out(pull(pos[0], pos[1]))
    elif cmd == "http":
        out({"url": pos[0], "response": jar("http " + pos[0]).strip()[:1500]})
    elif cmd == "httpfile":
        out({"url": pos[0], "path": pos[1], "detail": jar("httpfile %s %s" % (pos[0], pos[1])).strip()[:300]})
    elif cmd == "shell":
        rc, o, e = adb("shell", *pos, timeout=90)
        out({"rc": rc, "stdout": o.strip()[:4000], "stderr": e.strip()[:500]})
    elif cmd == "wifi":
        out(wifi_status())
    elif cmd == "wifi-connect":
        ssid, auth = pos[0], pos[1]
        psk = pos[2] if len(pos) > 2 else None
        res = wifi_connect(ssid, auth, psk, bssid=val("--bssid"), mac=val("--mac"))
        time.sleep(3)
        ok, w = wifi_wait(ssid, 30)
        res.update({"connected": ok, "wifi": w})
        if not ok:
            res["failure"] = failure_reason(ssid)
        out(res)
    elif cmd == "wifi-forget":
        out(wifi_forget(pos[0]))
    elif cmd == "wifi-forget-all":
        res = [wifi_forget(n["netid"]) for n in saved_networks()]
        out({"count": len(res)})
    elif cmd == "wifi-radio":
        out(wifi_radio(pos[0]))
    elif cmd == "list":
        out({"networks": saved_networks()})
    elif cmd == "scan":
        out({"results": scan(pos[0] if pos else None)})
    elif cmd == "probe":
        out(probe(pos[0] if pos else "http://1.1.1.1/"))
    elif cmd == "failure":
        out(failure_reason(pos[0] if pos else None))
    elif cmd == "jar":
        print(jar(" ".join(rest)))
    else:
        out({"ok": False, "error": "未知命令: %s" % cmd, "hint": "见 phone-use.py 文档"})
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
