#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
CALICO_VERSION="${CALICO_VERSION:-v3.27.0}"
POD_CIDR="${POD_CIDR:-192.168.0.0/16}"
MANIFEST_URL="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
TEMP_MANIFEST="/tmp/calico-manifest.yaml"

echo_info "Installing Calico CNI Plugin"
echo_info "Version: ${CALICO_VERSION}"
echo_info "Pod CIDR: ${POD_CIDR}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo_error "kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo_error "Cannot connect to Kubernetes cluster. Is the cluster running?"
    exit 1
fi

# ========================================
# 1. Download Calico Manifest
# ========================================
echo_info "Downloading Calico manifest from ${MANIFEST_URL}..."
curl -sSL "${MANIFEST_URL}" -o "${TEMP_MANIFEST}"

if [ ! -f "${TEMP_MANIFEST}" ]; then
    echo_error "Failed to download Calico manifest"
    exit 1
fi

echo_info "Manifest downloaded successfully"

# ========================================
# 2. Modify CIDR if not default
# ========================================
if [ "${POD_CIDR}" != "192.168.0.0/16" ]; then
    echo_info "Customizing Pod CIDR to ${POD_CIDR}..."

    # Uncomment and modify the CALICO_IPV4POOL_CIDR
    sed -i '/# - name: CALICO_IPV4POOL_CIDR/,/# value: "192.168.0.0\/16"/ {
        s/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/
        s@# value: "192.168.0.0/16"@value: "'"${POD_CIDR}"'"@
    }' "${TEMP_MANIFEST}"

    echo_info "CIDR configuration updated"
else
    echo_info "Using default Calico CIDR (192.168.0.0/16)"

    # Even with default, we should uncomment the CIDR settings for explicitness
    sed -i '/# - name: CALICO_IPV4POOL_CIDR/,/# value: "192.168.0.0\/16"/ {
        s/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/
        s@# value: "192.168.0.0/16"@value: "192.168.0.0/16"@
    }' "${TEMP_MANIFEST}"
fi

# ========================================
# 3. Apply Calico Manifest
# ========================================
echo_info "Applying Calico manifest to cluster..."
kubectl apply -f "${TEMP_MANIFEST}"

# ========================================
# 4. Wait for Calico to be Ready
# ========================================
echo_info "Waiting for Calico pods to be ready..."
echo_info "This may take a few minutes..."

# Wait for calico-kube-controllers deployment
kubectl wait --for=condition=available --timeout=300s \
    deployment/calico-kube-controllers -n kube-system || {
    echo_warn "Timeout waiting for calico-kube-controllers. Checking status..."
}

# Wait for calico-node daemonset
kubectl rollout status daemonset/calico-node -n kube-system --timeout=300s || {
    echo_warn "Timeout waiting for calico-node. Checking status..."
}

# ========================================
# 5. Verify Installation
# ========================================
echo_info "Verifying Calico installation..."

# Check if all Calico pods are running
CALICO_PODS=$(kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers 2>/dev/null | wc -l)
CALICO_RUNNING=$(kubectl get pods -n kube-system -l k8s-app=calico-node --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

echo_info "Calico node pods: ${CALICO_RUNNING}/${CALICO_PODS} running"

CONTROLLER_PODS=$(kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers --no-headers 2>/dev/null | wc -l)
CONTROLLER_RUNNING=$(kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

echo_info "Calico controller pods: ${CONTROLLER_RUNNING}/${CONTROLLER_PODS} running"

# ========================================
# 6. Display Status
# ========================================
echo_info ""
echo_info "Calico installation complete! ✓"
echo_info ""
echo_info "Current status:"
kubectl get pods -n kube-system -l 'k8s-app in (calico-node,calico-kube-controllers)'

echo_info ""
echo_info "To verify your nodes are ready:"
echo_info "  kubectl get nodes"
echo_info ""
echo_info "To check Calico network status:"
echo_info "  kubectl get pods -n kube-system -l k8s-app=calico-node"

# Clean up
rm -f "${TEMP_MANIFEST}"
echo_info ""
echo_info "Temporary manifest cleaned up"
