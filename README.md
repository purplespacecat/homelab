# This repo contains files and scripts that I use for my k8s homelab
|Folder|Description|
| ----------- | ----------- |
|helm|helm customizations|
|core|configs for core services|

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
