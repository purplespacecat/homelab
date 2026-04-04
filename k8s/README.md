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

All infrastructure components are managed by **FluxCD GitOps**:
- HelmRelease definitions live in `../infrastructure/` (source of truth for deployed values)
- Storage class: `nfs-client` (provided by NFS provisioner, set as default)
- K3s includes `local-path` storage class, but NFS is preferred for persistent data
- Legacy manual scripts in `../scripts/common/` are kept for disaster recovery only

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
│   │   └── nfs-config.yaml          # NFS server configuration
│   └── security/                   # Security-related configurations
│       └── network-policies.yaml
└── cert-manager/                   # TLS certificate management
    ├── cert-manager-issuers.yaml   # Let's Encrypt issuer
    └── local-ca.yaml               # Local CA for homelab
```

> **Note**: Helm chart values are defined inline in the HelmRelease specs under `../infrastructure/`. See `infrastructure/monitoring/prometheus-stack.yaml`, `infrastructure/networking/ingress-nginx.yaml`, etc.

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

#### `storage/nfs-config.yaml`
Contains NFS server configuration:
- **ConfigMap**: Stores NFS server address (192.168.100.98) and mount options
- Used by various components that need to access NFS storage

#### NFS Subdir External Provisioner (Managed by FluxCD)
Defined in `../infrastructure/storage/nfs-provisioner.yaml`:
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

## FluxCD-Managed Components

All Helm chart values are now defined inline in HelmRelease specs under `../infrastructure/`. Key files:

- **Prometheus Stack**: `../infrastructure/monitoring/prometheus-stack.yaml`
  - Prometheus, Grafana, Alertmanager, Node Exporter, Kube State Metrics
  - Storage: 10Gi NFS per component, 2-day retention
  - Grafana credentials via `grafana-admin-credentials` Secret

- **Loki + Promtail**: `../infrastructure/monitoring/loki-stack.yaml`
  - Centralized log aggregation, SingleBinary mode
  - 10Gi NFS storage, 30-day query lookback

- **Tempo**: `../infrastructure/monitoring/tempo.yaml`
  - Distributed tracing backend, 10Gi NFS storage

- **NGINX Ingress**: `../infrastructure/networking/ingress-nginx.yaml`
  - hostNetwork mode, ClusterIP service type, DaemonSet
  - Proxy timeouts: 300s, max body size: 100m

- **MetalLB**: `../infrastructure/networking/metallb.yaml`
  - L2 mode, IP pool: 192.168.100.200-250

- **Cert-Manager**: `../infrastructure/security/cert-manager.yaml`

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

All components are deployed automatically by FluxCD. See [Managing with Flux](../docs/managing-with-flux.md) for the full workflow.

For disaster recovery or fresh cluster setup, see the [Quick Start](../README.md#quick-start) in the main README.