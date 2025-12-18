#!/bin/bash
# Remote NFS Server Setup Script
# This version creates a setup script and runs it on the remote server
# Requires only ONE sudo password prompt

set -e

NFS_SERVER="${1:-192.168.100.98}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Remote NFS Server Setup${NC}"
echo -e "${BLUE}========================================================${NC}"
echo -e "Target server: ${YELLOW}$NFS_SERVER${NC}\n"

# Test SSH connectivity
echo -e "${YELLOW}Testing SSH connection...${NC}"
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$NFS_SERVER" "exit" 2>/dev/null; then
    echo -e "${RED}✗ Cannot connect to $NFS_SERVER via SSH${NC}"
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo -e "  1. Check if the server is reachable: ping $NFS_SERVER"
    echo -e "  2. Verify SSH is running on the server"
    echo -e "  3. Check your SSH keys: ssh-copy-id $NFS_SERVER"
    exit 1
fi
echo -e "${GREEN}✓ SSH connection successful${NC}\n"

# Create the setup script that will run on the remote server
REMOTE_SCRIPT=$(cat <<'SCRIPT_EOF'
#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Running NFS server setup...${NC}\n"

# Step 1: Install NFS server
echo -e "${YELLOW}[1/7] Installing NFS server packages...${NC}"
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-kernel-server >/dev/null 2>&1
echo -e "${GREEN}✓ Installed${NC}"

# Step 2: Create directories
echo -e "${YELLOW}[2/7] Creating directory structure...${NC}"
mkdir -p /data /data/media /data/plex
echo -e "${GREEN}✓ Created${NC}"

# Step 3: Set permissions
echo -e "${YELLOW}[3/7] Setting permissions...${NC}"
chmod 777 /data
chmod 755 /data/media /data/plex
echo -e "${GREEN}✓ Set${NC}"

# Step 4: Configure exports
echo -e "${YELLOW}[4/7] Configuring NFS exports...${NC}"
cat > /etc/exports <<'EOF'
# Kubernetes NFS Exports
# Main data directory for NFS provisioner (dynamic PVC creation)
/data *(rw,sync,no_subtree_check,no_root_squash)

# Media directory for Plex
/data/media *(rw,sync,no_subtree_check,no_root_squash)

# Plex config directory
/data/plex *(rw,sync,no_subtree_check,no_root_squash)
EOF
echo -e "${GREEN}✓ Configured${NC}"

# Step 5: Apply exports
echo -e "${YELLOW}[5/7] Applying NFS exports...${NC}"
exportfs -ra
echo -e "${GREEN}✓ Applied${NC}"

# Step 6: Restart NFS
echo -e "${YELLOW}[6/7] Restarting NFS server...${NC}"
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server >/dev/null 2>&1
echo -e "${GREEN}✓ Running${NC}"

# Step 7: Configure firewall if needed
echo -e "${YELLOW}[7/7] Checking firewall...${NC}"
if command -v ufw &>/dev/null && ufw status | grep -q 'active'; then
    echo -e "${YELLOW}Configuring firewall...${NC}"
    ufw allow from 192.168.100.0/24 to any port nfs >/dev/null 2>&1 || true
    ufw allow from 192.168.100.0/24 to any port 111 >/dev/null 2>&1 || true
    ufw allow from 192.168.100.0/24 to any port 2049 >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ Configured${NC}"
else
    echo -e "${BLUE}ℹ Firewall not active${NC}"
fi

# Verify
echo -e "\n${BLUE}Verification:${NC}"
if systemctl is-active --quiet nfs-kernel-server; then
    echo -e "${GREEN}✓ NFS server is running${NC}"
else
    echo -e "${RED}✗ NFS server is not running${NC}"
    exit 1
fi

echo -e "\n${BLUE}Exports:${NC}"
showmount -e localhost

echo -e "\n${BLUE}Directory structure:${NC}"
ls -lah /data/

echo -e "\n${GREEN}✓ NFS server setup complete!${NC}"
SCRIPT_EOF
)

# Copy script to remote server and execute with sudo
echo -e "${YELLOW}Uploading and executing setup script on $NFS_SERVER...${NC}"
echo -e "${YELLOW}(You may be prompted for sudo password once)${NC}\n"

# Use heredoc to pass the script via SSH and execute with sudo
ssh -t "$NFS_SERVER" "cat > /tmp/nfs-setup.sh && chmod +x /tmp/nfs-setup.sh && sudo /tmp/nfs-setup.sh && rm /tmp/nfs-setup.sh" <<< "$REMOTE_SCRIPT"

# Summary
echo -e "\n${BLUE}========================================================${NC}"
echo -e "${GREEN}✓ Remote NFS Server Setup Complete!${NC}"
echo -e "${BLUE}========================================================${NC}"
echo -e "\n${YELLOW}Configuration Summary:${NC}"
echo -e "  NFS Server: $NFS_SERVER"
echo -e "  Base Path: /data"
echo -e "  Media Path: /data/media"
echo -e ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Verify NFS setup:"
echo -e "     ${BLUE}./scripts/verify-nfs-setup.sh $NFS_SERVER${NC}"
echo -e ""
echo -e "  2. Install NFS provisioner in Kubernetes:"
echo -e "     ${BLUE}./scripts/install-nfs-provisioner.sh${NC}"
echo -e ""
echo -e "  3. Add media files to the server:"
echo -e "     ${BLUE}ssh $NFS_SERVER 'sudo mkdir -p /data/media/Movies /data/media/TV'${NC}"
echo -e "${BLUE}========================================================${NC}"
