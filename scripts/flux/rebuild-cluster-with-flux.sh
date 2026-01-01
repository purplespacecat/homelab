#!/bin/bash
#
# Complete Cluster Rebuild with FluxCD
# This script automates the entire cluster rebuild process using GitOps
#
# Usage:
#   ./rebuild-cluster-with-flux.sh k3s    # For K3s cluster
#   ./rebuild-cluster-with-flux.sh kubeadm # For kubeadm cluster
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CLUSTER_TYPE="${1:-k3s}"

if [ "$CLUSTER_TYPE" != "k3s" ] && [ "$CLUSTER_TYPE" != "kubeadm" ]; then
    echo "Usage: $0 <k3s|kubeadm>"
    echo ""
    echo "Examples:"
    echo "  $0 k3s      # Rebuild with K3s"
    echo "  $0 kubeadm  # Rebuild with kubeadm"
    exit 1
fi

echo "========================================"
echo "Homelab Cluster Rebuild with FluxCD"
echo "========================================"
echo ""
echo "This script will:"
echo "1. Set up a $CLUSTER_TYPE Kubernetes cluster"
echo "2. Install Flux CLI"
echo "3. Bootstrap FluxCD for GitOps"
echo "4. Deploy all infrastructure automatically"
echo ""
echo "⚠️  WARNING: This is meant for initial setup or disaster recovery"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Step 1: Setup Kubernetes Cluster
echo ""
echo "========================================"
echo "Step 1: Setting up $CLUSTER_TYPE cluster"
echo "========================================"
echo ""

if [ "$CLUSTER_TYPE" = "k3s" ]; then
    echo "Running K3s master setup..."
    echo ""
    if [ -f "$REPO_ROOT/scripts/k3s/setup-k3s-master.sh" ]; then
        sudo "$REPO_ROOT/scripts/k3s/setup-k3s-master.sh"
    else
        echo "❌ K3s setup script not found!"
        echo "Expected: $REPO_ROOT/scripts/k3s/setup-k3s-master.sh"
        exit 1
    fi
else
    echo "Running kubeadm master setup..."
    echo ""
    if [ -f "$REPO_ROOT/scripts/kubeadm/setup-master-node.sh" ]; then
        sudo "$REPO_ROOT/scripts/kubeadm/setup-master-node.sh"
    else
        echo "❌ Kubeadm setup script not found!"
        echo "Expected: $REPO_ROOT/scripts/kubeadm/setup-master-node.sh"
        exit 1
    fi
fi

echo ""
echo "✅ Kubernetes cluster setup complete"
echo ""

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
sleep 10

# Verify cluster
if ! kubectl get nodes &> /dev/null; then
    echo "❌ Cannot connect to cluster. Please check the setup."
    exit 1
fi

kubectl get nodes
echo ""

# Step 2: Install Flux CLI
echo ""
echo "========================================"
echo "Step 2: Installing Flux CLI"
echo "========================================"
echo ""

if [ -f "$REPO_ROOT/scripts/flux/install-flux-cli.sh" ]; then
    "$REPO_ROOT/scripts/flux/install-flux-cli.sh"
else
    echo "❌ Flux CLI installation script not found!"
    exit 1
fi

echo ""
echo "✅ Flux CLI installed"
echo ""

# Step 3: Bootstrap FluxCD
echo ""
echo "========================================"
echo "Step 3: Bootstrapping FluxCD"
echo "========================================"
echo ""

if [ -f "$REPO_ROOT/scripts/flux/bootstrap-flux.sh" ]; then
    "$REPO_ROOT/scripts/flux/bootstrap-flux.sh"
else
    echo "❌ Flux bootstrap script not found!"
    exit 1
fi

echo ""
echo "========================================"
echo "✅ Cluster Rebuild Complete!"
echo "========================================"
echo ""
echo "Your homelab cluster is now running with GitOps!"
echo ""
echo "Infrastructure Status:"
echo "  - Kubernetes: $CLUSTER_TYPE"
echo "  - GitOps: FluxCD (active)"
echo "  - Auto-deployment: Enabled"
echo ""
echo "Watch deployment progress:"
echo "  flux get kustomizations -w"
echo "  flux get helmreleases -A"
echo "  kubectl get pods -A"
echo ""
echo "Expected infrastructure (auto-deploying):"
echo "  ✓ NFS Subdir External Provisioner"
echo "  ✓ MetalLB (LoadBalancer)"
echo "  ✓ NGINX Ingress Controller"
echo "  ✓ Cert-Manager (TLS)"
echo "  ✓ Prometheus Stack (Monitoring)"
echo ""
echo "Access services (once deployed):"
echo "  NODE_IP=\$(kubectl get nodes -o wide | tail -1 | awk '{print \$6}')"
echo "  echo \"Prometheus: http://prometheus.\$NODE_IP.nip.io\""
echo "  echo \"Grafana: http://grafana.\$NODE_IP.nip.io\""
echo "  echo \"Alertmanager: http://alertmanager.\$NODE_IP.nip.io\""
echo ""
echo "Documentation:"
echo "  - Managing: docs/managing-with-flux.md"
echo "  - Cheat Sheet: docs/flux-cheatsheet.md"
echo ""
echo "Worker Nodes:"
if [ "$CLUSTER_TYPE" = "k3s" ]; then
    echo "  On each worker, run:"
    echo "    K3S_URL=https://\$(hostname -I | awk '{print \$1}'):6443"
    echo "    K3S_TOKEN=\$(sudo cat /var/lib/rancher/k3s/server/node-token)"
    echo "    echo \"Run on worker: K3S_URL=\$K3S_URL K3S_TOKEN=\$K3S_TOKEN sudo -E ./scripts/k3s/setup-k3s-worker.sh\""
else
    echo "  On each worker, run:"
    echo "    sudo ./scripts/kubeadm/setup-worker-node.sh"
    echo "    sudo ./scripts/kubeadm/join-worker-node.sh"
fi
echo ""
