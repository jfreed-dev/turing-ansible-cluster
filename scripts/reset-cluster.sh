#!/bin/bash
#
# Reset Turing Pi RK1 Cluster
# Wipes all data from NVMe drives and clears node state for clean reinstall
#
# Usage:
#   ./reset-cluster.sh              # Reset all nodes
#   ./reset-cluster.sh --nodes 1,2  # Reset specific nodes
#   ./reset-cluster.sh --flash      # Also reflash firmware via BMC
#   ./reset-cluster.sh --dry-run    # Show what would be done
#
# WARNING: This script is DESTRUCTIVE. All data will be lost!

set -euo pipefail

# Configuration
SSH_KEY="${SSH_KEY:-$HOME/.ssh/workbench}"
SSH_USER="${SSH_USER:-root}"
BMC_HOST="${BMC_HOST:-10.10.88.70}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Node definitions
declare -A NODE_IPS=(
    [1]="10.10.88.73"
    [2]="10.10.88.74"
    [3]="10.10.88.75"
    [4]="10.10.88.76"
)

declare -A NODE_NAMES=(
    [1]="node1"
    [2]="node2"
    [3]="node3"
    [4]="node4"
)

# Default options
NODES_TO_RESET="1,2,3,4"
DRY_RUN=false
DO_FLASH=false
SKIP_CONFIRM=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Reset Turing Pi RK1 cluster nodes for clean reinstall.

OPTIONS:
    --nodes NODES    Comma-separated list of nodes to reset (1-4)
                     Default: 1,2,3,4 (all nodes)
    --flash          Also reflash firmware via BMC after wipe
    --dry-run        Show what would be done without executing
    --yes            Skip confirmation prompt
    -h, --help       Show this help message

ENVIRONMENT VARIABLES:
    SSH_KEY          Path to SSH private key (default: ~/.ssh/workbench)
    SSH_USER         SSH user (default: root)
    BMC_HOST         Turing Pi BMC IP (default: 10.10.88.70)

EXAMPLES:
    $(basename "$0")                    # Reset all nodes
    $(basename "$0") --nodes 3,4        # Reset only nodes 3 and 4
    $(basename "$0") --flash --yes      # Reset all, reflash, no prompt
    $(basename "$0") --dry-run          # Preview actions

WARNING: This script is DESTRUCTIVE and will:
    - Stop and uninstall K3s
    - Wipe all data on NVMe drives
    - Clear Longhorn storage
    - Remove all cluster configuration
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --nodes)
                NODES_TO_RESET="$2"
                shift 2
                ;;
            --flash)
                DO_FLASH=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --yes|-y)
                SKIP_CONFIRM=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

check_dependencies() {
    local missing=()

    command -v ssh >/dev/null 2>&1 || missing+=("ssh")
    command -v tpi >/dev/null 2>&1 || missing+=("tpi (Turing Pi CLI)")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        exit 1
    fi

    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "SSH key not found: $SSH_KEY"
        exit 1
    fi
}

