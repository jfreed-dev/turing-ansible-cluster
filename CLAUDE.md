# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Repository Purpose

Infrastructure-as-code for deploying K3s Kubernetes clusters with NPU support on Turing RK1 hardware. Uses a hybrid Terraform + Ansible approach.

## Architecture

```
├── terraform/     # BMC operations (flash, power, boot verification)
│   └── Uses jfreed-dev/turingpi provider
└── ansible/       # OS config, K3s, and addon deployment
```

## Key Commands

```bash
# Terraform - BMC operations
cd terraform/environments/server
terraform init
terraform apply -var="flash_nodes=true" -var="firmware_path=/path/to/image.img"

# Ansible - Full cluster deployment
cd ansible
ansible-galaxy install -r requirements.yml
ansible-playbook -i inventories/server/hosts.yml playbooks/site.yml

# Ansible - Individual playbooks
ansible-playbook -i inventories/server/hosts.yml playbooks/bootstrap.yml
ansible-playbook -i inventories/server/hosts.yml playbooks/kubernetes.yml
ansible-playbook -i inventories/server/hosts.yml playbooks/addons.yml
ansible-playbook -i inventories/server/hosts.yml playbooks/npu-setup.yml

# Laptop/VM targets
ansible-playbook -i inventories/laptop/hosts.yml playbooks/workstation.yml
ansible-playbook -i inventories/vm/hosts.yml playbooks/site.yml
```

## Inventory Targets

| Target | Description | NPU Support |
|--------|-------------|-------------|
| server | Turing Pi RK1 (10.10.88.73-76) | Yes |
| vm | Virtual machines for testing | No |
| laptop | PopOS workstation | No |

## Cluster Configuration

- Pod CIDR: 10.244.0.0/16
- Service CIDR: 10.96.0.0/12
- MetalLB: 10.10.88.80-89
- Nodes: node1 (CP), node2/node3/node4 (workers)
- Ingress: grafana.local, prometheus.local → 10.10.88.80

## Related Repositories

- `~/Code/terraform-provider-turingpi` - Terraform BMC provider
- `~/Code/turing-rk1-cluster` - Original Talos cluster config
- `github.com/jfreed-dev/laptop-configs-popos` - PopOS dotfiles (private)

## Conventions

- Ansible roles follow standard structure: tasks/, templates/, handlers/, files/
- Helm values in ansible/files/helm-values/
- Templates use Jinja2 (.j2 extension)
- Sensitive data excluded via .gitignore (no secrets in repo)

## Commit Messages

- Do NOT include any references to Claude, AI, or automated generation in commit messages
- Do NOT include "Co-Authored-By" lines referencing Claude or Anthropic
- Do NOT include emojis or "Generated with" footers
- Keep commit messages concise and descriptive of the actual changes

## Testing

```bash
# Syntax check
ansible-playbook --syntax-check playbooks/site.yml

# Dry run
ansible-playbook -i inventories/server/hosts.yml playbooks/site.yml --check

# Limit to single node
ansible-playbook -i inventories/server/hosts.yml playbooks/bootstrap.yml --limit node1
```
