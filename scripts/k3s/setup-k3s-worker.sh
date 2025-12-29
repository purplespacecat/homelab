#!/bin/bash
# K3s worker/agent node setup
set -e

[ "$EUID" -ne 0 ] && { echo "Error: Run as root"; exit 1; }

K3S_VERSION="${K3S_VERSION:-v1.28.5+k3s1}"
K3S_URL="${K3S_URL:-}"
K3S_TOKEN="${K3S_TOKEN:-}"

# Validate parameters
if [ -z "$K3S_URL" ] || [ -z "$K3S_TOKEN" ]; then
    echo "Error: K3S_URL and K3S_TOKEN must be set"
    echo "Usage: K3S_URL=https://master-ip:6443 K3S_TOKEN=token sudo -E $0"
    exit 1
fi

# Install k3s agent
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh - 2>&1 | grep -i error || true

# Wait for k3s-agent to be ready
timeout=60
while [ $timeout -gt 0 ]; do
    if systemctl is-active --quiet k3s-agent; then
        break
    fi
    sleep 2
    ((timeout-=2))
done

if ! systemctl is-active --quiet k3s-agent; then
    echo "Error: k3s-agent failed to start"
    systemctl status k3s-agent --no-pager
    exit 1
fi

echo ""
echo "=== K3s Worker Setup Complete ==="
echo "Verify from master: kubectl get nodes"
