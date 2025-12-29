#!/bin/bash
# Join worker node to kubeadm cluster
set -e

[ "$EUID" -ne 0 ] && { echo "Error: Run as root"; exit 1; }

CONTROL_PLANE_HOST="${CONTROL_PLANE_HOST:-}"
CONTROL_PLANE_PORT="${CONTROL_PLANE_PORT:-6443}"
TOKEN="${TOKEN:-}"
CA_CERT_HASH="${CA_CERT_HASH:-}"

# Validate prerequisites
command -v kubelet &>/dev/null || { echo "Error: kubelet not installed. Run setup-worker-node.sh first"; exit 1; }
command -v kubeadm &>/dev/null || { echo "Error: kubeadm not installed. Run setup-worker-node.sh first"; exit 1; }
systemctl is-active --quiet containerd || { echo "Error: containerd not running"; exit 1; }

# Get join information
if [ -n "$CONTROL_PLANE_HOST" ] && [ -n "$TOKEN" ] && [ -n "$CA_CERT_HASH" ]; then
    : # Use environment variables
else
    read -p "Enter full kubeadm join command (or press Enter for manual input): " JOIN_COMMAND

    if [ -n "$JOIN_COMMAND" ]; then
        eval "$JOIN_COMMAND" 2>&1 | grep -iE "error|node joined" || true
        echo ""
        echo "=== Worker Node Joined ==="
        echo "Verify from master: kubectl get nodes"
        exit 0
    else
        read -p "Control plane host: " CONTROL_PLANE_HOST
        read -p "Control plane port [6443]: " CONTROL_PLANE_PORT_INPUT
        CONTROL_PLANE_PORT="${CONTROL_PLANE_PORT_INPUT:-6443}"
        read -p "Token: " TOKEN
        read -p "CA cert hash (sha256:xxxxx): " CA_CERT_HASH
    fi
fi

# Validate parameters
[ -z "$CONTROL_PLANE_HOST" ] && { echo "Error: Control plane host required"; exit 1; }
[ -z "$TOKEN" ] && { echo "Error: Token required"; exit 1; }
[ -z "$CA_CERT_HASH" ] && { echo "Error: CA cert hash required"; exit 1; }

# Ensure CA cert hash has sha256: prefix
[[ ! "$CA_CERT_HASH" =~ ^sha256: ]] && CA_CERT_HASH="sha256:$CA_CERT_HASH"

# Join cluster
kubeadm join "${CONTROL_PLANE_HOST}:${CONTROL_PLANE_PORT}" \
    --token "${TOKEN}" \
    --discovery-token-ca-cert-hash "${CA_CERT_HASH}" 2>&1 | grep -iE "error|node joined" || true

echo ""
echo "=== Worker Node Joined ==="
echo "Verify from master: kubectl get nodes"
