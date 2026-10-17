#!/bin/bash
python3 /tmp/unify-input.py
systemctl restart phone-wall; sleep 3
echo "wall=$(systemctl is-active phone-wall)  http=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8910/)"
grep -c 'id="v13"' /usr/local/share/phone-wall/wall-page.html
grep -c 'KEEP_ORDER_CLONE' /usr/local/share/phone-wall/wall-page.html
