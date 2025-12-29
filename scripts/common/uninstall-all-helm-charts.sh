#!/bin/bash
# Uninstall all Helm charts
set -e

FORCE="${FORCE:-false}"
if [ "$FORCE" != "true" ]; then
    read -p "Uninstall all Helm charts? (yes/no): " -r
    [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]] && { echo "Cancelled"; exit 0; }
fi

command -v helm &>/dev/null || { echo "Error: Helm not installed"; exit 1; }

# Uninstall charts
helm uninstall prometheus -n monitoring 2>&1 | grep -iE "error|uninstalled" || echo "Prometheus not found"
helm uninstall ingress-nginx -n ingress-nginx 2>&1 | grep -iE "error|uninstalled" || echo "Ingress NGINX not found"
helm uninstall nfs-provisioner -n kube-system 2>&1 | grep -iE "error|uninstalled" || echo "NFS provisioner not found"

# Delete cert-manager if installed
if kubectl get namespace cert-manager &>/dev/null; then
    kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml 2>&1 | grep -iE "error|deleted" || true
fi

# Delete MetalLB
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml 2>&1 | grep -iE "error|deleted" || true

echo ""
echo "=== Helm Charts Uninstalled ==="
helm list -A
