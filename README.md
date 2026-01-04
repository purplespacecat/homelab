# Kubernetes Homelab Repository

This repo contains files and scripts for a Kubernetes homelab with support for both **K3s** and **kubeadm**.

## Table of Contents

- [GitOps Active with FluxCD](#-gitops-active-with-fluxcd)
- [Repository Structure](#repository-structure)
- [Current Cluster Information](#current-cluster-information)
- [Deployed Infrastructure](#deployed-infrastructure)
- [Available Scripts](#available-scripts)
- [Quick Start](#quick-start)
- [Detailed Setup Guides](#detailed-setup-guides)
  - [Monitoring Stack Setup](#monitoring-stack-setup)
  - [Logging Stack Setup (Loki)](#logging-stack-setup-loki)
  - [TLS/HTTPS Setup with Cert-Manager](#tlshttps-setup-with-cert-manager-optional)
  - [Exposing Services to Local Network](#exposing-services-to-local-network)
- [Troubleshooting](#troubleshooting)
- [Architecture & Workflows](#architecture--workflows)
  - [Networking Flow](#networking-flow)
  - [Helm Workflow](#helm-workflow)
  - [Disaster Recovery & Cluster Rebuild](#disaster-recovery--cluster-rebuild)
- [Configuration Checklist](#configuration-checklist)
- [Important Notes](#important-notes)

## 🚀 GitOps Active with FluxCD

**This cluster is now managed by FluxCD GitOps!** All infrastructure is automatically deployed and synchronized from this Git repository.

**What this means:**
- ✅ **Git is the source of truth** - All changes go through Git
- ✅ **Automatic deployment** - Changes sync to cluster within 1 minute
- ✅ **Full audit trail** - Git history = deployment history
- ❌ **No manual kubectl/helm** - Use Git instead (see [Managing with Flux](docs/managing-with-flux.md))

**Quick Links:**
- 📖 [Managing Your Cluster with Flux](docs/managing-with-flux.md) - Complete guide
- ⚡ [Flux Cheat Sheet](docs/flux-cheatsheet.md) - Quick reference
- 🔧 [FluxCD Setup Guide](docs/fluxcd-guide.md) - Installation & concepts
- 🆚 [GitOps Comparison](docs/gitops-comparison.md) - Flux vs Argo

## Repository Structure

|Folder|Description|
| ----------- | ----------- |
|**clusters/homelab/**|**FluxCD cluster configuration (GitOps sync points)**|
|**infrastructure/**|**FluxCD-managed infrastructure (Helm charts, sources)**|
|k8s/core/namespaces|Kubernetes namespace definitions|
|k8s/core/networking|Network configuration (MetalLB, etc.)|
|k8s/core/storage|Storage configuration (NFS, StorageClasses)|
|k8s/core/security|Security-related configurations (NetworkPolicies)|
|k8s/cert-manager|TLS certificate management configuration|
|k8s/helm|Helm chart values (referenced by FluxCD)|
|k8s/applications|Your applications (managed by FluxCD)|
|docs|Documentation (GitOps guides, networking, management)|
|scripts/k3s|K3s cluster setup scripts (lightweight Kubernetes)|
|scripts/kubeadm|Kubeadm cluster setup scripts (full Kubernetes)|
|scripts/common|Shared utilities (NFS, Helm, cert-manager, etc.)|
|scripts/flux|FluxCD installation and bootstrap scripts|

## Current Cluster Information

**Cluster Details:**
- **Distribution**: K3s v1.33.6
- **Node**: spaceship (control-plane, single-node cluster)
- **Node IP**: 192.168.100.98
- **OS**: Ubuntu 22.04.5 LTS
- **Kernel**: 6.8.0-90-generic
- **Container Runtime**: containerd 2.1.5

**Management:**
- **GitOps**: FluxCD (all infrastructure managed via Git)
- **Repository**: All configurations in this Git repo

## Deployed Infrastructure

All components are managed by FluxCD and automatically deployed from this repository:

**Core Infrastructure:**
- **NFS Provisioner** (kube-system) - Dynamic storage provisioning
- **MetalLB** (metallb-system) - LoadBalancer support (IP pool: 192.168.100.200-250)
- **Cert-Manager** (cert-manager) - TLS certificate management
- **NGINX Ingress** (ingress-nginx) - HTTP/HTTPS routing (hostNetwork mode)

**Monitoring & Logging:**
- **Prometheus Stack** (monitoring) - Metrics collection and alerting
  - Prometheus - Metrics database
  - Grafana - Dashboards and visualization
  - Alertmanager - Alert routing
  - Node Exporter - Node metrics
  - Kube State Metrics - Kubernetes metrics
- **Loki Stack** (monitoring) - Log aggregation and querying
  - Loki - Log storage and querying
  - Promtail - Log collection from all pods
  - See [Loki Setup Guide](docs/loki-setup-guide.md) for details

**Access URLs:**
- Grafana: `http://grafana.192.168.100.98.nip.io` (default: admin/admin)
- Prometheus: `http://prometheus.192.168.100.98.nip.io`
- Alertmanager: `http://alertmanager.192.168.100.98.nip.io`

## Available Scripts

### K3s Cluster (Lightweight)
- **k3s/setup-k3s-master.sh** - Setup K3s server/master node
- **k3s/setup-k3s-worker.sh** - Setup K3s agent/worker node
- **k3s/teardown-k3s-cluster.sh** - Remove K3s from node

### Kubeadm Cluster (Full Kubernetes)
- **kubeadm/setup-master-node.sh** - Setup control plane (K8s + CNI + firewall)
- **kubeadm/setup-worker-node.sh** - Setup worker node (K8s + NFS + firewall)
- **kubeadm/join-worker-node.sh** - Join worker to cluster
- **kubeadm/teardown-cluster.sh** - Remove Kubernetes cluster

### FluxCD GitOps (Recommended)
- **flux/install-flux-cli.sh** - Install Flux CLI tool
- **flux/bootstrap-flux.sh** - Bootstrap Flux to cluster (GitOps setup)
- **flux/setup-flux-structure.sh** - Create FluxCD directory structure

### Common Utilities (All Cluster Types)
- **common/install-helm-charts.sh** - Install complete application stack (⚠️ Use FluxCD instead)
- **common/install-cert-manager.sh** - TLS certificate management (⚠️ FluxCD manages this)
- **common/uninstall-all-helm-charts.sh** - Uninstall all Helm releases
- **common/setup-nfs-server.sh** - Setup local NFS server
- **common/setup-nfs-server-remote.sh** - Setup remote NFS server
- **common/install-nfs-provisioner.sh** - NFS dynamic provisioner (⚠️ FluxCD manages this)
- **common/verify-nfs-setup.sh** - Verify NFS configuration
- **common/fix-worker-nfs-client.sh** - Install nfs-common on workers
- **common/secure-nfs.sh** - Secure NFS exports
- **common/install-calico.sh** - Standalone Calico CNI install
- **common/verify-exposure.sh** - Verify service URLs
- **common/extract-ca-cert.sh** - Extract cluster CA certificate
- **common/generate-grafana-creds.sh** - Generate Grafana credentials

## Quick Start

### Choose Your Path

#### Option A: GitOps with FluxCD (Recommended ⭐)
**Automated, Git-driven infrastructure management**

```bash
# 1. Setup Kubernetes cluster (choose K3s or Kubeadm below)

# 2. Install Flux CLI
./scripts/flux/install-flux-cli.sh

# 3. Bootstrap FluxCD (connects Git to cluster)
./scripts/flux/bootstrap-flux.sh

# 4. Done! All infrastructure deploys automatically from Git
# Watch deployment:
flux get kustomizations -w
```

#### Option B: Manual Installation (Legacy)
**Traditional kubectl/helm approach** ⚠️ Not recommended if using GitOps

### Step 1: Choose Your Kubernetes Distribution

#### Option 1: K3s (Recommended for beginners)
K3s is lightweight, easy to install, and perfect for homelabs.

```bash
# On master node
sudo ./scripts/k3s/setup-k3s-master.sh

# On worker nodes (use token and URL from master)
K3S_URL=https://master-ip:6443 K3S_TOKEN=<token> sudo -E ./scripts/k3s/setup-k3s-worker.sh
```

#### Option 2: Kubeadm (Full Kubernetes)
Full Kubernetes installation with more flexibility and features.

```bash
# On master node
sudo ./scripts/kubeadm/setup-master-node.sh

# On worker nodes
sudo ./scripts/kubeadm/setup-worker-node.sh
sudo ./scripts/kubeadm/join-worker-node.sh
```

### Step 2: Setup FluxCD GitOps (Recommended)

**Install Flux and let Git manage your infrastructure:**

```bash
# Install Flux CLI
./scripts/flux/install-flux-cli.sh

# Bootstrap Flux (one-time setup)
./scripts/flux/bootstrap-flux.sh

# That's it! All infrastructure deploys automatically:
# - NFS Provisioner
# - MetalLB
# - Cert-Manager
# - NGINX Ingress
# - Prometheus Stack
```

**OR use manual installation (not recommended):**

### Complete Application Stack Installation (Manual - Legacy)

⚠️ **Note:** If using FluxCD, skip this step. Flux manages all applications automatically.

Install the entire homelab stack with a single command:

```bash
./scripts/common/install-helm-charts.sh
```

This will install:
1. NFS Subdir External Provisioner (dynamic storage)
2. MetalLB (LoadBalancer support for non-HTTP services)
3. Cert-Manager (TLS certificate management)
4. NGINX Ingress Controller (hostNetwork mode for WiFi compatibility)
5. Prometheus Stack (Prometheus, Grafana, Alertmanager, Node Exporter, Kube State Metrics)

### Verify Installation

After installation, verify all services are exposed correctly:

```bash
./scripts/common/verify-exposure.sh
```

### Uninstall Application Stack

To remove all helm-installed components:

```bash
./scripts/common/uninstall-all-helm-charts.sh
```

## Detailed Setup Guides

### Monitoring Stack Setup

The monitoring stack (Prometheus, Grafana, Alertmanager) is automatically deployed via FluxCD.

**Current Stack (deployed):**
- Prometheus: `http://prometheus.192.168.100.98.nip.io`
- Grafana: `http://grafana.192.168.100.98.nip.io` (default: admin/admin)
- Alertmanager: `http://alertmanager.192.168.100.98.nip.io`

**GitOps Management:**

All Prometheus stack configuration is managed through Git. To update:

```bash
# Edit the values file
vi infrastructure/monitoring/prometheus-stack.yaml

# Commit changes
git add infrastructure/monitoring/prometheus-stack.yaml
git commit -m "Update Prometheus configuration"

# Flux will automatically apply changes (or force reconcile)
flux reconcile helmrelease -n monitoring prometheus-stack
```

**Verify Deployment:**
```bash
kubectl get helmrelease -n monitoring
kubectl get pods -n monitoring
```

### Logging Stack Setup (Loki)

The Loki logging stack is automatically deployed via FluxCD and provides centralized log aggregation for all pods in the cluster.

**Components:**
- **Loki** - Log storage and querying engine (single binary mode for homelab)
- **Promtail** - DaemonSet that collects logs from all pods
- **Grafana** - Explore logs using the Loki data source

**Access Logs in Grafana:**
1. Open Grafana: `http://grafana.192.168.100.98.nip.io`
2. Click **Explore** (compass icon in sidebar)
3. Select **Loki** from the data source dropdown
4. Query examples:
   - `{namespace="monitoring"}` - All logs from monitoring namespace
   - `{pod="loki-0"}` - Logs from specific pod
   - `{container="nginx"}` - Logs from specific container
   - `{namespace="kube-system"} |= "error"` - Filter for errors

**What's Being Collected:**
Promtail automatically collects logs from all Kubernetes pods with labels:
- `namespace` - Pod namespace
- `pod` - Pod name
- `container` - Container name
- All pod labels are also included

**GitOps Management:**
```bash
# Edit Loki or Promtail configuration
vi infrastructure/monitoring/loki-stack.yaml

# Commit and apply
git add infrastructure/monitoring/loki-stack.yaml
git commit -m "Update Loki configuration"
flux reconcile helmrelease -n monitoring loki
```

**Storage & Retention:**
- Storage: NFS-backed persistent volume (10Gi)
- Query lookback: 30 days
- Deployment mode: SingleBinary (optimized for single-node homelab)

**For detailed setup and troubleshooting**, see [Loki Setup Guide](docs/loki-setup-guide.md)

### TLS/HTTPS Setup with Cert-Manager (Optional)

Cert-manager is installed automatically with `./scripts/common/install-helm-charts.sh` and provides TLS certificate management.

**Available Certificate Issuers**:

1. **selfsigned-ca-issuer** - Self-signed root CA (for development)
2. **homelab-ca-issuer** - Homelab CA issuer (for internal certificates)
3. **homelab-issuer** - Let's Encrypt issuer (for public certificates)

**Enable HTTPS on an Ingress**:

Add the following annotation and tls section to your Ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-service-ingress
  namespace: my-namespace
  annotations:
    cert-manager.io/cluster-issuer: "homelab-ca-issuer"  # or "homelab-issuer" for Let's Encrypt
spec:
  tls:
  - hosts:
    - myservice.192.168.100.200.nip.io
    secretName: myservice-tls  # cert-manager will create this secret
  rules:
  - host: myservice.192.168.100.200.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

**Update Let's Encrypt Email** (if using homelab-issuer):
```bash
kubectl edit clusterissuer homelab-issuer
# Update the email field in spec.acme.email
```

**Verify Certificate Issuers**:
```bash
kubectl get clusterissuers
```

**Trust the Homelab CA Certificate** (for browsers):

To avoid certificate warnings when using the homelab CA:

1. Extract the CA certificate:
   ```bash
   ./scripts/common/extract-ca-cert.sh
   ```

2. Import `homelab-ca.crt` into your browser or system trust store:
   - **Windows**: Double-click → Install Certificate → Place in "Trusted Root Certification Authorities"
   - **Mac**: Double-click → Add to Keychain → Set to "Always Trust"
   - **Linux**: Copy to `/usr/local/share/ca-certificates/` and run `sudo update-ca-certificates`

**Enable HTTPS for Prometheus Stack**:

After installing cert-manager, update the Prometheus values to enable TLS:

```bash
# Edit the values file
vi k8s/helm/prometheus/values.yaml
```

For each ingress section (prometheus, grafana, alertmanager), add the cert-manager annotation and TLS configuration:

```yaml
prometheus:
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: "homelab-ca-issuer"
      nginx.ingress.kubernetes.io/ssl-redirect: "true"  # Change from "false" to "true"
    hosts:
      - "prometheus.<NODE-IP>.nip.io"
    paths:
      - "/"
    pathType: Prefix
    tls:  # Add this section
      - secretName: prometheus-tls
        hosts:
          - "prometheus.<NODE-IP>.nip.io"
```

Apply the changes:
```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f k8s/helm/prometheus/values.yaml
```

**Manual Installation**:
```bash
./scripts/common/install-cert-manager.sh
```

### Exposing Services to Local Network

Services are exposed using **NGINX Ingress Controller in hostNetwork mode** + **nip.io DNS**.

**Current Architecture** (optimized for WiFi networks):
1. **NGINX Ingress**: Runs with `hostNetwork: true`, binding directly to the node IP
2. **Node IP**: Check with `kubectl get nodes -o wide` to get your node's INTERNAL-IP
3. **nip.io**: Wildcard DNS (e.g., `service.<NODE-IP>.nip.io` → `<NODE-IP>`)

**Why hostNetwork mode?**
- MetalLB L2 mode doesn't work reliably over WiFi interfaces
- hostNetwork allows NGINX to bind directly to the node's network
- No need for LoadBalancer service type for HTTP/HTTPS traffic

**For detailed networking documentation**, see [docs/NETWORKING.md](docs/NETWORKING.md)

**Get Your Node IP**:
```bash
kubectl get nodes -o wide
# Check the INTERNAL-IP column
```

**Accessing Services**:

Services can be accessed via nip.io domains using your node IP (get it with `kubectl get nodes -o wide`):
- `http://prometheus.<NODE-IP>.nip.io`
- `http://grafana.<NODE-IP>.nip.io`
- `http://alertmanager.<NODE-IP>.nip.io`

**How nip.io works**: It's a magic DNS service that automatically resolves any hostname containing an IP to that IP. No configuration needed!

If nip.io doesn't work on your network, add entries to your hosts file:

**Windows**: Edit `C:\Windows\System32\drivers\etc\hosts` (as Administrator)
```
<NODE-IP> prometheus.local grafana.local alertmanager.local
```

**Linux/Mac**: Edit `/etc/hosts` (with sudo)
```
<NODE-IP> prometheus.local grafana.local alertmanager.local
```

Then access services via:
- `http://prometheus.local`
- `http://grafana.local`
- `http://alertmanager.local`

**Create an Ingress** (example):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-service-ingress
  namespace: my-namespace
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"  # HTTP only
spec:
  ingressClassName: nginx  # Use this instead of deprecated annotation
  rules:
  - host: myservice.<NODE-IP>.nip.io  # Use your node IP from kubectl get nodes -o wide
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

**Expose Non-HTTP Services**:
Use `type: LoadBalancer` services with MetalLB to get dedicated IPs for databases, message brokers, etc.
MetalLB IP pool: `192.168.100.200-192.168.100.250` (configured in `k8s/core/networking/metallb-config.yaml`)

## Troubleshooting

### NFS Issues
- **PVCs stuck in Pending**: Run `./scripts/common/verify-nfs-setup.sh` to diagnose
- **Mount failures**: Ensure `nfs-common` is installed on all nodes (use `./scripts/common/fix-worker-nfs-client.sh`)
- **Permission errors**: Check directory permissions on NFS server (usually needs 777 for testing)

### Service Exposure Issues
- **Can't access services**: Run `./scripts/common/verify-exposure.sh` to check configuration
- **Wrong IP in URLs**: Get the correct ingress IP with `kubectl get svc -n ingress-nginx`
- **Firewall blocking**: Firewall rules are configured automatically by setup scripts

### Cluster Issues
- **Pods not starting**: Check `kubectl get pods -A` and `kubectl describe pod <pod-name>`
- **Node NotReady**: Verify firewall rules allow required Kubernetes ports
- **CNI issues**: Check Calico pods in `kube-system` namespace

## Architecture & Workflows

### Networking Flow

This homelab uses **hostNetwork mode** for NGINX Ingress (optimized for WiFi):

```
[External Device] → [Node IP] → [NGINX Ingress (hostNetwork)] → [Service] → [Pod]
```

**Detailed Flow (HTTP/HTTPS Services)**:
1. **External Access**: User accesses `http://grafana.192.168.100.98.nip.io`
2. **DNS Resolution**: nip.io automatically resolves to `192.168.100.98` (the node IP - spaceship)
3. **Node Network**: Traffic arrives at port 80/443 on the K3s node (192.168.100.98)
4. **NGINX Ingress**: Running in hostNetwork mode, directly listens on node's port 80/443
5. **Routing**: NGINX routes traffic based on hostname to the appropriate backend service (ClusterIP)
6. **Kubernetes Service**: Load balances across pod replicas
7. **Pod**: Handles the request (e.g., Grafana pod)

**Why hostNetwork instead of LoadBalancer?**
- MetalLB L2 mode doesn't work reliably over WiFi interfaces
- hostNetwork allows NGINX to bind directly to the node's network interface
- Service type is ClusterIP (not LoadBalancer) since NGINX uses the node IP

**For non-HTTP services** (databases, etc.):
- Use `type: LoadBalancer` to get a MetalLB-assigned IP
- MetalLB IP pool: `192.168.100.200-192.168.100.250`

**Key Configuration Points**:
- NGINX Ingress: `k8s/helm/ingress-nginx/values.yaml` (hostNetwork: true)
- MetalLB IP pool: `k8s/core/networking/metallb-config.yaml` (for non-HTTP services)
- Ingress rules: Defined in Helm values (e.g., `k8s/helm/prometheus/values.yaml`)
- Service endpoints: Automatically managed by Kubernetes

**Full networking documentation**: See [docs/NETWORKING.md](docs/NETWORKING.md) for detailed explanations

### Helm Workflow

The homelab uses Helm for managing applications. Here's how it works:

**Installation Flow** (`./scripts/common/install-helm-charts.sh`):
1. Install/verify Helm is present
2. Create namespaces (`monitoring`, `ingress-nginx`)
3. Install MetalLB (raw manifests, not Helm)
4. Add Helm repositories (ingress-nginx, prometheus-community)
5. Install NGINX Ingress Controller (Helm chart)
6. Auto-update Prometheus values.yaml with detected external IP
7. Install Prometheus Stack (Helm chart)

**Helm Releases** (managed via Helm):
- `ingress-nginx` (namespace: `ingress-nginx`)
- `prometheus` (namespace: `monitoring`)
- `cert-manager` (namespace: `cert-manager`) - if installed

**Updating a Helm Release**:
```bash
# Edit values file
vi k8s/helm/prometheus/values.yaml

# Apply changes
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f k8s/helm/prometheus/values.yaml
```

**Checking Helm Releases**:
```bash
helm list -A  # List all releases across all namespaces
helm status prometheus -n monitoring  # Check specific release
```

### Disaster Recovery & Cluster Rebuild

If your cluster goes down, rebuild it from this repository:

**Full Cluster Rebuild Steps (GitOps Method - Recommended)**:

```bash
# 1. Rebuild Kubernetes Cluster
# For K3s:
sudo ./scripts/k3s/setup-k3s-master.sh
# For Kubeadm:
sudo ./scripts/kubeadm/setup-master-node.sh

# 2. Install Flux CLI
./scripts/flux/install-flux-cli.sh

# 3. Bootstrap FluxCD
./scripts/flux/bootstrap-flux.sh

# 4. Done! Everything deploys automatically from Git
# - NFS Provisioner
# - MetalLB
# - NGINX Ingress
# - Cert-Manager
# - Prometheus Stack (Prometheus, Grafana, Alertmanager)
# - Loki Stack (Loki, Promtail for log aggregation)
# - All your applications

# Watch deployment progress:
flux get kustomizations -w
flux get helmreleases -A

# Verify everything is running:
kubectl get pods -A
```

**Full Cluster Rebuild Steps (Manual Method - Legacy)**:

**For K3s:**
```bash
# Master node
sudo ./scripts/k3s/setup-k3s-master.sh

# Worker nodes
K3S_URL=https://master-ip:6443 K3S_TOKEN=<token> sudo -E ./scripts/k3s/setup-k3s-worker.sh
```

**For Kubeadm:**
```bash
# Master node
sudo ./scripts/kubeadm/setup-master-node.sh
# Configurable: KUBERNETES_VERSION, POD_NETWORK_CIDR, CNI_PLUGIN

# Worker nodes
sudo ./scripts/kubeadm/setup-worker-node.sh
sudo ./scripts/kubeadm/join-worker-node.sh
```

**Setup NFS and Infrastructure** (manual method):
```bash
# NFS storage (use your NFS server IP)
./scripts/common/setup-nfs-server-remote.sh <NFS-SERVER-IP>

# Infrastructure stack (MetalLB, Ingress, Cert-Manager, Prometheus)
./scripts/common/install-helm-charts.sh
```

**What You Need to Backup Separately**:
- Grafana dashboards (if customized)
- Prometheus alerting rules (if customized)
- Persistent data on NFS server (`/data/*`)
- **GitHub Personal Access Token** (for FluxCD bootstrap)
- Any secrets not encrypted in this repo
- Custom application configurations

**Critical Files to Preserve (Already in Git)**:
- `clusters/homelab/` - FluxCD cluster configuration
- `infrastructure/` - All Helm releases and sources
- `k8s/core/networking/metallb-config.yaml` - Your IP pool configuration
- `k8s/helm/*/values.yaml` - Customized Helm values
- `k8s/cert-manager/cert-manager-issuers.yaml` - Certificate issuer email

**Recovery Time**:
- **With FluxCD**: ~10-15 minutes (automated)
- **Manual Method**: ~30-45 minutes (manual steps)

### Configuration Checklist

Before deploying, ensure these are configured for your environment:

- [ ] **MetalLB IP Pool**: Update `k8s/core/networking/metallb-config.yaml` with your network IPs
- [ ] **MetalLB Interface**: Update `interfaces` in metallb-config.yaml (currently: `wlp2s0`)
- [ ] **NFS Server IP**: Used in storage and provisioner scripts (currently: `192.168.100.98`)
- [ ] **Firewall Network Range**: Update `192.168.100.0/24` in firewall scripts if different
- [ ] **Let's Encrypt Email**: Update in `k8s/cert-manager/cert-manager-issuers.yaml`
- [ ] **Prometheus Hosts**: Update nip.io IPs in `k8s/helm/prometheus/values.yaml`

## Important Notes

- **Default Credentials**: Grafana default is `admin/admin` - change in production
- **NFS Permissions**: Using `777` is for lab environments only; secure for production with `./scripts/secure-nfs.sh`
- **Firewall**: Ensure ports 80/443 are open on master node for external access
- **nip.io**: Free DNS service; consider proper DNS for production
- **IP Ranges**: Adjust MetalLB IP range to avoid conflicts with your network DHCP
- **Version Control**: Keep this repository updated with your configuration changes