confirm_reset() {
    if [[ "$SKIP_CONFIRM" == "true" ]]; then
        return 0
    fi

    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                    !!! WARNING !!!                           ║${NC}"
    echo -e "${RED}║                                                              ║${NC}"
    echo -e "${RED}║  This will PERMANENTLY DELETE all data on the following:    ║${NC}"
    echo -e "${RED}║                                                              ║${NC}"
    for node_num in ${NODES_TO_RESET//,/ }; do
        printf "${RED}║    - %-54s  ║${NC}\n" "${NODE_NAMES[$node_num]} (${NODE_IPS[$node_num]})"
    done
    echo -e "${RED}║                                                              ║${NC}"
    echo -e "${RED}║  Data that will be destroyed:                                ║${NC}"
    echo -e "${RED}║    - K3s cluster state and configuration                     ║${NC}"
    echo -e "${RED}║    - All Longhorn volumes and replicas                       ║${NC}"
    echo -e "${RED}║    - NVMe partition data                                     ║${NC}"
    echo -e "${RED}║    - Node identity and certificates                          ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    read -p "Type 'RESET' to confirm destruction: " confirm
    if [[ "$confirm" != "RESET" ]]; then
        log_info "Aborted."
        exit 0
    fi
}

ssh_cmd() {
    local node_ip="$1"
    shift
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        "${SSH_USER}@${node_ip}" "$@"
}

reset_node() {
    local node_num="$1"
    local node_ip="${NODE_IPS[$node_num]}"
    local node_name="${NODE_NAMES[$node_num]}"

    log_info "Resetting $node_name ($node_ip)..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would reset $node_name"
        return 0
    fi

    # Check if node is reachable
    if ! ssh_cmd "$node_ip" "echo ok" >/dev/null 2>&1; then
        log_warn "Node $node_name is not reachable, skipping..."
        return 1
    fi

    # Execute reset commands on node
    ssh_cmd "$node_ip" bash -s <<'REMOTE_SCRIPT'
set -euo pipefail

echo "=== Stopping services ==="

# Stop K3s agent or server
systemctl stop k3s-agent 2>/dev/null || true
systemctl stop k3s 2>/dev/null || true

# Stop rkllama if running
systemctl stop rkllama 2>/dev/null || true

# Kill any remaining k3s processes
pkill -9 -f k3s || true
pkill -9 -f containerd || true

echo "=== Uninstalling K3s ==="

# Uninstall K3s (agent or server)
if [[ -f /usr/local/bin/k3s-agent-uninstall.sh ]]; then
    /usr/local/bin/k3s-agent-uninstall.sh || true
elif [[ -f /usr/local/bin/k3s-uninstall.sh ]]; then
    /usr/local/bin/k3s-uninstall.sh || true
fi

echo "=== Cleaning K3s data ==="

# Remove K3s data directories
rm -rf /etc/rancher/k3s
rm -rf /etc/rancher/node
rm -rf /var/lib/rancher/k3s
rm -rf /var/lib/kubelet
rm -rf /var/lib/cni
rm -rf /etc/cni

# Remove K3s binaries if still present
rm -f /usr/local/bin/k3s
rm -f /usr/local/bin/kubectl
rm -f /usr/local/bin/crictl
rm -f /usr/local/bin/ctr

echo "=== Cleaning Longhorn data ==="

# Unmount any Longhorn volumes
umount /var/lib/longhorn/* 2>/dev/null || true

# Wipe Longhorn directory
rm -rf /var/lib/longhorn/*

echo "=== Cleaning NVMe partitions ==="

# Find NVMe device
if [[ -b /dev/nvme0n1 ]]; then
    # Check for Longhorn partition (usually nvme0n1p2)
    if [[ -b /dev/nvme0n1p2 ]]; then
        echo "Wiping Longhorn partition /dev/nvme0n1p2..."
        umount /dev/nvme0n1p2 2>/dev/null || true
        wipefs -a /dev/nvme0n1p2 || true
        mkfs.xfs -f /dev/nvme0n1p2 || true
    fi

    # If booting from eMMC and NVMe is data-only, wipe entire NVMe
    if [[ -b /dev/mmcblk0 ]] && grep -q "mmcblk0" /proc/cmdline 2>/dev/null; then
        echo "System boots from eMMC, wiping entire NVMe..."
        umount /dev/nvme0n1* 2>/dev/null || true
        wipefs -a /dev/nvme0n1 || true
    fi
fi

echo "=== Cleaning rkllama/NPU data ==="

rm -rf /opt/rkllama
rm -rf ~/RKLLAMA
rm -f /etc/systemd/system/rkllama.service

echo "=== Cleaning container data ==="

rm -rf /var/lib/containerd
rm -rf /run/containerd
rm -rf /var/lib/docker 2>/dev/null || true

echo "=== Cleaning network configuration ==="

# Remove CNI configs
rm -rf /etc/cni/net.d/*
rm -rf /var/lib/cni/*

# Flush iptables rules added by K3s
iptables -F 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
ip6tables -F 2>/dev/null || true
ip6tables -t nat -F 2>/dev/null || true

echo "=== Reloading systemd ==="

systemctl daemon-reload

echo "=== Node reset complete ==="
REMOTE_SCRIPT

    log_info "Node $node_name reset complete"
}

power_cycle_node() {
    local node_num="$1"
    local node_name="${NODE_NAMES[$node_num]}"

    log_info "Power cycling $node_name via BMC..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would power cycle $node_name"
        return 0
    fi

    # Power off
    tpi power off -n "$node_num" || true
    sleep 2

    # Power on
    tpi power on -n "$node_num" || true

    log_info "Power cycle initiated for $node_name"
}

flash_node() {
    local node_num="$1"
    local node_name="${NODE_NAMES[$node_num]}"

    log_warn "Flashing must be done via Terraform or manually"
    log_info "Run: cd $REPO_ROOT/terraform/environments/server && terraform apply -var='flash_nodes=true'"
}

main() {
    parse_args "$@"

    echo ""
    log_info "Turing Pi RK1 Cluster Reset"
    log_info "============================"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY-RUN MODE - No changes will be made"
        echo ""
    fi

    check_dependencies

    # Convert comma-separated to array
    IFS=',' read -ra nodes_array <<< "$NODES_TO_RESET"

    # Validate node numbers
    for node_num in "${nodes_array[@]}"; do
        if [[ ! "${NODE_IPS[$node_num]+isset}" ]]; then
            log_error "Invalid node number: $node_num (valid: 1-4)"
            exit 1
        fi
    done

    log_info "Nodes to reset: ${nodes_array[*]}"

    confirm_reset

    echo ""
    log_info "Starting reset process..."
    echo ""

    # Reset each node
    local failed_nodes=()
    for node_num in "${nodes_array[@]}"; do
        if ! reset_node "$node_num"; then
            failed_nodes+=("$node_num")
        fi
        echo ""
    done

    # Power cycle nodes
    log_info "Power cycling nodes..."
    for node_num in "${nodes_array[@]}"; do
        power_cycle_node "$node_num"
    done

    # Flash if requested
    if [[ "$DO_FLASH" == "true" ]]; then
        echo ""
        log_info "Flashing requested - use Terraform:"
        echo ""
        echo "  cd $REPO_ROOT/terraform/environments/server"
        echo "  terraform apply -var='flash_nodes=true' -var='firmware_path=/path/to/image.img'"
        echo ""
    fi

    echo ""
    log_info "Reset complete!"
    echo ""

    if [[ ${#failed_nodes[@]} -gt 0 ]]; then
        log_warn "Some nodes were not reachable: ${failed_nodes[*]}"
    fi

    echo "Next steps:"
    echo "  1. Wait for nodes to boot (1-2 minutes)"
    echo "  2. Verify SSH access: ssh -i $SSH_KEY root@10.10.88.73"
    echo "  3. Run Ansible: cd $REPO_ROOT/ansible && ansible-playbook -i inventories/server/hosts.yml playbooks/site.yml"
    echo ""
}

main "$@"
