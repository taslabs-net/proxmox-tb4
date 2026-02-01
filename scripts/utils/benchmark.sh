#!/bin/bash
# Quick benchmark script for TB4 + Ceph
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

print_header "Performance Benchmark"

load_config

read -ra nodes <<< "$(get_node_ips)"

# Find a node to run tests from
TEST_NODE=""
for node in "${nodes[@]}"; do
    if check_ssh "$node"; then
        TEST_NODE="$node"
        break
    fi
done

if [[ -z "$TEST_NODE" ]]; then
    log_error "No reachable nodes found"
    exit 1
fi

log_info "Running benchmarks from $TEST_NODE"
echo ""

log_step "1. TB4 Latency Test"

echo "Testing ping latency to other nodes..."
echo ""

for node in "${nodes[@]}"; do
    if [[ "$node" == "$TEST_NODE" ]]; then continue; fi
    
    # Get TB4 IP
    tb4_ip=$(ssh "root@$node" "ip addr show ${TB4_IFACE1} 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" || echo "")
    
    if [[ -n "$tb4_ip" ]]; then
        echo "Ping to $node ($tb4_ip):"
        ssh "root@$TEST_NODE" "ping -c 10 -i 0.2 $tb4_ip" 2>/dev/null | tail -1
        echo ""
    fi
done

log_step "2. Ceph RADOS Benchmark"

# Check if Ceph is installed
if ! ssh "root@$TEST_NODE" "command -v rados" &>/dev/null; then
    log_warn "Ceph not installed, skipping RADOS benchmark"
else
    # Check if pool exists
    pool="${CEPH_POOL_NAME:-cephtb4}"
    if ssh "root@$TEST_NODE" "ceph osd pool ls | grep -q $pool" 2>/dev/null; then
        
        echo "Running 10-second write test..."
        echo ""
        ssh "root@$TEST_NODE" "rados -p $pool bench 10 write --no-cleanup 2>&1 | grep -E '(Bandwidth|Average IOPS|Average Latency)'"
        
        echo ""
        echo "Running 10-second read test..."
        echo ""
        ssh "root@$TEST_NODE" "rados -p $pool bench 10 seq 2>&1 | grep -E '(Bandwidth|Average IOPS|Average Latency)'"
        
        echo ""
        echo "Cleaning up test objects..."
        ssh "root@$TEST_NODE" "rados -p $pool cleanup" 2>/dev/null || true
        
    else
        log_warn "Pool '$pool' not found, skipping RADOS benchmark"
    fi
fi

log_step "3. MTU Verification"

echo "Testing jumbo frames (65520 MTU)..."
echo ""

for node in "${nodes[@]}"; do
    if [[ "$node" == "$TEST_NODE" ]]; then continue; fi
    
    tb4_ip=$(ssh "root@$node" "ip addr show ${TB4_IFACE1} 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" || echo "")
    
    if [[ -n "$tb4_ip" ]]; then
        echo -n "  MTU to $node: "
        if ssh "root@$TEST_NODE" "ping -c 1 -M do -s 65492 $tb4_ip" &>/dev/null; then
            echo -e "${GREEN}PASS${NC} (65520 bytes)"
        else
            echo -e "${RED}FAIL${NC}"
        fi
    fi
done

log_step "Summary"

echo ""
echo "Expected performance targets:"
echo "  - Latency: < 1ms"
echo "  - Write throughput: > 1,000 MB/s"
echo "  - Read throughput: > 1,500 MB/s"
echo ""
echo "For detailed benchmarks, see docs/09-benchmarking.md"
echo ""
