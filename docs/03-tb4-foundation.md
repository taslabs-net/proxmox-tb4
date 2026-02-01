# TB4 Foundation Setup

This phase configures the Thunderbolt 4 hardware, kernel modules, and interface naming.

## Overview

By the end of this section, you'll have:
- TB4 kernel modules loaded and persistent
- Consistent interface names (en05, en06)
- Interfaces configured with 65520 MTU

> **PVE 9.1+ Note:** If you installed Proxmox with TB4 cables already connected, interfaces may appear automatically as `thunderbolt0`/`thunderbolt1` in the GUI. In this case, you may not need the renaming steps below - just use the auto-detected names.

## Interface Naming

Different setups may see different interface names:

| Name | When It Appears |
|------|-----------------|
| `thunderbolt0`, `thunderbolt1` | Auto-detected by PVE 9.1+ at install |
| `enp0s13f0`, etc. | PCI path-based naming |
| `en05`, `en06` | After applying systemd link files (this guide) |

**Choose one naming scheme and be consistent.** This guide uses `en05`/`en06` but adjust all commands if using different names.

## Automated Setup

```bash
./scripts/02-install-tb4-modules.sh
```

## Manual Setup

### Step 1: Load Kernel Modules

The Linux kernel needs two modules for TB4 networking:
- `thunderbolt` - Core TB4 controller support
- `thunderbolt-net` - Network interface support over TB4

**Load modules on all nodes:**

```bash
# Using node names from SSH config
for node in n2 n3 n4; do
    echo "=== Loading TB4 modules on $node ==="
    
    # Add to /etc/modules for persistence
    ssh $node "grep -q 'thunderbolt$' /etc/modules || echo 'thunderbolt' >> /etc/modules"
    ssh $node "grep -q 'thunderbolt-net' /etc/modules || echo 'thunderbolt-net' >> /etc/modules"
    
    # Also add to modules-load.d for early loading (helps with cold boot)
    ssh $node "cat > /etc/modules-load.d/thunderbolt.conf << 'EOF'
thunderbolt
thunderbolt_net
EOF"
    
    # Load immediately
    ssh $node "modprobe thunderbolt && modprobe thunderbolt-net"
done
```

> **Why both /etc/modules AND modules-load.d?** The modules-load.d method ensures modules load early in boot, even during cold boot (power outage) when all nodes start simultaneously with no TB4 links to auto-detect.

**Verify modules loaded:**

```bash
for node in n2 n3 n4; do
    echo "=== TB4 modules on $node ==="
    ssh $node "lsmod | grep thunderbolt"
done
```

**Expected output:**
```
=== TB4 modules on n2 ===
thunderbolt_net        28672  0
thunderbolt           212992  1 thunderbolt_net
```

### Step 2: Identify TB4 Hardware

Find your TB4 controllers and their PCI paths:

```bash
for node in n2 n3 n4; do
    echo "=== TB4 hardware on $node ==="
    ssh $node "lspci | grep -i thunderbolt"
    echo ""
    ssh $node "ls -la /sys/class/net/ | grep -i thunderbolt"
done
```

**Expected output (Intel 13th Gen example):**
```
=== TB4 hardware on n2 ===
00:0d.0 USB controller: Intel Corporation Device 7a60
00:0d.2 USB controller: Intel Corporation Device 7a62
00:0d.3 USB controller: Intel Corporation Device 7a63
```

**Note the PCI addresses** (00:0d.2 and 00:0d.3 in this example). You'll need these for the next step.

### Step 3: Find Current Interface Names

Before renaming, see what Linux calls your TB4 interfaces:

```bash
for node in n2 n3 n4; do
    echo "=== Network interfaces on $node ==="
    ssh $node "ip link show | grep -E '^[0-9]+: (en|eth|thunderbolt)'"
done
```

TB4 interfaces often appear as:
- `enp0s13f0`, `enp0s13f1` (PCI path based)
- `thunderbolt0`, `thunderbolt1` (driver based)
- Random names if no udev rules

### Step 4: Create Systemd Link Files

Systemd link files rename interfaces based on PCI path. This ensures consistent naming across reboots.

**Create on all nodes:**

```bash
for node in n2 n3 n4; do
    echo "=== Creating link files on $node ==="
    
    # First TB4 port -> en05
    ssh $node "cat > /etc/systemd/network/00-thunderbolt0.link << 'EOF'
[Match]
Path=pci-0000:00:0d.2
Driver=thunderbolt-net

[Link]
MACAddressPolicy=none
Name=en05
EOF"

    # Second TB4 port -> en06
    ssh $node "cat > /etc/systemd/network/00-thunderbolt1.link << 'EOF'
[Match]
Path=pci-0000:00:0d.3
Driver=thunderbolt-net

[Link]
MACAddressPolicy=none
Name=en06
EOF"
done
```

**Important:** Adjust the PCI paths (`pci-0000:00:0d.2`, `pci-0000:00:0d.3`) if your hardware differs!

### Step 5: Enable systemd-networkd

The link files require systemd-networkd:

```bash
for node in n2 n3 n4; do
    ssh $node "systemctl enable systemd-networkd"
    ssh $node "systemctl start systemd-networkd"
done
```

### Step 6: Update Initramfs

Apply the changes to the boot image:

```bash
for node in n2 n3 n4; do
    echo "=== Updating initramfs on $node ==="
    ssh $node "update-initramfs -u -k all"
done
```

### Step 7: Reboot Nodes

Reboot to apply all changes:

```bash
echo "Rebooting all nodes..."
for node in n2 n3 n4; do
    ssh $node "reboot" &
done

echo "Waiting 90 seconds for nodes to come back..."
sleep 90
```

### Step 8: Verify Interface Names

After reboot, verify the interfaces are named correctly:

```bash
for node in n2 n3 n4; do
    echo "=== Interfaces on $node ==="
    ssh $node "ip link show | grep -E '(en05|en06)'"
done
```

**Expected output:**
```
=== Interfaces on n2 ===
11: en05: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT
12: en06: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT
```

The interfaces will show `state DOWN` until configured with IPs.

## Troubleshooting

### Interfaces Not Renamed

If interfaces still have old names:

1. **Check PCI paths match:**
   ```bash
   ssh n2 "udevadm info -e | grep -A 10 thunderbolt"
   ```

2. **Check link file syntax:**
   ```bash
   ssh n2 "cat /etc/systemd/network/00-thunderbolt0.link"
   ```

3. **Force udev to reprocess:**
   ```bash
   ssh n2 "udevadm control --reload-rules && udevadm trigger"
   ```

### Modules Not Loading

If `lsmod | grep thunderbolt` shows nothing:

1. **Check kernel support:**
   ```bash
   ssh n2 "modinfo thunderbolt"
   ```

2. **Check for errors:**
   ```bash
   ssh n2 "dmesg | grep -i thunderbolt"
   ```

3. **BIOS setting:** Ensure TB4 is enabled in BIOS/UEFI

### Wrong Number of Interfaces

If you see only 1 interface (or none):

1. **Check cable connections** - TB4 interfaces only appear when cables are connected!

2. **Check both ports:**
   ```bash
   ssh n2 "ls /sys/class/net/"
   ```

3. **Try unplugging and replugging cables**

## Understanding Interface States

| State | Meaning |
|-------|---------|
| DOWN | Interface exists but not activated |
| UP | Interface activated, may not have IP |
| LOWER_UP | Physical link detected (cable connected) |
| NO-CARRIER | No cable or peer not responding |

## Next Steps

1. [Network Configuration](04-network-config.md) - Assign IPs and configure routing
