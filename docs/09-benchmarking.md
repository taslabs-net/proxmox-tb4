# Benchmarking

Test and validate your cluster performance.

## Quick Benchmark

```bash
./scripts/utils/benchmark.sh
```

## Expected Results

With properly configured TB4 + NVMe + optimizations:

| Test | Expected | Good | Excellent |
|------|----------|------|-----------|
| Write Throughput | 800+ MB/s | 1,000 MB/s | 1,300+ MB/s |
| Read Throughput | 1,000+ MB/s | 1,500 MB/s | 1,700+ MB/s |
| Latency | <1ms | <0.7ms | <0.5ms |
| IOPS (4K random) | 10,000+ | 50,000+ | 100,000+ |

## Ceph Benchmarks

### RADOS Bench (Quick)

Test raw Ceph performance:

```bash
# Write test (10 seconds)
rados -p cephtb4 bench 10 write --no-cleanup

# Sequential read test
rados -p cephtb4 bench 10 seq

# Random read test
rados -p cephtb4 bench 10 rand

# Cleanup
rados -p cephtb4 cleanup
```

**Interpreting results:**
```
Total time run:         10.02 sec
Total writes made:      332
Write size:             4194304    # 4MB blocks
Object size:            4194304
Bandwidth (MB/sec):     1294.23    # This is your throughput
Average IOPS:           323
Average Latency(s):     0.0486
```

### Extended RADOS Bench

For more thorough testing:

```bash
# Larger write test with more threads
rados -p cephtb4 bench 60 write --no-cleanup -b 4M -t 16

# Extended read test
rados -p cephtb4 bench 60 rand -t 16

# Cleanup
rados -p cephtb4 cleanup
```

## FIO Benchmarks (In VM/LXC)

For realistic workload testing, create an LXC on Ceph storage:

### Setup Test Container

1. Create Debian 13 LXC on `cephtb4` storage
2. Give it 25GB disk, 4 cores, 8GB RAM
3. Install fio:
   ```bash
   apt update && apt install -y fio
   ```

### Test 1: Random 4K Read/Write (Database Workload)

```bash
fio --name=random-rw \
    --ioengine=libaio \
    --rw=randrw \
    --rwmixread=70 \
    --bs=4k \
    --direct=1 \
    --size=1G \
    --numjobs=4 \
    --runtime=30 \
    --time_based \
    --group_reporting \
    --filename=/root/test.fio
```

**Expected results:**
- Read IOPS: 50,000+
- Write IOPS: 20,000+
- Latency P50: <1ms

### Test 2: Sequential Write (Large File Transfer)

```bash
fio --name=seq-write \
    --ioengine=libaio \
    --rw=write \
    --bs=1M \
    --direct=1 \
    --size=2G \
    --numjobs=1 \
    --runtime=30 \
    --time_based \
    --group_reporting \
    --filename=/root/test-seq.fio
```

**Expected results:**
- Bandwidth: 1,000+ MB/s

### Test 3: Sequential Read

```bash
fio --name=seq-read \
    --ioengine=libaio \
    --rw=read \
    --bs=1M \
    --direct=1 \
    --size=2G \
    --numjobs=1 \
    --runtime=30 \
    --time_based \
    --group_reporting \
    --filename=/root/test-seq.fio
```

**Expected results:**
- Bandwidth: 1,500+ MB/s

### Test 4: Database Simulation (8K blocks, high queue depth)

```bash
fio --name=db-workload \
    --ioengine=libaio \
    --rw=randrw \
    --rwmixread=80 \
    --bs=8k \
    --direct=1 \
    --size=5G \
    --numjobs=8 \
    --iodepth=32 \
    --runtime=30 \
    --time_based \
    --group_reporting \
    --filename=/root/test-db.fio
```

### Cleanup Test Files

```bash
rm -f /root/test*.fio
```

## Network Benchmarks

### TB4 Latency

```bash
# From n2, test latency to other nodes
for ip in 10.100.0.12 10.100.0.13 10.100.0.14; do
    echo "=== Latency to $ip ==="
    ping -c 10 -i 0.2 $ip | tail -1
done
```

**Expected:** ~0.6ms average

### TB4 Throughput

Install iperf3:
```bash
apt install iperf3
```

**On n3 (server):**
```bash
iperf3 -s -B 10.100.0.13
```

**On n2 (client):**
```bash
iperf3 -c 10.100.0.13 -B 10.100.0.12 -t 30
```

**Expected:** 20-35 Gbps (TB4 theoretical max is 40 Gbps)

### MTU Verification

```bash
# Test jumbo frames work end-to-end
ping -c 3 -M do -s 65492 10.100.0.13
```

If this fails, MTU isn't configured correctly.

## Monitoring During Tests

### Watch Ceph Status

```bash
watch -n 1 ceph -s
```

### Monitor OSD Performance

```bash
ceph osd perf
```

### Watch Network Traffic

```bash
# On n2
iftop -i en05
```

### CPU Usage

```bash
htop
```

## Interpreting Poor Results

### Low Throughput (<500 MB/s write)

1. **Check cluster_network:**
   ```bash
   ceph config get osd cluster_network
   ```
   Must be `10.100.0.0/24`

2. **Check TB4 is being used:**
   ```bash
   iftop -i en05  # Run during benchmark
   ```

3. **Check for recovery activity:**
   ```bash
   ceph -s | grep -E "(recover|backfill)"
   ```

4. **Apply optimizations:**
   ```bash
   ./scripts/ceph/04-apply-optimizations.sh
   ```

### High Latency (>5ms)

1. **Check for packet loss:**
   ```bash
   ping -c 100 10.100.0.13 | tail -3
   ```

2. **Check MTU:**
   ```bash
   ip link show en05 | grep mtu
   ```

3. **Check CPU throttling:**
   ```bash
   dmesg | grep -i throttl
   ```

### Inconsistent Results

1. **Background activity:**
   ```bash
   ceph -s  # Check for scrubbing
   ```

2. **Other VMs using storage:**
   ```bash
   ceph osd pool stats cephtb4
   ```

3. **Thermal throttling:**
   ```bash
   sensors  # If installed
   ```

## Benchmark Comparison Table

Fill this in with your results:

| Test | Your Result | Expected | Status |
|------|-------------|----------|--------|
| RADOS Write | _____ MB/s | 1,000+ | |
| RADOS Read | _____ MB/s | 1,500+ | |
| TB4 Latency | _____ ms | <1ms | |
| TB4 Throughput | _____ Gbps | 20+ | |
| FIO Random IOPS | _____ | 50,000+ | |
| FIO Seq Write | _____ MB/s | 1,000+ | |

## Saving Results

```bash
# Create results directory
mkdir -p ~/benchmarks/$(date +%Y%m%d)

# Run and save
rados -p cephtb4 bench 60 write --no-cleanup 2>&1 | tee ~/benchmarks/$(date +%Y%m%d)/rados-write.txt
rados -p cephtb4 bench 60 seq 2>&1 | tee ~/benchmarks/$(date +%Y%m%d)/rados-read.txt
rados -p cephtb4 cleanup
```

## Congratulations!

If your benchmarks meet expectations, you've successfully built a high-performance Proxmox + TB4 + Ceph cluster!

**Summary of what you've achieved:**
- TB4 mesh network with sub-millisecond latency
- 65520 MTU jumbo frames
- Ceph storage with TB4 as cluster network
- 1,000+ MB/s throughput
- Redundant storage across 3 nodes
