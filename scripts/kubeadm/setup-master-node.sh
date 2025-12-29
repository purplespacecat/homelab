#!/bin/bash
# Kubeadm master/control-plane node setup
set -e

[ "$EUID" -ne 0 ] && { echo "Error: Run as root"; exit 1; }

KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.28}"
POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-10.244.0.0/16}"
CNI_PLUGIN="${CNI_PLUGIN:-calico}"

# Update and install prerequisites
apt-get update -qq
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release socat conntrack ipset 2>&1 | grep -i error || true

# Disable swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Load kernel modules
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Configure sysctl
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

# Install containerd
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq containerd.io 2>&1 | grep -i error || true

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd >/dev/null 2>&1

# Install Kubernetes components
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl 2>&1 | grep -i error || true
apt-mark hold kubelet kubeadm kubectl >/dev/null
systemctl enable kubelet >/dev/null 2>&1

# Configure firewall
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow 80/tcp >/dev/null
    ufw allow 443/tcp >/dev/null
    ufw allow from 192.168.100.0/24 to any port 7946 >/dev/null
    ufw allow 30000:32767/tcp >/dev/null
    ufw reload >/dev/null
fi

# Initialize control plane
kubeadm init --pod-network-cidr="${POD_NETWORK_CIDR}" --kubernetes-version="$(kubeadm version -o short)" 2>&1 | grep -iE "error|kubeadm join" || true

# Setup kubeconfig
export KUBECONFIG=/etc/kubernetes/admin.conf
if [ -n "$SUDO_USER" ]; then
    SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    mkdir -p "$SUDO_USER_HOME/.kube"
    cp /etc/kubernetes/admin.conf "$SUDO_USER_HOME/.kube/config"
    chown -R "$SUDO_USER:$SUDO_USER" "$SUDO_USER_HOME/.kube"
fi

# Install CNI plugin
case "$CNI_PLUGIN" in
    calico)
        kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml 2>&1 | grep -i error || true
        ;;
    flannel)
        kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml 2>&1 | grep -i error || true
        ;;
    cilium)
        CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
        CLI_ARCH=amd64
        [ "$(uname -m)" = "aarch64" ] && CLI_ARCH=arm64
        curl -sL --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
        sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum 2>&1 | grep -v OK || true
        tar xzf cilium-linux-${CLI_ARCH}.tar.gz -C /usr/local/bin
        rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
        cilium install 2>&1 | grep -i error || true
        ;;
esac

# Generate join command
kubeadm token create --print-join-command > /tmp/kubeadm-join-command.sh
chmod +x /tmp/kubeadm-join-command.sh

# Wait for cluster to stabilize
sleep 5

# Summary
echo ""
echo "=== Kubeadm Master Setup Complete ==="
kubectl get nodes 2>&1 || echo "Error: kubectl not accessible"
echo ""
echo "Join command: /tmp/kubeadm-join-command.sh"
cat /tmp/kubeadm-join-command.sh
echo ""
echo "Next steps:"
echo "  1. Join worker nodes"
echo "  2. kubectl apply -f k8s/core/networking/metallb-config.yaml"
echo "  3. ./scripts/install-helm-charts.sh"
