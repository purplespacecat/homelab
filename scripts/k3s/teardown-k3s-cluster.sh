#!/bin/bash
# Remove k3s from node
set -e

[ "$EUID" -ne 0 ] && { echo "Error: Run as root"; exit 1; }

FORCE="${FORCE:-false}"
if [ "$FORCE" != "true" ]; then
    read -p "Remove k3s cluster from this node? (yes/no): " -r
    [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]] && { echo "Cancelled"; exit 0; }
fi

# Determine if this is a server or agent
if systemctl list-units --full --all | grep -q k3s.service; then
    echo "Removing k3s server..."
    /usr/local/bin/k3s-uninstall.sh 2>&1 | grep -i error || true
elif systemctl list-units --full --all | grep -q k3s-agent.service; then
    echo "Removing k3s agent..."
    /usr/local/bin/k3s-agent-uninstall.sh 2>&1 | grep -i error || true
else
    echo "No k3s installation found"
    exit 0
fi

# Verify removal
if systemctl is-active --quiet k3s || systemctl is-active --quiet k3s-agent; then
    echo "Error: k3s services still running"
    exit 1
fi

echo ""
echo "=== K3s Removed Successfully ==="
