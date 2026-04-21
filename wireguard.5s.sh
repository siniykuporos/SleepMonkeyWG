#!/bin/bash
# Detect wg path (Apple Silicon vs Intel)
WG=$( [[ -f /opt/homebrew/bin/wg ]] && echo "/opt/homebrew/bin/wg" || echo "/usr/local/bin/wg" )

WG_OUT=$(/usr/bin/sudo "$WG" show 2>/dev/null)

IP_CACHE1="/tmp/swiftbar_ip1"
IP_CACHE2="/tmp/swiftbar_ip2"

if [ ! -f "$IP_CACHE1" ] || [ $(( $(date +%s) - $(stat -f %m "$IP_CACHE1") )) -gt 60 ]; then
    /usr/bin/curl -s --max-time 3 https://2ip.ru | tr -d '[:space:]' > "$IP_CACHE1"
fi
if [ ! -f "$IP_CACHE2" ] || [ $(( $(date +%s) - $(stat -f %m "$IP_CACHE2") )) -gt 60 ]; then
    /usr/bin/curl -s --max-time 3 https://2ip.io | tr -d '[:space:]' > "$IP_CACHE2"
fi

IP1=$(cat "$IP_CACHE1" 2>/dev/null || echo "n/a")
IP2=$(cat "$IP_CACHE2" 2>/dev/null || echo "n/a")

if [ -n "$WG_OUT" ]; then
    echo "🙈"
    echo "---"
    echo "2ip.ru: $IP1"
    echo "2ip.io: $IP2"
    echo "---"
    echo "🟢 Connected"
    echo "---"
    echo "🔴 Disconnect | bash=/usr/bin/sudo param1=/bin/launchctl param2=stop param3=com.wireguard.wg0 terminal=false refresh=true"
else
    echo "🐵"
    echo "---"
    echo "2ip.ru: $IP1"
    echo "2ip.io: $IP2"
    echo "---"
    echo "🔴 Disconnected"
    echo "---"
    echo "🟢 Connect | bash=/usr/bin/sudo param1=/bin/launchctl param2=start param3=com.wireguard.wg0 terminal=false refresh=true"
fi
