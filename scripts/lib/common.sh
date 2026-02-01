#!/bin/bash
# Common functions for proxmox-tb4 scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Load configuration
load_config() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="${script_dir}/../../config.env"
    
    if [[ -f "$config_file" ]]; then
        source "$config_file"
        log_success "Loaded configuration from config.env"
    else
        log_error "config.env not found!"
        log_info "Copy config.env.example to config.env and edit it first."
        exit 1
    fi
}

# Get all node IPs as array
get_node_ips() {
    echo "$NODE1_MGMT_IP $NODE2_MGMT_IP $NODE3_MGMT_IP"
}

# Get all node names as array
get_node_names() {
    echo "$NODE1_NAME $NODE2_NAME $NODE3_NAME"
}

# Check if we can SSH to a node
check_ssh() {
    local host="$1"
    ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$host" "echo ok" &>/dev/null
}

# Run command on all nodes
run_on_all_nodes() {
    local cmd="$1"
    local nodes=($(get_node_ips))
    
    for node in "${nodes[@]}"; do
        log_info "Running on $node..."
        ssh "root@$node" "$cmd"
    done
}

# Run command on a specific node
run_on_node() {
    local node="$1"
    local cmd="$2"
    ssh "root@$node" "$cmd"
}

# Ask for confirmation
confirm() {
    local prompt="${1:-Continue?}"
    
    if [[ "$INTERACTIVE" != "true" ]]; then
        return 0
    fi
    
    echo ""
    read -p "$prompt [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    return 0
}

# Check if running as expected user
check_user() {
    if [[ "$EUID" -eq 0 ]]; then
        log_warn "Running as root. Make sure you're running from your workstation, not a node."
    fi
}

# Check prerequisites
check_prereqs() {
    local missing=()
    
    # Check for required commands
    for cmd in ssh ssh-keygen; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        exit 1
    fi
}

# Dry run wrapper
maybe_run() {
    local cmd="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $cmd"
    else
        eval "$cmd"
    fi
}

# Create backup of a file
backup_file() {
    local node="$1"
    local file="$2"
    local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    run_on_node "$node" "cp '$file' '$backup' 2>/dev/null || true"
    log_info "Backed up $file to $backup"
}

# Wait for node to come back online
wait_for_node() {
    local node="$1"
    local timeout="${2:-120}"
    local elapsed=0
    
    log_info "Waiting for $node to come back online..."
    
    while [[ $elapsed -lt $timeout ]]; do
        if check_ssh "$node"; then
            log_success "$node is back online"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    
    echo ""
    log_error "Timeout waiting for $node"
    return 1
}

# Print script header
print_header() {
    local title="$1"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  Proxmox TB4 + Ceph Setup                                    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  $title$(printf '%*s' $((46 - ${#title})) '')${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}
