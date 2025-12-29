#!/bin/bash
# Install complete Helm-based application stack
set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Verify kubectl
command -v kubectl &>/dev/null || { echo "Error: kubectl not installed"; exit 1; }
kubectl cluster-info &>/dev/null || { echo "Error: Not connected to cluster"; exit 1; }

# Install Helm if needed
if ! command -v helm &>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash 2>&1 | grep -i error || true
fi

# Create namespaces
kubectl apply -f "$REPO_ROOT/k8s/core/namespaces/" 2>&1 | grep -iE "error|created|configured" || true

# Install MetalLB
METALLB_VERSION="v0.14.9"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml 2>&1 | grep -iE "error|created|configured" || true

if ! kubectl get secret memberlist -n metallb-system &>/dev/null; then
    kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)" 2>&1 | grep -i error || true
fi

kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=120s 2>&1 | grep -iE "error|met" || true
kubectl apply -f "$REPO_ROOT/k8s/core/networking/metallb-config.yaml" 2>&1 | grep -iE "error|created|configured" || true

# Add Helm repos
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

# Install NFS provisioner
if [ ! -f "$REPO_ROOT/k8s/helm/nfs-provisioner/values.yaml" ]; then
    echo "Error: NFS provisioner values not found"
    exit 1
fi
helm upgrade --install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    -n kube-system -f "$REPO_ROOT/k8s/helm/nfs-provisioner/values.yaml" 2>&1 | grep -iE "error|deployed" || true

# Install NGINX Ingress
if [ ! -f "$REPO_ROOT/k8s/helm/ingress-nginx/values.yaml" ]; then
    echo "Error: Ingress NGINX values not found"
    exit 1
fi
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    -n ingress-nginx -f "$REPO_ROOT/k8s/helm/ingress-nginx/values.yaml" 2>&1 | grep -iE "error|deployed" || true

kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s 2>&1 | grep -iE "error|met" || true

# Get external IP
EXTERNAL_IP=""
timeout=60
while [ $timeout -gt 0 ]; do
    EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    [ -n "$EXTERNAL_IP" ] && break
    sleep 2
    ((timeout-=2))
done

if [ -z "$EXTERNAL_IP" ]; then
    echo "Warning: Could not detect external IP, using placeholder"
    EXTERNAL_IP="192.168.100.200"
fi

# Update Prometheus values with external IP
if [ -f "$REPO_ROOT/k8s/helm/prometheus/values.yaml" ]; then
    sed -i "s/hosts:/hosts:\n      - \"prometheus.${EXTERNAL_IP}.nip.io\"/" "$REPO_ROOT/k8s/helm/prometheus/values.yaml" 2>/dev/null || true
fi

# Install Prometheus Stack
if [ ! -f "$REPO_ROOT/k8s/helm/prometheus/values.yaml" ]; then
    echo "Error: Prometheus values not found"
    exit 1
fi
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    -n monitoring -f "$REPO_ROOT/k8s/helm/prometheus/values.yaml" 2>&1 | grep -iE "error|deployed" || true

# Summary
echo ""
echo "=== Helm Charts Installation Complete ==="
kubectl get pods -A | grep -E "NAME|metallb|ingress|prometheus|grafana|nfs"
echo ""
echo "External IP: $EXTERNAL_IP"
echo "Prometheus: http://prometheus.${EXTERNAL_IP}.nip.io"
echo "Grafana: http://grafana.${EXTERNAL_IP}.nip.io"
echo "Alertmanager: http://alertmanager.${EXTERNAL_IP}.nip.io"
echo ""
echo "Verify: ./scripts/common/verify-exposure.sh"
