# Building Armbian for Turing RK1

This guide covers building a custom Armbian image for Turing RK1 compute modules using the official [Armbian build framework](https://github.com/armbian/build).

## Why Build Your Own Image?

- **NPU Support**: The vendor kernel (6.1.x) includes the rknpu driver required for NPU inference
- **Customization**: Pre-configure users, SSH keys, network settings, and packages
- **Reproducibility**: Consistent builds for all cluster nodes
- **Latest Updates**: Get newer packages than pre-built images

## Prerequisites

### System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Ubuntu 22.04+ / Debian 12+ | Ubuntu 24.04 |
| RAM | 4 GB | 8+ GB |
| Disk | 30 GB free | 50+ GB SSD |
| Docker | Required | Latest version |

### Install Dependencies

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y git curl docker.io

# Add user to docker group (logout/login required)
sudo usermod -aG docker $USER
```

## Quick Start

### Clone the Build Framework

```bash
git clone --depth=1 https://github.com/armbian/build ~/armbian-build
cd ~/armbian-build
```

### Build with Default Settings

```bash
./compile.sh build \
  BOARD=turing-rk1 \
  BRANCH=vendor \
  RELEASE=bookworm \
  BUILD_MINIMAL=no \
  BUILD_DESKTOP=no \
  KERNEL_CONFIGURE=no
```

### Output Location

```
~/armbian-build/output/images/Armbian-unofficial_<version>_Turing-rk1_bookworm_vendor_<kernel>.img
```

## Build Parameters

### Required Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `BOARD` | `turing-rk1` | Target board definition |
| `BRANCH` | `vendor` | Kernel branch (vendor = Rockchip BSP with NPU) |
| `RELEASE` | `bookworm` | Debian 12 (recommended) |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `BUILD_MINIMAL` | `no` | `yes` = minimal image, `no` = full packages |
| `BUILD_DESKTOP` | `no` | `yes` = include desktop, `no` = server only |
| `KERNEL_CONFIGURE` | `no` | `yes` = interactive kernel config |
| `COMPRESS_OUTPUTIMAGE` | `sha,img` | Compression options |
| `EXPERT` | `no` | Show advanced options |

### Kernel Branches

| Branch | Kernel | NPU Support | Use Case |
|--------|--------|-------------|----------|
| `vendor` | 6.1.x | Yes | **Production with NPU** |
| `current` | 6.6.x | Limited | Mainline features |
| `edge` | 6.x | No | Testing only |

## Customization

### Pre-configure Root Password and SSH Keys

Create a customization script that runs during build:

```bash
# Create userpatches directory
mkdir -p ~/armbian-build/userpatches

# Create customization script
cat > ~/armbian-build/userpatches/customize-image.sh << 'EOF'
#!/bin/bash

# Set root password (change this!)
echo "root:YourSecurePassword" | chpasswd

# Add SSH public key
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat > /root/.ssh/authorized_keys << 'KEYS'
ssh-ed25519 AAAA... your-key-here
KEYS
chmod 600 /root/.ssh/authorized_keys

# Install additional packages
apt-get update
apt-get install -y \
  htop \
  vim \
  curl \
  wget \
  git \
  jq \
  python3-pip

# Enable SSH
systemctl enable ssh
EOF

chmod +x ~/armbian-build/userpatches/customize-image.sh
```

### Pre-configure Static IP (Per Node)

For cluster deployments, build separate images with static IPs:

```bash
# Build image for node 1 (control plane)
cat > ~/armbian-build/userpatches/customize-image.sh << 'EOF'
#!/bin/bash

# Set hostname
echo "node1" > /etc/hostname

# Configure static IP
cat > /etc/netplan/10-static.yaml << 'NETPLAN'
network:
  version: 2
  ethernets:
    end0:
      dhcp4: no
      addresses:
        - 10.10.88.73/24
      routes:
        - to: default
          via: 10.10.88.1
      nameservers:
        addresses:
          - 10.10.88.1
          - 8.8.8.8
NETPLAN
EOF

chmod +x ~/armbian-build/userpatches/customize-image.sh

# Build
./compile.sh build BOARD=turing-rk1 BRANCH=vendor RELEASE=bookworm

# Rename output
mv output/images/Armbian-*.img output/images/armbian-node1.img
```

Repeat for nodes 2-4 with appropriate IPs (10.10.88.74-76).

### Add Custom Packages

```bash
# Create package list
cat > ~/armbian-build/userpatches/lib.config << 'EOF'
PACKAGE_LIST_ADDITIONAL="htop vim curl wget git jq nfs-common cryptsetup"
EOF
```

## Automated Multi-Node Build

Build all 4 node images with a script:

```bash
#!/bin/bash
# build-cluster-images.sh

NODES=(
  "node1:10.10.88.73"
  "node2:10.10.88.74"
  "node3:10.10.88.75"
  "node4:10.10.88.76"
)

GATEWAY="10.10.88.1"
SSH_PUBKEY="ssh-ed25519 AAAA... your-key"

cd ~/armbian-build

for node_config in "${NODES[@]}"; do
  HOSTNAME="${node_config%%:*}"
  IP="${node_config##*:}"

  echo "Building image for $HOSTNAME ($IP)..."

  cat > userpatches/customize-image.sh << EOF
#!/bin/bash
echo "$HOSTNAME" > /etc/hostname

cat > /etc/netplan/10-static.yaml << 'NETPLAN'
network:
  version: 2
  ethernets:
    end0:
      dhcp4: no
      addresses:
        - $IP/24
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
          - $GATEWAY
          - 8.8.8.8
NETPLAN

mkdir -p /root/.ssh
echo "$SSH_PUBKEY" > /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
EOF

  chmod +x userpatches/customize-image.sh

  ./compile.sh build \
    BOARD=turing-rk1 \
    BRANCH=vendor \
    RELEASE=bookworm \
    BUILD_MINIMAL=no \
    BUILD_DESKTOP=no \
    KERNEL_CONFIGURE=no

  mv output/images/Armbian-*.img "output/images/armbian-${HOSTNAME}.img"
done

echo "Build complete! Images in ~/armbian-build/output/images/"
```

## Troubleshooting

### Build Fails with Docker Errors

```bash
# Ensure Docker is running
sudo systemctl start docker

# Verify Docker access
docker run --rm hello-world

# Clean Docker cache if needed
docker system prune -a
```

### Out of Disk Space

```bash
# Clean previous builds
cd ~/armbian-build
./compile.sh clean

# Remove old images
rm -rf output/images/*
```

### Kernel Configuration Issues

```bash
# Force rebuild of kernel
./compile.sh build \
  BOARD=turing-rk1 \
  BRANCH=vendor \
  RELEASE=bookworm \
  CLEAN_LEVEL=images,debs
```

### Verify NPU Support After Flash

```bash
# Check driver version
cat /sys/kernel/debug/rknpu/version
# Expected: RKNPU driver: v0.9.8

# Check NPU device
ls -la /dev/dri/renderD129

# Check driver loaded
dmesg | grep -i rknpu
```

## Alternative: Download Pre-built Images

If you don't need customization, download official images:

- **Armbian**: https://www.armbian.com/turing-rk1/
- **Turing Pi Ubuntu**: https://firmware.turingpi.com/turing-rk1/

> **Note**: Pre-built images may not have the latest vendor kernel with NPU support. Building your own ensures you get the `vendor` branch kernel.

## Next Steps

After building your images:

1. Flash using Terraform or `tpi` CLI (see [INSTALL.md](../INSTALL.md#flashing-nodes))
2. Run Ansible playbooks to deploy K3s (see [README.md](../README.md#quick-start))
