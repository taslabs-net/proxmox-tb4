#!/bin/bash
# Configure TB4 network interfaces
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

print_header "TB4 Interface Configuration"

load_config

nodes=($(get_node_ips))
names=($NODE1_NAME $NODE2_NAME $NODE3_NAME)

# Build node-specific configs
declare -A node_en05_ip
declare -A node_en06_ip

node_en05_ip[$NODE1_MGMT_IP]="$NODE1_TB4_EN05_IP/$NODE1_TB4_EN05_MASK"
node_en06_ip[$NODE1_MGMT_IP]="$NODE1_TB4_EN06_IP/$NODE1_TB4_EN06_MASK"
node_en05_ip[$NODE2_MGMT_IP]="$NODE2_TB4_EN05_IP/$NODE2_TB4_EN05_MASK"
node_en06_ip[$NODE2_MGMT_IP]="$NODE2_TB4_EN06_IP/$NODE2_TB4_EN06_MASK"
node_en05_ip[$NODE3_MGMT_IP]="$NODE3_TB4_EN05_IP/$NODE3_TB4_EN05_MASK"
node_en06_ip[$NODE3_MGMT_IP]="$NODE3_TB4_EN06_IP/$NODE3_TB4_EN06_MASK"

log_step "Step 1: Check Current Interface State"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    echo ""
    log_info "=== $name ($node) ==="
    ssh "root@$node" "ip link show ${TB4_IFACE1} 2>/dev/null || echo '${TB4_IFACE1} not found'"
    ssh "root@$node" "ip link show ${TB4_IFACE2} 2>/dev/null || echo '${TB4_IFACE2} not found'"
done

log_step "Step 2: Configure /etc/network/interfaces"

echo ""
log_warn "IMPORTANT: TB4 interfaces must be defined BEFORE 'source /etc/network/interfaces.d/*'"
log_info "This prevents conflicts with SDN configuration."
echo ""

if confirm "Add TB4 interface configuration to all nodes?"; then
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        name="${names[$i]}"
        en05_ip="${node_en05_ip[$node]}"
        en06_ip="${node_en06_ip[$node]}"
        
        log_info "Configuring $name ($node)..."
        log_info "  ${TB4_IFACE1}: $en05_ip"
        log_info "  ${TB4_IFACE2}: $en06_ip"
        
        # Backup existing config
        backup_file "$node" "/etc/network/interfaces"
        
        # Check if already configured
        if ssh "root@$node" "grep -q '${TB4_IFACE1} inet static' /etc/network/interfaces 2>/dev/null"; then
            log_warn "$name: TB4 interfaces already configured, skipping"
            continue
        fi
        
        # Add configuration
        ssh "root@$node" "cat >> /etc/network/interfaces << 'EOF'

# TB4 Interfaces - DO NOT EDIT IN GUI
iface ${TB4_IFACE1} inet manual #do not edit in GUI
iface ${TB4_IFACE2} inet manual #do not edit in GUI

# TB4 Point-to-Point Links
auto ${TB4_IFACE1}
iface ${TB4_IFACE1} inet static
    address ${en05_ip}
    mtu ${TB4_MTU}

auto ${TB4_IFACE2}
iface ${TB4_IFACE2} inet static
    address ${en06_ip}
    mtu ${TB4_MTU}
EOF"
        
        log_success "$name: Configuration added"
    done
fi

log_step "Step 3: Enable IPv4 Forwarding"

log_info "Required for OpenFabric routing"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    ssh "root@$node" "grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf"
    ssh "root@$node" "sysctl -w net.ipv4.ip_forward=1 >/dev/null"
    
    log_success "$name: IPv4 forwarding enabled"
done

log_step "Step 4: Apply Network Configuration"

if confirm "Apply network configuration now?"; then
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        name="${names[$i]}"
        
        log_info "Applying configuration on $name..."
        ssh "root@$node" "ifreload -a 2>/dev/null || ifdown ${TB4_IFACE1} ${TB4_IFACE2} 2>/dev/null; ifup ${TB4_IFACE1} ${TB4_IFACE2} 2>/dev/null || true"
        
        log_success "$name: Configuration applied"
    done
fi

log_step "Step 5: Verify Configuration"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    expected_en05="${node_en05_ip[$node]}"
    expected_en06="${node_en06_ip[$node]}"
    
    echo ""
    log_info "=== $name ($node) ==="
    
    # Check en05
    if ssh "root@$node" "ip addr show ${TB4_IFACE1} 2>/dev/null | grep -q inet"; then
        ssh "root@$node" "ip addr show ${TB4_IFACE1} | grep -E '(inet |mtu )'"
        log_success "${TB4_IFACE1}: Configured"
    else
        log_warn "${TB4_IFACE1}: No IP address (cable connected?)"
    fi
    
    # Check en06
    if ssh "root@$node" "ip addr show ${TB4_IFACE2} 2>/dev/null | grep -q inet"; then
        ssh "root@$node" "ip addr show ${TB4_IFACE2} | grep -E '(inet |mtu )'"
        log_success "${TB4_IFACE2}: Configured"
    else
        log_warn "${TB4_IFACE2}: No IP address (cable connected?)"
    fi
done

log_step "Step 6: Test Point-to-Point Connectivity"

echo ""
log_info "Testing direct connectivity between nodes..."
echo ""

# Test from node1 to node2 and node3
log_info "From $NODE1_NAME:"
ssh "root@$NODE1_MGMT_IP" "ping -c 1 -W 2 ${NODE2_TB4_EN05_IP} >/dev/null 2>&1 && echo '  -> ${NODE2_NAME} (${NODE2_TB4_EN05_IP}): OK' || echo '  -> ${NODE2_NAME} (${NODE2_TB4_EN05_IP}): FAILED'"
ssh "root@$NODE1_MGMT_IP" "ping -c 1 -W 2 ${NODE3_TB4_EN05_IP} >/dev/null 2>&1 && echo '  -> ${NODE3_NAME} (${NODE3_TB4_EN05_IP}): OK' || echo '  -> ${NODE3_NAME} (${NODE3_TB4_EN05_IP}): FAILED'"

log_step "Summary"

log_success "Interface configuration complete!"
echo ""
log_info "If connectivity fails:"
log_info "  1. Check TB4 cables are firmly connected"
log_info "  2. Verify IP addresses are in the same /30 subnet"
log_info "  3. See docs/08-troubleshooting.md"
echo ""
log_info "Next step: ./scripts/04-setup-udev-rules.sh"
echo ""
