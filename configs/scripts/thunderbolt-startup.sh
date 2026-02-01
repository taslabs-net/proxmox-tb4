#!/bin/bash
# Thunderbolt Boot Startup Script
# Copy to: /usr/local/bin/thunderbolt-startup.sh
# Make executable: chmod +x /usr/local/bin/thunderbolt-startup.sh

LOGFILE="/var/log/thunderbolt-startup.log"

echo "$(date): Starting Thunderbolt interface configuration" >> "$LOGFILE"

# Wait up to 30 seconds for interfaces to appear
for i in {1..30}; do
    if ip link show en05 &>/dev/null && ip link show en06 &>/dev/null; then
        echo "$(date): Thunderbolt interfaces found" >> "$LOGFILE"
        break
    fi
    echo "$(date): Waiting for Thunderbolt interfaces... ($i/30)" >> "$LOGFILE"
    sleep 1
done

# Configure interfaces if they exist
if ip link show en05 &>/dev/null; then
    /usr/local/bin/pve-en05.sh
    echo "$(date): en05 configured" >> "$LOGFILE"
fi

if ip link show en06 &>/dev/null; then
    /usr/local/bin/pve-en06.sh
    echo "$(date): en06 configured" >> "$LOGFILE"
fi

echo "$(date): Thunderbolt configuration completed" >> "$LOGFILE"
