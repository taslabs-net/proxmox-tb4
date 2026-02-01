#!/bin/bash
# Diagnostic script for troubleshooting TB4 + Ceph issues
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

print_header "Diagnostics"

load_config

nodes=($(get_node_ips))
names=($NODE1_NAME $NODE2_NAME $NODE3_NAME)

echo "Gathering diagnostic information..."
echo "=================================="
echo ""

log_step "1. Node Connectivity"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    echo -n "$name ($node): "
    if check_ssh "$node"; then
        echo -e "${GREEN}REACHABLE${NC}"
    else
        echo -e "${RED}UNREACHABLE${NC}"
    fi
done

log_step "2. TB4 Interface Status"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    if ! check_ssh "$node"; then
        echo "$name: SKIPPED (unreachable)"
        continue
    fi
    
    echo ""
    echo "=== $name ==="
    ssh "root@$node" "ip addr show ${TB4_IFACE1} ${TB4_IFACE2} 2>/dev/null || echo 'TB4 interfaces not found'"
done

log_step "3. TB4 Kernel Modules"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    if ! check_ssh "$node"; then continue; fi
    
    echo ""
    echo "=== $name ==="
    ssh "root@$node" "lsmod | grep thunderbolt || echo 'No thunderbolt modules loaded'"
done

log_step "4. Systemd Services"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    if ! check_ssh "$node"; then continue; fi
    
    echo ""
    echo "=== $name ==="
    
    echo -n "  thunderbolt-interfaces.service: "
    status=$(ssh "root@$node" "systemctl is-active thunderbolt-interfaces.service 2>/dev/null" || echo "unknown")
    case "$status" in
        active) echo -e "${GREEN}$status${NC}" ;;
        failed) echo -e "${RED}$status${NC}" ;;
        *) echo -e "${YELLOW}$status${NC}" ;;
    esac
    
    echo -n "  frr.service: "
    status=$(ssh "root@$node" "systemctl is-active frr 2>/dev/null" || echo "not installed")
    case "$status" in
        active) echo -e "${GREEN}$status${NC}" ;;
        failed) echo -e "${RED}$status${NC}" ;;
        *) echo -e "${YELLOW}$status${NC}" ;;
    esac
    
    echo -n "  ceph-osd.target: "
    status=$(ssh "root@$node" "systemctl is-active ceph-osd.target 2>/dev/null" || echo "not installed")
    case "$status" in
        active) echo -e "${GREEN}$status${NC}" ;;
        failed) echo -e "${RED}$status${NC}" ;;
        *) echo -e "${YELLOW}$status${NC}" ;;
    esac
done

log_step "5. Script Health Check"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    if ! check_ssh "$node"; then continue; fi
    
    echo ""
    echo "=== $name ==="
    
    # Check for corrupted scripts
    for script in /usr/local/bin/pve-en05.sh /usr/local/bin/pve-en06.sh /usr/local/bin/thunderbolt-startup.sh; do
        if ssh "root@$node" "test -f $script" 2>/dev/null; then
            lines=$(ssh "root@$node" "wc -l < $script")
            shebang=$(ssh "root@$node" "head -1 $script")
            
            echo -n "  $script: "
            if [[ "$lines" -gt 100 ]]; then
                echo -e "${RED}CORRUPTED ($lines lines - should be ~15)${NC}"
            elif [[ "$shebang" != "#!/bin/bash" ]]; then
                echo -e "${RED}BAD SHEBANG ($shebang)${NC}"
            else
                echo -e "${GREEN}OK ($lines lines)${NC}"
            fi
        else
            echo "  $script: MISSING"
        fi
    done
done

log_step "6. Ceph Status"

# Try to get Ceph status from first reachable node
for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    
    if check_ssh "$node"; then
        if ssh "root@$node" "command -v ceph" &>/dev/null; then
            echo ""
            ssh "root@$node" "ceph -s 2>/dev/null" || echo "Ceph not configured or not running"
        else
            echo "Ceph not installed"
        fi
        break
    fi
done

log_step "7. Recent Errors"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    if ! check_ssh "$node"; then continue; fi
    
    echo ""
    echo "=== $name (last 5 errors) ==="
    ssh "root@$node" "journalctl -p err --no-pager -n 5 2>/dev/null" || echo "No errors found"
done

log_step "8. Network Routes"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    if ! check_ssh "$node"; then continue; fi
    
    echo ""
    echo "=== $name ==="
    ssh "root@$node" "ip route | grep -E '(${TB4_NETWORK}|${TB4_IFACE1}|${TB4_IFACE2})' || echo 'No TB4 routes found'"
done

log_step "Summary"

echo ""
echo "Diagnostic collection complete."
echo ""
echo "To save this output:"
echo "  ./scripts/utils/troubleshoot.sh > diagnostics.txt 2>&1"
echo ""
