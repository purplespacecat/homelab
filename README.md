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
