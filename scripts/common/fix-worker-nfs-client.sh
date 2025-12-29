#!/bin/bash
# Script to install nfs-common on Kubernetes worker nodes
# This is required for NFS volume mounting

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Fix Worker Node NFS Client${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Get all worker nodes
echo -e "${YELLOW}Detecting worker nodes...${NC}"
WORKER_NODES=$(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')

if [ -z "$WORKER_NODES" ]; then
    echo -e "${RED}No worker nodes found${NC}"
    exit 1
fi

echo -e "${GREEN}Found worker nodes:${NC}"
for NODE_IP in $WORKER_NODES; do
    NODE_NAME=$(kubectl get nodes -o json | jq -r ".items[] | select(.status.addresses[] | select(.type==\"InternalIP\" and .address==\"$NODE_IP\")) | .metadata.name")
    echo "  - $NODE_NAME ($NODE_IP)"
done
echo ""

# Ask for confirmation
echo -e "${YELLOW}This script will install nfs-common on all worker nodes via SSH.${NC}"
read -p "Do you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${RED}Aborted${NC}"
    exit 0
fi

echo ""

# Install nfs-common on each worker
for NODE_IP in $WORKER_NODES; do
    NODE_NAME=$(kubectl get nodes -o json | jq -r ".items[] | select(.status.addresses[] | select(.type==\"InternalIP\" and .address==\"$NODE_IP\")) | .metadata.name")
    echo -e "${YELLOW}Installing nfs-common on $NODE_NAME ($NODE_IP)...${NC}"

    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$NODE_IP" "sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-common" 2>&1; then
        echo -e "${GREEN}✓ Successfully installed on $NODE_NAME${NC}"
    else
        echo -e "${RED}✗ Failed to install on $NODE_NAME${NC}"
        echo -e "${YELLOW}  Try manually: ssh $NODE_IP 'sudo apt-get install -y nfs-common'${NC}"
    fi
    echo ""
done

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Installation complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Delete existing NFS provisioner pods to force restart:"
echo -e "     ${BLUE}kubectl delete pods -n nfs-provisioner --all${NC}"
echo -e ""
echo -e "  2. Watch pods come back up:"
echo -e "     ${BLUE}kubectl get pods -n nfs-provisioner -w${NC}"
echo -e ""
echo -e "  3. Verify provisioner is ready:"
echo -e "     ${BLUE}kubectl get deployment -n nfs-provisioner${NC}"
echo ""
