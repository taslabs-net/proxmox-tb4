# Troubleshooting

Common issues and their solutions.

## Quick Diagnostics

Run this script for a full system check:

```bash
./scripts/utils/troubleshoot.sh
```

## TB4 Mesh Issues

### Interfaces Not Coming Up After Reboot

**Symptoms:**
- `ip link show en05` shows DOWN state
- Ceph OSDs fail to start
- Ping to other nodes fails

**Diagnosis:**
```bash
# Check interface state
ip link show en05 en06

# Check udev log
cat /tmp/udev-debug.log

# Check systemd service
systemctl status thunderbolt-interfaces.service
```

**Solutions:**

1. **Manual bringup:**
   ```bash
   for node in n2 n3 n4; do
       ssh $node "ip link set en05 up mtu 65520"
       ssh $node "ip link set en06 up mtu 65520"
       ssh $node "ifreload -a"
   done
   ```

2. **Fix corrupted scripts:**
   ```bash
   # Check script line count (should be ~13, not thousands)
   wc -l /usr/local/bin/pve-en05.sh
   
   # Recreate if corrupted
   ./scripts/04-setup-udev-rules.sh
   ```

3. **Fix shebang errors:**
   ```bash
   # Check for escaped shebang
   head -1 /usr/local/bin/thunderbolt-startup.sh
   
   # Fix if shows #\!/bin/bash instead of #!/bin/bash
   sed -i '1s/#\\!/#!/' /usr/local/bin/*.sh
   ```

### "Exec format error" on Boot

**Cause:** Corrupted shebang line in scripts.

**Fix:**
```bash
for node in n2 n3 n4; do
    ssh $node "sed -i '1s/#\\\\!/#!/' /usr/local/bin/thunderbolt-startup.sh"
    ssh $node "sed -i '1s/#\\\\!/#!/' /usr/local/bin/pve-en05.sh"
    ssh $node "sed -i '1s/#\\\\!/#!/' /usr/local/bin/pve-en06.sh"
    ssh $node "systemctl restart thunderbolt-interfaces.service"
done
```

### Cold Boot / Power Outage (All Nodes Boot Simultaneously)

**Symptoms:**
- TB4 interfaces don't appear after power outage
- All nodes booted at same time with no TB4 links to detect
- Modules fail to load because there's nothing to detect

**Cause:** TB4 modules only load when they detect connected devices. If all nodes boot simultaneously, there's nothing to detect.

**Fix:** Force modules to load at boot:
```bash
for node in n2 n3 n4; do
    ssh $node "cat > /etc/modules-load.d/thunderbolt.conf << 'EOF'
thunderbolt
thunderbolt_net
EOF"
done
```

### Ceph/FRR Start Before TB4 Interfaces Ready

**Symptoms:**
- Ceph OSDs fail to bind to cluster_network
- FRR can't find interfaces
- Services start before TB4 is up

**Cause:** TB4 interfaces load a few seconds AFTER the network stack.

**Fix:** Create improved systemd service that makes Ceph wait:
```bash
cat > /etc/systemd/system/thunderbolt-network.service << 'EOF'
[Unit]
Description=Thunderbolt network interfaces ready
After=sys-subsystem-net-devices-thunderbolt0.device sys-subsystem-net-devices-thunderbolt1.device
Wants=sys-subsystem-net-devices-thunderbolt0.device sys-subsystem-net-devices-thunderbolt1.device
Before=ceph.target frr.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'for i in {1..60}; do ip link show thunderbolt0 2>/dev/null | grep -q "state UP" && ip link show thunderbolt1 2>/dev/null | grep -q "state UP" && echo "Thunderbolt interfaces ready" && exit 0; sleep 1; done; echo "Warning: Thunderbolt interfaces not ready after 60s"; exit 0'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable thunderbolt-network.service
```

**Note:** Adjust interface names (`thunderbolt0`/`thunderbolt1` vs `en05`/`en06`) based on your setup.

### SDN Requires Re-Apply After Every Reboot

**Symptoms:**
- SDN shows as "pending" after reboot
- Need to click "Apply" in GUI each time

**Workaround:** This is a known issue with some configurations. You can:
1. Apply SDN manually after each reboot
2. Create a script to run `pvesh set /cluster/sdn --apply` at boot

### Mesh Connectivity Partial (Some Nodes Unreachable)

**Diagnosis:**
```bash
# Test each link
ssh n2 "ping -c 2 10.100.0.1"   # to n3 via en05
ssh n2 "ping -c 2 10.100.0.6"   # to n4 via en06
ssh n3 "ping -c 2 10.100.0.10"  # to n4 via en06
```

**Common causes:**
1. **Cable issue:** Reseat or replace TB4 cable
2. **Interface not configured:** Check `/etc/network/interfaces`
3. **Wrong subnet:** IPs must be in same /30

### High Latency (>5ms)

**Expected:** ~0.6ms

**Check:**
```bash
# Verify MTU
ip link show en05 | grep mtu

# Should show 65520
# If lower, fix with:
ip link set en05 mtu 65520
```

