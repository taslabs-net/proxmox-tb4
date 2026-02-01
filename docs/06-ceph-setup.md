# Ceph Setup

This phase installs Ceph and configures it to use the TB4 mesh for cluster traffic.

## Overview

You'll set up:
- Ceph packages on all nodes
- 3 monitors (one per node for quorum)
- 6 OSDs (2 NVMe drives per node)
- Storage pool with 2:1 replication

## Prerequisites

- TB4 mesh fully operational (verified with ping tests)
- NVMe drives available for OSDs (check with `lsblk`)
- At least 32GB RAM per node

## Automated Setup

```bash
# Install Ceph packages
./scripts/ceph/01-install-ceph.sh

# Create monitors
./scripts/ceph/02-create-monitors.sh

# Create OSDs  
./scripts/ceph/03-create-osds.sh

# Apply optimizations
./scripts/ceph/04-apply-optimizations.sh
```

## Manual Setup

### Step 1: Install Ceph Packages

```bash
for node in n2 n3 n4; do
    echo "=== Installing Ceph on $node ==="
    ssh $node "pveceph install --repository test"
done
```

**Note:** Use `--repository no-subscription` for stable releases, `--repository test` for latest features.

This installs:
- ceph-common
- ceph-mon
- ceph-osd
- ceph-mgr

### Step 2: Create Directory Structure

```bash
for node in n2 n3 n4; do
    ssh $node "mkdir -p /var/lib/ceph && chown ceph:ceph /var/lib/ceph"
    ssh $node "mkdir -p /etc/ceph && chown ceph:ceph /etc/ceph"
done
```

### Step 3: Create First Monitor

Create the initial monitor on n2:

**GUI Method:**
1. Navigate: n2 → Ceph → Monitor
2. Click: "Create"
3. Wait for completion

**CLI Method:**
```bash
ssh n2 "pveceph mon create"
```

**Verify:**
```bash
ssh n2 "ceph -s"
```

Expected output:
```
cluster:
  id:     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  health: HEALTH_OK

services:
  mon: 1 daemons, quorum n2
  mgr: n2(active)
  osd: 0 osds: 0 up, 0 in
```

### Step 4: Configure Network Settings

**Critical:** Set networks BEFORE creating additional monitors.

> **Common Pitfall:** If you set `public_network` to a slow network (e.g., 1GbE) and `cluster_network` to TB4, you'll get a massive bottleneck (~175 MB/s instead of 1,300+ MB/s). This is because Ceph client I/O goes through the public network first.
>
> **Options:**
> - **Option A (Recommended for homelab):** Set BOTH networks to TB4 if VMs access Ceph locally
> - **Option B:** Set public to your fastest ethernet, cluster to TB4

```bash
# Option A: Both networks on TB4 (best for local-only access)
ssh n2 "ceph config set global public_network 10.100.0.0/24"
ssh n2 "ceph config set global cluster_network 10.100.0.0/24"

# Option B: Split networks (if VMs need external Ceph access)
# Public network (client I/O) - use your fast ethernet
ssh n2 "ceph config set global public_network 10.11.11.0/24"

# Cluster network (OSD replication) - THIS IS YOUR TB4 NETWORK!
ssh n2 "ceph config set global cluster_network 10.100.0.0/24"

# Also set for monitors explicitly
ssh n2 "ceph config set mon public_network 10.11.11.0/24"
ssh n2 "ceph config set mon cluster_network 10.100.0.0/24"
```

**Verify settings:**
```bash
ssh n2 "ceph config get mon public_network"
ssh n2 "ceph config get mon cluster_network"
```

### Step 5: Create Additional Monitors

Now create monitors on n3 and n4:

**GUI Method:**
1. n3 → Ceph → Monitor → Create
2. n4 → Ceph → Monitor → Create

**CLI Method:**
```bash
ssh n3 "pveceph mon create"
ssh n4 "pveceph mon create"
```

**Verify 3-node quorum:**
```bash
ssh n2 "ceph quorum_status --format json-pretty | head -20"
```

Should show all 3 monitors in quorum.

### Step 6: Identify Available Drives

Check which drives are available for OSDs:

```bash
for node in n2 n3 n4; do
    echo "=== Drives on $node ==="
    ssh $node "lsblk -d -o NAME,SIZE,MODEL,TYPE | grep disk"
done
```

**Warning:** Only use drives that don't contain your OS! Typically:
- `/dev/nvme0n1` - Often the OS drive
- `/dev/nvme1n1`, `/dev/nvme2n1` - Available for Ceph

### Step 7: Create OSDs

