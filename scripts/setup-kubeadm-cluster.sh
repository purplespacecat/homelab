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
POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-10.244.0.0/16}"
CONTROL_PLANE="${CONTROL_PLANE:-false}"
CNI_PLUGIN="${CNI_PLUGIN:-calico}" # calico, flannel, or cilium

echo_info "Starting kubeadm cluster setup..."
echo_info "Kubernetes version: ${KUBERNETES_VERSION}"
echo_info "Pod network CIDR: ${POD_NETWORK_CIDR}"
echo_info "Control plane: ${CONTROL_PLANE}"
echo_info "CNI plugin: ${CNI_PLUGIN}"

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
# 7. Initialize Control Plane (if applicable)
# ========================================
if [ "$CONTROL_PLANE" = "true" ]; then
    echo_info "Initializing control plane..."

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
    # 8. Install CNI Plugin
    # ========================================
    echo_info "Installing CNI plugin: ${CNI_PLUGIN}..."

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

    # Generate join command
    echo_info "Generating worker node join command..."
    kubeadm token create --print-join-command > /tmp/kubeadm-join-command.sh
    chmod +x /tmp/kubeadm-join-command.sh

    echo_info "Control plane initialization complete!"
    echo_info "Join command saved to: /tmp/kubeadm-join-command.sh"
    echo_info ""
    echo_info "To join worker nodes, run the following on each worker:"
    cat /tmp/kubeadm-join-command.sh

else
    echo_info "Worker node prerequisites installed."
    echo_info "To join this node to a cluster, run:"
    echo_info "  sudo kubeadm join <control-plane-host>:<port> --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
fi

echo_info ""
echo_info "Setup complete! ✓"

# Print status
if [ "$CONTROL_PLANE" = "true" ]; then
    echo_info ""
    echo_info "Cluster status:"
    sleep 5
    kubectl get nodes
    kubectl get pods -A
fi
