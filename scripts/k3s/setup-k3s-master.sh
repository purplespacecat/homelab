#!/bin/bash
# K3s master/server node setup
set -e

[ "$EUID" -ne 0 ] && { echo "Error: Run as root"; exit 1; }

K3S_VERSION="${K3S_VERSION:-}"  # Default to latest version
INSTALL_K3S_EXEC="${INSTALL_K3S_EXEC:---disable traefik --disable servicelb --write-kubeconfig-mode 644}"

# Install k3s server (latest version unless K3S_VERSION is set)
if [ -n "$K3S_VERSION" ]; then
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" INSTALL_K3S_EXEC="$INSTALL_K3S_EXEC" sh - 2>&1 | grep -i error || true
else
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="$INSTALL_K3S_EXEC" sh - 2>&1 | grep -i error || true
fi

# Wait for k3s to be ready
timeout=60
while [ $timeout -gt 0 ]; do
    if systemctl is-active --quiet k3s && kubectl get nodes &>/dev/null; then
        break
    fi
    sleep 2
    ((timeout-=2))
done

if ! systemctl is-active --quiet k3s; then
    echo "Error: k3s failed to start"
    systemctl status k3s --no-pager
    exit 1
fi

# Setup kubeconfig for sudo user
if [ -n "$SUDO_USER" ]; then
    SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    mkdir -p "$SUDO_USER_HOME/.kube"
    cp /etc/rancher/k3s/k3s.yaml "$SUDO_USER_HOME/.kube/config"
    chown -R "$SUDO_USER:$SUDO_USER" "$SUDO_USER_HOME/.kube"
fi

# Generate join token
K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
K3S_URL="https://$(hostname -I | awk '{print $1}'):6443"

# Save join command
cat > /tmp/k3s-join-command.sh <<EOF
#!/bin/bash
curl -sfL https://get.k3s.io | K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh -
EOF
chmod +x /tmp/k3s-join-command.sh

# Summary
echo ""
echo "=== K3s Master Setup Complete ==="
kubectl get nodes
echo ""
echo "Join command saved to: /tmp/k3s-join-command.sh"
echo "Token: $K3S_TOKEN"
echo "Server URL: $K3S_URL"
