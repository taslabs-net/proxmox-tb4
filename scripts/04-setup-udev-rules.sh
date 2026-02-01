#!/bin/bash
# Set up udev rules and interface bringup scripts
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

print_header "Udev Rules & Scripts"

load_config

nodes=($(get_node_ips))
names=($NODE1_NAME $NODE2_NAME $NODE3_NAME)

log_step "Step 1: Create Udev Rules"

log_info "These rules trigger scripts when TB4 cables are connected"
echo ""

if confirm "Create udev rules on all nodes?"; then
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        name="${names[$i]}"
        
        log_info "Creating udev rules on $name..."
        
        ssh "root@$node" 'cat > /etc/udev/rules.d/10-tb-en.rules << '\''EOF'\''
# TB4 interface hotplug rules
# Trigger bringup scripts when interfaces are renamed
ACTION=="move", SUBSYSTEM=="net", KERNEL=="en05", RUN+="/usr/local/bin/pve-en05.sh"
ACTION=="move", SUBSYSTEM=="net", KERNEL=="en06", RUN+="/usr/local/bin/pve-en06.sh"
EOF'
        
        log_success "$name: Udev rules created"
    done
fi

log_step "Step 2: Create Interface Bringup Scripts"

if confirm "Create bringup scripts on all nodes?"; then
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        name="${names[$i]}"
        
        log_info "Creating scripts on $name..."
        
        # en05 script
        ssh "root@$node" 'cat > /usr/local/bin/pve-en05.sh << '\''EOF'\''
#!/bin/bash
LOGFILE="/tmp/udev-debug.log"
echo "$(date): en05 bringup triggered" >> "$LOGFILE"

for i in {1..5}; do
    if ip link set en05 up mtu 65520 2>/dev/null; then
        echo "$(date): en05 up successful on attempt $i" >> "$LOGFILE"
        break
    else
        echo "$(date): Attempt $i failed, retrying in 3 seconds..." >> "$LOGFILE"
        sleep 3
    fi
done
EOF'
        ssh "root@$node" "chmod +x /usr/local/bin/pve-en05.sh"
        
        # en06 script
        ssh "root@$node" 'cat > /usr/local/bin/pve-en06.sh << '\''EOF'\''
#!/bin/bash
LOGFILE="/tmp/udev-debug.log"
echo "$(date): en06 bringup triggered" >> "$LOGFILE"

for i in {1..5}; do
    if ip link set en06 up mtu 65520 2>/dev/null; then
        echo "$(date): en06 up successful on attempt $i" >> "$LOGFILE"
        break
    else
        echo "$(date): Attempt $i failed, retrying in 3 seconds..." >> "$LOGFILE"
        sleep 3
    fi
done
EOF'
        ssh "root@$node" "chmod +x /usr/local/bin/pve-en06.sh"
        
        log_success "$name: Scripts created"
    done
fi

log_step "Step 3: Create Systemd Boot Service"

log_info "This service ensures TB4 interfaces come up at boot"
echo ""

if confirm "Create systemd service on all nodes?"; then
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        name="${names[$i]}"
        
        log_info "Creating systemd service on $name..."
        
        # Service file
        ssh "root@$node" 'cat > /etc/systemd/system/thunderbolt-interfaces.service << '\''EOF'\''
[Unit]
Description=Configure Thunderbolt Network Interfaces
After=network.target thunderbolt.service
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/thunderbolt-startup.sh

[Install]
WantedBy=multi-user.target
EOF'
        
        # Startup script
        ssh "root@$node" 'cat > /usr/local/bin/thunderbolt-startup.sh << '\''EOF'\''
#!/bin/bash
LOGFILE="/var/log/thunderbolt-startup.log"

echo "$(date): Starting Thunderbolt interface configuration" >> "$LOGFILE"

# Wait up to 30 seconds for interfaces to appear
for i in {1..30}; do
    if ip link show en05 &>/dev/null && ip link show en06 &>/dev/null; then
        echo "$(date): Thunderbolt interfaces found" >> "$LOGFILE"
        break
    fi
    echo "$(date): Waiting for Thunderbolt interfaces... ($i/30)" >> "$LOGFILE"
    sleep 1
done

# Configure interfaces if they exist
if ip link show en05 &>/dev/null; then
    /usr/local/bin/pve-en05.sh
    echo "$(date): en05 configured" >> "$LOGFILE"
fi

if ip link show en06 &>/dev/null; then
    /usr/local/bin/pve-en06.sh
    echo "$(date): en06 configured" >> "$LOGFILE"
fi

echo "$(date): Thunderbolt configuration completed" >> "$LOGFILE"
EOF'
        ssh "root@$node" "chmod +x /usr/local/bin/thunderbolt-startup.sh"
        
        # Enable service
        ssh "root@$node" "systemctl daemon-reload"
        ssh "root@$node" "systemctl enable thunderbolt-interfaces.service"
        
        log_success "$name: Systemd service created and enabled"
    done
fi

log_step "Step 4: Reload Udev Rules"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    ssh "root@$node" "udevadm control --reload-rules"
    log_success "$name: Udev rules reloaded"
done

log_step "Step 5: Verify Installation"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    echo ""
    log_info "=== $name ($node) ==="
    
    # Check files exist
    echo -n "  Udev rules: "
    if ssh "root@$node" "test -f /etc/udev/rules.d/10-tb-en.rules"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}MISSING${NC}"
    fi
    
    echo -n "  pve-en05.sh: "
    if ssh "root@$node" "test -x /usr/local/bin/pve-en05.sh"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}MISSING${NC}"
    fi
    
    echo -n "  pve-en06.sh: "
    if ssh "root@$node" "test -x /usr/local/bin/pve-en06.sh"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}MISSING${NC}"
    fi
    
    echo -n "  thunderbolt-startup.sh: "
    if ssh "root@$node" "test -x /usr/local/bin/thunderbolt-startup.sh"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}MISSING${NC}"
    fi
    
    echo -n "  Systemd service: "
    if ssh "root@$node" "systemctl is-enabled thunderbolt-interfaces.service >/dev/null 2>&1"; then
        echo -e "${GREEN}ENABLED${NC}"
    else
        echo -e "${RED}DISABLED${NC}"
    fi
done

log_step "Summary"

log_success "Udev rules and scripts installed!"
echo ""
log_info "The TB4 interfaces will now:"
log_info "  - Come up automatically on boot"
log_info "  - Come up when cables are connected"
log_info "  - Use MTU 65520 for optimal performance"
echo ""
log_info "Next step: ./scripts/05-setup-systemd.sh (if not already run)"
log_info "Or continue to: ./scripts/06-verify-mesh.sh"
echo ""
