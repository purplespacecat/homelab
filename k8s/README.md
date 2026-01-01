# Kubernetes Resources Documentation

This document provides an overview of all Kubernetes resources defined in this repository for the homelab setup. It explains the purpose and functionality of each resource.

## Important Notes

### Networking Architecture

This homelab uses **NGINX Ingress in hostNetwork mode** due to WiFi compatibility:
- NGINX binds directly to the node IP (check with `kubectl get nodes -o wide`)
- Service type: ClusterIP (not LoadBalancer)
- All Ingress hostnames should use: `service-name.<NODE-IP>.nip.io`

**For detailed networking documentation**, see [../docs/NETWORKING.md](../docs/NETWORKING.md)

### Installation Method

All infrastructure components are installed via **Helm CLI** (not Kustomize or HelmChart CRDs):
- Installation scripts in `../scripts/common/` handle all deployments
- Storage class: `nfs-client` (provided by NFS provisioner, set as default)
- K3s includes `local-path` storage class, but NFS is preferred for persistent data

## Directory Structure

```
k8s/
├── core/                           # Core infrastructure components
│   ├── namespaces/                 # Namespace definitions
│   │   ├── ingress-nginx-namespace.yaml
│   │   └── monitoring-namespaces.yaml
│   ├── networking/                 # Network configuration
│   │   └── metallb-config.yaml
│   ├── storage/                    # Storage configuration
│   │   ├── monitoring-storage.yaml  # Static PVs (optional/legacy)
│   │   └── nfs-config.yaml          # NFS server configuration
│   └── security/                   # Security-related configurations
│       └── network-policies.yaml
├── cert-manager/                   # TLS certificate management
│   ├── cert-manager-issuers.yaml   # Let's Encrypt issuer
│   └── local-ca.yaml               # Local CA for homelab
└── helm/                           # Helm chart values
    ├── ingress-nginx/
    │   └── values.yaml
    └── prometheus/
        └── values.yaml             # Includes Grafana configuration
```

## Core Resources

### Namespaces

#### `namespaces/ingress-nginx-namespace.yaml`
Defines a dedicated namespace for the NGINX ingress controller:
- **Namespace**: `ingress-nginx` - Isolates the ingress controller resources from other applications
- **Labels**: Provides organizational metadata for the namespace

#### `namespaces/monitoring-namespaces.yaml`
Creates a namespace for all monitoring-related services:
- **Namespace**: `monitoring` - Contains Prometheus, Grafana, and Alertmanager resources
- **Labels**: Adds metadata for the monitoring namespace

### Network Resources

#### `networking/metallb-config.yaml`
Configures MetalLB for load balancing in a bare-metal Kubernetes environment:
- **IPAddressPool**: Defines IP address range `192.168.100.200-192.168.100.250` for load balancer services
- **L2Advertisement**: Advertises the IP pool on Layer 2 for the local network, making services accessible

### Storage Configuration

#### `storage/monitoring-storage.yaml`
**Optional/Legacy** - Contains static PersistentVolumes for monitoring components:

- **PersistentVolumes** (all use `nfs-client` StorageClass):
  - **prometheus-server-pv**: 10Gi storage at `/data/prometheus` on NFS server
  - **grafana-pv**: 10Gi storage at `/data/grafana` on NFS server
  - **alertmanager-pv-0** and **alertmanager-pv-1**: 10Gi storage each at respective paths
  - All have specific labels that can be used by PVC selectors

**Note**: With the NFS provisioner installed, these static PVs are optional. The `nfs-client` StorageClass will dynamically provision volumes as needed.

#### `storage/nfs-config.yaml`
Contains NFS server configuration:
- **ConfigMap**: Stores NFS server address (192.168.100.98) and mount options
- Used by various components that need to access NFS storage

#### NFS Subdir External Provisioner (Installed via Helm)
**Installed by**: `scripts/install-nfs-provisioner.sh`

The NFS provisioner is now installed via Helm CLI instead of K3s HelmChart CRD:
- Creates a dedicated namespace `nfs-provisioner`
- Creates the `nfs-client` StorageClass (set as default)
- Automatically provisions PersistentVolumes on the NFS server
- Configuration: NFS server at 192.168.100.98, path `/data`

### Security Resources

#### `security/network-policies.yaml`
Implements network security policies to restrict pod-to-pod communication:
- **default-deny-all**: Denies all ingress/egress traffic by default in the monitoring namespace
- **allow-prometheus**: Allows specific traffic to/from Prometheus pods
- **allow-grafana**: Allows web access to Grafana and communications to Prometheus
- **allow-alertmanager**: Manages access to and from Alertmanager

## Certificate Management

### Cert-Manager (Installed via Helm)
**Installed by**: `scripts/install-cert-manager.sh`

Cert-manager is now installed via Helm CLI instead of K3s HelmChart CRD:
- Creates the `cert-manager` namespace
- Deploys cert-manager with CRDs enabled
- Installs version v1.13.1 by default

