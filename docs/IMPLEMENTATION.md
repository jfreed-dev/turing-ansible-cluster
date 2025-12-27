# Implementation Plan: Turing RK1 Ansible Cluster Deployment

## Overview

This plan covers the complete deployment of a K3s Kubernetes cluster on Turing RK1 hardware using the `turing-ansible-cluster` infrastructure-as-code repository. The deployment replaces the existing Talos Linux setup with Ubuntu/Armbian + K3s while maintaining identical networking, storage, and monitoring configurations.

## Target Environments

| Environment | Nodes | Use Case |
|-------------|-------|----------|
| **Server** | 4x RK1 (10.10.88.73-76) | Production with NPU |
| **VM** | 3x VMs (192.168.122.x) | Testing |
| **Laptop** | 1x PopOS | Development workstation |

---

## Phase 0: Prerequisites

### 0.1 Workstation Setup

```bash
# Install required tools
sudo apt install -y ansible terraform python3-pip

# Verify versions
terraform --version  # >= 1.5
ansible --version    # >= 2.15

# Install Ansible collections
cd ~/Code/turing-ansible-cluster/ansible
ansible-galaxy install -r requirements.yml
```

### 0.2 Network Verification

```bash
# Verify BMC access
ping -c 3 10.10.88.70

# Verify node network (if already running)
for ip in 10.10.88.{73..76}; do ping -c 1 $ip; done
```

### 0.3 SSH Key Distribution

```bash
# Copy SSH key to nodes (after OS flash)
for ip in 10.10.88.{73..76}; do
  ssh-copy-id ubuntu@$ip
done
```

### 0.4 Firmware Image Download

```bash
# Download Ubuntu 22.04 for RK1 from Turing Pi
wget -O ~/Downloads/ubuntu-22.04-rk1.img.xz \
  https://firmware.turingpi.com/turing-rk1/ubuntu/ubuntu-22.04-server.img.xz

# Extract (optional - Terraform can handle .xz)
xz -dk ~/Downloads/ubuntu-22.04-rk1.img.xz
```

---

## Phase 1: Firmware Flashing (Terraform)

### 1.1 Configure Terraform

```bash
cd ~/Code/turing-ansible-cluster/terraform/environments/server

# Set BMC credentials
export TURINGPI_USERNAME=root
export TURINGPI_PASSWORD=turing
export TURINGPI_ENDPOINT=https://10.10.88.70
# WARNING: Only use TURINGPI_INSECURE in trusted networks (disables TLS verification)
export TURINGPI_INSECURE=true

# Initialize Terraform
terraform init
```

### 1.2 Flash All Nodes

```bash
# Plan the flash operation
terraform plan \
  -var="flash_nodes=true" \
  -var="firmware_path=$HOME/Downloads/ubuntu-22.04-rk1.img"

# Execute flash (WARNING: destructive, ~30-60 min per node)
terraform apply \
  -var="flash_nodes=true" \
  -var="firmware_path=$HOME/Downloads/ubuntu-22.04-rk1.img"
```

### 1.3 Verify Boot

```bash
# Terraform waits for boot_pattern="login:" on UART
# Manual verification:
ssh ubuntu@10.10.88.73  # Default password may be "ubuntu"
```

### 1.4 Post-Flash: Set Static IPs

If the Ubuntu image uses DHCP, configure static IPs:

```bash
# On each node, edit netplan
sudo vim /etc/netplan/01-netcfg.yaml
# Set static IP matching inventory (10.10.88.73-76)
sudo netplan apply
```

**Estimated Time:** 2-4 hours (sequential flash + boot verification)

---

## Phase 2: OS Bootstrap (Ansible)

### 2.1 Verify Connectivity

```bash
cd ~/Code/turing-ansible-cluster/ansible

# Test SSH access
ansible -i inventories/server/hosts.yml all -m ping
```

### 2.2 Run Bootstrap Playbook

```bash
ansible-playbook -i inventories/server/hosts.yml playbooks/bootstrap.yml
```

**Actions Performed:**

- Update apt cache
- Install base packages (curl, wget, git, htop, btop, vim, tmux, jq, open-iscsi, nfs-common)
- Load kernel modules (iscsi_tcp, dm_crypt)
- Apply sysctl settings for Kubernetes networking
- Set hostnames (node1, node2, node3, node4)
- Configure /etc/hosts with cluster nodes
- Enable iscsid service (for Longhorn)
- Disable swap
- Mount NVMe storage on worker nodes (/var/lib/longhorn)

**Estimated Time:** 5-10 minutes

---

## Phase 3: K3s Installation (Ansible)

### 3.1 Deploy K3s Cluster

```bash
ansible-playbook -i inventories/server/hosts.yml playbooks/kubernetes.yml
```

**Execution Order:**

1. **Control Plane (node1)** - serial execution
   - Install K3s server v1.31.3+k3s1
   - Configure: Pod CIDR 10.244.0.0/16, Service CIDR 10.96.0.0/12
   - Disable traefik and servicelb (using MetalLB + NGINX instead)
   - Generate cluster token
   - Fetch kubeconfig to local machine

