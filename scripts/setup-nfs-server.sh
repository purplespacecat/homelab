#!/bin/bash
# Comprehensive NFS Server Setup Script for Kubernetes Homelab
# This script sets up the NFS server to work with both:
# 1. Dynamic provisioning (nfs-client StorageClass)
# 2. Direct NFS mounts (like Plex media)
#
# IMPORTANT: Run this script DIRECTLY ON the NFS server machine
# Usage: sudo ./setup-nfs-server.sh

set -e

# Check if running with sudo/root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run with sudo"
    echo "Usage: sudo ./setup-nfs-server.sh"
    exit 1
fi

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  NFS Server Setup for Kubernetes Homelab${NC}"
echo -e "${BLUE}========================================================${NC}"

# Step 1: Install NFS server
echo -e "\n${YELLOW}[1/8] Installing NFS server packages...${NC}"
apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-kernel-server
echo -e "${GREEN}✓ NFS server packages installed${NC}"

# Step 2: Create base directory structure
echo -e "\n${YELLOW}[2/8] Creating directory structure...${NC}"
mkdir -p /data
mkdir -p /data/media  # For Plex
mkdir -p /data/plex   # For Plex config if needed
echo -e "${GREEN}✓ Directory structure created${NC}"

# Step 3: Set permissions
echo -e "\n${YELLOW}[3/8] Setting permissions...${NC}"
# The /data directory needs to allow the NFS provisioner to create subdirectories
chmod 777 /data
chmod 755 /data/media
chmod 755 /data/plex
echo -e "${GREEN}✓ Permissions configured${NC}"

# Step 4: Configure NFS exports
echo -e "\n${YELLOW}[4/8] Configuring NFS exports...${NC}"

cat > /etc/exports <<'EOF'
# Kubernetes NFS Exports
# Main data directory for NFS provisioner (dynamic PVC creation)
/data *(rw,sync,no_subtree_check,no_root_squash)

# Media directory for Plex
/data/media *(rw,sync,no_subtree_check,no_root_squash)

# Plex config directory
/data/plex *(rw,sync,no_subtree_check,no_root_squash)
EOF

echo -e "${GREEN}✓ Exports configured${NC}"

# Step 5: Apply NFS exports
echo -e "\n${YELLOW}[5/8] Applying NFS exports...${NC}"
exportfs -ra
echo -e "${GREEN}✓ Exports applied${NC}"

# Step 6: Start and enable NFS server
echo -e "\n${YELLOW}[6/8] Starting NFS server...${NC}"
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server
echo -e "${GREEN}✓ NFS server started${NC}"

# Step 7: Configure firewall (if active)
echo -e "\n${YELLOW}[7/8] Checking firewall configuration...${NC}"
if command -v ufw &>/dev/null && ufw status | grep -q 'active'; then
    echo -e "${YELLOW}Firewall is active, opening NFS ports...${NC}"
    ufw allow from 192.168.100.0/24 to any port nfs
    ufw allow from 192.168.100.0/24 to any port 111
    ufw allow from 192.168.100.0/24 to any port 2049
    echo -e "${GREEN}✓ Firewall configured${NC}"
else
    echo -e "${BLUE}ℹ Firewall not active or ufw not installed${NC}"
fi

# Step 8: Verify setup
echo -e "\n${YELLOW}[8/8] Verifying NFS server setup...${NC}"

# Check NFS service status
if systemctl is-active --quiet nfs-kernel-server; then
    echo -e "${GREEN}✓ NFS server is running${NC}"
else
    echo -e "${RED}✗ NFS server is not running${NC}"
    systemctl status nfs-kernel-server --no-pager
    exit 1
fi

# Check exports
echo -e "\n${BLUE}Current NFS exports:${NC}"
showmount -e localhost

# Display summary
echo -e "\n${BLUE}========================================================${NC}"
echo -e "${GREEN}✓ NFS Server Setup Complete!${NC}"
echo -e "${BLUE}========================================================${NC}"
echo -e "\n${YELLOW}Configuration Summary:${NC}"
echo -e "  NFS Server: $(hostname -I | awk '{print $1}')"
echo -e "  Base Path: /data"
echo -e "  Media Path: /data/media (for Plex)"
echo -e ""
echo -e "${YELLOW}What was configured:${NC}"
echo -e "  ✓ NFS server installed and running"
echo -e "  ✓ /data exported for dynamic provisioning"
echo -e "  ✓ /data/media exported for Plex media"
echo -e "  ✓ Firewall configured (if applicable)"
echo -e ""
echo -e "${YELLOW}Next steps (run from your Kubernetes control node):${NC}"
echo -e "  1. Verify NFS setup from K8s node:"
echo -e "     ${BLUE}./scripts/verify-nfs-setup.sh $(hostname -I | awk '{print $1}')${NC}"
echo -e ""
echo -e "  2. Install NFS provisioner in Kubernetes:"
echo -e "     ${BLUE}./scripts/install-nfs-provisioner.sh${NC}"
echo -e ""
echo -e "  3. Add media files to this server:"
echo -e "     ${BLUE}mkdir -p /data/media/Movies /data/media/TV${NC}"
echo -e "     ${BLUE}# Copy your media files to /data/media/${NC}"
echo -e ""
echo -e "${YELLOW}Directory structure:${NC}"
ls -lah /data/
echo -e "${BLUE}========================================================${NC}"
