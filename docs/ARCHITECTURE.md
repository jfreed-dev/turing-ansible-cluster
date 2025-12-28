# Architecture Documentation

This document provides visual architecture documentation for the Turing Ansible Cluster - K3s deployment on Turing Pi RK1 hardware.

## Table of Contents

1. [System Overview](#system-overview)
2. [Network Topology](#network-topology)
3. [Deployment Pipeline](#deployment-pipeline)
4. [Component Interaction](#component-interaction)
5. [Storage Architecture](#storage-architecture)
6. [Kubernetes Stack](#kubernetes-stack)
7. [NPU Integration](#npu-integration)

---

## System Overview

```mermaid
graph TB
    subgraph "Operator Workstation"
        TF[Terraform CLI]
        Ansible[Ansible Playbooks]
    end

    subgraph "Turing Pi 2.5 Board"
        BMC[BMC Controller<br/>10.10.88.70]

        subgraph "Compute Modules"
            N1[Node 1 - Control Plane<br/>10.10.88.73]
            N2[Node 2 - Worker<br/>10.10.88.74]
            N3[Node 3 - Worker<br/>10.10.88.75]
            N4[Node 4 - Worker<br/>10.10.88.76]
        end
    end

    subgraph "Kubernetes Cluster"
        K3S[K3s v1.31.3]
        Flannel[Flannel CNI<br/>10.244.0.0/16]
        MetalLB[MetalLB<br/>10.10.88.80-89]
        Longhorn[Longhorn Storage]
        Monitoring[Prometheus + Grafana]
    end

    subgraph "External Services"
        Ingress[Ingress VIP<br/>10.10.88.80]
        Portainer[Portainer VIP<br/>10.10.88.81]
    end

    TF --> BMC
    BMC --> N1
    BMC --> N2
    BMC --> N3
    BMC --> N4

    Ansible --> N1
    Ansible --> N2
    Ansible --> N3
    Ansible --> N4

    N1 --> K3S
    N2 --> K3S
    N3 --> K3S
    N4 --> K3S

    K3S --> Flannel
    K3S --> MetalLB
    K3S --> Longhorn
    K3S --> Monitoring

    MetalLB --> Ingress
    MetalLB --> Portainer
```

---

## Network Topology

```mermaid
graph TB
    subgraph "External Network - 10.10.88.0/24"
        Router[Router/Gateway]
        Admin[Admin Workstation]
    end

    subgraph "Turing Pi Board"
        subgraph "BMC Network"
            BMC[BMC<br/>10.10.88.70]
        end

        subgraph "Compute Network"
            N1[Node 1<br/>10.10.88.73<br/>Control Plane]
            N2[Node 2<br/>10.10.88.74<br/>Worker]
            N3[Node 3<br/>10.10.88.75<br/>Worker]
            N4[Node 4<br/>10.10.88.76<br/>Worker]
        end
    end

    subgraph "Kubernetes Networks"
        subgraph "Pod Network - 10.244.0.0/16"
            Pods[Pod IPs]
        end

        subgraph "Service Network - 10.96.0.0/12"
            CoreDNS[CoreDNS<br/>10.96.0.10]
            Services[ClusterIP Services]
        end

        subgraph "MetalLB Pool - 10.10.88.80-89"
            VIP80[Ingress<br/>10.10.88.80]
            VIP81[Portainer<br/>10.10.88.81]
            VIP82_89[Available<br/>10.10.88.82-89]
        end
    end

    Router --> BMC
    Router --> N1
    Router --> N2
    Router --> N3
    Router --> N4

    Admin --> Router

    N1 --> Pods
    N2 --> Pods
    N3 --> Pods
    N4 --> Pods

    Pods --> CoreDNS
    Pods --> Services

    N1 --> VIP80
    N2 --> VIP80
    N3 --> VIP80
    N4 --> VIP80
```

### IP Address Allocation

| Component | IP Address | Purpose |
|-----------|------------|---------|
| BMC | 10.10.88.70 | Board management |
| Node 1 | 10.10.88.73 | Control plane |
| Node 2 | 10.10.88.74 | Worker |
| Node 3 | 10.10.88.75 | Worker |
| Node 4 | 10.10.88.76 | Worker |
| Ingress VIP | 10.10.88.80 | NGINX Ingress |
| Portainer VIP | 10.10.88.81 | Management UI |
| Available | 10.10.88.82-89 | Future services |

---

## Deployment Pipeline

```mermaid
sequenceDiagram
    participant Op as Operator
    participant TF as Terraform
    participant BMC as Turing Pi BMC
    participant Nodes as Compute Nodes
    participant Ansible as Ansible

    rect rgb(200, 220, 240)
        Note over Op,BMC: Phase 1: Firmware Provisioning (Terraform)
        Op->>TF: terraform apply
        TF->>BMC: Authenticate
        BMC-->>TF: Token

        loop Each Node
            TF->>BMC: Flash Armbian image
            BMC->>Nodes: Write firmware
            Nodes-->>BMC: Flash complete
            TF->>BMC: Power on
            BMC->>Nodes: Enable power
            TF->>BMC: Monitor UART
            Nodes-->>BMC: "login:" prompt
            BMC-->>TF: Boot complete
        end
    end

    rect rgb(220, 240, 200)
        Note over Op,Ansible: Phase 2: OS Bootstrap (Ansible)
        Op->>Ansible: ansible-playbook bootstrap.yml
        Ansible->>Nodes: SSH connect
        Ansible->>Nodes: Install packages
        Ansible->>Nodes: Configure NVMe
        Ansible->>Nodes: Set hostname
        Ansible->>Nodes: Configure kernel modules
    end

    rect rgb(240, 220, 200)
        Note over Op,Ansible: Phase 3: Kubernetes Installation
        Op->>Ansible: ansible-playbook kubernetes.yml
        Ansible->>Nodes: Install K3s (control plane first)
        Nodes-->>Ansible: K3s token
        Ansible->>Nodes: Join workers with token
    end

    rect rgb(240, 200, 220)
        Note over Op,Ansible: Phase 4: Addon Deployment
        Op->>Ansible: ansible-playbook addons.yml
        Ansible->>Nodes: Deploy MetalLB
        Ansible->>Nodes: Deploy NGINX Ingress
        Ansible->>Nodes: Deploy Longhorn
        Ansible->>Nodes: Deploy Prometheus Stack
        Ansible->>Nodes: Deploy Portainer Agent
    end
```

---

## Component Interaction

```mermaid
graph TB
    subgraph "Terraform Layer"
        TFMain[terraform/environments/server/main.tf]
        TFModule[terraform/modules/bmc/main.tf]
        TFProvider[terraform-provider-turingpi]
    end

    subgraph "Ansible Layer"
        subgraph "Playbooks"
            Site[site.yml<br/>Full Deployment]
            Bootstrap[bootstrap.yml<br/>OS Setup]
            Kubernetes[kubernetes.yml<br/>K3s Install]
            Addons[addons.yml<br/>Helm Charts]
            NPU[npu-setup.yml<br/>RKNN Runtime]
        end

        subgraph "Roles"
            RBase[base<br/>System packages]
            RK3sPrereq[k3s_prereq<br/>Prerequisites]
            RK3sServer[k3s_server<br/>Control plane]
            RK3sAgent[k3s_agent<br/>Workers]
            RLonghorn[longhorn<br/>Storage]
            RMetalLB[metallb<br/>LoadBalancer]
            RNginx[nginx_ingress<br/>Ingress]
            RPrometheus[prometheus_stack<br/>Monitoring]
            RPortainer[portainer<br/>Management]
            RRKNN[rknn<br/>NPU Runtime]
        end
    end

    subgraph "Inventory"
        Server[inventories/server/hosts.yml]
        GroupVars[group_vars/all.yml]
    end

    TFMain --> TFModule
    TFModule --> TFProvider

    Site --> Bootstrap
    Site --> Kubernetes
    Site --> Addons

    Bootstrap --> RBase
    Bootstrap --> RK3sPrereq

    Kubernetes --> RK3sServer
    Kubernetes --> RK3sAgent

    Addons --> RMetalLB
    Addons --> RNginx
    Addons --> RLonghorn
    Addons --> RPrometheus
    Addons --> RPortainer

    NPU --> RRKNN

    Server --> Site
    GroupVars --> Site
```

---

## Storage Architecture

```mermaid
graph TB
    subgraph "Node 1 (Control Plane)"
        N1_eMMC[eMMC 64GB<br/>System Only]
        N1_Boot[Armbian Boot]
    end

    subgraph "Node 2 (Worker)"
        N2_eMMC[eMMC 64GB<br/>System]
        N2_NVMe[NVMe 512GB<br/>Data]
        N2_Longhorn[Longhorn Volume]
    end

    subgraph "Node 3 (Worker)"
        N3_eMMC[eMMC 64GB<br/>System]
        N3_NVMe[NVMe 512GB<br/>Data]
        N3_Longhorn[Longhorn Volume]
    end

    subgraph "Node 4 (Worker)"
        N4_eMMC[eMMC 64GB<br/>System]
        N4_NVMe[NVMe 512GB<br/>Data]
        N4_Longhorn[Longhorn Volume]
    end

    subgraph "Longhorn Cluster Storage"
        Manager[Longhorn Manager]
        Engine[Longhorn Engine]
        Replica2[2x Replication]
    end

    subgraph "Kubernetes PVs"
        PVC[PersistentVolumeClaim]
        SC[StorageClass: longhorn]
    end

    N1_eMMC --> N1_Boot

    N2_eMMC --> N2_NVMe
    N2_NVMe --> N2_Longhorn

    N3_eMMC --> N3_NVMe
    N3_NVMe --> N3_Longhorn

    N4_eMMC --> N4_NVMe
    N4_NVMe --> N4_Longhorn

    N2_Longhorn --> Manager
    N3_Longhorn --> Manager
    N4_Longhorn --> Manager

    Manager --> Engine
    Engine --> Replica2

    PVC --> SC
    SC --> Manager
```

### Storage Configuration

| Node | eMMC | NVMe | Longhorn Mount |
|------|------|------|----------------|
| Node 1 | 64GB (System) | - | - |
| Node 2 | 64GB (System) | 512GB | /var/lib/longhorn |
| Node 3 | 64GB (System) | 512GB | /var/lib/longhorn |
| Node 4 | 64GB (System) | 512GB | /var/lib/longhorn |

---

## Kubernetes Stack

```mermaid
graph TB
    subgraph "kube-system"
        CoreDNS[CoreDNS]
        KubeProxy[kube-proxy]
        Flannel[Flannel CNI]
        Metrics[metrics-server]
    end

    subgraph "metallb-system"
        Controller[MetalLB Controller]
        Speaker[MetalLB Speaker]
        IPPool[IPAddressPool<br/>10.10.88.80-89]
    end

    subgraph "ingress-nginx"
        IngressCtrl[Ingress Controller]
        IngressSvc[LoadBalancer Service<br/>10.10.88.80]
    end

    subgraph "longhorn-system"
        LHManager[Longhorn Manager]
        LHUI[Longhorn UI]
        LHDriver[CSI Driver]
        LHEngine[Volume Engine]
    end

    subgraph "monitoring"
        Prometheus[Prometheus]
        Grafana[Grafana]
        Alertmanager[Alertmanager]
        NodeExporter[Node Exporter]
    end

    subgraph "portainer"
        PortainerAgent[Portainer Agent]
    end

    subgraph "Addon Dependencies"
        direction LR
        D1[MetalLB] --> D2[NGINX Ingress]
        D2 --> D3[Longhorn]
        D3 --> D4[Prometheus Stack]
        D4 --> D5[Portainer]
    end

    Controller --> IPPool
    Speaker --> IPPool
    IPPool --> IngressSvc

    IngressCtrl --> IngressSvc

    LHManager --> LHEngine
    LHManager --> LHDriver

    Prometheus --> NodeExporter
    Prometheus --> Grafana
    Prometheus --> Alertmanager
```

---

## NPU Integration

```mermaid
graph TB
    subgraph "RK3588 SoC"
        CPU[Cortex-A76 x4<br/>Cortex-A55 x4]
        NPU[NPU 6 TOPS<br/>INT8 Inference]
        GPU[Mali-G610<br/>Not Available]
        DRM[DRM Subsystem<br/>/dev/dri/renderD129]
    end

    subgraph "RKNN Stack"
        Driver[rknpu Driver<br/>v0.9.8+]
        Runtime[rknn-llm Runtime]
        API[RKLLAMA API<br/>Port 8080]
    end

    subgraph "Systemd Services"
        RKLLAMASvc[rkllama.service]
    end

    subgraph "Model Storage"
        Models[/opt/rkllama/models/]
        DeepSeek[DeepSeek-R1-1.5B<br/>~1.9GB]
    end

    CPU --> NPU
    NPU --> DRM
    DRM --> Driver
    Driver --> Runtime
    Runtime --> API

    RKLLAMASvc --> API
    API --> Models
    Models --> DeepSeek
```

### NPU Configuration

| Component | Details |
|-----------|---------|
| Driver | rknpu v0.9.8+ (vendor kernel) |
| Device | /dev/dri/renderD129 |
| Runtime | rknn-llm v1.2.3 |
| API Port | 8080 |
| CPU Cores | 4-7 (big cores for NPU) |

---

## Inventory Structure

```mermaid
graph TB
    subgraph "Inventory Targets"
        Server[inventories/server/<br/>Turing Pi RK1]
        VM[inventories/vm/<br/>Virtual Machines]
        Laptop[inventories/laptop/<br/>PopOS Workstation]
    end

    subgraph "Server Inventory"
        ControlPlane[controlplane<br/>node1]
        Workers[workers<br/>node2, node3, node4]
        K3sCluster[k3s_cluster<br/>All nodes]
        NPUNodes[npu_nodes<br/>All nodes]
    end

    subgraph "Group Variables"
        AllVars[group_vars/all.yml]
        K3sVars[K3s version, CNI, CIDRs]
        NetworkVars[MetalLB pool, Ingress IP]
        StorageVars[Longhorn replicas, NVMe paths]
    end

    Server --> ControlPlane
    Server --> Workers
    ControlPlane --> K3sCluster
    Workers --> K3sCluster
    K3sCluster --> NPUNodes

    AllVars --> K3sVars
    AllVars --> NetworkVars
    AllVars --> StorageVars
```

---

## File Structure

```
turing-ansible-cluster/
├── terraform/
│   ├── modules/bmc/
│   │   └── main.tf           # turingpi_node resource
│   └── environments/server/
│       └── main.tf           # Node configurations
├── ansible/
│   ├── playbooks/
│   │   ├── site.yml          # Full deployment
│   │   ├── bootstrap.yml     # OS configuration
│   │   ├── kubernetes.yml    # K3s installation
│   │   ├── addons.yml        # Helm charts
│   │   └── npu-setup.yml     # RKNN runtime
│   ├── roles/
│   │   ├── base/             # System packages
│   │   ├── k3s_prereq/       # K3s prerequisites
│   │   ├── k3s_server/       # Control plane
│   │   ├── k3s_agent/        # Worker nodes
│   │   ├── longhorn/         # Distributed storage
│   │   ├── metallb/          # Load balancer
│   │   ├── nginx_ingress/    # Ingress controller
│   │   ├── prometheus_stack/ # Monitoring
│   │   ├── portainer/        # Management UI
│   │   └── rknn/             # NPU runtime
│   ├── inventories/
│   │   ├── server/           # Production cluster
│   │   ├── vm/               # Test VMs
│   │   └── laptop/           # Workstation
│   └── files/helm-values/    # Helm chart values
└── docs/
    ├── ARCHITECTURE.md       # This file
    ├── IMPLEMENTATION.md     # Deployment procedures
    ├── NETWORKING.md         # Network configuration
    ├── STORAGE.md            # Storage setup
    └── MONITORING.md         # Observability
```
