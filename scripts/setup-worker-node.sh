#!/bin/bash
# Consolidated worker node setup script
# This script combines: prepare-worker-node.sh + fix-worker-node-firewall.sh
# It prepares a worker node with all necessary components and firewall rules

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

echo_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo_error "Please run as root or with sudo"
    exit 1
fi

# Configuration
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.28}"

echo_section "Worker Node Complete Setup"
echo_info "Kubernetes version: ${KUBERNETES_VERSION}"
echo ""

# ========================================
# PART 1: KUBERNETES PREREQUISITES
# ========================================
echo_section "Part 1: Installing Kubernetes Prerequisites"

# Update package index
echo_info "Updating package index..."
apt-get update

# Install required packages
echo_info "Installing required packages..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    socat \
    conntrack \
    ipset \
    nfs-common

# ========================================
# PART 2: SYSTEM CONFIGURATION
# ========================================
echo_section "Part 2: System Configuration"

# Disable Swap
echo_info "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Load Kernel Modules
echo_info "Loading kernel modules..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Configure Sysctl Parameters
echo_info "Configuring sysctl parameters..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# ========================================
# PART 3: INSTALL CONTAINERD
# ========================================
echo_section "Part 3: Installing containerd"

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
# PART 4: INSTALL KUBERNETES COMPONENTS
# ========================================
echo_section "Part 4: Installing Kubernetes Components"

# Add Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

# ========================================
# PART 5: CONFIGURE FIREWALL
# ========================================
echo_section "Part 5: Configuring Firewall"

# Check if UFW is installed and active
if ! command -v ufw &>/dev/null; then
    echo_warn "UFW is not installed. Skipping firewall configuration."
elif ! ufw status | grep -q "Status: active"; then
    echo_warn "UFW is not active. Skipping firewall configuration."
else
    echo_info "UFW is active. Opening required ports..."

    # Allow kubelet API from local network
    echo_info "Opening kubelet API port (10250)..."
    ufw allow from 192.168.100.0/24 to any port 10250 proto tcp

    # Allow kube-proxy health check
    echo_info "Opening kube-proxy port (10256)..."
    ufw allow from 192.168.100.0/24 to any port 10256 proto tcp

    # Allow NodePort range
    echo_info "Opening NodePort range (30000-32767)..."
    ufw allow 30000:32767/tcp

    # Reload UFW
    echo_info "Reloading UFW..."
    ufw reload

    echo_info "Firewall configuration complete!"
fi

# ========================================
# FINAL VERIFICATION
# ========================================
echo_section "Setup Complete - Verification"

echo_info "Kubernetes version: $(kubeadm version -o short)"
echo_info "containerd status: $(systemctl is-active containerd)"
echo_info "kubelet status: $(systemctl is-enabled kubelet)"

if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    echo_info "UFW status: active"
    echo ""
    echo_info "Open ports:"
    ufw status numbered | grep -E "(10250|10256|30000:32767)" || echo "  (firewall rules configured)"
fi

echo ""
echo_section "Worker Node Ready!"
echo ""
echo_info "This node is now ready to join a Kubernetes cluster."
echo_info "To join this node to your cluster, use the join-worker-node.sh script"
echo_info "or run the kubeadm join command from your control plane:"
echo ""
echo_info "  sudo kubeadm join <control-plane-host>:<port> --token <token> \\"
echo_info "    --discovery-token-ca-cert-hash sha256:<hash>"
echo ""
echo_info "Test kubelet connectivity from control plane with:"
echo_info "  nc -zv <THIS_NODE_IP> 10250"
echo ""
