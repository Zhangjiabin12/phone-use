#!/bin/bash
T=$(systemctl show phone-agent -p ActiveEnterTimestamp --value)
echo "  本次启动于: $T"
echo -n "  启动后报错行数="
journalctl -u phone-agent --since "$T" --no-pager 2>/dev/null | grep -ciE 'valueerror|traceback'
echo "  最近 3 行:"
journalctl -u phone-agent -n 3 --no-pager | sed 's/^/    /'
echo "  三个服务: $(systemctl is-active phone-hub) / $(systemctl is-active phone-agent) / $(systemctl is-active phone-wall)"
