# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.6] - 2025-12-27

### Fixed

- `k3s_prereq` role: Symlink for `/var/lib/rancher` now created for all nodes with NVMe
  - Previously only created for agent nodes, causing control plane K3s data loss on re-runs
- `k3s_agent` role: Fixed template variable names in `config.yaml.j2`
  - Changed `k3s_server_url` → `k3s_agent_server_url`
  - Changed `k3s_server_token` → `k3s_agent_server_token`
- `rknn` role: Removed `/opt/rkllama` from directory creation list
  - Directory is now created by git clone to avoid "directory not empty" errors
- `longhorn` role: Added node labeling for automatic disk detection
  - Nodes are now labeled with `node.longhorn.io/create-default-disk=true`
  - Required for `createDefaultDiskLabeledNodes: true` helm setting

### Changed

- Updated README to show node1 has NVMe (matches inventory)
- Updated INSTALL.md hardware table to reflect NVMe boot on all nodes

## [1.3.5] - 2025-12-27

### Added

- Cluster reset script (`scripts/reset-cluster.sh`) for clean reinstall
  - Stops and uninstalls K3s on all nodes
  - Wipes NVMe data partitions and Longhorn storage
  - Clears container, CNI, and iptables configuration
  - Power cycles nodes via BMC
  - Supports dry-run mode and selective node targeting

## [1.3.4] - 2025-12-27

### Changed

- Made yamllint a hard failure in CI (was continue-on-error)
- Made terraform fmt a hard failure in CI (was continue-on-error)
- Fixed terraform formatting in `environments/server/main.tf`

## [1.3.3] - 2025-12-27

### Changed

- Renamed Ansible roles to use underscores for ansible-lint compliance
  - `k3s-agent` → `k3s_agent`
  - `k3s-prereq` → `k3s_prereq`
  - `k3s-server` → `k3s_server`
  - `nginx-ingress` → `nginx_ingress`
  - `prometheus-stack` → `prometheus_stack`
- Fixed variable naming to use role prefixes
  - `k3s_server_token` → `k3s_agent_server_token`
  - `k3s_server_url` → `k3s_agent_server_url`
  - `ingress_controller` → `nginx_ingress_controller`
- Removed `role-name` skip from `.ansible-lint` (now fully compliant)

## [1.3.2] - 2025-12-27

### Changed

- Removed default Grafana password from playbook output (use secrets file)
- Added security warnings for `TURINGPI_INSECURE` flag (TLS bypass)
- Added security comments for git clone operations documenting repo trust
- Pinned Ansible collection versions for reproducible builds
  - kubernetes.core: 6.2.0
  - community.general: 12.1.0
  - ansible.posix: 2.1.0

## [1.3.1] - 2025-12-27

### Fixed

- Security: Kubeconfig permissions changed from 0644 to 0600 (owner-only access)
- Security: SSH StrictHostKeyChecking now uses `accept-new` instead of disabled
  - Accepts new host keys on first connection
  - Detects MITM attacks on subsequent connections
- Security: Added k3s binary version verification after installation
- Ansible role variable naming to follow `role_prefix_` convention
  - `base` role: `kernel_modules` → `base_kernel_modules`, etc.
  - `rknn` role: `rkllama_*` → `rknn_*`
- Shell tasks with pipes now use `set -o pipefail` for proper error handling
- YAML line length violations in playbooks
- Broken Armbian download link (armbian.com/turing-rk1 → armbian-builds.techki.to)
- Broken rkllama GitHub link in NPU-API docs (notpunhnox → jfreed-dev)

### Changed

- Replaced `systemctl` command with `ansible.builtin.systemd` module in bootstrap.yml
- Pip upgrade task uses `state: present` with `--upgrade` instead of `state: latest`
- Added `# noqa: no-handler` for appropriate debug tasks

## [1.3.0] - 2025-12-26

### Added

- NPU LLM API service with systemd integration
  - rkllama Flask server runs on each node (port 8080)
  - Auto-starts on boot, restarts on failure
  - OpenAI-compatible `/generate` endpoint
