#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""phone-wall —— 浏览器手机墙（看 + 点 + 直接派任务）

· 每台终端一张卡：实时画面（MJPEG）、状态/后端/能力集/Wi-Fi/电量
· 点画面 = 直接在真机上点（root 机 → 坐标手势 tap；免 root 机 → 无障碍节点动作 click-xy）
· 卡片里输入一句话 → 转发 phone-agent(:8902 /task)，显示结论与证据
· 占用/释放走 phone-hub 的租约
端口 :8910（HTTP，无需登录）
"""
import io
import json
import os
import re
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PHONE_WALL_PORT", "8910"))
HUB = os.environ.get("PHONE_HUB_BASE", "http://127.0.0.1:8901")
AGENT = os.environ.get("PHONE_AGENT_BASE", "http://127.0.0.1:8902")
JPEG_W = int(os.environ.get("PHONE_WALL_WIDTH", "480"))
FPS = float(os.environ.get("PHONE_WALL_FPS", "2"))
FRAME_CACHE, WALL_LOOPS, LOCK = {}, {}, threading.Lock()
ALIAS_FILE = "/usr/local/share/phone-wall/aliases.json"
try:
    ALIASES = json.load(open(ALIAS_FILE, encoding="utf-8"))
except Exception:
    ALIASES = {}


def _save_aliases():
    try:
        with open(ALIAS_FILE, "w", encoding="utf-8") as _f:
            json.dump(ALIASES, _f, ensure_ascii=False, indent=2)
    except Exception:
        pass



def sh(cmd, timeout=60, binary=False):
    p = subprocess.run(cmd, capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)
    return p.returncode, (p.stdout if binary else p.stdout.decode(errors="ignore")), p.stderr.decode(errors="ignore")


def hub(method, path, body=None, timeout=120):
    req = urllib.request.Request(HUB + path,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 method=method, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def grab_jpeg(serial):
    rc, png, _ = sh(["adb", "-s", serial, "exec-out", "screencap", "-p"], timeout=30, binary=True)
    if rc != 0 or not png:
        return None, True
    try:
        from PIL import Image
        im = Image.open(io.BytesIO(png)).convert("RGB")
        lo, hi = im.convert("L").getextrema()      # 全黑帧识别（熄屏但系统仍报 Awake 的情况）
        blank = hi < 12
        im = im.resize((JPEG_W, int(im.height * JPEG_W / im.width)))
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=60)
        return buf.getvalue(), blank
    except Exception:
        return None, True


def frame_loop(serial):
    while True:
        jpg, blank = grab_jpeg(serial)
        if jpg:
            with LOCK:
                FRAME_CACHE[serial] = (jpg, time.time(), blank)
        time.sleep(1.0 / max(FPS, 0.2))


def ensure_loop(serial):
    with LOCK:
        if serial not in WALL_LOOPS:
            WALL_LOOPS[serial] = True
            threading.Thread(target=frame_loop, args=(serial,), daemon=True).start()


def _load_page():
    """页面从 wall-page.html 读（便于单独改版式）；读不到就退回内置极简页"""
    here = os.path.dirname(os.path.abspath(__file__))
    for p in (os.path.join(here, "wall-page.html"), "/usr/local/share/phone-wall/wall-page.html"):
        try:
            with open(p, encoding="utf-8") as f:
                return f.read()
        except Exception:
            continue
    return "<!DOCTYPE html><html><body style='background:#0b0e14;color:#e8eef7;font:16px sans-serif'>" \
           "<p>wall-page.html 未找到（请随 phone-wall.py 一起下发）</p></body></html>"


PAGE = _load_page()


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, body, ctype="application/json; charset=utf-8", code=200):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = self.path.split("?")[0]
        if p in ("/", "/index.html"):
            return self._send(PAGE, "text/html; charset=utf-8")
        if p == "/api/devices":
            try:
                d = hub("GET", "/devices", timeout=40)
                with LOCK:
                    for dev in d.get("devices", []):
                        item = FRAME_CACHE.get(dev.get("serial"))
                        dev["screen_blank"] = bool(item[2]) if item else None
                        dev["alias"] = ALIASES.get(dev.get("serial"))
                return self._send(d)
            except Exception as e:
                return self._send({"error": str(e)}, code=500)
        m = re.match(r"^/screen/([^/]+)$", p)
        if m:
            serial = m.group(1)
            ensure_loop(serial)
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.end_headers()
            try:
                while True:
                    with LOCK:
                        item = FRAME_CACHE.get(serial)
                    if item:
                        jpg = item[0]          # 缓存是 (jpeg, ts, blank)，别用两元解包
                        self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: "
                                         + str(len(jpg)).encode() + b"\r\n\r\n" + jpg + b"\r\n")
                        self.wfile.flush()
                    time.sleep(1.0 / max(FPS, 0.2))
            except Exception:
                return
        return self._send({"error": "not found"}, code=404)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            body = {}
        p = self.path.split("?")[0]
        serial = body.get("serial")
        try:
            if p == "/api/alias":
                name = (body.get("name") or "").strip()[:40]
                if name:
                    ALIASES[serial] = name
                else:
                    ALIASES.pop(serial, None)
                _save_aliases()
                return self._send({"serial": serial, "alias": ALIASES.get(serial)})
            if p == "/api/click":
                dev = hub("GET", "/devices/%s" % serial, timeout=30)
                if dev.get("lease") and dev["lease"].get("owner") != "wall":
                    return self._send({"blocked": True,
                                       "error": "终端被 %s 占用（剩余 %ss）；先释放或点『强制收回』" % (
                                           dev["lease"]["owner"], dev["lease"].get("remaining_s"))}, 409)
                # AUTO_WAKE：屏幕黑着时点击不会有任何反应，先唤醒
                try:
                    if (dev.get("screen_display_on") is False) or (dev.get("screen") and dev.get("screen") != "Awake"):
                        hub("POST", "/devices/%s/exec" % serial,
                            {"args": ["key", "wakeup"], "owner": "wall", "force": True}, timeout=60)
                except Exception:
                    pass
                argv = ["tap", str(body["x"]), str(body["y"])] if dev.get("root") \
                    else ["click-xy", str(body["x"]), str(body["y"])]
                r = hub("POST", "/devices/%s/exec" % serial,
                        {"args": argv, "owner": "wall", "force": True}, timeout=120)
                return self._send({"argv": argv, "rc": r.get("rc"),
                                   "stdout": (r.get("stdout") or "").strip()[:400]})
            if p == "/api/swipe":
                dev = hub("GET", "/devices/%s" % serial, timeout=30)
                if dev.get("lease") and dev["lease"].get("owner") != "wall":
                    return self._send({"blocked": True,
                                       "error": "终端被 %s 占用（剩余 %ss）；先释放或点『强制收回』" % (
                                           dev["lease"]["owner"], dev["lease"].get("remaining_s"))}, 409)
                argv = ["swipe", str(body["x1"]), str(body["y1"]), str(body["x2"]), str(body["y2"]),
                        str(body.get("ms", 300))]
                r = hub("POST", "/devices/%s/exec" % serial,
                        {"args": argv, "owner": "wall", "force": True}, timeout=120)
                return self._send({"argv": argv, "rc": r.get("rc"),
                                   "stdout": (r.get("stdout") or "").strip()[:400]})
            if p == "/api/task":
                payload = {"text": body["text"], "device": serial or body.get("device", "auto")}
                if body.get("devices"):
                    payload["devices"] = body["devices"]
                    payload["device"] = "auto"
                req = urllib.request.Request(AGENT + "/task",
                                             data=json.dumps(payload).encode(),
                                             headers={"Content-Type": "application/json"})
                with urllib.request.urlopen(req, timeout=1800) as r:
                    return self._send(json.loads(r.read().decode()))
            if p == "/api/doctor":
                req = urllib.request.Request("%s/devices/%s/doctor" % (HUB, serial), data=b"{}",
                                             headers={"Content-Type": "application/json"})
                with urllib.request.urlopen(req, timeout=900) as r:
                    return self._send(json.loads(r.read().decode()))
            if p == "/api/key":
                k = body.get("key")
                dev = hub("GET", "/devices/%s" % serial, timeout=30)
                if dev.get("lease") and dev["lease"].get("owner") != "wall":
                    return self._send({"ok": False,
                                       "error": "终端被 %s 占用" % dev["lease"]["owner"]}, 409)
                argv = ["key", k] if k not in ("notifications",) else ["global", "notifications"]
                r = hub("POST", "/devices/%s/exec" % serial,
                        {"args": argv, "owner": "wall", "force": True}, timeout=120)
                try:
                    j = json.loads((r.get("stdout") or "{}").strip().splitlines()[-1])
                except Exception:
                    j = {}
                return self._send({"ok": bool(j.get("ok")), "backend": j.get("backend"),
                                   "argv": argv, "error": j.get("detail") or (r.get("stderr") or "")[:200]})
            if p == "/api/lease":
                return self._send(hub("POST", "/devices/%s/lease" % serial,
                                      {"owner": body.get("owner", "wall"),
                                       "ttl": int(body.get("ttl", 900))}, timeout=30))
            if p == "/api/release":
                return self._send(hub("POST", "/devices/%s/release" % serial,
                                      {"owner": body.get("owner", "wall"),
                                       "reason": "页面释放"}, timeout=30))
            if p == "/api/heartbeat":
                return self._send(hub("POST", "/devices/%s/heartbeat" % serial,
                                      {"owner": body.get("owner", "wall")}, timeout=20))
            if p == "/api/reclaim":
                return self._send(hub("POST", "/devices/%s/reclaim" % serial,
                                      {"reason": body.get("reason", "页面手动收回")}, timeout=30))
        except Exception as e:
            return self._send({"error": str(e)}, code=500)
        return self._send({"error": "not found"}, code=404)


if __name__ == "__main__":
    print(json.dumps({"phone_wall": "listening", "port": PORT}, ensure_ascii=False))
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