Create 2 OSDs per node (adjust drive names as needed):

**GUI Method:**
1. n2 → Ceph → OSD → Create: OSD
2. Select drive (e.g., /dev/nvme1n1)
3. Leave DB/WAL as default (co-located)
4. Repeat for all drives on all nodes

**CLI Method:**
```bash
# On n2
ssh n2 "pveceph osd create /dev/nvme1n1"
ssh n2 "pveceph osd create /dev/nvme2n1"

# On n3
ssh n3 "pveceph osd create /dev/nvme1n1"
ssh n3 "pveceph osd create /dev/nvme2n1"

# On n4
ssh n4 "pveceph osd create /dev/nvme1n1"
ssh n4 "pveceph osd create /dev/nvme2n1"
```

**Verify OSDs:**
```bash
ssh n2 "ceph osd tree"
```

Expected output:
```
ID  CLASS  WEIGHT   TYPE NAME      STATUS  REWEIGHT  PRI-AFF
-1         5.45776  root default                              
-3         1.81959      host n2                               
 0    ssd  0.90979          osd.0      up   1.00000  1.00000
 1    ssd  0.90979          osd.1      up   1.00000  1.00000
-5         1.81959      host n3                               
 2    ssd  0.90979          osd.2      up   1.00000  1.00000
 3    ssd  0.90979          osd.3      up   1.00000  1.00000
-7         1.81959      host n4                               
 4    ssd  0.90979          osd.4      up   1.00000  1.00000
 5    ssd  0.90979          osd.5      up   1.00000  1.00000
```

### Step 8: Create Storage Pool

Create a pool with optimal settings for homelab:

```bash
# Create pool with 256 PGs (good for 6 OSDs)
ssh n2 "ceph osd pool create cephtb4 256 256"

# Set 2:1 replication (size=2, min_size=1)
ssh n2 "ceph osd pool set cephtb4 size 2"
ssh n2 "ceph osd pool set cephtb4 min_size 1"

# Enable RBD application
ssh n2 "ceph osd pool application enable cephtb4 rbd"
```

**Why 2:1 replication?**
- Homelab doesn't need 3-way replication
- Saves 33% storage space
- Still protected against single drive failure

### Step 9: Verify Cluster Health

```bash
ssh n2 "ceph -s"
```

Expected:
```
cluster:
  id:     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  health: HEALTH_OK

services:
  mon: 3 daemons, quorum n2,n3,n4
  mgr: n2(active), standbys: n3, n4
  osd: 6 osds: 6 up, 6 in

data:
  pools:   1 pools, 256 pgs
  objects: 0 objects, 0 B
  usage:   6.0 GiB used, 5.4 TiB / 5.4 TiB avail
  pgs:     256 active+clean
```

### Step 10: Add Storage to Proxmox

**GUI Method:**
1. Datacenter → Storage → Add → RBD
2. Configure:
   - ID: `cephtb4`
   - Pool: `cephtb4`
   - Monitor(s): auto-detected
3. Click: Add

**CLI Method:**
```bash
pvesm add rbd cephtb4 --pool cephtb4 --content images,rootdir
```

## Verify TB4 Is Being Used

Confirm OSDs are using the TB4 network:

```bash
# Check OSD network bindings
ssh n2 "ceph config get osd cluster_network"
# Should show: 10.100.0.0/24

# Watch OSD traffic on TB4 interface
ssh n2 "iftop -i en05"  # Ctrl+C to exit
```

## Troubleshooting

### OSDs Won't Start

```bash
# Check OSD status
ssh n2 "systemctl status ceph-osd@0"

# Check logs
ssh n2 "journalctl -u ceph-osd@0 -n 50"
```

Common causes:
- TB4 interfaces not up → OSDs can't bind to cluster_network
- Wrong cluster_network configured

### "Cannot assign requested address"

The cluster_network IPs aren't available:

```bash
# Verify TB4 interfaces have IPs
ssh n2 "ip addr show en05 en06"

# Bring up interfaces
ssh n2 "/usr/local/bin/pve-en05.sh"
ssh n2 "/usr/local/bin/pve-en06.sh"

# Restart OSDs
ssh n2 "systemctl restart ceph-osd.target"
```

### Slow Performance

See [Performance Tuning](07-performance.md) for optimization settings.

### PGs Not Active+Clean

```bash
# Check PG status
ssh n2 "ceph pg stat"

# Find stuck PGs
ssh n2 "ceph pg dump_stuck"
```

Usually resolves after a few minutes as data rebalances.

## Next Steps

1. [Performance Tuning](07-performance.md) - Optimize for your hardware
