#!/bin/bash
# Set up SSH key authentication to all nodes
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

print_header "SSH Key Setup"

# Load config
load_config

# Determine SSH key path
if [[ -n "$SSH_KEY_PATH" && -f "$SSH_KEY_PATH" ]]; then
    KEY_PATH="$SSH_KEY_PATH"
elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    KEY_PATH="$HOME/.ssh/id_ed25519"
elif [[ -f "$HOME/.ssh/id_rsa" ]]; then
    KEY_PATH="$HOME/.ssh/id_rsa"
else
    KEY_PATH=""
fi

log_step "Step 1: SSH Key"

if [[ -n "$KEY_PATH" ]]; then
    log_success "Found existing SSH key: $KEY_PATH"
    PUB_KEY_PATH="${KEY_PATH}.pub"
else
    log_info "No SSH key found. Generating new ed25519 key..."
    
    KEY_PATH="$HOME/.ssh/id_ed25519"
    PUB_KEY_PATH="${KEY_PATH}.pub"
    
    if confirm "Generate new SSH key?"; then
        ssh-keygen -t ed25519 -C "$SSH_KEY_COMMENT" -f "$KEY_PATH" -N ""
        log_success "Generated new SSH key: $KEY_PATH"
    else
        log_error "Cannot continue without SSH key"
        exit 1
    fi
fi

# Read public key
if [[ ! -f "$PUB_KEY_PATH" ]]; then
    log_error "Public key not found: $PUB_KEY_PATH"
    exit 1
fi

PUB_KEY=$(cat "$PUB_KEY_PATH")
log_info "Public key: ${PUB_KEY:0:50}..."

log_step "Step 2: Accept Host Keys"

read -ra nodes <<< "$(get_node_ips)"
read -ra names <<< "$NODE1_NAME $NODE2_NAME $NODE3_NAME"

log_info "You may need to type 'yes' to accept each host key."
log_info "You may also need to enter the root password for each node."
echo ""

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    # Check if already in known_hosts
    if ssh-keygen -F "$node" &>/dev/null; then
        log_success "$name ($node): Host key already known"
    else
        log_info "Connecting to $name ($node) to accept host key..."
        if ssh -o StrictHostKeyChecking=accept-new "root@$node" "echo 'Host key accepted'" 2>/dev/null; then
            log_success "$name ($node): Host key accepted"
        else
            log_warn "$name ($node): Could not connect (will try key deployment anyway)"
        fi
    fi
done

log_step "Step 3: Deploy SSH Key"

for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    log_info "Deploying key to $name ($node)..."
    
    # Check if key already deployed
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "root@$node" "echo ok" &>/dev/null; then
        log_success "$name ($node): Key already works"
        continue
    fi
    
    # Try to deploy key
    if command -v ssh-copy-id &>/dev/null; then
        ssh-copy-id -i "$KEY_PATH" "root@$node" 2>/dev/null || {
            log_warn "ssh-copy-id failed, trying manual method..."
            ssh "root@$node" "mkdir -p ~/.ssh && echo '$PUB_KEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        }
    else
        ssh "root@$node" "mkdir -p ~/.ssh && echo '$PUB_KEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    fi
    
    log_success "$name ($node): Key deployed"
done

log_step "Step 4: Verify SSH Access"

all_ok=true
for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"
    name="${names[$i]}"
    
    echo -n "Testing $name ($node)... "
    
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "root@$node" "hostname" &>/dev/null; then
        hostname=$(ssh "root@$node" "hostname")
        echo -e "${GREEN}OK${NC} (hostname: $hostname)"
    else
        echo -e "${RED}FAILED${NC}"
        all_ok=false
    fi
done

log_step "Summary"

if [[ "$all_ok" == "true" ]]; then
    log_success "SSH access configured for all nodes!"
    echo ""
    log_info "You can now run commands like:"
    log_info "  ssh root@$NODE1_MGMT_IP"
    log_info "  ssh root@$NODE2_MGMT_IP"
    log_info "  ssh root@$NODE3_MGMT_IP"
    echo ""
    log_info "Next step: ./scripts/02-install-tb4-modules.sh"
else
    log_error "Some nodes failed SSH test. Please check connectivity."
fi

echo ""
