#!/bin/bash
# Verify TB4 mesh connectivity
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

print_header "TB4 Mesh Verification"

load_config

nodes=($(get_node_ips))
names=($NODE1_NAME $NODE2_NAME $NODE3_NAME)

log_step "Step 1: Interface Status"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    echo ""
    log_info "=== $name ($node) ==="
    
    # Check interface status
    for iface in ${TB4_IFACE1} ${TB4_IFACE2}; do
        status=$(ssh "root@$node" "ip link show $iface 2>/dev/null | head -1" || echo "NOT FOUND")
        
        if echo "$status" | grep -q "UP"; then
            if echo "$status" | grep -q "LOWER_UP"; then
                echo -e "  $iface: ${GREEN}UP (link detected)${NC}"
            else
                echo -e "  $iface: ${YELLOW}UP (no link)${NC}"
            fi
        elif echo "$status" | grep -q "DOWN"; then
            echo -e "  $iface: ${RED}DOWN${NC}"
        else
            echo -e "  $iface: ${RED}NOT FOUND${NC}"
        fi
    done
    
    # Show IPs
    echo "  IPs:"
    ssh "root@$node" "ip addr show ${TB4_IFACE1} 2>/dev/null | grep 'inet ' | awk '{print \"    ${TB4_IFACE1}: \" \$2}'" || echo "    ${TB4_IFACE1}: no IP"
    ssh "root@$node" "ip addr show ${TB4_IFACE2} 2>/dev/null | grep 'inet ' | awk '{print \"    ${TB4_IFACE2}: \" \$2}'" || echo "    ${TB4_IFACE2}: no IP"
    
    # Show MTU
    echo "  MTU:"
    ssh "root@$node" "ip link show ${TB4_IFACE1} 2>/dev/null | grep -o 'mtu [0-9]*' | head -1 | sed 's/^/    ${TB4_IFACE1}: /'" || true
    ssh "root@$node" "ip link show ${TB4_IFACE2} 2>/dev/null | grep -o 'mtu [0-9]*' | head -1 | sed 's/^/    ${TB4_IFACE2}: /'" || true
done

log_step "Step 2: Point-to-Point Connectivity"

echo ""
log_info "Testing direct link connectivity..."
echo ""

# Define expected connections
declare -A connections
connections["$NODE1_NAME-$NODE2_NAME"]="$NODE1_MGMT_IP:$NODE2_TB4_EN05_IP"
connections["$NODE1_NAME-$NODE3_NAME"]="$NODE1_MGMT_IP:$NODE3_TB4_EN05_IP"
connections["$NODE2_NAME-$NODE3_NAME"]="$NODE2_MGMT_IP:$NODE3_TB4_EN06_IP"

all_ok=true
for link in "${!connections[@]}"; do
    IFS=':' read -r source_ip target_ip <<< "${connections[$link]}"
    
    echo -n "  $link: "
    if ssh "root@$source_ip" "ping -c 1 -W 2 $target_ip" &>/dev/null; then
        latency=$(ssh "root@$source_ip" "ping -c 1 $target_ip 2>/dev/null | grep 'time=' | sed 's/.*time=//'" || echo "?")
        echo -e "${GREEN}OK${NC} (${latency})"
    else
        echo -e "${RED}FAILED${NC}"
        all_ok=false
    fi
done

log_step "Step 3: Router ID Connectivity (via OpenFabric)"

echo ""
log_info "Testing router ID reachability..."
echo ""

router_ids=("$NODE1_ROUTER_ID" "$NODE2_ROUTER_ID" "$NODE3_ROUTER_ID")
router_names=("$NODE1_NAME" "$NODE2_NAME" "$NODE3_NAME")

for i in "${!router_ids[@]}"; do
    rid="${router_ids[$i]}"
    rname="${router_names[$i]}"
    
    echo -n "  $rname ($rid): "
    if ping -c 1 -W 2 "$rid" &>/dev/null; then
        latency=$(ping -c 1 "$rid" 2>/dev/null | grep 'time=' | sed 's/.*time=//' || echo "?")
        echo -e "${GREEN}OK${NC} (${latency})"
    else
        echo -e "${YELLOW}UNREACHABLE${NC} (OpenFabric may not be configured yet)"
    fi
done

log_step "Step 4: Latency Test"

echo ""
log_info "Running 10-ping latency test..."
echo ""

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    if [[ $i -eq 0 ]]; then
        continue  # Skip first node (we'll ping from here)
    fi
    
    # Get a TB4 IP from this node
    target_ip=$(ssh "root@$node" "ip addr show ${TB4_IFACE1} 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1")
    
    if [[ -n "$target_ip" ]]; then
        echo -n "  ${NODE1_NAME} -> $name ($target_ip): "
        result=$(ssh "root@$NODE1_MGMT_IP" "ping -c 10 -i 0.2 $target_ip 2>/dev/null | tail -1")
        echo "$result"
    fi
done

log_step "Step 5: MTU Test (Jumbo Frames)"

echo ""
log_info "Testing 65520 MTU end-to-end..."
echo ""

# Test from node1 to node2
target_ip="$NODE2_TB4_EN05_IP"
echo -n "  ${NODE1_NAME} -> ${NODE2_NAME}: "

# 65520 MTU - 20 IP header - 8 ICMP header = 65492 payload
if ssh "root@$NODE1_MGMT_IP" "ping -c 1 -M do -s 65492 $target_ip" &>/dev/null; then
    echo -e "${GREEN}PASS${NC} (65520 MTU working)"
else
    echo -e "${RED}FAIL${NC} (MTU may not be configured correctly)"
fi

log_step "Summary"

echo ""
if [[ "$all_ok" == "true" ]]; then
    log_success "All connectivity tests passed!"
    echo ""
    log_info "Your TB4 mesh is operational."
    log_info ""
    log_info "Next steps:"
    log_info "  1. Configure SDN/OpenFabric in Proxmox GUI"
    log_info "  2. Or run: ./scripts/ceph/01-install-ceph.sh"
else
    log_warn "Some tests failed. Please check:"
    log_info "  1. TB4 cables are firmly connected"
    log_info "  2. IP addressing is correct"
    log_info "  3. See docs/08-troubleshooting.md"
fi

echo ""
