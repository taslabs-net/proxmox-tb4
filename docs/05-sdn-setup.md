# SDN Setup (OpenFabric)

This phase configures Proxmox SDN with OpenFabric for dynamic routing across the TB4 mesh.

> **Is SDN Required?** No! SDN/OpenFabric is completely optional. Many users run Ceph over TB4 with simple static point-to-point addressing. SDN provides GUI integration and automatic failover, but adds complexity. See [Static Routes Alternative](#static-routes-alternative) if you prefer simplicity.

## Why SDN/OpenFabric?

OpenFabric is a link-state routing protocol (based on IS-IS) that:
- Automatically discovers mesh topology
- Routes traffic optimally
- Provides failover if a link goes down
- Integrates with Proxmox GUI

## Alternative Approaches

| Approach | Complexity | GUI Integration | Failover |
|----------|------------|-----------------|----------|
| /30 static routes | Simple | None | Manual |
| /31 static routes | Simple | None | Manual |
| /32 with SDN | Medium | Full | Automatic |
| OpenFabric | Complex | Full | Automatic |

For most homelabs, **/31 or /32 static routes work fine**. Choose SDN if you want GUI visibility and automatic failover.

## Prerequisites

Before starting:
- TB4 interfaces configured and UP (from previous section)
- Nodes can ping each other over point-to-point links
- You have access to Proxmox web UI

## GUI Configuration

### Step 1: Create OpenFabric Fabric

1. **Navigate:** Datacenter → SDN → Fabrics
2. **Click:** "Add" → "OpenFabric"
3. **Configure:**
   - **Name:** `tb4`
   - **IPv4 Prefix:** `10.100.0.0/24`
   - **IPv6 Prefix:** (leave empty for IPv4-only)
   - **Hello Interval:** `3` (default)
   - **CSNP Interval:** `10` (default)
4. **Click:** "OK"

![Create Fabric](../images/sdn-create-fabric.png)

### Step 2: Add Nodes to Fabric

Still in Fabrics view:

1. **Select:** the `tb4` fabric
2. **Click:** "Add Node"

**For n2:**
- **Node:** n2
- **IPv4:** 10.100.0.12 (router ID)
- **Interfaces:** Select `en05` and `en06`

**For n3:**
- **Node:** n3  
- **IPv4:** 10.100.0.13
- **Interfaces:** Select `en05` and `en06`

**For n4:**
- **Node:** n4
- **IPv4:** 10.100.0.14
- **Interfaces:** Select `en05` and `en06`

### Step 3: Apply SDN Configuration

**Critical step!** Nothing works until you apply.

1. **Navigate:** Datacenter → SDN
2. **Click:** "Apply" (button in toolbar)
3. **Verify:** Status shows "OK" for all nodes

### Step 4: Start FRR Service

OpenFabric requires FRR (Free Range Routing):

```bash
for node in n2 n3 n4; do
    ssh $node "systemctl start frr"
    ssh $node "systemctl enable frr"
done
```

**Verify FRR is running:**

```bash
for node in n2 n3 n4; do
    echo "=== FRR on $node ==="
    ssh $node "systemctl status frr | grep Active"
done
```

Expected:
```
=== FRR on n2 ===
     Active: active (running) since ...
```

## CLI Configuration (Alternative)

If you prefer CLI over GUI:

### Create Fabric

```bash
# On any node with pvesh access
pvesh create /cluster/sdn/fabrics \
    --fabric tb4 \
    --type openfabric \
    --ipv4 10.100.0.0/24
```

### Add Nodes

```bash
# Add n2
pvesh create /cluster/sdn/fabrics/tb4/nodes \
    --node n2 \
    --ipv4 10.100.0.12 \
    --interfaces en05,en06

# Repeat for n3 and n4
```

### Apply Configuration

```bash
pvesh set /cluster/sdn --apply
```

## Verify Mesh Connectivity

### Test Router ID Connectivity

Each node should be reachable via its router ID:

```bash
for ip in 10.100.0.12 10.100.0.13 10.100.0.14; do
    echo "=== Ping $ip ==="
    ping -c 3 $ip
done
```

**Expected:**
```
=== Ping 10.100.0.12 ===
64 bytes from 10.100.0.12: icmp_seq=1 ttl=64 time=0.618 ms
64 bytes from 10.100.0.12: icmp_seq=2 ttl=64 time=0.582 ms
```

Key metrics:
- **Latency:** Should be sub-millisecond (~0.6ms)
- **Packet loss:** Should be 0%

### Check FRR Routing Table

```bash
ssh n2 "vtysh -c 'show ip route'"
```

You should see routes to all router IDs via the TB4 interfaces.

### Check OpenFabric Neighbors

```bash
ssh n2 "vtysh -c 'show openfabric neighbor'"
```

Should show n3 and n4 as neighbors.

## Static Routes Alternative

If you don't want SDN/OpenFabric, use static routes:

### On n2:
```bash
ssh n2 "ip route add 10.100.0.13/32 via 10.100.0.1 dev en05"  # to n3
ssh n2 "ip route add 10.100.0.14/32 via 10.100.0.6 dev en06"  # to n4
```

### Make Persistent

Add to `/etc/network/interfaces`:

```
up ip route add 10.100.0.13/32 via 10.100.0.1 dev en05
up ip route add 10.100.0.14/32 via 10.100.0.6 dev en06
```

### Pros/Cons

| Aspect | Static Routes | OpenFabric |
|--------|---------------|------------|
| Complexity | Simple | More setup |
| Failover | Manual | Automatic |
| GUI Integration | None | Full |
| Maintenance | Per-node | Centralized |

## Troubleshooting

### FRR Not Starting

```bash
# Check logs
ssh n2 "journalctl -u frr -n 50"

# Check configuration
ssh n2 "cat /etc/frr/frr.conf"
```

### No Neighbors Detected

1. Verify interfaces are UP:
   ```bash
   ssh n2 "ip link show en05 en06"
   ```

2. Check IP addressing:
   ```bash
   ssh n2 "ip addr show en05 en06"
   ```

3. Verify SDN applied:
   ```bash
   ssh n2 "cat /etc/frr/frr.conf | grep openfabric"
   ```

### SDN Apply Fails

Check for configuration conflicts:
```bash
# View pending changes
pvesh get /cluster/sdn/pending

# Check for errors
journalctl -u pve-cluster | tail -20
```

### High Latency (>5ms)

- Check cable quality
- Verify MTU is 65520 on both ends
- Check for CPU throttling

## GUI Verification

After setup, you should see in Proxmox UI:

1. **Datacenter → SDN → Fabrics:** Shows `tb4` fabric with all nodes
2. **Each Node → Network:** Shows `en05` and `en06` interfaces
3. **Datacenter → SDN:** Status "OK" for all nodes

## Next Steps

1. [Ceph Setup](06-ceph-setup.md) - Install and configure Ceph storage
