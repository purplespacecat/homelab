#!/bin/bash
# Install cert-manager for TLS certificate management
set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.13.2}"

command -v kubectl &>/dev/null || { echo "Error: kubectl not installed"; exit 1; }
kubectl cluster-info &>/dev/null || { echo "Error: Not connected to cluster"; exit 1; }

# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml 2>&1 | grep -iE "error|created|configured" || true

# Wait for cert-manager
kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=120s 2>&1 | grep -iE "error|met" || true

# Apply cluster issuers
if [ -f "$REPO_ROOT/k8s/cert-manager/cert-manager-issuers.yaml" ]; then
    kubectl apply -f "$REPO_ROOT/k8s/cert-manager/cert-manager-issuers.yaml" 2>&1 | grep -iE "error|created|configured" || true
fi

# Summary
echo ""
echo "=== Cert-Manager Installation Complete ==="
kubectl get pods -n cert-manager
echo ""
kubectl get clusterissuers
echo ""
echo "To enable HTTPS, add to your Ingress:"
echo '  annotations:'
echo '    cert-manager.io/cluster-issuer: "homelab-ca-issuer"'
echo '  tls:'
echo '    - hosts: [myapp.example.com]'
echo '      secretName: myapp-tls'
