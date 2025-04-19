# This repo contains files and scripts that I use for my k8s homelab
|Folder|Description|
| ----------- | ----------- |
|k8s/core|Core infrastructure components (namespaces, MetalLB config, storage)|
|k8s/helm|Helm chart values for various applications and services|
|k8s/helm/data-apps|Deployments for data applications like crypto dashboard|
|k8s/helm/grafana|Grafana configuration values|
|k8s/helm/ingress-nginx|Ingress NGINX controller configuration|
|k8s/helm/kafka|Kafka and message streaming configuration|
|k8s/helm/prometheus|Prometheus monitoring stack configuration|
|network|Network configuration files including cloud-init setups|
|scripts|Utility scripts for installation and verification|

## Core Components Installation

### 1. MetalLB Installation
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb-operator/v0.13.12/config/manifests/metallb-native.yaml
kubectl apply -f k8s/core/metallb-config.yaml
```

### 2. NGINX Ingress Controller Installation
```bash
# Create namespace
kubectl apply -f k8s/core/ingress-nginx-namespace.yaml

# Add and update helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install nginx-ingress
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  -f k8s/helm/ingress-nginx/values.yaml
```

## Complete Monitoring Setup Guide

This guide will walk you through setting up a full monitoring stack with Prometheus, Grafana, and Alertmanager, accessible from your local network.

### 1. Set Up NFS Server on Host Machine (192.168.100.98)

The monitoring stack requires persistent storage. We'll use NFS to provide this.

```bash
# SSH into the host machine
ssh 192.168.100.98

# Copy and run the NFS setup script
scp scripts/setup-nfs.sh 192.168.100.98:/tmp/
ssh 192.168.100.98 "chmod +x /tmp/setup-nfs.sh && sudo /tmp/setup-nfs.sh"

# Verify NFS exports are working correctly
ssh 192.168.100.98 "showmount -e localhost"
```

Expected output should show the following exports:
```
/data/prometheus *
/data/grafana *
/data/alertmanager-0 *
/data/alertmanager-1 *
```

### 2. Set Up NFS Client on Kubernetes Nodes

Each Kubernetes node needs to be able to mount the NFS shares.

```bash
# Run the NFS client setup script on your Kubernetes node(s)
# If you have multiple nodes, run this on each one
./scripts/setup-nfs-client.sh
```

### 3. Create Storage Resources in Kubernetes

```bash
# Create the monitoring namespace
kubectl apply -f k8s/core/monitoring-namespaces.yaml

# Create the PersistentVolumes for Prometheus, Grafana, and Alertmanager
kubectl apply -f k8s/core/monitoring-storage.yaml

# Verify that the PVs were created correctly
kubectl get pv
```

### 4. Install Prometheus Stack with Helm

```bash
# Add the Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install the Prometheus stack (includes Prometheus, Grafana, and Alertmanager)
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f k8s/helm/prometheus/values.yaml

# Wait for all pods to be running
kubectl get pods -n monitoring --watch
```

### 5. Verify and Access Services

Run the verification script to check that everything is working properly:

```bash
./scripts/verify-exposure.sh
```

The script will output the URLs you can use to access your services. Typically, you can access:

- Prometheus: http://prometheus.192.168.100.202.nip.io
- Grafana: http://grafana.192.168.100.202.nip.io (default credentials: admin/admin)
- Alertmanager: http://alertmanager.192.168.100.202.nip.io

> **Note**: The IP address in the URLs should match the external IP of your NGINX Ingress Controller. The script will show you the correct address.

### 6. Troubleshooting PVC Binding Issues

If PVCs remain in a "Pending" state, follow these steps:

1. Verify NFS server is running on the host:
   ```bash
   ssh 192.168.100.98 "sudo systemctl status nfs-kernel-server"
   ```

2. Check that exports are correctly configured:
   ```bash
   ssh 192.168.100.98 "sudo cat /etc/exports"
   ssh 192.168.100.98 "sudo exportfs -v"
   ```

3. Test NFS mounting from a Kubernetes node:
   ```bash
   mkdir -p /tmp/nfs-test
   sudo mount -t nfs 192.168.100.98:/data/prometheus /tmp/nfs-test
   # If successful
   sudo umount /tmp/nfs-test
   rmdir /tmp/nfs-test
   ```

4. Check PV and PVC status:
   ```bash
   kubectl get pv
   kubectl get pvc -n monitoring
   kubectl describe pvc <pvc-name> -n monitoring
   ```

5. For Alertmanager specific issues, ensure directories exist and have correct permissions:
   ```bash
   ssh 192.168.100.98 "ls -la /data/alertmanager-0 /data/alertmanager-1"
   ssh 192.168.100.98 "sudo chmod -R 777 /data/alertmanager-0 /data/alertmanager-1"
   ```

### 7. Updating Configuration

If you need to update the Prometheus stack configuration:

```bash
# Edit the values file
vi k8s/helm/prometheus/values.yaml

