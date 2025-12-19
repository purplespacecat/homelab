#!/bin/bash
# Script to open firewall ports on the master node for external access
# This allows the MetalLB LoadBalancer services to be accessible from the network

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Fix Master Node Firewall for MetalLB${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run with sudo${NC}"
    echo -e "${YELLOW}Usage: sudo ./fix-master-node-firewall.sh${NC}"
    exit 1
fi

echo -e "${YELLOW}This script will open the following ports for MetalLB LoadBalancer access:${NC}"
echo -e "  - 80/tcp   (HTTP for ingress)"
echo -e "  - 443/tcp  (HTTPS for ingress)"
echo -e "  - 7946/tcp & 7946/udp  (MetalLB speaker coordination)"
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

# Allow HTTP from anywhere
echo -e "${YELLOW}[1/4] Opening HTTP port (80)...${NC}"
ufw allow 80/tcp
echo -e "${GREEN}✓ Port 80 opened${NC}"

# Allow HTTPS from anywhere
echo -e "\n${YELLOW}[2/4] Opening HTTPS port (443)...${NC}"
ufw allow 443/tcp
echo -e "${GREEN}✓ Port 443 opened${NC}"

# Allow MetalLB speaker coordination (port 7946)
echo -e "\n${YELLOW}[3/4] Opening MetalLB speaker coordination port (7946 TCP/UDP)...${NC}"
ufw allow from 192.168.100.0/24 to any port 7946
echo -e "${GREEN}✓ Port 7946 opened for local network${NC}"

# Allow NodePort range (optional, for direct NodePort access)
echo -e "\n${YELLOW}[4/4] Opening NodePort range (30000-32767)...${NC}"
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
ufw status numbered | head -20
echo ""
echo -e "${YELLOW}Test access from another PC on your network:${NC}"
echo -e "${BLUE}  http://grafana.192.168.100.200.nip.io${NC}"
echo -e "${BLUE}  http://prometheus.192.168.100.200.nip.io${NC}"
echo -e "${BLUE}  http://alertmanager.192.168.100.200.nip.io${NC}"
echo ""
