#!/bin/bash
# Comprehensive setup script for the remote host machine (192.168.100.98)
# This script consolidates the functionality of previous setup scripts
# Usage: ./setup-remote-host.sh

set -e

HOST_IP="192.168.100.98"
SSH_OPTIONS="-o StrictHostKeyChecking=no"

# Colors for formatting output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Remote Host Setup Script for Kubernetes Homelab${NC}"
echo -e "${BLUE}========================================================${NC}"

# Function to execute commands on remote host
execute_remote() {
    local cmd="$1"
    echo -e "${YELLOW}Executing on $HOST_IP:${NC} $cmd"
    ssh $SSH_OPTIONS $HOST_IP "$cmd"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Command executed successfully${NC}"
    else
        echo -e "${RED}✗ Command failed${NC}"
        exit 1
    fi
}

# Check SSH connectivity
echo -e "\n${BLUE}Checking SSH connectivity to $HOST_IP...${NC}"
if ssh $SSH_OPTIONS -q $HOST_IP "exit" 2>/dev/null; then
    echo -e "${GREEN}✓ SSH connection successful${NC}"
else
    echo -e "${RED}✗ Cannot connect to $HOST_IP via SSH. Please check the host and SSH configuration.${NC}"
    exit 1
fi

# NFS Server Setup
echo -e "\n${BLUE}Setting up NFS server...${NC}"

# Create data directories
echo -e "\n${YELLOW}Creating data directories...${NC}"
execute_remote "sudo mkdir -p /data/prometheus /data/grafana /data/alertmanager-0 /data/alertmanager-1"

# Set proper permissions
echo -e "\n${YELLOW}Setting directory permissions...${NC}"
execute_remote "sudo chmod -R 777 /data/"

# Install NFS server
echo -e "\n${YELLOW}Installing NFS server packages...${NC}"
execute_remote "sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-kernel-server"

# Configure exports
echo -e "\n${YELLOW}Configuring NFS exports...${NC}"
cat << EOF > /tmp/exports
/data/prometheus *(rw,sync,no_subtree_check,no_root_squash)
/data/grafana *(rw,sync,no_subtree_check,no_root_squash)
/data/alertmanager-0 *(rw,sync,no_subtree_check,no_root_squash)
/data/alertmanager-1 *(rw,sync,no_subtree_check,no_root_squash)
EOF

# Copy exports file to remote host
scp $SSH_OPTIONS /tmp/exports $HOST_IP:/tmp/exports
execute_remote "sudo cp /tmp/exports /etc/exports"

# Restart the NFS server
echo -e "\n${YELLOW}Restarting NFS server...${NC}"
execute_remote "sudo systemctl stop nfs-kernel-server || true"
execute_remote "sudo systemctl start nfs-kernel-server"
execute_remote "sudo systemctl enable nfs-kernel-server"

# Re-export all directories
echo -e "\n${YELLOW}Exporting NFS directories...${NC}"
execute_remote "sudo exportfs -ra"

# Verify NFS is running
echo -e "\n${YELLOW}Verifying NFS service status...${NC}"
if ssh $SSH_OPTIONS $HOST_IP "sudo systemctl is-active nfs-kernel-server"; then
    echo -e "${GREEN}✓ NFS server is running${NC}"
else
    echo -e "${RED}✗ NFS server failed to start. Checking logs...${NC}"
    ssh $SSH_OPTIONS $HOST_IP "sudo journalctl -u nfs-kernel-server --no-pager | tail -n 20"
    exit 1
fi

# Verify exports are configured
echo -e "\n${YELLOW}Verifying NFS exports...${NC}"
if ssh $SSH_OPTIONS $HOST_IP "sudo showmount -e localhost"; then
    echo -e "${GREEN}✓ NFS exports configured correctly${NC}"
else
    echo -e "${RED}✗ NFS exports not configured correctly${NC}"
    ssh $SSH_OPTIONS $HOST_IP "sudo systemctl status rpcbind --no-pager"
    exit 1
fi

# Open firewall ports if firewall is active
echo -e "\n${YELLOW}Checking firewall status...${NC}"
if ssh $SSH_OPTIONS $HOST_IP "command -v ufw &>/dev/null && sudo ufw status | grep -q 'active'"; then
    echo -e "${YELLOW}Opening firewall ports for NFS...${NC}"
    execute_remote "sudo ufw allow 111/tcp"
    execute_remote "sudo ufw allow 111/udp"
    execute_remote "sudo ufw allow 2049/tcp"
    execute_remote "sudo ufw allow 2049/udp"
    execute_remote "sudo ufw allow 32764:32769/tcp"
    execute_remote "sudo ufw allow 32764:32769/udp"
    echo -e "${GREEN}✓ Firewall configured for NFS${NC}"
fi

# Test file creation
echo -e "\n${YELLOW}Creating test files to verify permissions...${NC}"
execute_remote "sudo touch /data/prometheus/test.txt"
execute_remote "sudo touch /data/grafana/test.txt"
execute_remote "sudo touch /data/alertmanager-0/test.txt"
execute_remote "sudo touch /data/alertmanager-1/test.txt"

# Test NFS Client setup on local machine
echo -e "\n${BLUE}Setting up NFS client on local machine...${NC}"
echo -e "${YELLOW}Installing NFS client...${NC}"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-common
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ NFS client installed${NC}"
else
    echo -e "${RED}✗ Failed to install NFS client${NC}"
    exit 1
fi

# Test mounting the NFS shares
echo -e "\n${YELLOW}Testing NFS connectivity to $HOST_IP...${NC}"
mkdir -p /tmp/nfs-test
if sudo mount -t nfs $HOST_IP:/data/prometheus /tmp/nfs-test; then
    echo -e "${GREEN}✓ NFS mount successful!${NC}"
    sudo umount /tmp/nfs-test
else
    echo -e "${RED}✗ ERROR: Unable to mount NFS share. Check network connectivity and NFS server configuration.${NC}"
    exit 1
fi
rmdir /tmp/nfs-test

# Check for NFS support in the kernel
if ! grep -q nfs /proc/filesystems; then
    echo -e "${YELLOW}WARNING: NFS filesystem support not found in the kernel${NC}"
    echo -e "${YELLOW}You may need to load the necessary kernel modules:${NC}"
    echo -e "${YELLOW}sudo modprobe nfs${NC}"
    echo -e "${YELLOW}sudo modprobe nfsd${NC}"
else
    echo -e "${GREEN}✓ NFS filesystem support verified in kernel${NC}"
fi

echo -e "\n${BLUE}========================================================${NC}"
echo -e "${GREEN}✓ Remote host setup complete!${NC}"
echo -e "${BLUE}========================================================${NC}"
echo -e "NFS server is running on $HOST_IP"
echo -e "The following directories are exported:"
ssh $SSH_OPTIONS $HOST_IP "showmount -e localhost"
echo -e "\nYou can now proceed with installing the Kubernetes components."