**Other causes:**
- CPU throttling (check `dmesg | grep throttl`)
- Bad cable
- Background processes

## Ceph Issues

### OSDs Won't Start

**Symptoms:**
- `ceph -s` shows OSDs down
- OSD service fails

**Diagnosis:**
```bash
# Check specific OSD
systemctl status ceph-osd@0

# Check logs
journalctl -u ceph-osd@0 -n 100
```

**Common causes:**

1. **TB4 not up (most common):**
   ```bash
   # Fix TB4 first
   ip link set en05 up mtu 65520
   ip link set en06 up mtu 65520
   
   # Then restart OSDs
   systemctl restart ceph-osd.target
   ```

2. **Wrong cluster_network:**
   ```bash
   ceph config get osd cluster_network
   # Should show 10.100.0.0/24
   ```

3. **Disk issues:**
   ```bash
   smartctl -a /dev/nvme1n1
   ```

### "Cannot assign requested address"

**Cause:** OSD trying to bind to cluster_network but TB4 interface has no IP.

**Fix:**
```bash
# Verify TB4 has IPs
ip addr show en05 en06

# If no IPs, bring up interfaces
ifreload -a

# Or manually
ifup en05
ifup en06
```

### Slow Ceph Performance

**Check current performance:**
```bash
rados -p cephtb4 bench 10 write --no-cleanup
```

**If slow (<500 MB/s):**

1. **Verify using TB4 network:**
   ```bash
   # Watch traffic during benchmark
   iftop -i en05
   ```

2. **Check OSD health:**
   ```bash
   ceph osd perf
   ```

3. **Apply optimizations:**
   ```bash
   ./scripts/ceph/04-apply-optimizations.sh
   ```

4. **Check for recovery activity:**
   ```bash
   ceph -s  # Look for "recovering" or "backfilling"
   ```

### PGs Stuck (Not Active+Clean)

**Check status:**
```bash
ceph pg stat
ceph pg dump_stuck
```

**Common states:**

| State | Meaning | Action |
|-------|---------|--------|
| activating | Coming online | Wait |
| peering | Finding peers | Wait, check network |
| degraded | Missing replicas | Wait for recovery |
| incomplete | Not enough OSDs | Add OSDs or reduce size |
| stale | No updates received | Check OSD health |

**Force recovery:**
```bash
# Increase recovery priority temporarily
ceph config set osd osd_recovery_max_active 16
ceph config set osd osd_max_backfills 8

# After recovery completes, reset
ceph config set osd osd_recovery_max_active 8
ceph config set osd osd_max_backfills 4
```

### Monitor Quorum Lost

**Symptoms:**
- `ceph -s` fails or shows only 1-2 monitors

**Check:**
```bash
ceph quorum_status
```

**Fix:**
```bash
# Restart monitors
for node in n2 n3 n4; do
    ssh $node "systemctl restart ceph-mon.target"
done
```

## SDN/OpenFabric Issues

### FRR Not Running

```bash
# Check status
systemctl status frr

# Start if stopped
systemctl start frr
systemctl enable frr
```

### No Neighbors in OpenFabric

```bash
# Check neighbor discovery
vtysh -c "show openfabric neighbor"
```

**If empty:**
1. Verify interfaces are UP
2. Check SDN is applied in Proxmox GUI
3. Verify FRR configuration:
   ```bash
   cat /etc/frr/frr.conf | grep openfabric
   ```

### SDN Apply Fails

**In GUI:** Check error message

**CLI check:**
```bash
pvesh get /cluster/sdn/pending
```

**Common causes:**
- Interface doesn't exist
- Invalid IP configuration
- Conflicting settings

## General Proxmox Issues

### Web UI Not Accessible

```bash
# Check pveproxy
systemctl status pveproxy

# Restart if needed
systemctl restart pveproxy
```

### Cluster Communication Failing

```bash
# Check cluster status
pvecm status

# Check corosync
systemctl status corosync
```

## Diagnostic Commands Reference

### TB4/Network
```bash
ip link show                    # Interface status
ip addr show en05 en06          # IP addresses
ethtool en05                    # Link details
ping -c 3 10.100.0.x           # Connectivity
iftop -i en05                   # Traffic monitor
```

### Ceph
```bash
ceph -s                         # Cluster status
ceph osd tree                   # OSD hierarchy
ceph osd perf                   # OSD performance
ceph health detail              # Detailed health
ceph pg stat                    # PG status
```

### System
```bash
dmesg | tail -50               # Kernel messages
journalctl -p err -n 50        # Recent errors
systemctl --failed              # Failed services
```

## Getting Help

If you're stuck:

1. **Gather diagnostics:**
   ```bash
   ./scripts/utils/troubleshoot.sh > diagnostics.txt
   ```

2. **Check logs:**
   ```bash
   journalctl -p err --since "1 hour ago"
   ```

3. **Search issues:** Check GitHub issues for similar problems

4. **Ask for help:** Include your diagnostics output

## Next Steps

1. [Benchmarking](09-benchmarking.md) - Verify performance
