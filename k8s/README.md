# Kubernetes Resources Documentation

This document provides an overview of all Kubernetes resources defined in this repository for the homelab setup. It explains the purpose and functionality of each resource.

## Directory Structure

```
k8s/
├── core/               # Core infrastructure components
│   ├── ingress-nginx-namespace.yaml
│   ├── metallb-config.yaml
│   ├── monitoring-namespaces.yaml
│   └── monitoring-storage.yaml
└── helm/              # Helm chart values and application deployments
    ├── data-apps/
    │   └── crypto-data-app-deployment.yaml
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

#### `ingress-nginx-namespace.yaml`
Defines a dedicated namespace for the NGINX ingress controller:
- **Namespace**: `ingress-nginx` - Isolates the ingress controller resources from other applications
- **Labels**: Provides organizational metadata for the namespace

#### `monitoring-namespaces.yaml`
Creates a namespace for all monitoring-related services:
- **Namespace**: `monitoring` - Contains Prometheus, Grafana, and Alertmanager resources
- **Labels**: Adds metadata for the monitoring namespace

### Network Resources

#### `metallb-config.yaml`
Configures MetalLB for load balancing in a bare-metal Kubernetes environment:
- **IPAddressPool**: Defines IP address range `192.168.100.200-192.168.100.250` for load balancer services
- **L2Advertisement**: Advertises the IP pool on Layer 2 for the local network, making services accessible

### Storage Configuration

#### `monitoring-storage.yaml`
Sets up persistent storage for monitoring components using NFS:

1. **StorageClass**: `nfs-storage`
   - Uses the `no-provisioner` which requires manual PV creation
   - **VolumeBindingMode**: `WaitForFirstConsumer` - Delays volume binding until a pod uses it

2. **PersistentVolumes**:
   - **prometheus-server-pv**: 10Gi storage at `/data/prometheus` on NFS server
   - **grafana-pv**: 10Gi storage at `/data/grafana` on NFS server
   - **alertmanager-pv-0** and **alertmanager-pv-1**: 10Gi storage each at respective paths
   - All volumes use the `nfs-storage` storage class
   - All have specific labels that match the selectors in PVCs defined in Helm values

## Application Deployments

### Monitoring Stack

#### `prometheus/values.yaml`
Configures the Prometheus monitoring stack:

1. **Prometheus Server**:
   - **Storage**: Uses 10Gi PV with `nfs-storage` class
   - **Retention**: 30 days data retention
   - **Resources**: Requests 500m CPU, 512Mi memory; limits to 1000m CPU, 1Gi memory
   - **Ingress**: Exposes at `prometheus.local` and `prometheus.192.168.100.202.nip.io`

2. **Grafana** (embedded in Prometheus chart):
   - **Storage**: 10Gi persistent storage
   - **Ingress**: Configured at `grafana.local` and `grafana.192.168.100.202.nip.io`
   - **Default Credentials**: admin/admin (should be changed for production)

3. **AlertManager**:
   - **Storage**: 10Gi for each replica
   - **Ingress**: Available at `alertmanager.local` and `alertmanager.192.168.100.202.nip.io`
   
4. **Exporters**:
   - **Node Exporter**: Enabled to collect host metrics
   - **Kube State Metrics**: Enabled to collect Kubernetes object metrics

#### `grafana/values.yaml`
Dedicated Grafana configuration (separate from the one in Prometheus chart):
- **Service**: ClusterIP type on port 3000
- **Ingress**: Exposed at `grafana.local`
- **Storage**: 10Gi with label-based selector for the PV
- **Data Sources**: Pre-configured with Prometheus
- **Resources**: Requests 100m CPU, 128Mi memory; limits to 500m CPU, 512Mi memory

### Networking

#### `ingress-nginx/values.yaml`
NGINX Ingress Controller configuration:
- **Service Type**: LoadBalancer (uses MetalLB)
- **Metrics**: Enabled with Prometheus annotations for auto-discovery
- **Configuration**:
  - Max body size: 100m
  - Timeouts: 300 seconds for read/send operations
- **Resources**: Requests 100m CPU, 128Mi memory; limits to 500m CPU, 512Mi memory

### Applications

#### `crypto-data-app-deployment.yaml`
Deploys a cryptocurrency price dashboard:
- **Deployment**: Single replica running `spacecrab/crypto-price-dashboard` image
- **Service**: ClusterIP exposing port 8501
- **Ingress**: Makes the app available at `crypto.local`

#### `kafka/values.yaml`
Configuration for Kafka-related applications:
- **Kafka Broker**: `kafka.kafka.svc.cluster.local:9092`
- **Topic**: `crypto-prices`
- **Data Source**: CoinGecko API for Bitcoin and Ethereum prices
- **Poll Interval**: 10 seconds

## Best Practices Used

1. **Resource Isolation**: Separate namespaces for different components
2. **Persistent Storage**: NFS-based persistence for stateful applications
3. **Resource Limits**: CPU and memory constraints on all deployments
4. **Ingress Management**: Centralized ingress configuration with NGINX
5. **Monitoring**: Complete stack with Prometheus, Grafana, and Alertmanager

## Security Considerations

1. **Default Credentials**: The Grafana admin password is set to default values and should be changed
2. **Network Exposure**: Services are exposed through Ingress with proper routing
3. **Resource Isolation**: Components are isolated in their respective namespaces

## Usage

These resources are applied to a Kubernetes cluster in the following order:
1. Core namespace definitions
2. Storage configurations
3. MetalLB for load balancing
4. Ingress controller
5. Monitoring stack
6. Applications