2. **Workers (node2/node3/node4)** - parallel execution
   - Install K3s agent
   - Join cluster using token from control plane
   - Wait for node Ready status

### 3.2 Verify Cluster

```bash
export KUBECONFIG=~/Code/turing-ansible-cluster/ansible/kubeconfig

kubectl get nodes -o wide
# Expected: 4 nodes in Ready state

kubectl get pods -A
# Expected: CoreDNS, Flannel, metrics-server running
```

**Estimated Time:** 10-15 minutes

---

## Phase 4: Addon Deployment (Ansible)

### 4.1 Deploy All Addons

```bash
ansible-playbook -i inventories/server/hosts.yml playbooks/addons.yml
```

**Deployment Order (critical for dependencies):**

| Order | Addon | Namespace | Purpose |
|-------|-------|-----------|---------|
| 1 | MetalLB | metallb-system | L2 LoadBalancer (10.10.88.80-89) |
| 2 | NGINX Ingress | ingress-nginx | Ingress controller at 10.10.88.80 |
| 3 | Longhorn | longhorn-system | Distributed storage (2 replicas) |
| 4 | Prometheus Stack | monitoring | Grafana, Prometheus, Alertmanager |
| 5 | Portainer | portainer | Agent connects to 10.10.81.81:9001 |

### 4.2 Verify Addons

```bash
# Check all pods
kubectl get pods -A

# Verify LoadBalancer services
kubectl get svc -A | grep LoadBalancer

# Expected services:
# ingress-nginx-controller  LoadBalancer  10.10.88.80
# portainer-agent           LoadBalancer  10.10.88.81
```

### 4.3 Configure Local Access

```bash
# Add to /etc/hosts on your workstation
echo "10.10.88.80  grafana.local prometheus.local alertmanager.local longhorn.local" | sudo tee -a /etc/hosts
```

**Estimated Time:** 15-30 minutes

---

## Phase 5: NPU Setup (Optional)

### 5.1 Deploy RKNN Runtime

```bash
ansible-playbook -i inventories/server/hosts.yml playbooks/npu-setup.yml
```

**Installed Components (runtime only, ~800MB):**

- RKNN-LLM runtime → /opt/rknn-llm
- rkllama server → /opt/rkllama
- librknnrt.so → /usr/lib/

> **Note:** Dev tools (rknn-toolkit2, ezrknpu) are not installed to save ~10GB per node.
> For model conversion, use a separate development machine.

### 5.2 Verify NPU

```bash
ssh root@10.10.88.73

# Check NPU device (uses DRM subsystem)
ls -la /dev/dri/renderD129

# Check driver version
cat /sys/kernel/debug/rknpu/version
# Expected: RKNPU driver: v0.9.8

# Check NPU load
cat /sys/kernel/debug/rknpu/load
# Expected: NPU load:  Core0:  0%, Core1:  0%, Core2:  0%,

# Source environment
source /etc/profile.d/rknn.sh
```

### 5.3 Run LLM Inference

```bash
# Start rkllama server
cd /opt/rkllama
python3 server.py --target_platform rk3588 --port 8080

# Check NPU status
cat /sys/kernel/debug/rknpu/version
cat /sys/kernel/debug/rknpu/load
```

**Note:** NPU support requires Armbian with Rockchip vendor kernel (6.1.x). Mainline kernels lack the rknpu driver.

**Estimated Time:** 10-20 minutes

---

## Phase 6: Post-Deployment Verification

### 6.1 Cluster Health

```bash
# Node status
kubectl get nodes

# All pods running
kubectl get pods -A | grep -v Running

# Storage health
kubectl -n longhorn-system get pods
```

### 6.2 Application Access

| Application | URL | Credentials |
|-------------|-----|-------------|
| Grafana | http://grafana.local | admin / admin |
| Prometheus | http://prometheus.local | - |
| Alertmanager | http://alertmanager.local | - |
| Longhorn UI | http://longhorn.local | - |
| Portainer | 10.10.81.81:9001 | Agent connection |

### 6.3 Storage Verification

```bash
# Create test PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

# Verify provisioning
kubectl get pvc test-pvc

# Cleanup
kubectl delete pvc test-pvc
```

---

## Phase 7: VM Cluster Deployment (Pop!_OS)

### 7.1 Create VMs

Create 3 Pop!_OS VMs with the following specifications:

| VM | Hostname | IP | vCPU | RAM | Disk |
|----|----------|-----|------|-----|------|
| vm-cp1 | popos-k3s-cp1 | 192.168.122.10 | 4 | 8GB | 50GB |
| vm-w1 | popos-k3s-w1 | 192.168.122.11 | 4 | 8GB | 50GB |
| vm-w2 | popos-k3s-w2 | 192.168.122.12 | 4 | 8GB | 50GB |

**Pop!_OS Installation Settings:**

