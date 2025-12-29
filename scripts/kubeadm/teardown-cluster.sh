#!/bin/bash
# Remove kubeadm cluster from node
set -e

[ "$EUID" -ne 0 ] && { echo "Error: Run as root"; exit 1; }

FORCE="${FORCE:-false}"
if [ "$FORCE" != "true" ]; then
    read -p "Remove Kubernetes cluster from this node? (yes/no): " -r
    [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]] && { echo "Cancelled"; exit 0; }
fi

# Drain and delete node if part of cluster
if command -v kubectl &>/dev/null && [ -f /etc/kubernetes/admin.conf ]; then
    NODE_NAME=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || hostname)
    kubectl --kubeconfig=/etc/kubernetes/admin.conf drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data --force 2>&1 | grep -i error || true
    kubectl --kubeconfig=/etc/kubernetes/admin.conf delete node "$NODE_NAME" 2>&1 | grep -i error || true
fi

# Reset kubeadm
kubeadm reset -f 2>&1 | grep -i error || true

# Clean up
rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd /etc/cni/net.d ~/.kube
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X 2>/dev/null || true
ipvsadm --clear 2>/dev/null || true

# Stop and disable services
systemctl stop kubelet 2>/dev/null || true
systemctl disable kubelet 2>/dev/null || true

# Remove packages if requested
if [ "${REMOVE_PACKAGES:-false}" = "true" ]; then
    apt-mark unhold kubelet kubeadm kubectl 2>/dev/null || true
    apt-get remove -y --purge kubelet kubeadm kubectl containerd.io 2>&1 | grep -i error || true
    apt-get autoremove -y 2>&1 | grep -i error || true
fi

echo ""
echo "=== Kubeadm Cluster Removed ==="
[ "${REMOVE_PACKAGES:-false}" = "true" ] && echo "Packages removed" || echo "Packages retained (set REMOVE_PACKAGES=true to remove)"
