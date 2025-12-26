# NVMe Boot Migration Guide

This guide documents the process of migrating a Turing RK1 node from eMMC boot to NVMe boot using live system cloning.

## Overview

The migration clones the running system from eMMC to NVMe, updates boot configuration, and optionally adds remaining NVMe space to Longhorn storage.

### Benefits

- **Faster boot and I/O**: NVMe provides significantly better performance than eMMC
- **More storage**: Typical NVMe drives (500GB) offer much more space than eMMC (32GB)
- **Reliability**: Enterprise NVMe drives have better endurance than eMMC

### Partition Layout

```
nvme0n1
├── nvme0n1p1  50G   ext4   /              (root filesystem)
└── nvme0n1p2  ~415G xfs    /var/lib/longhorn (storage)
```

## Prerequisites

- SSH access to the target node
- NVMe drive installed in the node
- Backup of critical data (recommended)

## Migration Steps

### Phase 1: Preparation

#### 1.1 Backup K3s State (Control Plane Only)

```bash
ssh -i ~/.ssh/workbench root@<NODE_IP>

# For control plane nodes, backup state files
mkdir -p /root/k3s-backup
cp -a /var/lib/rancher/k3s/server/db/state.db* /root/k3s-backup/
cp -a /var/lib/rancher/k3s/server/token /root/k3s-backup/
```

#### 1.2 Stop K3s

```bash
systemctl stop k3s    # Control plane
# or
systemctl stop k3s-agent  # Worker nodes
```

#### 1.3 Unmount Existing NVMe (If Mounted)

If the node is already using NVMe for Longhorn storage:

```bash
# Check current mounts
mount | grep nvme

# Unmount if necessary
umount /var/lib/longhorn
```

#### 1.4 Partition NVMe

```bash
# Wipe existing partition table
wipefs -a /dev/nvme0n1

# Create GPT partition table
parted -s /dev/nvme0n1 mklabel gpt

# Create 50G root partition
parted -s /dev/nvme0n1 mkpart primary ext4 1MiB 50GiB

# Create remaining space for Longhorn
parted -s /dev/nvme0n1 mkpart primary xfs 50GiB 100%

# Verify
lsblk /dev/nvme0n1
```

#### 1.5 Format Partitions

```bash
# Install xfsprogs if needed
apt-get update && apt-get install -y xfsprogs

# Format root partition
mkfs.ext4 -L nvme_root /dev/nvme0n1p1

# Format Longhorn partition
mkfs.xfs -L longhorn /dev/nvme0n1p2
```

### Phase 2: Clone System

#### 2.1 Mount NVMe Root

```bash
mkdir -p /mnt/nvme
mount /dev/nvme0n1p1 /mnt/nvme
```

#### 2.2 Clone with rsync

```bash
rsync -axHAWXS --numeric-ids --info=progress2 \
  --exclude='/mnt' \
  --exclude='/proc' \
  --exclude='/sys' \
  --exclude='/dev' \
  --exclude='/run' \
  --exclude='/tmp' \
  / /mnt/nvme/
```

#### 2.3 Create Mount Points

```bash
mkdir -p /mnt/nvme/{proc,sys,dev,run,tmp,mnt}
```

### Phase 3: Update Boot Configuration

#### 3.1 Get New UUIDs

```bash
NEW_ROOT_UUID=$(blkid -s UUID -o value /dev/nvme0n1p1)
LONGHORN_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)
echo "Root UUID: $NEW_ROOT_UUID"
echo "Longhorn UUID: $LONGHORN_UUID"
```

#### 3.2 Update fstab

```bash
cat > /mnt/nvme/etc/fstab << EOF
UUID=${NEW_ROOT_UUID} / ext4 defaults,commit=120,errors=remount-ro 0 1
UUID=${LONGHORN_UUID} /var/lib/longhorn xfs defaults,nofail 0 2
tmpfs /tmp tmpfs defaults,nosuid 0 0
EOF
```

#### 3.3 Update armbianEnv.txt

```bash
sed -i "s|rootdev=UUID=.*|rootdev=UUID=${NEW_ROOT_UUID}|" /mnt/nvme/boot/armbianEnv.txt

# Verify
cat /mnt/nvme/boot/armbianEnv.txt
```

#### 3.4 Create Longhorn Directory

```bash
mkdir -p /mnt/nvme/var/lib/longhorn
```

### Phase 4: Reboot

```bash
sync
umount /mnt/nvme
reboot
```

### Phase 5: Post-Migration Verification

#### 5.1 Verify Boot Device

```bash
ssh -i ~/.ssh/workbench root@<NODE_IP>

# Should show nvme0n1p1 as root
lsblk -o NAME,SIZE,MOUNTPOINT,FSTYPE
df -h / /var/lib/longhorn
```

Expected output:
```
NAME           SIZE MOUNTPOINT        FSTYPE
nvme0n1       465.8G
├─nvme0n1p1     50G /                 ext4
└─nvme0n1p2  415.8G /var/lib/longhorn xfs
mmcblk0       29.1G
└─mmcblk0p1   28.8G                   ext4
```

#### 5.2 Verify K3s

```bash
# Control plane
systemctl status k3s
kubectl get nodes

# Worker
systemctl status k3s-agent
```

### Phase 6: Update Longhorn (If Applicable)

