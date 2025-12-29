#!/bin/bash
# Kubeadm worker node setup
set -e

[ "$EUID" -ne 0 ] && { echo "Error: Run as root"; exit 1; }

KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.28}"

# Update and install prerequisites
apt-get update -qq
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release socat conntrack ipset nfs-common 2>&1 | grep -i error || true

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
    ufw allow from 192.168.100.0/24 to any port 10250 proto tcp >/dev/null
    ufw allow from 192.168.100.0/24 to any port 10256 proto tcp >/dev/null
    ufw allow 30000:32767/tcp >/dev/null
    ufw reload >/dev/null
fi

# Summary
echo ""
echo "=== Kubeadm Worker Setup Complete ==="
echo "Kubernetes: $(kubeadm version -o short)"
echo "Containerd: $(systemctl is-active containerd)"
echo "Kubelet: $(systemctl is-enabled kubelet)"
echo ""
echo "Join this node using: ./scripts/kubeadm/join-worker-node.sh"
echo "Or run: sudo kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
