#!/bin/bash
set -e
DIR=/usr/local/share/phone-view
PORT=8899
install -m 0644 /tmp/phone-view.py "$DIR/phone-view.py"
if [ -f "$DIR/phone-view.pid" ]; then kill "$(cat "$DIR/phone-view.pid")" 2>/dev/null || true; sleep 1; fi
pkill -f "phone-view.py" 2>/dev/null || true
sleep 1
nohup python3 "$DIR/phone-view.py" auto "$PORT" 0.5 >/var/log/phone-view.log 2>&1 &
echo $! > "$DIR/phone-view.pid"
sleep 3
echo "pid=$(cat "$DIR/phone-view.pid")"; cat /var/log/phone-view.log
echo "== 本机取帧（JPEG 大小）=="
curl -s -o /tmp/pv.jpg -w "HTTP %{http_code}  %{size_download} bytes  %{time_total}s\n" "http://127.0.0.1:${PORT}/frame.jpg"
file /tmp/pv.jpg 2>/dev/null || true
ls -l /tmp/pv.jpg
