#!/bin/bash
# Consolidated master node setup script
# This script combines: setup-kubeadm-cluster.sh (CONTROL_PLANE=true) + fix-master-node-firewall.sh
# It initializes a Kubernetes master/control-plane node with all necessary components and firewall rules

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
POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-10.244.0.0/16}"
CNI_PLUGIN="${CNI_PLUGIN:-calico}"

echo_section "Master Node Complete Setup"
echo_info "Kubernetes version: ${KUBERNETES_VERSION}"
echo_info "Pod network CIDR: ${POD_NETWORK_CIDR}"
echo_info "CNI plugin: ${CNI_PLUGIN}"
echo ""

# ========================================
# PART 1: KUBERNETES PREREQUISITES
# ========================================
echo_section "Part 1: Installing Prerequisites"

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
    ipset

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

    # Allow HTTP from anywhere
    echo_info "Opening HTTP port (80)..."
    ufw allow 80/tcp

    # Allow HTTPS from anywhere
    echo_info "Opening HTTPS port (443)..."
    ufw allow 443/tcp

    # Allow MetalLB speaker coordination
    echo_info "Opening MetalLB speaker coordination port (7946)..."
    ufw allow from 192.168.100.0/24 to any port 7946

    # Allow NodePort range
    echo_info "Opening NodePort range (30000-32767)..."
    ufw allow 30000:32767/tcp

    # Reload UFW
    echo_info "Reloading UFW..."
    ufw reload

    echo_info "Firewall configuration complete!"
fi

# ========================================
# PART 6: INITIALIZE CONTROL PLANE
# ========================================
echo_section "Part 6: Initializing Control Plane"

kubeadm init \
    --pod-network-cidr="${POD_NETWORK_CIDR}" \
    --kubernetes-version="$(kubeadm version -o short)" \
    --v=5

# Setup kubeconfig for root user
export KUBECONFIG=/etc/kubernetes/admin.conf

# Also setup for regular user if SUDO_USER is set
if [ -n "$SUDO_USER" ]; then
    SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    mkdir -p "$SUDO_USER_HOME/.kube"
    cp -i /etc/kubernetes/admin.conf "$SUDO_USER_HOME/.kube/config"
    chown -R "$SUDO_USER:$SUDO_USER" "$SUDO_USER_HOME/.kube"
    echo_info "Kubeconfig copied to $SUDO_USER_HOME/.kube/config"
fi

# ========================================
# PART 7: INSTALL CNI PLUGIN
# ========================================
echo_section "Part 7: Installing CNI Plugin (${CNI_PLUGIN})"

case "$CNI_PLUGIN" in
    calico)
        kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
        ;;
    flannel)
        kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
        ;;
    cilium)
        # Install Cilium CLI
        CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
        CLI_ARCH=amd64
        if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
        curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
        sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
        tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
        rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

        # Install Cilium
        cilium install
        ;;
    *)
        echo_warn "Unknown CNI plugin: ${CNI_PLUGIN}. Skipping CNI installation."
        ;;
esac

# ========================================
# PART 8: GENERATE JOIN COMMAND
# ========================================
echo_section "Part 8: Generating Worker Join Command"

kubeadm token create --print-join-command > /tmp/kubeadm-join-command.sh
chmod +x /tmp/kubeadm-join-command.sh

# ========================================
# FINAL VERIFICATION
# ========================================
echo_section "Setup Complete - Verification"

echo_info "Waiting for cluster to stabilize..."
sleep 5

echo_info "Cluster Nodes:"
kubectl get nodes

echo ""
echo_info "System Pods:"
kubectl get pods -A

if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    echo ""
    echo_info "UFW status: active"
    echo_info "Open ports:"
    ufw status numbered | grep -E "(80|443|7946|30000:32767)" | head -10 || echo "  (firewall rules configured)"
fi

echo ""
echo_section "Master Node Ready!"
echo ""
echo_info "Join command saved to: /tmp/kubeadm-join-command.sh"
echo_info ""
echo_info "To join worker nodes, run the following on each worker:"
echo ""
cat /tmp/kubeadm-join-command.sh
echo ""
echo_info "Next steps:"
echo_info "  1. Join worker nodes using the command above"
echo_info "  2. Install MetalLB: kubectl apply -f k8s/core/networking/metallb-config.yaml"
echo_info "  3. Install application stack: ./scripts/install-helm-charts.sh"
echo ""
