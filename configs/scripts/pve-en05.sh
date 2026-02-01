#!/bin/bash
# TB4 Interface Bringup Script - en05
# Copy to: /usr/local/bin/pve-en05.sh
# Make executable: chmod +x /usr/local/bin/pve-en05.sh

LOGFILE="/tmp/udev-debug.log"
echo "$(date): en05 bringup triggered" >> "$LOGFILE"

for i in {1..5}; do
    if ip link set en05 up mtu 65520 2>/dev/null; then
        echo "$(date): en05 up successful on attempt $i" >> "$LOGFILE"
        break
    else
        echo "$(date): Attempt $i failed, retrying in 3 seconds..." >> "$LOGFILE"
        sleep 3
    fi
done
