# Network Configuration

This phase configures IP addresses, MTU, and automatic interface bringup for TB4 interfaces.

## Overview

You'll configure:
- Static IP addresses on each TB4 interface
- 65520 MTU for maximum performance
- Udev rules for hot-plug support
- Systemd service for boot reliability

## Automated Setup

```bash
./scripts/03-configure-interfaces.sh
./scripts/04-setup-udev-rules.sh
./scripts/05-setup-systemd.sh
```

## Manual Setup

### Step 1: Plan Your IP Addressing

Using /30 subnets for point-to-point links:

| Link | Node A | IP | Node B | IP |
|------|--------|-----|--------|-----|
| Link 1 | N2 en05 | 10.100.0.2/30 | N3 en05 | 10.100.0.1/30 |
| Link 2 | N2 en06 | 10.100.0.5/30 | N4 en05 | 10.100.0.6/30 |
| Link 3 | N3 en06 | 10.100.0.9/30 | N4 en06 | 10.100.0.10/30 |

### Step 2: Configure /etc/network/interfaces

**Critical:** TB4 interfaces MUST be defined BEFORE the `source /etc/network/interfaces.d/*` line to avoid SDN conflicts.

**On Node 1 (n2):**

```bash
ssh n2 "cat >> /etc/network/interfaces << 'EOF'

# TB4 Interfaces - DO NOT EDIT IN GUI
iface en05 inet manual #do not edit in GUI
iface en06 inet manual #do not edit in GUI

# TB4 Point-to-Point Links
auto en05
iface en05 inet static
    address 10.100.0.2/30
    mtu 65520

auto en06
iface en06 inet static
    address 10.100.0.5/30
    mtu 65520
EOF"
```

**On Node 2 (n3):**

```bash
ssh n3 "cat >> /etc/network/interfaces << 'EOF'

# TB4 Interfaces - DO NOT EDIT IN GUI
iface en05 inet manual #do not edit in GUI
iface en06 inet manual #do not edit in GUI

# TB4 Point-to-Point Links
auto en05
iface en05 inet static
    address 10.100.0.1/30
    mtu 65520

auto en06
iface en06 inet static
    address 10.100.0.9/30
    mtu 65520
EOF"
```

**On Node 3 (n4):**

```bash
ssh n4 "cat >> /etc/network/interfaces << 'EOF'

# TB4 Interfaces - DO NOT EDIT IN GUI
iface en05 inet manual #do not edit in GUI
iface en06 inet manual #do not edit in GUI

# TB4 Point-to-Point Links
auto en05
iface en05 inet static
    address 10.100.0.6/30
    mtu 65520

auto en06
iface en06 inet static
    address 10.100.0.10/30
    mtu 65520
EOF"
```

### Step 3: Create Udev Rules

Udev rules trigger scripts when TB4 cables are connected:

```bash
for node in n2 n3 n4; do
    ssh $node "cat > /etc/udev/rules.d/10-tb-en.rules << 'EOF'
# TB4 interface hotplug rules
ACTION==\"move\", SUBSYSTEM==\"net\", KERNEL==\"en05\", RUN+=\"/usr/local/bin/pve-en05.sh\"
ACTION==\"move\", SUBSYSTEM==\"net\", KERNEL==\"en06\", RUN+=\"/usr/local/bin/pve-en06.sh\"
EOF"
done
```

### Step 4: Create Interface Bringup Scripts

These scripts bring up interfaces with correct settings:

**en05 script:**

```bash
for node in n2 n3 n4; do
    ssh $node 'cat > /usr/local/bin/pve-en05.sh << '\''EOF'\''
#!/bin/bash
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
EOF'
    ssh $node "chmod +x /usr/local/bin/pve-en05.sh"
done
```

**en06 script:**

```bash
for node in n2 n3 n4; do
    ssh $node 'cat > /usr/local/bin/pve-en06.sh << '\''EOF'\''
#!/bin/bash
LOGFILE="/tmp/udev-debug.log"
echo "$(date): en06 bringup triggered" >> "$LOGFILE"

for i in {1..5}; do
    if ip link set en06 up mtu 65520 2>/dev/null; then
        echo "$(date): en06 up successful on attempt $i" >> "$LOGFILE"
        break
    else
        echo "$(date): Attempt $i failed, retrying in 3 seconds..." >> "$LOGFILE"
        sleep 3
    fi
done
EOF'
    ssh $node "chmod +x /usr/local/bin/pve-en06.sh"
done
```

### Step 5: Create Systemd Boot Service

Ensure interfaces come up even if udev rules fail:

**Create service file:**

```bash
for node in n2 n3 n4; do
    ssh $node "cat > /etc/systemd/system/thunderbolt-interfaces.service << 'EOF'
[Unit]
Description=Configure Thunderbolt Network Interfaces
After=network.target thunderbolt.service
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/thunderbolt-startup.sh

[Install]
WantedBy=multi-user.target
EOF"
done
```

**Create startup script:**

```bash
for node in n2 n3 n4; do
    ssh $node 'cat > /usr/local/bin/thunderbolt-startup.sh << '\''EOF'\''
#!/bin/bash
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
EOF'
    ssh $node "chmod +x /usr/local/bin/thunderbolt-startup.sh"
done
```

**Enable the service:**

```bash
for node in n2 n3 n4; do
    ssh $node "systemctl daemon-reload"
    ssh $node "systemctl enable thunderbolt-interfaces.service"
done
```

### Step 6: Enable IPv4 Forwarding

Required for OpenFabric routing:

```bash
for node in n2 n3 n4; do
    ssh $node "grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf"
    ssh $node "sysctl -p"
done
```

### Step 7: Apply Network Configuration

Reload network settings:

```bash
for node in n2 n3 n4; do
    ssh $node "ifreload -a"
done
```

### Step 8: Verify Configuration

**Check interface status:**

```bash
for node in n2 n3 n4; do
    echo "=== $node interfaces ==="
    ssh $node "ip addr show en05 en06"
done
```

**Expected output:**
```
=== n2 interfaces ===
11: en05: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65520 qdisc fq_codel state UP
    inet 10.100.0.2/30 scope global en05
12: en06: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65520 qdisc fq_codel state UP
    inet 10.100.0.5/30 scope global en06
```

**Test point-to-point connectivity:**

```bash
# From n2, ping the other end of each link
ssh n2 "ping -c 2 10.100.0.1"  # n3 via en05
ssh n2 "ping -c 2 10.100.0.6"  # n4 via en06
```

## Troubleshooting

### Interfaces Show DOWN

```bash
# Manually bring up
ssh n2 "ip link set en05 up mtu 65520"
ssh n2 "ip link set en06 up mtu 65520"

# Check cable connection
ssh n2 "ethtool en05"
```

### No IP Address Assigned

```bash
# Check interfaces file
ssh n2 "grep -A5 'en05' /etc/network/interfaces"

# Manually apply
ssh n2 "ifup en05"
```

### Ping Fails

1. Verify both ends have IPs in the same /30
2. Check MTU matches on both sides
3. Verify cables are properly connected

### "Network is unreachable"

The IPs aren't in the same subnet. Check your /30 addressing.

## Next Steps

1. [SDN Setup](05-sdn-setup.md) - Configure OpenFabric routing in Proxmox
