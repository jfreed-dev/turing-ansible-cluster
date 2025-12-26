#!/bin/bash
# Prepare Armbian image with packages, SSH keys, and configuration
#
# Usage: ./scripts/prepare-armbian-image.sh <image.img> [node_number]
#
# This script mounts an Armbian image and:
# - Installs required packages (open-iscsi, nfs-common, etc.)
# - Injects SSH keys for passwordless login
# - Configures hostname and static IP (if node specified)
# - Sets up first-boot autoconfig to skip interactive wizard
#
# Reference: https://docs.armbian.com/User-Guide_Autoconfig/

set -e

# Configuration - Override via environment variables
ROOT_PASSWORD="${ROOT_PASSWORD:-Turing@Rk1#2024}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-$HOME/.ssh/workbench.pub}"
TIMEZONE="${TIMEZONE:-America/Chicago}"
LOCALE="${LOCALE:-en_US.UTF-8}"
SKIP_PACKAGES="${SKIP_PACKAGES:-false}"

# Packages to install (required for K3s and Longhorn)
PACKAGES=(
    open-iscsi
    nfs-common
    curl
    wget
    git
    htop
    jq
    rsync
    vim
)

# Node-specific static IPs
declare -A NODE_IPS=(
    [1]="10.10.88.73"
    [2]="10.10.88.74"
    [3]="10.10.88.75"
    [4]="10.10.88.76"
)
NETMASK="24"
GATEWAY="10.10.88.1"
DNS="10.10.88.1"

# Hostnames (using node1-4 to match Ansible inventory)
declare -A NODE_HOSTNAMES=(
    [1]="node1"
    [2]="node2"
    [3]="node3"
    [4]="node4"
)

usage() {
    echo "Usage: $0 <armbian-image.img> [node_number]"
    echo ""
    echo "Arguments:"
    echo "  armbian-image.img   Path to Armbian image file"
    echo "  node_number         Optional: 1-4 for static IP and hostname config"
    echo ""
    echo "Environment variables:"
    echo "  ROOT_PASSWORD       Root password (default: Turing@Rk1#2024)"
    echo "  SSH_PUBKEY_FILE     Path to SSH public key (default: ~/.ssh/workbench.pub)"
    echo "  TIMEZONE            Timezone (default: America/Chicago)"
    echo "  SKIP_PACKAGES       Skip package installation (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0 Armbian.img                    # DHCP, inject SSH key + packages"
    echo "  $0 Armbian.img 1                  # Static IP for node1"
    echo "  SKIP_PACKAGES=true $0 Armbian.img # Skip package installation"
    exit 1
}

