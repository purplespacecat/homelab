# Kubernetes Resources Documentation

This document provides an overview of all Kubernetes resources defined in this repository for the homelab setup. It explains the purpose and functionality of each resource.

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
│   │   ├── monitoring-storage.yaml
│   │   ├── nfs-config.yaml
│   │   └── nfs-subdir-external-provisioner.yaml
│   └── security/                   # Security-related configurations
│       └── network-policies.yaml
├── applications/                   # Application deployments
│   ├── crypto/                     # Cryptocurrency dashboard
│   │   └── crypto-data-app-deployment.yaml
│   └── kafka/                      # Kafka-related applications
├── cert-manager/                   # TLS certificate management
│   ├── cert-manager.yaml
│   ├── cert-manager-issuers.yaml
│   └── local-ca.yaml
└── helm/                           # Helm chart values 
    ├── grafana/
    │   └── values.yaml
    ├── ingress-nginx/
    │   └── values.yaml
    ├── kafka/
    │   └── values.yaml
    └── prometheus/
        └── values.yaml
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
Sets up persistent storage for monitoring components using NFS:

1. **StorageClass**: `nfs-storage`
   - Uses the `no-provisioner` which requires manual PV creation
   - **VolumeBindingMode**: `WaitForFirstConsumer` - Delays volume binding until a pod uses it

2. **StorageClass**: `nfs-client-dynamic`
   - Uses the dynamic provisioner for automatic PV creation
   - Set as the default storage class

3. **PersistentVolumes**:
   - **prometheus-server-pv**: 10Gi storage at `/data/prometheus` on NFS server
   - **grafana-pv**: 10Gi storage at `/data/grafana` on NFS server
   - **alertmanager-pv-0** and **alertmanager-pv-1**: 10Gi storage each at respective paths
   - All volumes use the `nfs-storage` storage class
   - All have specific labels that match the selectors in PVCs defined in Helm values

#### `storage/nfs-config.yaml`
Contains NFS server configuration:
- **ConfigMap**: Stores NFS server address (192.168.100.98) and mount options
- Used by various components that need to access NFS storage

#### `storage/nfs-subdir-external-provisioner.yaml`
Configures the NFS subdir external provisioner:
- Creates a dedicated namespace `nfs-provisioner` for the provisioner
- Deploys the provisioner using a Helm chart
- Configures NFS connection details and StorageClass parameters

### Security Resources

#### `security/network-policies.yaml`
Implements network security policies to restrict pod-to-pod communication:
- **default-deny-all**: Denies all ingress/egress traffic by default in the monitoring namespace
- **allow-prometheus**: Allows specific traffic to/from Prometheus pods
- **allow-grafana**: Allows web access to Grafana and communications to Prometheus
- **allow-alertmanager**: Manages access to and from Alertmanager

## Certificate Management

### `cert-manager/cert-manager.yaml`
Configures cert-manager for TLS certificate management:
- Creates the `cert-manager` namespace
- Deploys cert-manager through a Helm chart with CRDs enabled
- Sets security policy configuration

### `cert-manager/cert-manager-issuers.yaml`
Defines certificate issuers for the homelab:
- **selfsigned-issuer**: For self-signed certificates
- **homelab-issuer**: Let's Encrypt issuer configured for HTTP-01 challenges through Nginx

### `cert-manager/local-ca.yaml`
Sets up a local Certificate Authority for the homelab:
- **selfsigned-ca-issuer**: Self-signs the root CA certificate
- **homelab-ca**: Root CA certificate with ECDSA private key
- **homelab-ca-issuer**: Issues certificates signed by the local CA

## Application Deployments

### `applications/crypto/crypto-data-app-deployment.yaml`
Deploys a cryptocurrency price dashboard:
- **Deployment**: Single replica running `spacecrab/crypto-price-dashboard` image
- **Service**: ClusterIP exposing port 8501
- **Ingress**: Makes the app available at `crypto.local`

## Helm Chart Values

### `helm/prometheus/values.yaml`
Configures the Prometheus monitoring stack:

1. **Prometheus Server**:
   - **Storage**: Uses 10Gi PV with `nfs-client-dynamic` class
   - **Retention**: 30 days data retention
   - **Resources**: Requests 500m CPU, 512Mi memory; limits to 1000m CPU, 1Gi memory
   - **Ingress**: Exposes at `prometheus.local` and `prometheus.192.168.100.202.nip.io`
   - **TLS**: Configured with `homelab-ca-issuer`

2. **Grafana**:
   - **Storage**: 10Gi persistent storage with `local-storage` class
   - **Ingress**: Configured at `grafana.local` and `grafana.192.168.100.202.nip.io`
   - **Security**: Uses a Kubernetes secret for admin credentials
   - **TLS**: Configured with `homelab-ca-issuer`

3. **AlertManager**:
   - **Storage**: 10Gi with `nfs-client-dynamic` for each replica
   - **Ingress**: Available at `alertmanager.local` and `alertmanager.192.168.100.202.nip.io`
   - **TLS**: Configured with `homelab-ca-issuer`
   
4. **Exporters**:
   - **Node Exporter**: Enabled to collect host metrics
   - **Kube State Metrics**: Enabled to collect Kubernetes object metrics

### `helm/grafana/values.yaml`
Dedicated Grafana configuration:
- **Service**: ClusterIP type on port 3000
- **Ingress**: Exposed at `grafana.local`
- **Storage**: 10Gi with label-based selector for the PV
- **Data Sources**: Pre-configured with Prometheus
- **Resources**: Requests 100m CPU, 128Mi memory; limits to 500m CPU, 512Mi memory

### `helm/ingress-nginx/values.yaml`
NGINX Ingress Controller configuration:
- **Service Type**: LoadBalancer (uses MetalLB)
- **Metrics**: Enabled with Prometheus annotations for auto-discovery
- **Configuration**:
  - Max body size: 100m
  - Timeouts: 300 seconds for read/send operations
- **Resources**: Requests 100m CPU, 128Mi memory; limits to 500m CPU, 512Mi memory

### `helm/kafka/values.yaml`
Configuration for Kafka-related applications:
- **Kafka Broker**: `kafka.kafka.svc.cluster.local:9092`
- **Topic**: `crypto-prices`
- **Data Source**: CoinGecko API for Bitcoin and Ethereum prices
- **Poll Interval**: 10 seconds

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

## Usage

These resources should be applied to a Kubernetes cluster in the following order:
1. Core namespace definitions
2. Storage configurations (NFS provisioner)
3. MetalLB for load balancing
4. cert-manager for TLS
5. Ingress controller
6. Monitoring stack
7. Applications