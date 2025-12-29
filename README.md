# Kubernetes Homelab Repository

This repo contains files and scripts for a Kubernetes homelab with support for both **K3s** and **kubeadm**.

## Repository Structure

|Folder|Description|
| ----------- | ----------- |
|k8s/core/namespaces|Kubernetes namespace definitions|
|k8s/core/networking|Network configuration (MetalLB, etc.)|
|k8s/core/storage|Storage configuration (NFS, StorageClasses)|
|k8s/core/security|Security-related configurations (NetworkPolicies)|
|k8s/applications|Application deployments (Plex, Ollama, etc.)|
|k8s/cert-manager|TLS certificate management configuration|
|k8s/helm|Helm chart values (Prometheus, Ingress NGINX)|
|network|Network configuration files including cloud-init setups|
|scripts/k3s|K3s cluster setup scripts (lightweight Kubernetes)
|scripts/kubeadm|Kubeadm cluster setup scripts (full Kubernetes)
|scripts/common|Shared utilities (NFS, Helm, cert-manager, etc.)|

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

### Common Utilities (All Cluster Types)
- **common/install-helm-charts.sh** - Install complete application stack
- **common/install-cert-manager.sh** - TLS certificate management
- **common/uninstall-all-helm-charts.sh** - Uninstall all Helm releases
- **common/setup-nfs-server.sh** - Setup local NFS server
- **common/setup-nfs-server-remote.sh** - Setup remote NFS server
- **common/install-nfs-provisioner.sh** - NFS dynamic provisioner
- **common/verify-nfs-setup.sh** - Verify NFS configuration
- **common/fix-worker-nfs-client.sh** - Install nfs-common on workers
- **common/secure-nfs.sh** - Secure NFS exports
- **common/install-calico.sh** - Standalone Calico CNI install
- **common/verify-exposure.sh** - Verify service URLs
- **common/extract-ca-cert.sh** - Extract cluster CA certificate
- **common/generate-grafana-creds.sh** - Generate Grafana credentials

## Quick Start

### Choose Your Kubernetes Distribution

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

### Setup NFS Storage

```bash
# For remote NFS server
./scripts/common/setup-nfs-server-remote.sh 192.168.100.98

# For local NFS server
./scripts/common/setup-nfs-server.sh
```

### Complete Application Stack Installation

Install the entire homelab stack with a single command:

```bash
./scripts/common/install-helm-charts.sh
```

This will install:
1. NFS Subdir External Provisioner (dynamic storage)
2. MetalLB (LoadBalancer support)
3. Cert-Manager (TLS certificates)
4. NGINX Ingress Controller
5. Prometheus Stack (Prometheus, Grafana, Alertmanager)

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

The monitoring stack (Prometheus, Grafana, Alertmanager) is installed automatically with `./scripts/common/install-helm-charts.sh`.

**Access URLs** (after installation):
- Prometheus: `http://prometheus.<INGRESS_IP>.nip.io`
- Grafana: `http://grafana.<INGRESS_IP>.nip.io` (default: admin/admin)
- Alertmanager: `http://alertmanager.<INGRESS_IP>.nip.io`

Run `./scripts/common/verify-exposure.sh` to get the exact URLs for your cluster.

**Updating Prometheus Configuration**:
```bash
# Edit the values file
vi k8s/helm/prometheus/values.yaml

# Apply changes
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f k8s/helm/prometheus/values.yaml
```

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
      - "prometheus.192.168.100.200.nip.io"
    paths:
      - "/"
    pathType: Prefix
    tls:  # Add this section
      - secretName: prometheus-tls
        hosts:
          - "prometheus.192.168.100.200.nip.io"
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

Services are exposed using MetalLB + NGINX Ingress Controller + nip.io DNS.

**Key Components**:
1. **MetalLB**: Provides LoadBalancer IPs from your local network
2. **NGINX Ingress**: Routes HTTP/HTTPS traffic to services
3. **nip.io**: Wildcard DNS (e.g., `service.192.168.100.200.nip.io` → `192.168.100.200`)

**Configure MetalLB IP Pool**:
Edit `k8s/core/networking/metallb-config.yaml` to set your IP range:
```yaml
spec:
  addresses:
  - 192.168.100.200-192.168.100.220  # Adjust for your network
```

Apply: `kubectl apply -f k8s/core/networking/metallb-config.yaml`

**Get Ingress Controller IP**:
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

**Accessing Services**:

Services can be accessed via nip.io domains (e.g., `http://prometheus.192.168.100.200.nip.io`).

If nip.io doesn't work on Windows or your network, add entries to your hosts file:

**Windows**: Edit `C:\Windows\System32\drivers\etc\hosts` (as Administrator)
```
192.168.100.200 prometheus.local grafana.local alertmanager.local
```

**Linux/Mac**: Edit `/etc/hosts` (with sudo)
```
192.168.100.200 prometheus.local grafana.local alertmanager.local
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
spec:
  rules:
  - host: myservice.<INGRESS_IP>.nip.io  # or myservice.local if using hosts file
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
Use `type: LoadBalancer` services to get dedicated IPs for databases, message brokers, etc.

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

This homelab uses a multi-layer networking approach:

```
[External Device] → [MetalLB LoadBalancer IP] → [NGINX Ingress Controller] → [Service] → [Pod]
```

**Detailed Flow**:
1. **External Access**: User accesses `http://grafana.192.168.100.200.nip.io`
2. **DNS Resolution**: nip.io resolves to `192.168.100.200` (or use hosts file)
3. **MetalLB**: Assigns `192.168.100.200` from the IP pool to the NGINX Ingress service (type: LoadBalancer)
4. **NGINX Ingress**: Routes traffic based on hostname to the appropriate backend service
5. **Kubernetes Service**: Load balances across pod replicas
6. **Pod**: Handles the request (e.g., Grafana pod)

**Key Configuration Points**:
- MetalLB IP pool: `k8s/core/networking/metallb-config.yaml` (must match your network segment)
- Ingress rules: Defined in Helm values (e.g., `k8s/helm/prometheus/values.yaml`)
- Service endpoints: Automatically managed by Kubernetes

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

**Full Cluster Rebuild Steps**:

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

**Setup NFS and Applications** (both cluster types):
```bash
# NFS storage
./scripts/common/setup-nfs-server-remote.sh 192.168.100.98

# Application stack
./scripts/common/install-helm-charts.sh
```

5. **Restore Custom Configurations**:
   - Update MetalLB IP pool if needed: `kubectl apply -f k8s/core/networking/metallb-config.yaml`
   - Update email for Let's Encrypt: `kubectl edit clusterissuer homelab-issuer`
   - Apply any custom application deployments from `k8s/applications/`

**What You Need to Backup Separately**:
- Grafana dashboards (if customized)
- Prometheus alerting rules (if customized)
- Persistent data on NFS server (`/data/*`)
- Any secrets not in this repo
- Custom application configurations

**Critical Files to Preserve**:
- `k8s/core/networking/metallb-config.yaml` - Your IP pool configuration
- `k8s/helm/*/values.yaml` - Customized Helm values
- `k8s/cert-manager/cert-manager-issuers.yaml` - Certificate issuer email

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
