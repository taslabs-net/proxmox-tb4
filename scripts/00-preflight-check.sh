#!/bin/bash
# Preflight check - verify prerequisites before starting setup
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

print_header "Preflight Check"

# Load config
load_config

log_step "Checking local prerequisites"

# Check SSH available
if command -v ssh &>/dev/null; then
    log_success "SSH client available"
else
    log_error "SSH client not found"
    exit 1
fi

# Check config values
log_step "Verifying configuration"

if [[ -z "$NODE1_MGMT_IP" || -z "$NODE2_MGMT_IP" || -z "$NODE3_MGMT_IP" ]]; then
    log_error "Node management IPs not configured in config.env"
    exit 1
fi
log_success "Node IPs configured: $NODE1_MGMT_IP, $NODE2_MGMT_IP, $NODE3_MGMT_IP"

if [[ -z "$TB4_NETWORK" ]]; then
    log_error "TB4 network not configured in config.env"
    exit 1
fi
log_success "TB4 network: $TB4_NETWORK"

# Check SSH connectivity
log_step "Testing SSH connectivity"

read -ra nodes <<< "$(get_node_ips)"
read -ra names <<< "$NODE1_NAME $NODE2_NAME $NODE3_NAME"
all_reachable=true

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    echo -n "Testing $name ($node)... "
    
    if check_ssh "$node"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        all_reachable=false
    fi
done

if [[ "$all_reachable" != "true" ]]; then
    echo ""
    log_warn "Some nodes are not reachable via SSH."
    log_info "Run ./scripts/01-setup-ssh.sh to configure SSH access."
    log_info "Or manually set up SSH keys first."
fi

# Check Proxmox version on reachable nodes
log_step "Checking Proxmox versions"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    if check_ssh "$node"; then
        version=$(ssh "root@$node" "pveversion 2>/dev/null | head -1" || echo "unknown")
        if [[ "$version" == *"pve-manager/9"* ]]; then
            log_success "$name: $version"
        elif [[ "$version" == *"pve-manager/8"* ]]; then
            log_warn "$name: $version (PVE 8 detected - guide targets PVE 9)"
        else
            log_warn "$name: $version"
        fi
    fi
done

# Check TB4 hardware on reachable nodes
log_step "Checking Thunderbolt 4 hardware"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    if check_ssh "$node"; then
        tb4_count=$(ssh "root@$node" "lspci | grep -ci thunderbolt" 2>/dev/null || echo "0")
        if [[ "$tb4_count" -gt 0 ]]; then
            log_success "$name: $tb4_count TB4 controller(s) detected"
        else
            log_warn "$name: No TB4 controllers detected (might show as USB controller)"
        fi
    fi
done

# Summary
log_step "Summary"

echo ""
if [[ "$all_reachable" == "true" ]]; then
    log_success "All preflight checks passed!"
    echo ""
    log_info "Next steps:"
    log_info "  1. ./scripts/02-install-tb4-modules.sh"
    log_info "  2. ./scripts/03-configure-interfaces.sh"
    log_info "  3. Continue with remaining scripts..."
else
    log_warn "Some checks failed. Please resolve issues before continuing."
    echo ""
    log_info "If SSH fails, run: ./scripts/01-setup-ssh.sh"
fi

echo ""