- DeepSeek 1.5B model auto-download (~1.9GB)
  - Pre-configured Modelfile for API server
  - Symlinked from `/opt/rkllama/models/` to `~/RKLLAMA/models/`
- Python virtual environment at `/opt/rkllama/venv`
  - Bypasses Debian externally-managed-environment restrictions
  - Includes transformers, flask, huggingface_hub
- NPU API documentation (`docs/NPU-API.md`)
  - Full endpoint reference with examples
  - Python client examples
  - Load balancing guide
  - Troubleshooting section

### Changed

- Updated README NPU section with API quick start
- Enhanced rknn role with service deployment tasks
- Added handlers for service restart on config changes

## [1.2.1] - 2025-12-26

### Changed

- Migrated image storage from GitHub Releases to Cloudflare R2
  - Custom domain: `armbian-builds.techki.to`
  - 10GB free storage with no egress fees
  - S3-compatible API via rclone
- Updated workflow to use PAT token for branch protection bypass
- Download script now fetches from Cloudflare R2

## [1.2.0] - 2025-12-26

### Added

- Automated Armbian image build workflow (`.github/workflows/armbian-build.yml`)
  - Daily check for upstream armbian/build version changes
  - Automatic build with QEMU ARM64 cross-compilation
  - Auto-updates `images.json` with new image metadata
- Image metadata registry (`images.json`)
  - Tracks latest image version, checksum, download URL
  - Build history with release links
- `--latest` flag for download script
  - Fetches image info from `images.json`
  - Automatic SHA256 verification
- Upload/download scripts for Google Drive distribution

### Changed

- Updated `docs/ARMBIAN-BUILD.md` with "Latest Pre-built Image" section
- Enhanced download script to support direct URLs and `--latest` flag

## [1.1.9] - 2025-12-26

### Changed

- Enhanced `prepare-armbian-image.sh` script
  - Installs required packages via chroot (open-iscsi, nfs-common, curl, etc.)
  - Enables iSCSI services for Longhorn compatibility
  - SSH keys injected directly (no manual provisioning needed)
  - Hostnames updated to match Ansible inventory (node1-4)
  - Auto-detects cross-architecture and uses QEMU if available
  - SKIP_PACKAGES=true option to skip package installation

## [1.1.8] - 2025-12-26

### Added

- Node recovery playbook (`playbooks/recover-node.yml`)
  - Cleans up stale K3s node password secrets
  - Removes stale Longhorn disk entries
  - Re-registers nodes with cluster
  - Configures Longhorn storage automatically
  - Usage: `ansible-playbook playbooks/recover-node.yml --limit node3`

### Changed

- Improved `base` role
  - Added role defaults for packages and kernel modules
  - Enhanced iSCSI configuration with socket and initiator setup
  - Fixed hostname persistence in /etc/hostname

- Improved `k3s-prereq` role
  - Auto-detects NVMe boot vs eMMC boot scenarios
  - Handles post-migration partition layout (nvme0n1p1=root, nvme0n1p2=longhorn)
  - Better idempotency for storage configuration

- Improved `k3s-agent` role
  - Added service existence check before restart
  - Waits for node to reach Ready state
  - Creates node password directory

- Improved `bootstrap.yml` playbook
  - Added pre-flight checks (memory, architecture, NVMe)
  - Post-bootstrap verification of iSCSI and storage
  - Better logging of configuration state

## [1.1.7] - 2025-12-26

### Changed

- Completed node3 NVMe boot migration
  - Reflashed with fresh Armbian image via BMC
  - Migrated to NVMe boot (50G root + 415G Longhorn)
  - Re-registered with K3s cluster
  - All 4 nodes now fully operational on NVMe

### Fixed

- K3s server crash on node1 caused by empty node-passwd file
- Longhorn manager crash on node3 (missing open-iscsi package)

## [1.1.6] - 2025-12-26

### Added

