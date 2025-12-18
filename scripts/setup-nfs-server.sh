#!/bin/bash
# Comprehensive NFS Server Setup Script for Kubernetes Homelab
# This script sets up the NFS server to work with both:
# 1. Dynamic provisioning (nfs-client StorageClass)
# 2. Direct NFS mounts (like Plex media)
#
# Run this script ON the NFS server machine (192.168.100.98)
# OR run it remotely: ./setup-nfs-server.sh [remote-host-ip]

set -e

# Configuration
NFS_SERVER="${1:-192.168.100.98}"
RUN_REMOTE=false

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Determine if we're running remotely
if [ "$NFS_SERVER" != "localhost" ] && [ "$NFS_SERVER" != "127.0.0.1" ]; then
    RUN_REMOTE=true
    echo -e "${BLUE}Running setup on remote server: $NFS_SERVER${NC}"
else
    echo -e "${BLUE}Running setup on local machine${NC}"
fi

# Function to execute commands (local or remote)
run_cmd() {
    local cmd="$1"
    if [ "$RUN_REMOTE" = true ]; then
        ssh -o StrictHostKeyChecking=no "$NFS_SERVER" "$cmd"
    else
        eval "$cmd"
    fi
}

echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  NFS Server Setup for Kubernetes Homelab${NC}"
echo -e "${BLUE}========================================================${NC}"

# Step 1: Install NFS server
echo -e "\n${YELLOW}[1/8] Installing NFS server packages...${NC}"
run_cmd "sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-kernel-server"
echo -e "${GREEN}✓ NFS server packages installed${NC}"

# Step 2: Create base directory structure
echo -e "\n${YELLOW}[2/8] Creating directory structure...${NC}"
run_cmd "sudo mkdir -p /data"
run_cmd "sudo mkdir -p /data/media"  # For Plex
run_cmd "sudo mkdir -p /data/plex"   # For Plex config if needed
echo -e "${GREEN}✓ Directory structure created${NC}"

# Step 3: Set permissions
echo -e "\n${YELLOW}[3/8] Setting permissions...${NC}"
# The /data directory needs to allow the NFS provisioner to create subdirectories
run_cmd "sudo chmod 777 /data"
run_cmd "sudo chmod 755 /data/media"
run_cmd "sudo chmod 755 /data/plex"
echo -e "${GREEN}✓ Permissions configured${NC}"

# Step 4: Configure NFS exports
echo -e "\n${YELLOW}[4/8] Configuring NFS exports...${NC}"

# Create exports configuration
EXPORTS_CONFIG='# Kubernetes NFS Exports
# Main data directory for NFS provisioner (dynamic PVC creation)
/data *(rw,sync,no_subtree_check,no_root_squash)

# Media directory for Plex
/data/media *(rw,sync,no_subtree_check,no_root_squash)

# Plex config directory
/data/plex *(rw,sync,no_subtree_check,no_root_squash)'

if [ "$RUN_REMOTE" = true ]; then
    echo "$EXPORTS_CONFIG" | ssh "$NFS_SERVER" "sudo tee /etc/exports > /dev/null"
else
    echo "$EXPORTS_CONFIG" | sudo tee /etc/exports > /dev/null
fi

echo -e "${GREEN}✓ Exports configured${NC}"

# Step 5: Apply NFS exports
echo -e "\n${YELLOW}[5/8] Applying NFS exports...${NC}"
run_cmd "sudo exportfs -ra"
echo -e "${GREEN}✓ Exports applied${NC}"

# Step 6: Start and enable NFS server
echo -e "\n${YELLOW}[6/8] Starting NFS server...${NC}"
run_cmd "sudo systemctl restart nfs-kernel-server"
run_cmd "sudo systemctl enable nfs-kernel-server"
echo -e "${GREEN}✓ NFS server started${NC}"

# Step 7: Configure firewall (if active)
echo -e "\n${YELLOW}[7/8] Checking firewall configuration...${NC}"
if run_cmd "command -v ufw &>/dev/null && sudo ufw status | grep -q 'active'"; then
    echo -e "${YELLOW}Firewall is active, opening NFS ports...${NC}"
    run_cmd "sudo ufw allow from 192.168.100.0/24 to any port nfs"
    run_cmd "sudo ufw allow from 192.168.100.0/24 to any port 111"
    run_cmd "sudo ufw allow from 192.168.100.0/24 to any port 2049"
    echo -e "${GREEN}✓ Firewall configured${NC}"
else
    echo -e "${BLUE}ℹ Firewall not active or ufw not installed${NC}"
fi

# Step 8: Verify setup
echo -e "\n${YELLOW}[8/8] Verifying NFS server setup...${NC}"

# Check NFS service status
if run_cmd "sudo systemctl is-active --quiet nfs-kernel-server"; then
    echo -e "${GREEN}✓ NFS server is running${NC}"
else
    echo -e "${RED}✗ NFS server is not running${NC}"
    run_cmd "sudo systemctl status nfs-kernel-server --no-pager"
    exit 1
fi

# Check exports
echo -e "\n${BLUE}Current NFS exports:${NC}"
run_cmd "sudo showmount -e localhost"

# Display summary
echo -e "\n${BLUE}========================================================${NC}"
echo -e "${GREEN}✓ NFS Server Setup Complete!${NC}"
echo -e "${BLUE}========================================================${NC}"
echo -e "\n${YELLOW}Configuration Summary:${NC}"
echo -e "  NFS Server: $NFS_SERVER"
echo -e "  Base Path: /data"
echo -e "  Media Path: /data/media (for Plex)"
echo -e ""
echo -e "${YELLOW}What was configured:${NC}"
echo -e "  ✓ NFS server installed and running"
echo -e "  ✓ /data exported for dynamic provisioning"
echo -e "  ✓ /data/media exported for Plex media"
echo -e "  ✓ Firewall configured (if applicable)"
echo -e ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Install NFS provisioner in Kubernetes:"
echo -e "     ${BLUE}./scripts/install-nfs-provisioner.sh${NC}"
echo -e ""
echo -e "  2. Test NFS mount from a Kubernetes node:"
echo -e "     ${BLUE}sudo apt-get install -y nfs-common${NC}"
echo -e "     ${BLUE}sudo mount -t nfs $NFS_SERVER:/data /mnt${NC}"
echo -e "     ${BLUE}sudo umount /mnt${NC}"
echo -e ""
echo -e "${YELLOW}Directory structure:${NC}"
run_cmd "sudo ls -lah /data/"
echo -e "${BLUE}========================================================${NC}"
