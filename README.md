# Kubernetes Homelab Repository

This repo contains files and scripts for a Kubernetes homelab running on **kubeadm**.

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
|scripts|Utility scripts for installation, setup, and verification|

## Available Scripts

### Cluster Setup & Management
- **setup-master-node.sh** - Complete master/control-plane setup (K8s + CNI + firewall)
- **setup-worker-node.sh** - Complete worker node setup (K8s + NFS client + firewall)
- **join-worker-node.sh** - Join a worker node to the cluster
- **teardown-kubeadm-cluster.sh** - Completely remove Kubernetes cluster

### Network Configuration
- **install-calico.sh** - Install Calico CNI plugin (standalone)

### Storage & NFS
- **setup-nfs-server.sh** - Setup NFS server locally
- **setup-nfs-server-remote.sh** - Setup NFS server on remote host
- **fix-worker-nfs-client.sh** - Install nfs-common on worker nodes
- **install-nfs-provisioner.sh** - Install NFS dynamic provisioner
- **verify-nfs-setup.sh** - Verify NFS server and client configuration
- **secure-nfs.sh** - Secure NFS exports

### Application Stack Installation
- **install-helm-charts.sh** - Install all helm charts (complete stack)
- **install-cert-manager.sh** - Install cert-manager for TLS certificates
- **uninstall-all-helm-charts.sh** - Uninstall all helm charts

### Verification & Utilities
- **verify-exposure.sh** - Verify service exposure and get access URLs
- **generate-grafana-creds.sh** - Generate Grafana credentials
- **extract-ca-cert.sh** - Extract cluster CA certificate
- **setup-remote-host.sh** - Setup remote host for cluster operations

### Consolidated Scripts

The following scripts have been consolidated for streamlined workflows:

**✓ setup-master-node.sh** - All-in-one master node setup including:
- Kubernetes components (kubeadm, kubelet, kubectl)
- Container runtime (containerd)
- CNI plugin installation (Calico by default)
- Firewall configuration (HTTP/HTTPS/MetalLB ports)
- Cluster initialization

**✓ setup-worker-node.sh** - All-in-one worker node setup including:
- Kubernetes components (kubeadm, kubelet, kubectl)
- Container runtime (containerd)
- NFS client (nfs-common)
- Firewall configuration (Kubelet/NodePort ranges)

## Quick Start

### Prerequisites

Before installing the application stack, ensure your Kubernetes cluster is set up:

1. **Master Node Setup**: Run `sudo ./scripts/setup-master-node.sh` on your master node
2. **Worker Node Setup**: Run `sudo ./scripts/setup-worker-node.sh` on each worker, then join using `./scripts/join-worker-node.sh`
3. **Setup NFS Storage**: Run `./scripts/setup-nfs-server.sh` on your NFS host (or `setup-nfs-server-remote.sh` for remote hosts)

### Complete Application Stack Installation

Install the entire homelab stack with a single command:

```bash
./scripts/install-helm-charts.sh
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
./scripts/verify-exposure.sh
```

### Uninstall Application Stack

To remove all helm-installed components:

```bash
./scripts/uninstall-all-helm-charts.sh
```

## Detailed Setup Guides

### Monitoring Stack Setup

The monitoring stack (Prometheus, Grafana, Alertmanager) is installed automatically with `./scripts/install-helm-charts.sh`.

**Access URLs** (after installation):
- Prometheus: `http://prometheus.<INGRESS_IP>.nip.io`
- Grafana: `http://grafana.<INGRESS_IP>.nip.io` (default: admin/admin)
- Alertmanager: `http://alertmanager.<INGRESS_IP>.nip.io`

Run `./scripts/verify-exposure.sh` to get the exact URLs for your cluster.

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

Cert-manager is installed automatically with `./scripts/install-helm-charts.sh` and provides TLS certificate management.

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
   ./scripts/extract-ca-cert.sh
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
./scripts/install-cert-manager.sh
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
- **PVCs stuck in Pending**: Run `./scripts/verify-nfs-setup.sh` to diagnose
- **Mount failures**: Ensure `nfs-common` is installed on all nodes (use `./scripts/fix-worker-nfs-client.sh`)
- **Permission errors**: Check directory permissions on NFS server (usually needs 777 for testing)

### Service Exposure Issues
- **Can't access services**: Run `./scripts/verify-exposure.sh` to check configuration
- **Wrong IP in URLs**: Get the correct ingress IP with `kubectl get svc -n ingress-nginx`
- **Firewall blocking**: Run firewall fix scripts on master/worker nodes

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

**Installation Flow** (`./scripts/install-helm-charts.sh`):
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

1. **Rebuild Master Node**:
   ```bash
   sudo ./scripts/setup-master-node.sh
   # Configurable: KUBERNETES_VERSION, POD_NETWORK_CIDR, CNI_PLUGIN
   ```

2. **Rebuild Worker Nodes**:
   ```bash
   # On each worker node
   sudo ./scripts/setup-worker-node.sh

   # Join to cluster (get join command from master)
   sudo kubeadm join <master-ip>:6443 --token <token> \
     --discovery-token-ca-cert-hash sha256:<hash>
   ```

3. **Setup NFS Storage** (if NFS server also went down):
   ```bash
   ./scripts/setup-nfs-server.sh  # or setup-nfs-server-remote.sh
   ```

4. **Install Application Stack**:
   ```bash
   ./scripts/install-helm-charts.sh
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
