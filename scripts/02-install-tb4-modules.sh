#!/bin/bash
# Install and configure TB4 kernel modules
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

print_header "TB4 Kernel Modules"

load_config

read -ra nodes <<< "$(get_node_ips)"
read -ra names <<< "$NODE1_NAME $NODE2_NAME $NODE3_NAME"

log_step "Step 1: Load TB4 Kernel Modules"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    log_info "Configuring $name ($node)..."
    
    # Add to /etc/modules for persistence
    ssh "root@$node" "grep -q '^thunderbolt$' /etc/modules 2>/dev/null || echo 'thunderbolt' >> /etc/modules"
    ssh "root@$node" "grep -q '^thunderbolt-net$' /etc/modules 2>/dev/null || echo 'thunderbolt-net' >> /etc/modules"
    
    # Load modules now
    ssh "root@$node" "modprobe thunderbolt 2>/dev/null || true"
    ssh "root@$node" "modprobe thunderbolt-net 2>/dev/null || true"
    
    log_success "$name: Modules configured"
done

log_step "Step 2: Verify Modules Loaded"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    echo ""
    log_info "=== $name ($node) ==="
    ssh "root@$node" "lsmod | grep thunderbolt || echo 'No thunderbolt modules loaded'"
done

log_step "Step 3: Create Systemd Link Files"

log_info "These files ensure consistent interface naming (en05, en06)"
echo ""

if confirm "Create systemd link files on all nodes?"; then
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        name="${names[$i]}"
        
        log_info "Creating link files on $name..."
        
        # First TB4 port -> en05
        ssh "root@$node" "cat > /etc/systemd/network/00-thunderbolt0.link << 'EOF'
[Match]
Path=${TB4_PCI_PATH_0}
Driver=thunderbolt-net

[Link]
MACAddressPolicy=none
Name=${TB4_IFACE1}
EOF"

        # Second TB4 port -> en06
        ssh "root@$node" "cat > /etc/systemd/network/00-thunderbolt1.link << 'EOF'
[Match]
Path=${TB4_PCI_PATH_1}
Driver=thunderbolt-net

[Link]
MACAddressPolicy=none
Name=${TB4_IFACE2}
EOF"
        
        log_success "$name: Link files created"
    done
fi

log_step "Step 4: Enable systemd-networkd"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    ssh "root@$node" "systemctl enable systemd-networkd 2>/dev/null"
    ssh "root@$node" "systemctl start systemd-networkd 2>/dev/null || true"
    
    log_success "$name: systemd-networkd enabled"
done

log_step "Step 5: Update Initramfs"

if confirm "Update initramfs on all nodes? (required for changes to take effect)"; then
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        name="${names[$i]}"
        
        log_info "Updating initramfs on $name (this may take a minute)..."
        ssh "root@$node" "update-initramfs -u -k all"
        log_success "$name: Initramfs updated"
    done
fi

log_step "Step 6: Reboot Nodes"

echo ""
log_warn "A reboot is required to apply interface renaming."
echo ""

if confirm "Reboot all nodes now?"; then
    log_info "Rebooting nodes..."
    
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        name="${names[$i]}"
        ssh "root@$node" "reboot" &
    done
    
    echo ""
    log_info "Waiting 90 seconds for nodes to reboot..."
    sleep 90
    
    # Verify nodes are back
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        name="${names[$i]}"
        wait_for_node "$node" 120
    done
    
    log_step "Verifying Interface Names After Reboot"
    
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        name="${names[$i]}"
        
        echo ""
        log_info "=== $name ==="
        ssh "root@$node" "ip link show | grep -E '(${TB4_IFACE1}|${TB4_IFACE2})' || echo 'TB4 interfaces not found (cables connected?)'"
    done
else
    log_warn "Remember to reboot nodes manually before continuing!"
fi

log_step "Summary"

log_success "TB4 module installation complete!"
echo ""
log_info "If interfaces don't appear after reboot:"
log_info "  1. Ensure TB4 cables are connected"
log_info "  2. Check PCI paths match your hardware"
log_info "  3. See docs/08-troubleshooting.md"
echo ""
log_info "Next step: ./scripts/03-configure-interfaces.sh"
echo ""
