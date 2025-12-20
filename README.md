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

## Important Notes

- **Default Credentials**: Grafana default is `admin/admin` - change in production
- **NFS Permissions**: Using `777` is for lab environments only; secure for production with `./scripts/secure-nfs.sh`
- **Firewall**: Ensure ports 80/443 are open on master node for external access
- **nip.io**: Free DNS service; consider proper DNS for production
- **IP Ranges**: Adjust MetalLB IP range to avoid conflicts with your network DHCP
