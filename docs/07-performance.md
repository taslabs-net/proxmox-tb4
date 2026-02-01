# Performance Tuning

This section covers optimizations for high-performance hardware (64GB RAM, modern CPUs, NVMe, TB4).

## Overview

The default Ceph settings are conservative. With homelab hardware like:
- 64GB RAM per node
- 13th Gen Intel / Ryzen 7000 series
- NVMe storage
- TB4 networking

...you can significantly improve performance.

## Quick Apply Script

```bash
./scripts/ceph/04-apply-optimizations.sh
```

## Memory Optimizations

### OSD Memory Target

Each OSD can use more RAM for caching:

```bash
# 12GB per OSD (recommended for 64GB nodes with 2 OSDs = 24GB for Ceph)
ssh n2 "ceph config set osd osd_memory_target 12884901888"

# Minimum cache before eviction
ssh n2 "ceph config set osd osd_memory_cache_min 1073741824"  # 1GB

# Cache resize interval
ssh n2 "ceph config set osd osd_memory_cache_resize_interval 1"
```

**Adjust based on your RAM:**
| Node RAM | OSDs | osd_memory_target |
|----------|------|-------------------|
| 32GB | 2 | 6GB (6442450944) |
| 64GB | 2 | 12GB (12884901888) |
| 128GB | 2 | 16GB (17179869184) |

### BlueStore Cache

```bash
# 4GB cache for SSDs/NVMe
ssh n2 "ceph config set osd bluestore_cache_size_ssd 4294967296"
```

## CPU Optimizations

### Threading for Modern CPUs

```bash
# Operation shards and threads
ssh n2 "ceph config set osd osd_op_num_shards 8"
ssh n2 "ceph config set osd osd_op_num_threads_per_shard 2"

# Async messaging threads
ssh n2 "ceph config set global ms_async_op_threads 8"

# Client message handling
ssh n2 "ceph config set osd osd_client_message_cap 1000"
ssh n2 "ceph config set osd osd_client_message_size_cap 1073741824"
```

## Network Optimizations

### For TB4 (High Bandwidth, Low Latency)

```bash
# Disable Nagle's algorithm for low latency
ssh n2 "ceph config set global ms_tcp_nodelay true"

# Large receive buffer
ssh n2 "ceph config set global ms_tcp_rcvbuf 134217728"  # 128MB

# Prefetch optimization
ssh n2 "ceph config set global ms_tcp_prefetch_max_size 65536"

# CRC mode for cluster (faster than secure)
ssh n2 "ceph config set global ms_cluster_mode crc"

# Dispatch throttling
ssh n2 "ceph config set global ms_dispatch_throttle_bytes 1073741824"
```

### Heartbeat Tuning

For fast, reliable networks:

```bash
# Heartbeat interval (seconds)
ssh n2 "ceph config set osd osd_heartbeat_interval 6"

# Grace period before marking OSD down
ssh n2 "ceph config set osd osd_heartbeat_grace 20"
```

## BlueStore Optimizations

### Compression

LZ4 compression improves effective throughput:

```bash
# Use LZ4 (fast)
ssh n2 "ceph config set osd bluestore_compression_algorithm lz4"

# Compress aggressively
ssh n2 "ceph config set osd bluestore_compression_mode aggressive"

# Only store if 30%+ smaller
ssh n2 "ceph config set osd bluestore_compression_required_ratio 0.7"
```

### NVMe-Specific Settings

```bash
# Disable sync on commit (NVMe has capacitors)
ssh n2 "ceph config set osd bluestore_sync_submit_transaction false"

# Throttling for high-speed storage
ssh n2 "ceph config set osd bluestore_throttle_bytes 268435456"
ssh n2 "ceph config set osd bluestore_throttle_deferred_bytes 134217728"

# Cache trim interval
ssh n2 "ceph config set osd bluestore_cache_trim_interval 200"
```

### DB and WAL Sizing

If using separate DB/WAL devices:

```bash
# 5GB for DB
ssh n2 "ceph config set osd bluestore_block_db_size 5368709120"

# 1GB for WAL
ssh n2 "ceph config set osd bluestore_block_wal_size 1073741824"
```

## Scrubbing and Maintenance

### Schedule Scrubbing Off-Peak

```bash
# Only scrub 2 AM - 6 AM
ssh n2 "ceph config set osd osd_scrub_begin_hour 2"
ssh n2 "ceph config set osd osd_scrub_end_hour 6"

# Don't scrub during recovery
ssh n2 "ceph config set osd osd_scrub_during_recovery false"

# Deep scrub every 2 weeks
ssh n2 "ceph config set osd osd_deep_scrub_interval 1209600"
ssh n2 "ceph config set osd osd_scrub_max_interval 1209600"
ssh n2 "ceph config set osd osd_scrub_min_interval 86400"
```

### Recovery Settings

Optimize for TB4's high bandwidth:

```bash
# More concurrent recovery operations
ssh n2 "ceph config set osd osd_recovery_max_active 8"
ssh n2 "ceph config set osd osd_max_backfills 4"

# Low priority (don't impact client I/O)
ssh n2 "ceph config set osd osd_recovery_op_priority 1"
```

## OS-Level Tuning

### Network Stack

Apply to all nodes:

```bash
for node in n2 n3 n4; do
    ssh $node "cat >> /etc/sysctl.conf << 'EOF'
# Network buffer sizes
net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.core.netdev_max_backlog = 30000

# Memory management
vm.swappiness = 1
vm.min_free_kbytes = 4194304
EOF"
    ssh $node "sysctl -p"
done
```

### NVMe Queue Depth

```bash
for node in n2 n3 n4; do
    ssh $node "echo 1024 > /sys/block/nvme1n1/queue/nr_requests"
done
```

Make persistent via udev rule if needed.

## Verify Settings

### Check Applied Configs

```bash
# View all non-default settings
ssh n2 "ceph config dump"

# Check specific setting
ssh n2 "ceph config get osd osd_memory_target"
```

### Monitor Performance

```bash
# Real-time OSD performance
ssh n2 "ceph osd perf"

# Pool I/O stats
ssh n2 "ceph osd pool stats cephtb4"

# Detailed stats
ssh n2 "ceph -s"
```

## Quick Reference

### Recommended Settings Summary

| Setting | Value | Purpose |
|---------|-------|---------|
| osd_memory_target | 8GB | OSD caching |
| bluestore_cache_size_ssd | 4GB | Block cache |
| osd_op_num_shards | 8 | CPU threading |
| ms_tcp_nodelay | true | Low latency |
| bluestore_compression_algorithm | lz4 | Throughput |
| osd_recovery_max_active | 8 | Fast recovery |

### Memory Usage Calculation

For 64GB nodes with 2 OSDs:
- osd_memory_target × 2 = 16GB for Ceph OSDs
- System/VMs = ~48GB remaining
- Adjust as needed for your workload

## Next Steps

1. [Troubleshooting](08-troubleshooting.md) - Common issues and fixes
2. [Benchmarking](09-benchmarking.md) - Test your setup