If the node previously had Longhorn storage configured, refresh the disk:

#### 6.1 Remove Stale Disk Configuration

```bash
# Get current disk name
kubectl -n longhorn-system get nodes.longhorn.io <NODE_NAME> -o jsonpath='{.spec.disks}' | jq .

# Disable scheduling on old disk
kubectl -n longhorn-system patch nodes.longhorn.io <NODE_NAME> \
  --type=json -p='[{"op": "replace", "path": "/spec/disks/<OLD_DISK_NAME>/allowScheduling", "value": false}]'

# Wait a few seconds, then remove
kubectl -n longhorn-system patch nodes.longhorn.io <NODE_NAME> \
  --type=json -p='[{"op": "remove", "path": "/spec/disks/<OLD_DISK_NAME>"}]'
```

#### 6.2 Add New Disk

```bash
kubectl -n longhorn-system patch nodes.longhorn.io <NODE_NAME> \
  --type=merge -p '{"spec":{"disks":{"nvme-longhorn":{"path":"/var/lib/longhorn","allowScheduling":true,"storageReserved":0,"tags":[]}}}}'
```

#### 6.3 Verify Longhorn Detects New Disk

```bash
kubectl -n longhorn-system get nodes.longhorn.io <NODE_NAME> \
  -o jsonpath='{.status.diskStatus}' | jq '."nvme-longhorn" | {storageMaximum, filesystemType}'
```

Expected output:
```json
{
  "storageMaximum": 446202769408,
  "filesystemType": "xfs"
}
```

## Rollback Procedure

If NVMe boot fails, the eMMC remains unchanged and can be used for recovery:

### Option 1: Power Cycle

```bash
# From Turing Pi BMC or another machine
tpi power off -n <NODE_NUMBER>
sleep 5
tpi power on -n <NODE_NUMBER>
```

The RK1 should fallback to eMMC if NVMe boot fails.

### Option 2: Restore armbianEnv.txt

If you can access the system (e.g., via serial console):

```bash
# Get original eMMC UUID
EMMC_UUID=$(blkid -s UUID -o value /dev/mmcblk0p1)

# Update boot config to use eMMC
sed -i "s|rootdev=UUID=.*|rootdev=UUID=${EMMC_UUID}|" /boot/armbianEnv.txt
reboot
```

## Update Ansible Inventory

After successful migration, update the inventory:

```yaml
# ansible/inventories/server/hosts.yml
node1:
  ansible_host: 10.10.88.73
  tpi_node: 1
  k3s_role: server
  has_nvme: true  # Changed from false
```

## Quick Reference

| Step | Command |
|------|---------|
| Stop K3s | `systemctl stop k3s` |
| Partition | `parted -s /dev/nvme0n1 mklabel gpt && parted -s /dev/nvme0n1 mkpart primary ext4 1MiB 50GiB && parted -s /dev/nvme0n1 mkpart primary xfs 50GiB 100%` |
| Format | `mkfs.ext4 -L nvme_root /dev/nvme0n1p1 && mkfs.xfs -L longhorn /dev/nvme0n1p2` |
| Clone | `rsync -axHAWXS --numeric-ids --exclude='/mnt' --exclude='/proc' --exclude='/sys' --exclude='/dev' --exclude='/run' --exclude='/tmp' / /mnt/nvme/` |
| Get UUID | `blkid -s UUID -o value /dev/nvme0n1p1` |

## Node Status

| Node | Boot Device | Longhorn Storage | Migration Date |
|------|-------------|------------------|----------------|
| node1 | NVMe (50G) | NVMe (415G) | 2025-12-26 |
| node2 | NVMe (50G) | NVMe (415G) | 2025-12-26 |
| node3 | NVMe (50G) | NVMe (415G) | 2025-12-26* |
| node4 | NVMe (50G) | NVMe (415G) | 2025-12-26 |

\* Node3 requires BMC power cycle to complete migration

## Worker Node Considerations

Worker nodes may have `/var/lib/rancher` symlinked to `/var/lib/longhorn/rancher` to share the NVMe partition. After migration:

### K3s Agent Fails to Start

If K3s agent fails with "extracting data: no such file or directory":

```bash
# Create the required directory structure
mkdir -p /var/lib/longhorn/rancher/k3s/data

# Restart K3s agent
systemctl restart k3s-agent
```

### Longhorn Disk UUID Mismatch

After reformatting, Longhorn will show "diskUUID doesn't match". To fix:

```bash
# Disable scheduling on old disk
kubectl -n longhorn-system patch nodes.longhorn.io <NODE_NAME> \
  --type=json -p='[{"op": "replace", "path": "/spec/disks/<OLD_DISK_NAME>/allowScheduling", "value": false}]'

# Wait a few seconds, then remove old disk
kubectl -n longhorn-system patch nodes.longhorn.io <NODE_NAME> \
  --type=json -p='[{"op": "remove", "path": "/spec/disks/<OLD_DISK_NAME>"}]'

# Add new disk (wait for sync if needed)
kubectl -n longhorn-system patch nodes.longhorn.io <NODE_NAME> \
  --type=merge -p '{"spec":{"disks":{"nvme-longhorn":{"path":"/var/lib/longhorn","allowScheduling":true,"storageReserved":0,"tags":[]}}}}'
```