- Use Pop!_OS 24.04 LTS ISO
- No drive encryption
- Create initial user (any name - will be reconfigured)
- Set static IPs per table above

### 7.2 Provision VMs

```bash
cd ~/Code/turing-ansible-cluster/ansible

# First run - use password authentication
ansible-playbook -i inventories/vm/hosts.yml playbooks/vm-provision.yml -k --ask-become-pass
```

**Actions Performed:**

- Creates user `jon` with admin privileges
- Sets random passwords for `root` and `jon`
- Displays passwords and saves to `credentials/vm-credentials.txt`
- Sets hostnames per Pop!_OS best practices
- Installs KVM guest drivers (qemu-guest-agent, spice-vdagent)
- Configures SSH keys for passwordless access
- Disables swap for Kubernetes
- Enables automatic security updates

### 7.3 Deploy K3s to VMs

```bash
# Bootstrap (now passwordless SSH works)
ansible-playbook -i inventories/vm/hosts.yml playbooks/bootstrap.yml

# Full cluster deployment
ansible-playbook -i inventories/vm/hosts.yml playbooks/site.yml
```

### 7.4 Access VM Cluster

```bash
export KUBECONFIG=~/Code/turing-ansible-cluster/ansible/kubeconfig

# Add to /etc/hosts
echo "192.168.122.80  grafana.vm.local prometheus.vm.local longhorn.vm.local" | sudo tee -a /etc/hosts

kubectl get nodes
```

**Credentials Location:** `ansible/credentials/vm-credentials.txt` (git-ignored)

---

## Phase 8: Laptop/Workstation Setup

### 8.1 Deploy Workstation Playbook

```bash
cd ~/Code/turing-ansible-cluster/ansible

ansible-playbook -i inventories/laptop/hosts.yml playbooks/workstation.yml
```

**Installed Components:**

- Development packages (git, curl, vim, htop, tmux, jq)
- Docker CE
- kubectl
- Helm
- Dotfiles from laptop-configs-popos (optional)

### 8.2 Optional: Join Laptop to Cluster

Edit `inventories/laptop/hosts.yml`:

```yaml
join_cluster: true
k3s_server_url: "https://10.10.88.73:6443"
k3s_token: "<token from control plane>"
```

Then re-run playbook.

---

## Rollback Procedures

### Rollback K3s Installation

```bash
# On each node
/usr/local/bin/k3s-uninstall.sh      # Server
/usr/local/bin/k3s-agent-uninstall.sh # Agents
```

### Rollback to Talos

```bash
cd ~/Code/turing-ansible-cluster/terraform/environments/server

# Flash Talos image instead
terraform apply \
  -var="flash_nodes=true" \
  -var="firmware_path=$HOME/Code/turing-rk1-cluster/images/latest/metal-arm64.raw" \
  -var="boot_pattern=machine is running and ready"
```

### Emergency BMC Access

```bash
ssh root@10.10.88.70
tpi power off    # Power off all nodes
tpi power on     # Power on all nodes
```

---

## Maintenance Tasks

### Update K3s Version

Edit `ansible/inventories/server/hosts.yml`:

```yaml
k3s_version: "v1.32.0+k3s1"  # New version
```

Then run:

```bash
ansible-playbook -i inventories/server/hosts.yml playbooks/kubernetes.yml
```

### Update Helm Charts

Edit `ansible/inventories/server/group_vars/all.yml` chart versions, then:

```bash
ansible-playbook -i inventories/server/hosts.yml playbooks/addons.yml
```

### Backup Cluster

```bash
# Backup etcd (K3s stores in /var/lib/rancher/k3s/server/db/)
ssh ubuntu@10.10.88.73 "sudo tar czf /tmp/k3s-backup.tar.gz /var/lib/rancher/k3s/server/db"
scp ubuntu@10.10.88.73:/tmp/k3s-backup.tar.gz ~/backups/
```

---

## Summary: Complete Deployment Timeline

| Phase | Task | Duration |
|-------|------|----------|
| 0 | Prerequisites | 15 min |
| 1 | Terraform Flash (Server) | 2-4 hours |
| 2 | Ansible Bootstrap | 10 min |
| 3 | K3s Installation | 15 min |
| 4 | Addon Deployment | 30 min |
| 5 | NPU Setup (optional) | 20 min |
| 6 | Verification | 15 min |
| 7 | VM Cluster (Pop!_OS) | 45 min |
| 8 | Laptop Setup | 15 min |
| **Total (Server)** | | **3-5 hours** |
| **Total (VM)** | | **1-2 hours** |

---

## Critical Files Reference

| File | Purpose |
|------|---------|
| `terraform/environments/server/main.tf` | BMC flash configuration |
| `ansible/inventories/server/hosts.yml` | Node IPs and roles |
| `ansible/inventories/server/group_vars/all.yml` | Cluster config, Helm versions |
| `ansible/playbooks/site.yml` | Master playbook |
| `ansible/files/helm-values/*.yml` | Helm chart overrides |
| `ansible/kubeconfig` | Generated cluster access |
