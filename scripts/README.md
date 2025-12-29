# Homelab Scripts

This directory contains scripts for setting up and managing your Kubernetes homelab.

## Directory Structure

```
scripts/
├── k3s/          # K3s (lightweight Kubernetes) cluster scripts
├── kubeadm/      # Kubeadm (full Kubernetes) cluster scripts
└── common/       # Shared utilities for both cluster types
```

## K3s Scripts

Lightweight Kubernetes distribution, perfect for resource-constrained environments.

- `setup-k3s-master.sh` - Install K3s server/master node
- `setup-k3s-worker.sh` - Install K3s agent/worker node
- `teardown-k3s-cluster.sh` - Remove K3s from node

**Usage:**
```bash
# Master
sudo ./k3s/setup-k3s-master.sh

# Worker (get token from master output)
K3S_URL=https://master-ip:6443 K3S_TOKEN=<token> sudo -E ./k3s/setup-k3s-worker.sh
```

## Kubeadm Scripts

Full Kubernetes installation with more configuration options.

- `setup-master-node.sh` - Install control plane + CNI + firewall
- `setup-worker-node.sh` - Install worker node + NFS client + firewall
- `join-worker-node.sh` - Join worker to existing cluster
- `teardown-cluster.sh` - Remove Kubernetes from node

**Usage:**
```bash
# Master
sudo ./kubeadm/setup-master-node.sh

# Worker
sudo ./kubeadm/setup-worker-node.sh
sudo ./kubeadm/join-worker-node.sh
```

**Environment Variables:**
- `KUBERNETES_VERSION` - Kubernetes version (default: 1.28)
- `POD_NETWORK_CIDR` - Pod network CIDR (default: 10.244.0.0/16)
- `CNI_PLUGIN` - CNI plugin: calico, flannel, cilium (default: calico)

## Common Scripts

Utilities that work with both K3s and kubeadm clusters.

### Application Stack
- `install-helm-charts.sh` - Install full stack (MetalLB, Ingress, Prometheus, etc.)
- `install-cert-manager.sh` - Install cert-manager for TLS
- `uninstall-all-helm-charts.sh` - Remove all Helm releases

### NFS Storage
- `setup-nfs-server-remote.sh <ip>` - Setup NFS on remote host
- `setup-nfs-server.sh` - Setup NFS locally
- `install-nfs-provisioner.sh` - Install dynamic NFS provisioner
- `verify-nfs-setup.sh <ip>` - Verify NFS configuration
- `fix-worker-nfs-client.sh` - Install nfs-common on workers
- `secure-nfs.sh` - Lock down NFS exports

### Utilities
- `verify-exposure.sh` - Check service URLs and accessibility
- `extract-ca-cert.sh` - Export cluster CA certificate
- `generate-grafana-creds.sh` - Generate Grafana credentials
- `install-calico.sh` - Standalone Calico CNI installation

## Script Design

All scripts follow minimal output principles:
- **Errors only** - Only print actual errors
- **Final summary** - Show what succeeded/failed at the end
- **No verbosity** - No progress messages, colors, or decorative output

This makes logs cleaner and easier to parse.

## Quick Reference

### New Cluster Setup

**K3s:**
```bash
sudo ./k3s/setup-k3s-master.sh
K3S_URL=https://master:6443 K3S_TOKEN=xxx sudo -E ./k3s/setup-k3s-worker.sh
./common/setup-nfs-server-remote.sh 192.168.100.98
./common/install-helm-charts.sh
```

**Kubeadm:**
```bash
sudo ./kubeadm/setup-master-node.sh
sudo ./kubeadm/setup-worker-node.sh && sudo ./kubeadm/join-worker-node.sh
./common/setup-nfs-server-remote.sh 192.168.100.98
./common/install-helm-charts.sh
```

### Cluster Teardown

**K3s:**
```bash
sudo ./k3s/teardown-k3s-cluster.sh
```

**Kubeadm:**
```bash
sudo ./kubeadm/teardown-cluster.sh
# To also remove packages: REMOVE_PACKAGES=true sudo ./kubeadm/teardown-cluster.sh
```