# Check arguments
if [[ $# -lt 1 ]]; then
    usage
fi

IMAGE="$1"
NODE_NUM="${2:-}"

if [[ ! -f "$IMAGE" ]]; then
    echo "Error: Image file not found: $IMAGE"
    exit 1
fi

# Check for root/sudo
if [[ $EUID -ne 0 ]]; then
    echo "This script requires root privileges to mount the image."
    echo "Re-running with sudo..."
    exec sudo -E "$0" "$@"
fi

# Create mount point
MOUNT_POINT=$(mktemp -d)
LOOP_DEVICE=""

cleanup() {
    echo "Cleaning up..."
    # Unmount special filesystems if mounted
    umount "$MOUNT_POINT/proc" 2>/dev/null || true
    umount "$MOUNT_POINT/sys" 2>/dev/null || true
    umount "$MOUNT_POINT/dev/pts" 2>/dev/null || true
    umount "$MOUNT_POINT/dev" 2>/dev/null || true

    if [[ -n "$MOUNT_POINT" ]] && mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        umount "$MOUNT_POINT" || true
    fi
    if [[ -n "$LOOP_DEVICE" ]]; then
        losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    fi
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Preparing Armbian Image ==="
echo "Image: $IMAGE"
echo "Node: ${NODE_NUM:-generic (DHCP)}"
echo "Packages: ${SKIP_PACKAGES:-install}"
echo ""

# Setup loop device with partition support
echo "Setting up loop device..."
LOOP_DEVICE=$(losetup -fP --show "$IMAGE")
echo "Loop device: $LOOP_DEVICE"

# Wait for partition to appear
sleep 1

# Find the root partition (usually partition 1 for Armbian)
ROOT_PART="${LOOP_DEVICE}p1"
if [[ ! -b "$ROOT_PART" ]]; then
    ROOT_PART="${LOOP_DEVICE}p2"
fi

if [[ ! -b "$ROOT_PART" ]]; then
    echo "Error: Could not find root partition"
    losetup -d "$LOOP_DEVICE"
    exit 1
fi

echo "Root partition: $ROOT_PART"

# Mount the root partition
echo "Mounting root partition..."
mount "$ROOT_PART" "$MOUNT_POINT"

# Verify it's an Armbian image
if [[ ! -f "$MOUNT_POINT/etc/armbian-release" ]]; then
    echo "Warning: This doesn't appear to be an Armbian image (no /etc/armbian-release)"
fi

# Read SSH public key
SSH_KEY=""
if [[ -f "$SSH_PUBKEY_FILE" ]]; then
    SSH_KEY=$(cat "$SSH_PUBKEY_FILE")
    echo "SSH key loaded from: $SSH_PUBKEY_FILE"
else
    echo "Warning: SSH public key not found at $SSH_PUBKEY_FILE"
fi

#
# Install packages via chroot
#
if [[ "$SKIP_PACKAGES" != "true" ]]; then
    echo ""
    echo "=== Installing packages via chroot ==="

    # Check if we need QEMU for cross-architecture chroot
    IMAGE_ARCH=$(file "$MOUNT_POINT/bin/bash" 2>/dev/null | grep -o 'ARM\|aarch64' || echo "unknown")
    HOST_ARCH=$(uname -m)

    if [[ "$IMAGE_ARCH" == "aarch64" || "$IMAGE_ARCH" == "ARM" ]] && [[ "$HOST_ARCH" == "x86_64" ]]; then
        # Check for QEMU user-mode emulation
        if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
            echo "Warning: Cross-architecture chroot requires QEMU user-mode emulation"
            echo "Install with: sudo apt-get install qemu-user-static binfmt-support"
            echo "Skipping package installation..."
            SKIP_PACKAGES="true"
        else
            # Copy QEMU binary into chroot
            QEMU_BIN=$(which qemu-aarch64-static 2>/dev/null || echo "/usr/bin/qemu-aarch64-static")
            if [[ -f "$QEMU_BIN" ]]; then
                cp "$QEMU_BIN" "$MOUNT_POINT/usr/bin/"
                echo "QEMU aarch64 emulation enabled"
            fi
        fi
    fi
fi

if [[ "$SKIP_PACKAGES" != "true" ]]; then
    # Mount special filesystems for chroot
    mount --bind /dev "$MOUNT_POINT/dev"
    mount --bind /dev/pts "$MOUNT_POINT/dev/pts"
    mount --bind /proc "$MOUNT_POINT/proc"
    mount --bind /sys "$MOUNT_POINT/sys"

    # Copy resolv.conf for DNS resolution
    cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf.bak" 2>/dev/null || true
    cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"

    # Install packages
    echo "Updating package lists..."
    chroot "$MOUNT_POINT" apt-get update -qq

    echo "Installing packages: ${PACKAGES[*]}"
    chroot "$MOUNT_POINT" apt-get install -y -qq "${PACKAGES[@]}"

    # Enable iscsid service
    echo "Enabling iSCSI services..."
    chroot "$MOUNT_POINT" systemctl enable iscsid.socket 2>/dev/null || true
    chroot "$MOUNT_POINT" systemctl enable iscsid.service 2>/dev/null || true

    # Clean up apt cache to reduce image size
    echo "Cleaning apt cache..."
    chroot "$MOUNT_POINT" apt-get clean
    chroot "$MOUNT_POINT" rm -rf /var/lib/apt/lists/*

    # Restore resolv.conf
    if [[ -f "$MOUNT_POINT/etc/resolv.conf.bak" ]]; then
        mv "$MOUNT_POINT/etc/resolv.conf.bak" "$MOUNT_POINT/etc/resolv.conf"
    fi

    # Unmount special filesystems
    umount "$MOUNT_POINT/proc"
    umount "$MOUNT_POINT/sys"
    umount "$MOUNT_POINT/dev/pts"
    umount "$MOUNT_POINT/dev"

    echo "Packages installed successfully"
fi

#
# Configure SSH
#
echo ""
echo "=== Configuring SSH ==="

mkdir -p "$MOUNT_POINT/root/.ssh"
chmod 700 "$MOUNT_POINT/root/.ssh"

if [[ -n "$SSH_KEY" ]]; then
    echo "$SSH_KEY" > "$MOUNT_POINT/root/.ssh/authorized_keys"
    chmod 600 "$MOUNT_POINT/root/.ssh/authorized_keys"
    echo "SSH key installed to /root/.ssh/authorized_keys"
fi

#
# Configure hostname and network
#
if [[ -n "$NODE_NUM" ]] && [[ -n "${NODE_HOSTNAMES[$NODE_NUM]}" ]]; then
    HOSTNAME="${NODE_HOSTNAMES[$NODE_NUM]}"
    STATIC_IP="${NODE_IPS[$NODE_NUM]}"

    echo ""
    echo "=== Configuring node $NODE_NUM ==="

    # Set hostname
    echo "$HOSTNAME" > "$MOUNT_POINT/etc/hostname"
    echo "Hostname set to: $HOSTNAME"

    # Configure static IP via netplan
    mkdir -p "$MOUNT_POINT/etc/netplan"
    cat > "$MOUNT_POINT/etc/netplan/10-static.yaml" << EOF
network:
  version: 2
  ethernets:
    end0:
      dhcp4: no
      addresses:
        - ${STATIC_IP}/${NETMASK}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses:
          - ${DNS}
          - 8.8.8.8
EOF
    chmod 600 "$MOUNT_POINT/etc/netplan/10-static.yaml"
    echo "Static IP configured: $STATIC_IP"
fi

#
# Configure /etc/hosts
#
echo ""
echo "=== Configuring /etc/hosts ==="

cat > "$MOUNT_POINT/etc/hosts" << 'EOF'
127.0.0.1   localhost
::1         localhost ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters

# Turing Pi RK1 Cluster
10.10.88.70  turing-bmc bmc
10.10.88.73  node1
10.10.88.74  node2
10.10.88.75  node3
10.10.88.76  node4
EOF

#
# Create Armbian autoconfig for first boot
#
echo ""
echo "=== Creating first-boot autoconfig ==="

cat > "$MOUNT_POINT/root/.not_logged_in_yet" << EOF
# Armbian first-boot autoconfig
# Generated by prepare-armbian-image.sh
# Reference: https://docs.armbian.com/User-Guide_Autoconfig/

# Skip interactive prompts
PRESET_ROOT_PASSWORD="${ROOT_PASSWORD}"
PRESET_USER_SHELL="bash"

# Skip user creation (we'll use root)
# Leave PRESET_USER_NAME empty to skip

# Locale and timezone
PRESET_LOCALE="${LOCALE}"
PRESET_TIMEZONE="${TIMEZONE}"
SET_LANG_BASED_ON_LOCATION="0"
EOF

# Add static network config to autoconfig if node specified
if [[ -n "$NODE_NUM" ]] && [[ -n "${NODE_IPS[$NODE_NUM]}" ]]; then
    cat >> "$MOUNT_POINT/root/.not_logged_in_yet" << EOF

# Static network configuration for node $NODE_NUM
PRESET_NET_CHANGE_DEFAULTS="1"
PRESET_NET_USE_STATIC="1"
PRESET_NET_STATIC_IP="${NODE_IPS[$NODE_NUM]}"
PRESET_NET_STATIC_MASK="255.255.255.0"
PRESET_NET_STATIC_GATEWAY="${GATEWAY}"
PRESET_NET_STATIC_DNS="${DNS}"
EOF
fi

chmod 644 "$MOUNT_POINT/root/.not_logged_in_yet"

#
# Sync and finish
#
echo ""
echo "Syncing filesystem..."
sync

# Show summary
echo ""
echo "==========================================="
echo "  Image prepared successfully!"
echo "==========================================="
echo ""
echo "Configuration:"
echo "  - Root password: ${ROOT_PASSWORD}"
echo "  - SSH key: ${SSH_PUBKEY_FILE:-none}"
echo "  - Timezone: ${TIMEZONE}"
if [[ -n "$NODE_NUM" ]]; then
    echo "  - Hostname: ${NODE_HOSTNAMES[$NODE_NUM]}"
    echo "  - Static IP: ${NODE_IPS[$NODE_NUM]}"
else
    echo "  - Hostname: (default)"
    echo "  - Network: DHCP"
fi
if [[ "$SKIP_PACKAGES" != "true" ]]; then
    echo "  - Packages: ${PACKAGES[*]}"
fi
echo ""
echo "Flash with:"
echo "  tpi flash --node ${NODE_NUM:-1} --image-path $IMAGE"
echo ""
echo "After boot, SSH with:"
if [[ -n "$NODE_NUM" ]]; then
    echo "  ssh root@${NODE_IPS[$NODE_NUM]}"
else
    echo "  ssh root@<dhcp-ip>"
fi
echo ""
