# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.1.5]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.4...v1.1.5
[1.1.4]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jfreed-dev/turing-ansible-cluster/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/jfreed-dev/turing-ansible-cluster/releases/tag/v0.1.0
