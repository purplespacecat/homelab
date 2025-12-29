#!/bin/bash
# Install complete Helm-based application stack
set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Verify kubectl
command -v kubectl &>/dev/null || {
  echo "Error: kubectl not installed"
  exit 1
}
kubectl cluster-info &>/dev/null || {
  echo "Error: Not connected to cluster"
  exit 1
}

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
#if [ ! -f "$REPO_ROOT/k8s/helm/nfs-provisioner/values.yaml" ]; then
#   echo "Error: NFS provisioner values not found"
#  exit 1
#fi
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

# Get node IP for hostNetwork mode (ingress-nginx binds directly to node IP)
# This is more reliable than MetalLB L2 mode which doesn't work well on WiFi
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
if [ -z "$NODE_IP" ]; then
  echo "Warning: Could not detect node IP, using fallback"
  NODE_IP="192.168.100.98"
fi
EXTERNAL_IP="$NODE_IP"

# Install Prometheus Stack
if [ ! -f "$REPO_ROOT/k8s/helm/prometheus/values.yaml" ]; then
  echo "Error: Prometheus values not found"
  exit 1
fi

# Ensure monitoring namespace exists
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - &>/dev/null || true

# Create Grafana admin credentials secret if it doesn't exist
if ! kubectl get secret grafana-admin-credentials -n monitoring &>/dev/null; then
  echo "Creating Grafana admin credentials secret..."
  GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 20)
  kubectl create secret generic grafana-admin-credentials -n monitoring \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" 2>&1 | grep -i error || true
  echo "Grafana credentials - Username: admin, Password: $GRAFANA_ADMIN_PASSWORD"
fi

# Create Prometheus Operator admission webhook TLS secret if it doesn't exist
# Even though webhooks are disabled, the operator requires valid TLS certs for its web server
if ! kubectl get secret prometheus-kube-prometheus-admission -n monitoring &>/dev/null; then
  echo "Creating Prometheus Operator TLS certificates..."
  openssl req -x509 -newkey rsa:2048 -keyout /tmp/prom-key.pem -out /tmp/prom-cert.pem \
    -days 365 -nodes -subj "/CN=prometheus-kube-prometheus-admission.monitoring.svc" &>/dev/null
  kubectl create secret generic prometheus-kube-prometheus-admission -n monitoring \
    --from-file=cert=/tmp/prom-cert.pem \
    --from-file=key=/tmp/prom-key.pem 2>&1 | grep -i error || true
  rm -f /tmp/prom-cert.pem /tmp/prom-key.pem
fi

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring -f "$REPO_ROOT/k8s/helm/prometheus/values.yaml" 2>&1 | grep -iE "error|deployed" || true

# Summary
echo ""
echo "=== Helm Charts Installation Complete ==="
kubectl get pods -A | grep -E "NAME|metallb|ingress|prometheus|grafana|nfs"
echo ""
echo "Node IP: $EXTERNAL_IP"
echo "Prometheus: http://prometheus.${EXTERNAL_IP}.nip.io"
echo "Grafana: http://grafana.${EXTERNAL_IP}.nip.io"
echo "Alertmanager: http://alertmanager.${EXTERNAL_IP}.nip.io"
echo ""
echo "Note: Using hostNetwork mode (services bound to node IP on ports 80/443)"
echo ""
echo "=== Grafana Credentials ==="
if kubectl get secret grafana-admin-credentials -n monitoring &>/dev/null; then
  GRAFANA_USER=$(kubectl get secret grafana-admin-credentials -n monitoring -o jsonpath='{.data.admin-user}' | base64 -d)
  GRAFANA_PASS=$(kubectl get secret grafana-admin-credentials -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)
  echo "Username: $GRAFANA_USER"
  echo "Password: $GRAFANA_PASS"
fi
echo ""
echo "Verify: ./scripts/common/verify-exposure.sh"