- Google Drive image distribution scripts
  - `scripts/upload-armbian-image.sh` - Upload images with rclone, auto-compression, checksums
  - `scripts/download-armbian-image.sh` - Download with gdown/rclone/curl, checksum verification
- Image Distribution section in `docs/ARMBIAN-BUILD.md`
- Image Distribution quick reference in README

## [1.1.5] - 2025-12-26

### Changed

- Migrated worker nodes (node2, node4) from eMMC to NVMe boot
  - 50G root partition (ext4)
  - 415G Longhorn storage partition (xfs)
- Node3 NVMe migration prepared (pending BMC power cycle)
- All nodes now configured for NVMe boot with dual-partition layout

### Added

- Worker node considerations section in NVMe migration guide
  - K3s agent directory structure fix
  - Longhorn disk UUID mismatch resolution

## [1.1.4] - 2025-12-26

### Changed

- Migrated node1 (control plane) from eMMC to NVMe boot
  - 50G root partition (ext4)
  - 415G Longhorn storage partition (xfs)
- Updated `has_nvme: true` for node1 in server inventory

## [1.1.3] - 2025-12-26

### Added

- CHANGELOG.md with full release history

## [1.1.2] - 2025-12-26

### Added

- Comprehensive Armbian build documentation (`docs/ARMBIAN-BUILD.md`)
  - Build prerequisites and system requirements
  - Quick start build commands
  - Customization options (SSH keys, static IPs, packages)
  - Multi-node automated build script
  - Troubleshooting guide
- Building Armbian section in README

## [1.1.1] - 2025-12-26

### Added

- License badge in README

## [1.1.0] - 2025-12-26

### Added

- GitHub issue templates (bug report, feature request)
- Pull request template with checklist
- Dependabot configuration for Ansible collections and GitHub Actions
- CODEOWNERS file for automatic review requests

## [1.0.0] - 2025-12-26

### Added

- MIT LICENSE file
- SECURITY.md with vulnerability reporting policy
- CONTRIBUTING.md with contribution guidelines
- CI status badge in README
- Example inventory with placeholder IPs (`hosts.yml.example`)
- Templated Grafana password in Prometheus Helm values

### Changed

- Moved `prometheus.yml` to `templates/prometheus-values.yml.j2` for variable substitution
- Sanitized password examples in INSTALL.md documentation
- Updated .gitignore patterns

### Fixed

- Release workflow for repositories with few commits

## [0.1.0] - 2025-12-24

### Added

- Initial infrastructure-as-code for K3s on Turing Pi RK1
- Terraform modules for BMC flashing operations
- Ansible playbooks for cluster deployment:
  - `bootstrap.yml` - OS preparation
  - `kubernetes.yml` - K3s installation
  - `addons.yml` - Helm chart deployment
  - `npu-setup.yml` - RKNN runtime installation
- Ansible roles:
  - `base` - System configuration
  - `k3s-prereq` - K3s prerequisites and NVMe setup
  - `k3s-server` - Control plane installation
  - `k3s-agent` - Worker node installation
  - `metallb` - L2 load balancer
  - `nginx-ingress` - Ingress controller
  - `prometheus-stack` - Monitoring
  - `longhorn` - Distributed storage
  - `portainer` - Container management
  - `rknn` - NPU runtime
- GitHub Actions CI workflow (lint, syntax check, terraform validate)
- GitHub Actions release workflow
- Comprehensive installation guide (INSTALL.md)
- Implementation documentation (docs/IMPLEMENTATION.md)

[1.3.6]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.3.5...v1.3.6
[1.3.5]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.3.4...v1.3.5
[1.3.4]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.3.3...v1.3.4
[1.3.3]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.3.2...v1.3.3
[1.3.2]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.9...v1.2.0
[1.1.9]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.8...v1.1.9
[1.1.8]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.7...v1.1.8
[1.1.7]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.6...v1.1.7
[1.1.6]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.5...v1.1.6
[1.1.5]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.4...v1.1.5
[1.1.4]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/jfreed-dev/turing-ansible-cluster/releases/tag/v0.1.0
