#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""phone-view — 把 adb 屏幕截图变成浏览器可看的直播（免 root，只看不控）

用法:
    python3 phone-view.py [serial|auto] [port] [interval]
    serial 传 auto（或留空）时，每帧自动取当前唯一/第一台 adb 设备 —— 换手机不用重启
浏览器:
    http://<主机>:<port>/           实时画面（MJPEG）
    http://<主机>:<port>/frame.jpg  单张快照
说明:
    - 只调用 `adb exec-out screencap -p` + Pillow 降采样，**不需要 root**
    - 默认缩到宽 540、JPEG q70（约 50~100KB/帧），帧间隔 0.5s
"""
import io
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    from PIL import Image
    HAVE_PIL = True
except Exception:
    HAVE_PIL = False

_arg = sys.argv[1] if len(sys.argv) > 1 else "auto"
SERIAL = None if _arg in ("", "auto", "-") else _arg
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8899
INTERVAL = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
WIDTH = 540

_lock = threading.Lock()
_state = {"serial": SERIAL}


def current_serial():
    if SERIAL:
        return SERIAL
    try:
        out = subprocess.run(["adb", "devices"], capture_output=True, timeout=10,
                             stdin=subprocess.DEVNULL).stdout.decode(errors="ignore")
    except Exception:
        return None
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            return parts[0]
    return None


def grab_png():
    ser = current_serial()
    if not ser:
        return b"", None
    cmd = ["adb", "-s", ser, "exec-out", "screencap", "-p"]
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=20, stdin=subprocess.DEVNULL)
    except Exception:
        return b"", ser
    _state["serial"] = ser
    return (p.stdout or b""), ser


def to_jpeg(png):
    if not (HAVE_PIL and png):
        return None
    try:
        im = Image.open(io.BytesIO(png)).convert("RGB")
        if im.width > WIDTH:
            im = im.resize((WIDTH, int(im.height * WIDTH / im.width)), Image.BILINEAR)
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=70, optimize=True)
        return buf.getvalue()
    except Exception:
        return None


PAGE = ("<html><head><meta charset='utf-8'><title>phone-view</title></head>"
        "<body style='margin:0;background:#111;color:#ddd;font-family:sans-serif'>"
        "<div style='padding:6px 10px'>phone-view · serial=%(serial)s · "
        "<a style='color:#6cf' href='/frame.jpg'>/frame.jpg</a> 快照</div>"
        "<img src='/stream' style='max-width:100%%;max-height:92vh;display:block;margin:0 auto'>"
        "</body></html>")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _send(self, body, ctype):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/frame.jpg"):
            png, _ = grab_png()
            jpg = to_jpeg(png)
            if jpg:
                self._send(jpg, "image/jpeg")
            else:
                self._send(png, "image/png")
            return
        if self.path.startswith("/stream"):
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            try:
                while True:
                    png, _ = grab_png()
                    jpg = to_jpeg(png)
                    body = jpg or png
                    if body:
                        ctype = "image/jpeg" if jpg else "image/png"
                        self.wfile.write(b"--frame\r\nContent-Type: " + ctype.encode() + b"\r\n")
                        self.wfile.write(("Content-Length: %d\r\n\r\n" % len(body)).encode())
                        self.wfile.write(body)
                        self.wfile.write(b"\r\n")
                    time.sleep(INTERVAL)
            except (BrokenPipeError, ConnectionResetError):
                return
            return
        html = (PAGE % {"serial": _state.get("serial") or "auto"}).encode("utf-8")
        self._send(html, "text/html; charset=utf-8")


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    srv.daemon_threads = True
    print("phone-view on 0.0.0.0:%d serial=%s PIL=%s" % (PORT, SERIAL or "auto", HAVE_PIL), flush=True)
    srv.serve_forever()
