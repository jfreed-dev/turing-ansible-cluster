# Building Armbian for Turing RK1

This guide covers building a custom Armbian image for Turing RK1 compute modules using the official [Armbian build framework](https://github.com/armbian/build).

## Why Build Your Own Image?

- **NPU Support**: The vendor kernel (6.1.x) includes the rknpu driver required for NPU inference
- **Customization**: Pre-configure users, SSH keys, network settings, and packages
- **Reproducibility**: Consistent builds for all cluster nodes
- **Latest Updates**: Get newer packages than pre-built images

## Latest Pre-built Image

Pre-built images are automatically generated when new Armbian versions are released.

| Property | Value |
|----------|-------|
| Version | 26.02.0-trunk |
| Kernel | 6.1.115 (vendor branch, NPU support) |
| Release | Bookworm (Debian 12) |
| Size | ~491 MB (compressed) |

### Quick Download

```bash
# Using the download script
./scripts/download-armbian-image.sh --latest

# Or download directly
wget $(jq -r '.latest.download_url' images.json)
```

### Verify & Flash

```bash
# Verify checksum
echo "$(jq -r '.latest.sha256' images.json)  $(jq -r '.latest.filename' images.json)" | sha256sum -c

# Decompress
xz -d Armbian-*.img.xz

# Prepare for specific node (installs packages, SSH key, static IP)
./scripts/prepare-armbian-image.sh Armbian-*.img 1

# Flash to node
tpi flash --node 1 --image-path Armbian-*.img
```

See [Image Preparation](#image-preparation) for full details on the prepare script.

See [images.json](../images.json) for full metadata including download URLs and checksums.

> **Note**: The automated build workflow checks daily for new Armbian versions and uploads images to Cloudflare R2 at [armbian-builds.techki.to](https://armbian-builds.techki.to).

## Automated Build Setup (Maintainers)

The GitHub Actions workflow automatically builds and uploads images to Cloudflare R2 when new Armbian versions are released.

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `R2_ACCESS_KEY_ID` | Cloudflare R2 access key ID |
| `R2_SECRET_ACCESS_KEY` | Cloudflare R2 secret access key |
| `R2_ENDPOINT` | R2 S3-compatible endpoint URL |
| `R2_PUBLIC_URL` | Public URL for downloads (e.g., `https://armbian-builds.techki.to`) |
| `PAT_TOKEN` | GitHub Personal Access Token for pushing to protected branch |

### Setup Steps

1. **Create Cloudflare R2 Bucket**:
   - Go to Cloudflare Dashboard → R2 Object Storage
   - Create bucket named `armbian-builds`
   - Enable public access and configure custom domain (optional)

2. **Create R2 API Token**:
   - R2 → Manage R2 API Tokens → Create API Token
   - Permissions: Admin Read & Write
   - Scope: `armbian-builds` bucket
   - Copy Access Key ID and Secret Access Key

3. **Add secrets to GitHub repository**:
   ```bash
   gh secret set R2_ACCESS_KEY_ID
   gh secret set R2_SECRET_ACCESS_KEY
   gh secret set R2_ENDPOINT      # e.g., https://<account-id>.r2.cloudflarestorage.com
   gh secret set R2_PUBLIC_URL    # e.g., https://armbian-builds.techki.to
   gh secret set PAT_TOKEN        # GitHub PAT with repo write access
   ```

4. **Trigger a build**:
   ```bash
   gh workflow run armbian-build.yml -f force_build=true
   ```

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

## Image Preparation

The `prepare-armbian-image.sh` script prepares a generic Armbian image for deployment by:

- **Installing packages** via chroot (open-iscsi, nfs-common, curl, etc.)
- **Injecting SSH keys** directly into the image
- **Configuring hostname and static IP** for specific nodes
- **Setting up first-boot autoconfig** to skip interactive wizard

### Prerequisites (x86_64 hosts only)

When running on x86_64 to prepare aarch64 images, QEMU user-mode emulation is required:

```bash
sudo apt-get install qemu-user-static binfmt-support
```

The script auto-detects cross-architecture and skips package installation if QEMU is unavailable.

### Basic Usage

```bash
# Prepare image for node 3 (installs packages, sets hostname, static IP)
./scripts/prepare-armbian-image.sh Armbian-*.img 3

# Prepare generic image (DHCP, no hostname set)
./scripts/prepare-armbian-image.sh Armbian-*.img
```

### Node Configuration

When a node number (1-4) is specified, the script configures:

| Node | Hostname | Static IP |
|------|----------|-----------|
| 1 | node1 | 10.10.88.73 |
| 2 | node2 | 10.10.88.74 |
| 3 | node3 | 10.10.88.75 |
| 4 | node4 | 10.10.88.76 |

### Packages Installed

The following packages are installed for K3s and Longhorn compatibility:

```
open-iscsi nfs-common curl wget git htop jq rsync vim
```

iSCSI services (`iscsid.socket`, `iscsid.service`) are enabled automatically.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ROOT_PASSWORD` | `Turing@Rk1#2024` | Root password for first boot |
| `SSH_PUBKEY_FILE` | `~/.ssh/workbench.pub` | SSH public key to inject |
| `TIMEZONE` | `America/Chicago` | System timezone |
| `SKIP_PACKAGES` | `false` | Set to `true` to skip package installation |

### Examples

```bash
# Custom SSH key
SSH_PUBKEY_FILE=~/.ssh/id_ed25519.pub ./scripts/prepare-armbian-image.sh Armbian.img 1

# Custom root password
ROOT_PASSWORD="MySecurePass123" ./scripts/prepare-armbian-image.sh Armbian.img 2

# Skip package installation (faster, SSH/network config only)
SKIP_PACKAGES=true ./scripts/prepare-armbian-image.sh Armbian.img 3

# Different timezone
TIMEZONE="UTC" ./scripts/prepare-armbian-image.sh Armbian.img 4
```

### Prepare All Nodes

```bash
# Decompress image once
xz -dk Armbian-unofficial_26.02.0-trunk_Turing-rk1_bookworm_vendor_6.1.115.img.xz

# Create copies for each node
for n in 1 2 3 4; do
  cp Armbian-unofficial_26.02.0-trunk_Turing-rk1_bookworm_vendor_6.1.115.img node${n}.img
  ./scripts/prepare-armbian-image.sh node${n}.img $n
done

# Flash all nodes
for n in 1 2 3 4; do
  tpi flash --node $n --image-path node${n}.img
done
```

### What Gets Configured

After running the script, the image contains:

| File | Contents |
|------|----------|
| `/root/.ssh/authorized_keys` | Your SSH public key |
| `/etc/hostname` | Node hostname (e.g., `node1`) |
| `/etc/hosts` | Cluster node entries |
| `/etc/netplan/10-static.yaml` | Static IP configuration |
| `/root/.not_logged_in_yet` | Armbian first-boot autoconfig |

### After Boot

Nodes are immediately accessible via SSH:

```bash
# SSH to node (no password prompt)
ssh root@10.10.88.73

# Verify packages installed
dpkg -l | grep -E 'open-iscsi|nfs-common'

# Verify iSCSI ready for Longhorn
systemctl status iscsid
```

## Image Distribution

Pre-built Armbian images are hosted on Cloudflare R2 at [armbian-builds.techki.to](https://armbian-builds.techki.to).

### Download Latest Image

```bash
# Using the download script (recommended)
./scripts/download-armbian-image.sh --latest

# Or download directly
wget https://armbian-builds.techki.to/turing-rk1/26.02.0-trunk/Armbian-unofficial_26.02.0-trunk_Turing-rk1_bookworm_vendor_6.1.115.img.xz

# Download and auto-decompress
DECOMPRESS=true ./scripts/download-armbian-image.sh --latest

# Save to specific directory
DOWNLOAD_DIR=/tmp ./scripts/download-armbian-image.sh --latest
```

**Features:**
- Automatic SHA256 checksum verification
- Optional auto-decompression
- Shows next steps for prepare + flash

### Complete Workflow

```bash
# 1. Download latest pre-built image
./scripts/download-armbian-image.sh --latest

# 2. Decompress
xz -d Armbian-*.img.xz

# 3. Prepare image for specific node
#    - Installs packages (open-iscsi, nfs-common, etc.)
#    - Injects SSH key
#    - Configures hostname and static IP
./scripts/prepare-armbian-image.sh Armbian-*.img 1

# 4. Flash to node
tpi flash --node 1 --image-path Armbian-*.img

# 5. SSH immediately (no password, packages ready)
ssh root@10.10.88.73

# 6. Run Ansible to complete setup
ansible-playbook -i inventories/server/hosts.yml playbooks/site.yml --limit node1
```

## Next Steps

After building your images:

1. Flash using Terraform or `tpi` CLI (see [INSTALL.md](../INSTALL.md#flashing-nodes))
2. Run Ansible playbooks to deploy K3s (see [README.md](../README.md#quick-start))