# Apply changes with Helm upgrade
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f k8s/helm/prometheus/values.yaml
```

### Important Notes

- The default Grafana credentials are admin/admin. Change these in production!
- The nip.io domain service is used for easy access. It automatically resolves domains like `prometheus.192.168.100.202.nip.io` to the IP address `192.168.100.202`.
- For production environments, consider using more restrictive permissions on the NFS shares than the current 777.
- Make sure your firewall allows traffic to ports 80 and 443 on your ingress controller's IP address.

## Exposing Services to Local Network

This guide explains how to expose Kubernetes services to your local network, making them accessible from any device on your network.

### Prerequisites

- A functioning Kubernetes cluster
- MetalLB installed and configured (see Core Components Installation section)
- NGINX Ingress Controller installed (see Core Components Installation section)

### 1. Understanding the Components

The process of exposing services in this homelab relies on three key components:

1. **MetalLB**: Provides LoadBalancer service functionality with real IPs from your local network
2. **NGINX Ingress Controller**: Routes external HTTP/HTTPS requests to internal services
3. **nip.io**: A free wildcard DNS service that maps any IP to a hostname

### 2. Configuring MetalLB Address Pool

MetalLB needs to be configured with an address pool from your local network:

```bash
# Check your MetalLB configuration
kubectl get configmap -n metallb-system config -o yaml
```

If you need to modify the IP range, edit the `k8s/core/metallb-config.yaml` file:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.100.200-192.168.100.220  # Adjust this range to fit your network
```

Apply the changes:

```bash
kubectl apply -f k8s/core/metallb-config.yaml
```

### 3. Creating an Ingress Resource

To expose a service, create an Ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-service-ingress
  namespace: my-namespace
  annotations:
    kubernetes.io/ingress.class: nginx
    # Optional: Add TLS or other configurations
    # nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  rules:
  - host: myservice.192.168.100.202.nip.io  # Replace IP with your ingress controller's external IP
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

Save this to a file (e.g., `my-service-ingress.yaml`) and apply it:

```bash
kubectl apply -f my-service-ingress.yaml
```

### 4. Determining Your Ingress Controller's External IP

To find the external IP assigned to your NGINX Ingress Controller:

```bash
kubectl get service -n ingress-nginx ingress-nginx-controller
```

Look for the `EXTERNAL-IP` column. This IP will be used in your nip.io hostnames.

### 5. Accessing Your Services

Services can now be accessed using the nip.io domain format:

```
http://[service-name].[ingress-controller-ip].nip.io
```

For example:
- http://myservice.192.168.100.202.nip.io

### 6. Exposing Non-HTTP Services

For services that don't use HTTP (like databases or message brokers):

1. Create a LoadBalancer service that directly exposes the port:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kafka-external
  namespace: kafka
spec:
  type: LoadBalancer
  ports:
  - port: 9092
    targetPort: 9092
    protocol: TCP
    name: kafka
  selector:
    app: kafka
```

2. Apply the configuration:

```bash
kubectl apply -f kafka-external-service.yaml
```

3. Get the assigned external IP:

```bash
kubectl get svc -n kafka kafka-external
```

You can then connect to the service using the assigned external IP and port.

### 7. Verifying Exposure

Run the verification script to check your exposed services:

```bash
./scripts/verify-exposure.sh
```

### Troubleshooting

1. **Service not accessible:**
   - Check if the ingress resource was created correctly: `kubectl get ingress -n <namespace>`
   - Verify that the ingress controller's external IP is reachable from your network
   - Check ingress controller logs: `kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx`

2. **DNS resolution issues:**
   - Ensure you're using the correct IP address in the nip.io hostname
   - Try accessing the service directly via IP if nip.io is not working

3. **MetalLB issues:**
   - Check MetalLB speaker pods: `kubectl get pods -n metallb-system`
   - View logs: `kubectl logs -n metallb-system -l app=metallb`

4. **Port conflicts:**
   - Ensure no other services on your network are using the same ports
   - Check firewall rules on your router and hosts
