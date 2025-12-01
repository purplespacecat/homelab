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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo_error "Please run as root or with sudo"
    exit 1
fi

# Confirmation prompt
FORCE="${FORCE:-false}"
if [ "$FORCE" != "true" ]; then
    echo_warn "This will completely remove the Kubernetes cluster from this node."
    echo_warn "This action cannot be undone!"
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo_info "Teardown cancelled."
        exit 0
    fi
fi

echo_info "Starting kubeadm cluster teardown..."

# ========================================
# 1. Drain and Delete Node (if part of cluster)
# ========================================
if command -v kubectl &> /dev/null && [ -f /etc/kubernetes/admin.conf ]; then
    echo_info "Attempting to drain node..."
    NODE_NAME=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || hostname)

    kubectl --kubeconfig=/etc/kubernetes/admin.conf drain "$NODE_NAME" \
        --delete-emptydir-data \
        --force \
        --ignore-daemonsets 2>/dev/null || echo_warn "Could not drain node (might not be in cluster)"

    kubectl --kubeconfig=/etc/kubernetes/admin.conf delete node "$NODE_NAME" 2>/dev/null || echo_warn "Could not delete node (might not be in cluster)"
fi

# ========================================
# 2. Reset kubeadm
# ========================================
echo_info "Resetting kubeadm..."
kubeadm reset -f || echo_warn "kubeadm reset failed or not needed"

# ========================================
# 3. Stop and Disable Services
# ========================================
echo_info "Stopping services..."
systemctl stop kubelet 2>/dev/null || true
systemctl disable kubelet 2>/dev/null || true

# ========================================
# 4. Remove Kubernetes Packages
# ========================================
echo_info "Removing Kubernetes packages..."
apt-mark unhold kubelet kubeadm kubectl 2>/dev/null || true
apt-get purge -y kubelet kubeadm kubectl 2>/dev/null || true
apt-get autoremove -y

# ========================================
# 5. Clean up Kubernetes Directories
# ========================================
echo_info "Cleaning up Kubernetes directories..."
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /var/lib/etcd
rm -rf /etc/cni/net.d
rm -rf /opt/cni/bin
rm -rf /var/lib/cni
rm -rf ~/.kube
rm -rf /tmp/kubeadm-join-command.sh

# Clean up user kubeconfig if SUDO_USER is set
if [ -n "$SUDO_USER" ]; then
    SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    rm -rf "$SUDO_USER_HOME/.kube"
    echo_info "Removed kubeconfig from $SUDO_USER_HOME/.kube"
fi

# ========================================
# 6. Remove Kubernetes Repository
# ========================================
echo_info "Removing Kubernetes repository..."
rm -f /etc/apt/sources.list.d/kubernetes.list
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# ========================================
# 7. Clean up Container Runtime (containerd)
# ========================================
echo_info "Cleaning up containerd..."

# Stop containerd
systemctl stop containerd 2>/dev/null || true

# Remove containers and images
if command -v crictl &> /dev/null; then
    echo_info "Removing all containers and images..."
    crictl rm $(crictl ps -aq) 2>/dev/null || true
    crictl rmi $(crictl images -q) 2>/dev/null || true
fi

# Clean containerd data
rm -rf /var/lib/containerd

# Restart containerd to clean state
systemctl start containerd 2>/dev/null || true

# ========================================
# 8. Clean up iptables Rules
# ========================================
echo_info "Cleaning up iptables rules..."
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X 2>/dev/null || true
ip6tables -F && ip6tables -t nat -F && ip6tables -t mangle -F && ip6tables -X 2>/dev/null || true

# ========================================
# 9. Remove CNI Network Interfaces
# ========================================
echo_info "Removing CNI network interfaces..."
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true
ip link delete tunl0 2>/dev/null || true
ip link delete cilium_host 2>/dev/null || true
ip link delete cilium_net 2>/dev/null || true
ip link delete cilium_vxlan 2>/dev/null || true

# Remove all veth pairs
for iface in $(ip link show | grep -oP 'veth\w+'); do
    ip link delete "$iface" 2>/dev/null || true
done

# ========================================
# 10. Clean up ipvs
# ========================================
if command -v ipvsadm &> /dev/null; then
    echo_info "Cleaning up ipvs..."
    ipvsadm -C 2>/dev/null || true
fi

# ========================================
# 11. Remove sysctl configurations
# ========================================
echo_info "Removing Kubernetes sysctl configurations..."
rm -f /etc/sysctl.d/k8s.conf
sysctl --system >/dev/null 2>&1

# ========================================
# 12. Remove kernel modules configuration
# ========================================
echo_info "Removing kernel modules configuration..."
rm -f /etc/modules-load.d/k8s.conf

# ========================================
# 13. Update package cache
# ========================================
echo_info "Updating package cache..."
apt-get update

echo_info ""
echo_info "Teardown complete! ✓"
echo_info ""
echo_info "The following have been REMOVED:"
echo_info "  - Kubernetes cluster configuration"
echo_info "  - kubeadm, kubelet, kubectl packages"
echo_info "  - All pods, containers, and images"
echo_info "  - CNI network interfaces"
echo_info "  - Kubernetes iptables rules"
echo_info ""
echo_info "The following have been PRESERVED:"
echo_info "  - containerd (cleaned but still installed)"
echo_info "  - System prerequisites (curl, ca-certificates, etc.)"
echo_info "  - Kernel modules (overlay, br_netfilter)"
echo_info ""
echo_warn "Note: Swap is still disabled. To re-enable, edit /etc/fstab and run 'swapon -a'"