### `cert-manager/cert-manager-issuers.yaml`
Defines certificate issuer for the homelab:
- **homelab-issuer**: Let's Encrypt issuer configured for HTTP-01 challenges through Nginx
- Used for obtaining public TLS certificates

### `cert-manager/local-ca.yaml`
Sets up a local Certificate Authority for the homelab:
- **selfsigned-ca-issuer**: Self-signs the root CA certificate
- **homelab-ca**: Root CA certificate with ECDSA private key
- **homelab-ca-issuer**: Issues certificates signed by the local CA

## Helm Chart Values

### `helm/prometheus/values.yaml`
Configures the Prometheus monitoring stack (includes Prometheus, Grafana, and Alertmanager):

1. **Prometheus Server**:
   - **Storage**: Uses 10Gi PV with `nfs-client` StorageClass
   - **Retention**: 30 days data retention
   - **Resources**: Requests 500m CPU, 512Mi memory; limits to 1000m CPU, 1Gi memory
   - **Ingress**: Exposes at `prometheus.local` and `prometheus.<NODE-IP>.nip.io`
   - **TLS**: Can be configured with `homelab-ca-issuer` (optional)

2. **Grafana** (bundled with Prometheus stack):
   - **Storage**: 10Gi persistent storage with `nfs-client` StorageClass
   - **Ingress**: Configured at `grafana.local` and `grafana.<NODE-IP>.nip.io`
   - **Security**: Uses a Kubernetes secret for admin credentials
   - **TLS**: Can be configured with `homelab-ca-issuer` (optional)

3. **AlertManager**:
   - **Storage**: 10Gi with `nfs-client` StorageClass for each replica
   - **Ingress**: Available at `alertmanager.local` and `alertmanager.<NODE-IP>.nip.io`
   - **TLS**: Can be configured with `homelab-ca-issuer` (optional)

4. **Exporters**:
   - **Node Exporter**: Enabled to collect host metrics
   - **Kube State Metrics**: Enabled to collect Kubernetes object metrics

### `helm/ingress-nginx/values.yaml`
NGINX Ingress Controller configuration:
- **hostNetwork**: Enabled (true) - Binds directly to node's network interface
- **Service Type**: ClusterIP (not LoadBalancer, due to WiFi compatibility)
- **DNS Policy**: ClusterFirstWithHostNet
- **Why hostNetwork?**: MetalLB L2 mode doesn't work reliably over WiFi interfaces
- **Metrics**: Enabled with Prometheus annotations for auto-discovery
- **Configuration**:
  - Max body size: 100m
  - Timeouts: 300 seconds for read/send operations
- **Resources**: Requests 100m CPU, 128Mi memory; limits to 500m CPU, 512Mi memory

## Best Practices Used

1. **Logical Organization**: Resources organized by function (namespaces, networking, storage, security)
2. **Resource Isolation**: Separate namespaces for different components
3. **Persistent Storage**: NFS-based persistence with both static and dynamic provisioning
4. **Security Layers**: Network policies limit pod-to-pod communication
5. **TLS Security**: Certificate management for encrypted communication
6. **Resource Limits**: CPU and memory constraints on all deployments
7. **Ingress Management**: Centralized ingress configuration with NGINX
8. **Monitoring**: Complete stack with Prometheus, Grafana, and Alertmanager

## Security Considerations

1. **Network Policies**: Fine-grained control of pod-to-pod communication in the monitoring namespace
2. **TLS Certificates**: All ingresses configured with TLS using cert-manager
3. **Secure Credentials**: Grafana admin credentials stored in Kubernetes secrets
4. **NFS Security**: Improved NFS server permission settings

## Installation

### Quick Start (Recommended)

Use the master installation script to install all components in the correct order:

```bash
../scripts/install-all-helm-charts.sh
```

This script will install:
1. NFS Subdir External Provisioner (storage)
2. MetalLB (load balancing)
3. Cert-Manager (TLS certificates)
4. NGINX Ingress Controller
5. Prometheus Stack (Prometheus, Grafana, Alertmanager)

### Manual Installation Order

If installing components manually, follow this order:

1. **Storage**: Install NFS provisioner
   ```bash
   ../scripts/install-nfs-provisioner.sh
   ```

2. **Namespaces**: Create core namespaces
   ```bash
   kubectl apply -f core/namespaces/
   ```

3. **MetalLB**: Install load balancer
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
   sleep 10
   kubectl apply -f core/networking/metallb-config.yaml
   ```

4. **Cert-Manager**: Install certificate management
   ```bash
   ../scripts/install-cert-manager.sh
   ```

5. **Ingress Controller**: Install NGINX
   ```bash
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
   helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
     --namespace ingress-nginx \
     -f helm/ingress-nginx/values.yaml
   ```

6. **Monitoring Stack**: Install Prometheus, Grafana, Alertmanager
   ```bash
   kubectl apply -f core/storage/monitoring-storage.yaml  # Optional static PVs
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
     --namespace monitoring \
     -f helm/prometheus/values.yaml
   ```


## Uninstallation

To remove all components:

```bash
../scripts/uninstall-all-helm-charts.sh
```