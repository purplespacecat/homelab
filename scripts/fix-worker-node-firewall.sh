#!/bin/bash
# Script to fix worker node firewall issues
# This script opens necessary ports for Kubernetes worker node communication

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Fix Worker Node Firewall${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run with sudo${NC}"
    echo -e "${YELLOW}Usage: sudo ./fix-worker-node-firewall.sh${NC}"
    exit 1
fi

echo -e "${YELLOW}This script will open the following ports on the worker node:${NC}"
echo -e "  - 10250/tcp  (Kubelet API)"
echo -e "  - 10256/tcp  (kube-proxy health check)"
echo -e "  - 30000-32767/tcp  (NodePort services)"
echo ""

# Check if UFW is installed and active
if ! command -v ufw &>/dev/null; then
    echo -e "${YELLOW}UFW is not installed. Assuming no firewall blocking.${NC}"
    exit 0
fi

if ! ufw status | grep -q "Status: active"; then
    echo -e "${YELLOW}UFW is not active. No changes needed.${NC}"
    exit 0
fi

echo -e "${YELLOW}UFW is active. Opening required ports...${NC}"
echo ""

# Allow kubelet API from control plane
echo -e "${YELLOW}[1/3] Opening kubelet API port (10250)...${NC}"
ufw allow from 192.168.100.0/24 to any port 10250 proto tcp
echo -e "${GREEN}✓ Port 10250 opened${NC}"

# Allow kube-proxy health check
echo -e "\n${YELLOW}[2/3] Opening kube-proxy port (10256)...${NC}"
ufw allow from 192.168.100.0/24 to any port 10256 proto tcp
echo -e "${GREEN}✓ Port 10256 opened${NC}"

# Allow NodePort range
echo -e "\n${YELLOW}[3/3] Opening NodePort range (30000-32767)...${NC}"
ufw allow 30000:32767/tcp
echo -e "${GREEN}✓ NodePort range opened${NC}"

# Reload UFW
echo -e "\n${YELLOW}Reloading UFW...${NC}"
ufw reload
echo -e "${GREEN}✓ UFW reloaded${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Firewall configuration complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Current UFW status:${NC}"
ufw status numbered
echo ""
echo -e "${YELLOW}Test kubelet connectivity from control plane with:${NC}"
echo -e "${BLUE}  nc -zv <WORKER_NODE_IP> 10250${NC}"
echo ""
