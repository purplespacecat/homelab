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

# Configuration
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.28}"

echo_info "Starting worker node preparation..."
echo_info "Kubernetes version: ${KUBERNETES_VERSION}"

# ========================================
# 1. Install Prerequisites
# ========================================
echo_info "Installing prerequisites..."

# Update package index
apt-get update

# Install required packages
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    socat \
    conntrack \
    ipset

# ========================================
# 2. Disable Swap
# ========================================
echo_info "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# ========================================
# 3. Load Kernel Modules
# ========================================
echo_info "Loading kernel modules..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# ========================================
# 4. Configure Sysctl Parameters
# ========================================
echo_info "Configuring sysctl parameters..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# ========================================
# 5. Install containerd
# ========================================
echo_info "Installing containerd..."

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y containerd.io

# Configure containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Enable SystemdCgroup
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart containerd
systemctl restart containerd
systemctl enable containerd

# ========================================
# 6. Install kubeadm, kubelet, kubectl
# ========================================
echo_info "Installing kubeadm, kubelet, and kubectl..."

# Add Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

# ========================================
# 7. Verify Installation
# ========================================
echo_info "Verifying installation..."
echo_info "  - Kubernetes version: $(kubeadm version -o short)"
echo_info "  - containerd status: $(systemctl is-active containerd)"
echo_info "  - kubelet status: $(systemctl is-enabled kubelet)"

echo_info ""
echo_info "Worker node preparation complete! ✓"
echo_info ""
echo_info "This node is now ready to join a Kubernetes cluster."
echo_info "To join this node to your cluster, use the join-worker-node.sh script"
echo_info "or run the kubeadm join command from your control plane:"
echo_info ""
echo_info "  sudo kubeadm join <control-plane-host>:<port> --token <token> \\"
echo_info "    --discovery-token-ca-cert-hash sha256:<hash>"
echo_info ""
