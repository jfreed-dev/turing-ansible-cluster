# Turing RK1 Cluster Installation Guide

Manual installation guide for deploying Armbian + K3s on Turing Pi 2.5 with RK1 compute modules.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Hardware Overview](#hardware-overview)
3. [BMC Access](#bmc-access)
4. [Firmware Options](#firmware-options)
5. [Building Armbian](#building-armbian)
6. [Flashing Nodes](#flashing-nodes)
7. [Automated First Boot (Recommended)](#automated-first-boot-recommended)
8. [Manual First Boot Setup](#manual-first-boot-setup)
9. [SSH Configuration](#ssh-configuration)
10. [NPU Verification](#npu-verification)
11. [K3s Cluster Deployment](#k3s-cluster-deployment)
12. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Workstation Requirements

- Linux workstation (Ubuntu 22.04+ recommended)
- `tpi` CLI tool installed ([Turing Pi CLI](https://github.com/turing-machines/tpi))
- SSH client with key pair
- For Armbian builds: Docker, 8GB RAM, 50GB disk

### Install tpi CLI

```bash
# Download latest release
curl -L https://github.com/turing-machines/tpi/releases/latest/download/tpi-linux-amd64 -o tpi
chmod +x tpi
sudo mv tpi /usr/local/bin/
```

### Network Requirements

| Component | IP Address |
|-----------|------------|
| BMC | 10.10.88.70 |
| Node 1 (Control Plane) | 10.10.88.73 |
| Node 2 (Worker) | 10.10.88.74 |
| Node 3 (Worker) | 10.10.88.75 |
| Node 4 (Worker) | 10.10.88.76 |
| MetalLB Range | 10.10.88.80-89 |

---

## Hardware Overview

### Turing Pi 2.5 with RK1 Modules

| Slot | Hostname | Role | Storage |
|------|----------|------|---------|
| 1 | node1 | Control Plane | NVMe (boot + data) |
| 2 | node2 | Worker | NVMe (boot + data) |
| 3 | node3 | Worker | NVMe (boot + data) |
| 4 | node4 | Worker | NVMe (boot + data) |

### RK3588 Features

- 8-core ARM (4x Cortex-A76 + 4x Cortex-A55)
- 6 TOPS NPU (3 cores)
- 16GB/32GB RAM options
- Mali-G610 GPU

---

## BMC Access

### Environment Variables

Set these for all `tpi` commands:

```bash
export TPI_HOSTNAME=10.10.88.70
export TPI_USERNAME=root
export TPI_PASSWORD="your_bmc_password"
```

### Verify BMC Connection

```bash
# Check BMC info
tpi info

# Check node power status
tpi power status

# Expected output:
# node1: On
# node2: On
# node3: On
# node4: On
```

### BMC via SSH

```bash
# SSH to BMC (alternative method)
ssh root@10.10.88.70

# Run tpi commands locally on BMC
tpi power status
tpi uart --node 1 get
```

### Useful BMC Commands

```bash
# Power control
tpi power on --node 1
tpi power off --node 1
tpi power reset --node 1

# View UART console output (boot logs)
tpi uart --node 1 get

# Flash firmware
tpi flash --node 1 --image-path /path/to/image.img
```

---

## Firmware Options

### Option 1: Turing Pi Ubuntu (Pre-built)

Download from: https://firmware.turingpi.com/turing-rk1/ubuntu_22.04_rockchip_linux/v1.33/

```bash
# Download Ubuntu 22.04 Server
wget https://firmware.turingpi.com/turing-rk1/ubuntu_22.04_rockchip_linux/v1.33/ubuntu-22.04.3-preinstalled-server-arm64-turing-rk1_v1.33.img.xz

# Extract (optional - tpi can flash .xz directly)
xz -dk ubuntu-22.04.3-preinstalled-server-arm64-turing-rk1_v1.33.img.xz
```

**Default credentials:** `ubuntu` / `ubuntu` (password change required on first login)

### Option 2: Armbian (Recommended for NPU)

Build from source for latest vendor kernel with NPU support.

---

## Building Armbian

### Clone Build System

```bash
git clone --depth=1 https://github.com/armbian/build ~/armbian-build
cd ~/armbian-build
```

### Build Command

```bash
./compile.sh build \
  BOARD=turing-rk1 \
  BRANCH=vendor \
  RELEASE=bookworm \
  BUILD_MINIMAL=no \
  BUILD_DESKTOP=no \
  KERNEL_CONFIGURE=no
```

### Build Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `BOARD` | `turing-rk1` | Target board |
| `BRANCH` | `vendor` | Rockchip BSP kernel (NPU support) |
| `RELEASE` | `bookworm` | Debian 12 |
| `BUILD_DESKTOP` | `no` | Server only |
| `BUILD_MINIMAL` | `no` | Full package set |

### Build Output

```
~/armbian-build/output/images/Armbian-unofficial_26.02.0-trunk_Turing-rk1_bookworm_vendor_6.1.115.img
```

Build time: ~5-10 minutes (uses Docker, downloads cached packages)

---

## Flashing Nodes

### Flash Single Node

```bash
# Set BMC credentials
export TPI_HOSTNAME=10.10.88.70
export TPI_USERNAME=root
export TPI_PASSWORD="your_bmc_password"

# Flash node 1
tpi flash --node 1 --image-path ~/Downloads/Armbian-unofficial_26.02.0-trunk_Turing-rk1_bookworm_vendor_6.1.115.img

# Power on after flash
tpi power on --node 1
```

### Flash All Nodes

```bash
for node in 1 2 3 4; do
  echo "Flashing node $node..."
  tpi flash --node $node --image-path /path/to/image.img
  sleep 5
done

# Power on all
tpi power on
```

### Monitor Boot Progress

```bash
# Watch UART output during boot
watch -n 2 'tpi uart --node 1 get | tail -20'

# Wait for login prompt
tpi uart --node 1 get | grep -q "login:" && echo "Boot complete"
```

---

## Automated First Boot (Recommended)

Skip the interactive first-boot wizard by pre-configuring the image.

Reference: [Armbian Autoconfig Documentation](https://docs.armbian.com/User-Guide_Autoconfig/)

### Using the Preparation Script

```bash
# Prepare image for node 1 with static IP
sudo ./scripts/prepare-armbian-image.sh \
  ~/Downloads/Armbian-unofficial_26.02.0-trunk_Turing-rk1_bookworm_vendor_6.1.115.img \
  1

# Or with custom settings
ROOT_PASSWORD="<YOUR_SECURE_PASSWORD>" \
SSH_PUBKEY_FILE=~/.ssh/id_rsa.pub \
sudo ./scripts/prepare-armbian-image.sh image.img 2
```

### Prepare All Nodes

```bash
# Copy image for each node and prepare
for node in 1 2 3 4; do
  cp Armbian-base.img Armbian-node${node}.img
  sudo ./scripts/prepare-armbian-image.sh Armbian-node${node}.img $node
done

# Flash all nodes
for node in 1 2 3 4; do
  tpi flash --node $node --image-path Armbian-node${node}.img
done

# Power on all
tpi power on
```

### What the Script Does

1. Mounts the Armbian image
2. Creates `/root/.not_logged_in_yet` with:
   - `PRESET_ROOT_PASSWORD` - Sets root password
   - `PRESET_USER_SHELL` - Selects bash
   - `PRESET_NET_*` - Static IP configuration (if node specified)
   - `PRESET_LOCALE` / `PRESET_TIMEZONE` - System locale
3. Creates `/root/provisioning.sh` for post-boot setup:
   - Adds SSH authorized keys
   - Sets hostname
   - Configures /etc/hosts with cluster nodes
4. Unmounts the image

### Manual Autoconfig (Without Script)

Mount the image and create `/root/.not_logged_in_yet`:

```bash
# Mount image
sudo losetup -fP --show Armbian.img  # Returns /dev/loopX
sudo mount /dev/loopXp1 /mnt

# Create autoconfig
sudo tee /mnt/root/.not_logged_in_yet << 'EOF'
# Skip interactive wizard
PRESET_ROOT_PASSWORD="YourSecurePassword123!"
PRESET_USER_SHELL="bash"
PRESET_LOCALE="en_US.UTF-8"
PRESET_TIMEZONE="UTC"
SET_LANG_BASED_ON_LOCATION="0"

# Static IP (optional)
PRESET_NET_CHANGE_DEFAULTS="1"
PRESET_NET_USE_STATIC="1"
PRESET_NET_STATIC_IP="10.10.88.73"
PRESET_NET_STATIC_MASK="255.255.255.0"
PRESET_NET_STATIC_GATEWAY="10.10.88.1"
PRESET_NET_STATIC_DNS="10.10.88.1 8.8.8.8"
EOF

# Add SSH key
sudo mkdir -p /mnt/root/.ssh
sudo cp ~/.ssh/your_key.pub /mnt/root/.ssh/authorized_keys
sudo chmod 700 /mnt/root/.ssh
sudo chmod 600 /mnt/root/.ssh/authorized_keys

# Unmount
sudo umount /mnt
sudo losetup -d /dev/loopX
```

### Autoconfig Directives Reference

| Directive | Description | Example |
|-----------|-------------|---------|
| `PRESET_ROOT_PASSWORD` | Root password | `"<YOUR_PASSWORD>"` |
| `PRESET_USER_SHELL` | Default shell | `"bash"` or `"zsh"` |
| `PRESET_USER_NAME` | Create user (empty=skip) | `"admin"` |
| `PRESET_USER_PASSWORD` | User password | `"<YOUR_PASSWORD>"` |
| `PRESET_LOCALE` | System locale | `"en_US.UTF-8"` |
| `PRESET_TIMEZONE` | Timezone | `"America/New_York"` |
| `PRESET_NET_CHANGE_DEFAULTS` | Enable network config | `"1"` |
| `PRESET_NET_USE_STATIC` | Use static IP | `"1"` |
| `PRESET_NET_STATIC_IP` | IP address | `"10.10.88.73"` |
| `PRESET_NET_STATIC_MASK` | Netmask | `"255.255.255.0"` |
| `PRESET_NET_STATIC_GATEWAY` | Gateway | `"10.10.88.1"` |
| `PRESET_NET_STATIC_DNS` | DNS servers | `"8.8.8.8 8.8.4.4"` |

### Provisioning Script

For additional setup, create `/root/provisioning.sh` (runs once after first login):

```bash
#!/bin/bash
# /root/provisioning.sh - Runs once after first boot

# Set hostname
hostnamectl set-hostname node1

# Install packages
apt update && apt install -y htop vim curl

# Any other first-boot tasks
echo "Provisioning complete!"
```

---

## Manual First Boot Setup

If you didn't use autoconfig, complete the wizard manually.

### Armbian First-Run Wizard

Armbian requires interactive setup on first boot:

1. **Root password**: Set a strong password
2. **Shell selection**: Choose bash (1) or zsh (2)
3. **User creation**: Create user or press Ctrl-C to skip
4. **SSH public key**: Add your SSH public key for passwordless access

> **Important:** Set a strong root password in the `prepare-armbian-image.sh` script or via the `ROOT_PASSWORD` environment variable. For Ansible automation, store credentials in `ansible/secrets/server.yml` (see `server.yml.example` for the template).

### Via UART Console

```bash
# Connect to UART from BMC
ssh root@10.10.88.70
picocom -b 115200 /dev/ttyS1  # Node 1

# Complete wizard interactively
# Exit picocom: Ctrl-A, Ctrl-X
```

### Via tpi UART Commands

```bash
# Send password (after seeing "Create root password:" prompt)
tpi uart --node 1 set -c "YourStrongPassword123!"
sleep 1
tpi uart --node 1 set -c "YourStrongPassword123!"

# Select bash shell
tpi uart --node 1 set -c "1"

# Skip user creation (send Ctrl-C via BMC SSH)
ssh root@10.10.88.70 'printf "\x03" > /dev/ttyS1'
```

### Configure SSH Key via armbian-config

After first boot, use `armbian-config` to add your SSH public key for passwordless access:

```bash
# SSH into the node (with password)
ssh root@10.10.88.73

# Launch armbian-config
armbian-config
```

Navigate to: **Personal** → **SSH** → **SSH Key Management**

1. Select **Import from file** or **Paste key**
2. Add your public key (e.g., contents of `~/.ssh/id_ed25519.pub`)
3. Save and exit

Alternatively, add your key manually:

```bash
# On your workstation, copy the key
ssh-copy-id -i ~/.ssh/your_key root@10.10.88.73

# Or manually append
cat ~/.ssh/your_key.pub | ssh root@10.10.88.73 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

### Set Hostname via armbian-config

Set the node hostname during first boot (use node1, node2, node3, node4):

```bash
# Via armbian-config
armbian-config
# Navigate to: Personal → Hostname → Enter new hostname

# Or directly via command line
hostnamectl set-hostname node1  # Adjust for each node
```

| TPI Slot | Hostname | IP Address |
|----------|----------|------------|
| 1 | node1 | 10.10.88.73 |
| 2 | node2 | 10.10.88.74 |
| 3 | node3 | 10.10.88.75 |
| 4 | node4 | 10.10.88.76 |

### Ubuntu First Login

Ubuntu requires password change on first SSH login:

```bash
ssh ubuntu@10.10.88.73
# Current password: ubuntu
# New password: <your password>
# Confirm: <your password>
```

---

## SSH Configuration

### Copy SSH Key

```bash
# For Armbian (after first-run wizard)
ssh-copy-id -i ~/.ssh/your_key root@10.10.88.73

# For Ubuntu
sshpass -p 'newpassword' ssh-copy-id -i ~/.ssh/your_key ubuntu@10.10.88.73
```

### Test Connectivity

```bash
for ip in 10.10.88.{73..76}; do
  echo -n "$ip: "
  ssh -i ~/.ssh/your_key -o ConnectTimeout=5 root@$ip "hostname" 2>&1
done
```

### SSH Config (~/.ssh/config)

```
Host node1
    HostName 10.10.88.73
    User root
    IdentityFile ~/.ssh/your_key

Host node2
    HostName 10.10.88.74
    User root
    IdentityFile ~/.ssh/your_key

Host node3
    HostName 10.10.88.75
    User root
    IdentityFile ~/.ssh/your_key

Host node4
    HostName 10.10.88.76
    User root
    IdentityFile ~/.ssh/your_key

Host turing-bmc
    HostName 10.10.88.70
    User root
    IdentityFile ~/.ssh/your_key
```

---

## NPU Verification

### Important: NPU Device Location

The RK3588 NPU driver (rknpu v0.9.8+) uses the **DRM subsystem** instead of a dedicated device node:

| Old Method | New Method (Current) |
|------------|---------------------|
| `/dev/rknpu` | `/dev/dri/renderD129` |

### Verify NPU Driver

```bash
ssh root@10.10.88.73

# Check driver version
cat /sys/kernel/debug/rknpu/version
# Expected: RKNPU driver: v0.9.8

# Check NPU device
ls -la /dev/dri/renderD129
# Expected: crw-rw---- 1 root render 226, 129 ...

# Check NPU load (3 cores on RK3588)
cat /sys/kernel/debug/rknpu/load
# Expected: NPU load:  Core0:  0%, Core1:  0%, Core2:  0%,
```

### Verify via dmesg

```bash
dmesg | grep -i rknpu

# Expected output:
# RKNPU fdab0000.npu: RKNPU: rknpu iommu is enabled, using iommu mode
# [drm] Initialized rknpu 0.9.8 20240828 for fdab0000.npu on minor 1
```

### RKNN Software Versions

| Component | Latest Version | Repository |
|-----------|---------------|------------|
| RKNN-Toolkit2 | v2.3.2 | [airockchip/rknn-toolkit2](https://github.com/airockchip/rknn-toolkit2) |
| RKNN-LLM | v1.2.1 | [airockchip/rknn-llm](https://github.com/airockchip/rknn-llm) |
| ezrknpu | v1.2.1 | [Pelochus/ezrknpu](https://github.com/Pelochus/ezrknpu) |
| rknpu driver | v0.9.8 | Included in vendor kernel |

### Install via Ansible (Recommended)

```bash
ansible-playbook -i inventories/server/hosts.yml playbooks/npu-setup.yml
```

This installs runtime components only (~800MB vs ~10GB for full toolkit):
- `/opt/rknn-llm` - LLM runtime with librknnrt.so
- `/opt/rkllama` - Flask-based LLM server
- `/usr/lib/librknnrt.so` - RKNN runtime library

> **Note**: Dev tools (rknn-toolkit2, ezrknpu) are not installed to save disk space.
> For model conversion, use a separate development machine.

### Download Pre-converted LLM Models

Pre-converted `.rkllm` models are available on HuggingFace:

```bash
# Install huggingface CLI
pip3 install huggingface_hub

# Download DeepSeek-R1-1.5B (compatible with runtime v1.1.4)
huggingface-cli download VRxiaojie/DeepSeek-R1-Distill-Qwen-1.5B-RK3588S-RKLLM1.1.4 \
  --local-dir /tmp/deepseek-1.5b

# For runtime v1.2.x models, search HuggingFace:
# https://huggingface.co/models?search=rkllm
```

### Run LLM Server

```bash
cd /opt/rkllama

# Start server
python3 server.py --target_platform rk3588 --port 8080

# Check NPU status
cat /sys/kernel/debug/rknpu/version  # Driver version
cat /sys/kernel/debug/rknpu/load     # Core utilization
```

---

## K3s Cluster Deployment

### Using Ansible (Recommended)

```bash
cd ~/Code/turing-ansible-cluster/ansible

# Setup secrets
./scripts/setup-secrets.sh
# Edit secrets/server.yml with your passwords

# Deploy full cluster
ansible-playbook -i inventories/server/hosts.yml playbooks/site.yml
```

### Manual K3s Installation

#### Control Plane (Node 1)

```bash
ssh root@10.10.88.73

# Install K3s server
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.31.3+k3s1" sh -s - server \
  --cluster-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --disable=traefik \
  --disable=servicelb \
  --write-kubeconfig-mode=644

# Get join token
cat /var/lib/rancher/k3s/server/node-token
```

#### Workers (Nodes 2-4)

```bash
ssh root@10.10.88.74  # Repeat for .75, .76

# Install K3s agent
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.31.3+k3s1" \
  K3S_URL="https://10.10.88.73:6443" \
  K3S_TOKEN="<token from control plane>" \
  sh -s - agent
```

#### Verify Cluster

```bash
# On control plane
kubectl get nodes -o wide

# Expected:
# NAME         STATUS   ROLES                  AGE   VERSION
# node1   Ready    control-plane,master   5m    v1.31.3+k3s1
# node2    Ready    <none>                 3m    v1.31.3+k3s1
# node3    Ready    <none>                 3m    v1.31.3+k3s1
# node4    Ready    <none>                 3m    v1.31.3+k3s1
```

---

## Troubleshooting

### Node Won't Boot

```bash
# Check power status
tpi power status

# View UART for boot errors
tpi uart --node 1 get | tail -50

# Power cycle
tpi power off --node 1
sleep 5
tpi power on --node 1
```

### SSH Connection Refused

```bash
# Check if node is pingable
ping -c 3 10.10.88.73

# SSH might not be ready yet - check UART
tpi uart --node 1 get | grep -E "(login:|ssh)"

# Clear old host keys after reflash
ssh-keygen -R 10.10.88.73
```

### NPU Device Missing

If `/dev/dri/renderD129` is missing:

```bash
# Check kernel messages
dmesg | grep -i rknpu

# Verify vendor kernel (not mainline)
uname -r
# Should show: 6.1.x-vendor-rk35xx

# Check if driver loaded
lsmod | grep rknpu
cat /sys/bus/platform/drivers/RKNPU/
```

### Flash Fails

```bash
# Ensure node is in flash mode
tpi power off --node 1
sleep 2

# Try with smaller timeout
tpi flash --node 1 --image-path /path/to/image.img --skip-crc

# Check BMC logs
ssh root@10.10.88.70 "dmesg | tail -50"
```

### Network Issues

```bash
# Check if node got DHCP
tpi uart --node 1 get | grep -i "ip address"

# Verify from BMC
ssh root@10.10.88.70 "ping -c 2 10.10.88.73"

# Check network config on node
ssh root@10.10.88.73 "ip addr; ip route"
```

---

## Quick Reference

### BMC Environment Variables

```bash
export TPI_HOSTNAME=10.10.88.70
export TPI_USERNAME=root
export TPI_PASSWORD="your_password"
```

### Common Commands

```bash
# Power
tpi power status
tpi power on --node 1
tpi power off --node 1

# Console
tpi uart --node 1 get

# Flash
tpi flash --node 1 --image-path image.img

# BMC info
tpi info
```

### Node IPs

| Node | IP | Hostname |
|------|-----|----------|
| BMC | 10.10.88.70 | turing-bmc |
| 1 | 10.10.88.73 | node1 |
| 2 | 10.10.88.74 | node2 |
| 3 | 10.10.88.75 | node3 |
| 4 | 10.10.88.76 | node4 |

### Kernel Info

| Kernel | NPU Support | Use Case |
|--------|-------------|----------|
| `vendor` (6.1.x) | Yes | Production with NPU |
| `current` (6.6.x) | Limited | Mainline features |
| `edge` (6.x) | No | Testing only |

---

## Additional Resources

- [Turing Pi Documentation](https://docs.turingpi.com/)
- [Armbian Build Framework](https://github.com/armbian/build)
- [RKNN-Toolkit2](https://github.com/airockchip/rknn-toolkit2)
- [RKNN-LLM](https://github.com/airockchip/rknn-llm)
- [K3s Documentation](https://docs.k3s.io/)
