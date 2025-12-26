# Turing RK1 Ansible Cluster

[![CI](https://github.com/jfreed-dev/turing-ansible-cluster/actions/workflows/ci.yml/badge.svg)](https://github.com/jfreed-dev/turing-ansible-cluster/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Infrastructure-as-code for deploying K3s Kubernetes on Turing Pi RK1 hardware with NPU support.

## Overview

Deploy a 4-node K3s cluster on Turing Pi with:
- **Armbian** with Rockchip BSP kernel (NPU support)
- **Terraform** for BMC flashing via [terraform-provider-turingpi](https://github.com/jfreed-dev/terraform-provider-turingpi)
- **Ansible** for K3s installation and addon deployment
- **Networking** matching existing Talos cluster configuration

## Node Configuration

| Node | IP | Role | Hardware |
|------|-----|------|----------|
| node1 | 10.10.88.73 | Control Plane | RK1 (slot 1) |
| node2 | 10.10.88.74 | Worker | RK1 (slot 2) + NVMe |
| node3 | 10.10.88.75 | Worker | RK1 (slot 3) + NVMe |
| node4 | 10.10.88.76 | Worker | RK1 (slot 4) + NVMe |

## Prerequisites

- Terraform >= 1.5
- Ansible >= 2.15
- Turing Pi BMC access
- Armbian image (see [Building Armbian](#building-armbian) or download from [armbian.com/turing-rk1](https://www.armbian.com/turing-rk1/))

## Quick Start

### 1. Setup Secrets

```bash
cd ansible
./scripts/setup-secrets.sh
# Edit secrets/server.yml to set passwords
```

### 2. Flash Armbian via BMC

```bash
cd terraform/environments/server

# Set BMC credentials
export TURINGPI_USERNAME=root
export TURINGPI_PASSWORD=turing
export TURINGPI_ENDPOINT=https://10.10.88.70
export TURINGPI_INSECURE=true

# Flash all nodes (WARNING: destructive!)
terraform init
terraform apply -var="flash_nodes=true" -var="firmware_path=/path/to/armbian.img"
```

### 3. Deploy K3s Cluster

```bash
cd ansible
ansible-playbook -i inventories/server/hosts.yml playbooks/site.yml
```

### 4. Setup NPU (Optional)

```bash
ansible-playbook -i inventories/server/hosts.yml playbooks/npu-setup.yml
```

## Repository Structure

```
turing-ansible-cluster/
├── terraform/
│   ├── modules/bmc/              # BMC operations module
│   └── environments/server/      # RK1 cluster config
│
├── ansible/
│   ├── inventories/server/       # Node inventory
│   ├── playbooks/
│   │   ├── site.yml              # Full deployment
│   │   ├── bootstrap.yml         # OS preparation
│   │   ├── kubernetes.yml        # K3s installation
│   │   ├── addons.yml            # Helm addons
│   │   └── npu-setup.yml         # RKNN toolkit
│   ├── roles/                    # Ansible roles
│   ├── secrets/                  # Local secrets (gitignored)
│   └── scripts/setup-secrets.sh  # Initialize secrets
```

## Cluster Configuration

Matches existing Talos cluster:

| Component | Value |
|-----------|-------|
| Pod CIDR | 10.244.0.0/16 |
| Service CIDR | 10.96.0.0/12 |
| Cluster DNS | 10.96.0.10 |
| MetalLB Range | 10.10.88.80-89 |
| Ingress IP | 10.10.88.80 |

## Addons Deployed

- **MetalLB** - L2 LoadBalancer
- **NGINX Ingress** - Ingress controller
- **Longhorn** - Distributed storage (NVMe on workers)
- **Prometheus + Grafana** - Monitoring
- **Portainer Agent** - Container management

## Storage Optimization

Worker nodes with NVMe drives are automatically configured to use NVMe for both Longhorn and K3s container storage:

| Path | Location | Purpose |
|------|----------|---------|
| `/var/lib/longhorn` | NVMe | Longhorn distributed storage |
| `/var/lib/rancher` | NVMe (symlink) | K3s container images and data |

This frees ~8GB per worker on eMMC and improves container performance.

## NPU Support

Runtime-only RKNN installation for RK3588 NPU inference (~800MB vs ~10GB for full toolkit):
- **rknn-llm** - LLM inference runtime with librknnrt.so
- **rkllama** - Flask-based LLM server
- **NPU Device**: `/dev/dri/renderD129` (via DRM subsystem)
- **Driver**: rknpu v0.9.8+ (included in vendor kernel)

### Quick NPU Test

```bash
# Start LLM server on any node
ssh root@10.10.88.73
cd /opt/rkllama
python3 server.py --target_platform rk3588 --port 8080

# Check NPU status
cat /sys/kernel/debug/rknpu/version  # Driver version
cat /sys/kernel/debug/rknpu/load     # Core utilization
```

Requires Armbian with Rockchip vendor kernel (6.1.x).

> **Note**: Dev tools (rknn-toolkit2, ezrknpu) are not installed by default.
> For model conversion, install them manually or use a separate dev machine.

## Building Armbian

Build custom Armbian images with NPU support using the [Armbian build framework](https://github.com/armbian/build):

```bash
# Clone build framework
git clone --depth=1 https://github.com/armbian/build ~/armbian-build
cd ~/armbian-build

# Build image with vendor kernel (required for NPU)
./compile.sh build \
  BOARD=turing-rk1 \
  BRANCH=vendor \
  RELEASE=bookworm \
  BUILD_MINIMAL=no \
  BUILD_DESKTOP=no
```

Output: `~/armbian-build/output/images/Armbian-*_Turing-rk1_bookworm_vendor_*.img`

For advanced options (custom packages, static IPs, SSH keys), see **[docs/ARMBIAN-BUILD.md](docs/ARMBIAN-BUILD.md)**.

### Image Distribution

Pre-built images are hosted on Cloudflare R2 at [armbian-builds.techki.to](https://armbian-builds.techki.to):

```bash
# Download latest image
./scripts/download-armbian-image.sh --latest

# Prepare for specific node
./scripts/prepare-armbian-image.sh Armbian-*.img 1

# Flash to node
tpi flash --node 1 --image-path Armbian-*.img
```

See **[docs/ARMBIAN-BUILD.md#image-distribution](docs/ARMBIAN-BUILD.md#image-distribution)** for full usage.

## Development

### Local Testing

```bash
# Install dependencies
make install-deps

# Run all checks (lint + syntax)
make test

# Run individual checks
make lint
make syntax-check
```

### Releases

Uses semantic versioning with git tags:

```bash
# Create a release
make release VERSION=v1.0.0

# Push the tag (triggers GitHub release)
git push origin v1.0.0
```

### CI/CD

GitHub Actions runs on every push and PR:
- **Ansible Lint** - Code quality checks (production profile)
- **Syntax Check** - Validates all playbooks
- **Terraform Validate** - Checks Terraform configuration

## Related Repositories

- [terraform-provider-turingpi](https://github.com/jfreed-dev/terraform-provider-turingpi) - Terraform BMC provider
- [turing-rk1-cluster](https://github.com/jfreed-dev/turing-rk1-cluster) - Original Talos Linux cluster

## License

MIT
