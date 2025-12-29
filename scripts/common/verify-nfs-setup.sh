#!/bin/bash
# Script to verify NFS server setup and troubleshoot issues
#
# RECOMMENDED: Run this script directly ON the NFS server for complete checks
# Can also be run from remote machines, but some checks will require SSH access
#
# Usage: ./verify-nfs-setup.sh [NFS_SERVER_IP]
# Example: ./verify-nfs-setup.sh 192.168.100.98
#          (If run on the NFS server itself, IP should match local IP)

set -e

NFS_SERVER="${1:-192.168.100.98}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  NFS Server Verification Script${NC}"
echo -e "${BLUE}========================================================${NC}"
echo -e "Target NFS Server: ${YELLOW}$NFS_SERVER${NC}\n"

ERRORS=0

# Test 1: Network connectivity
echo -e "${YELLOW}[1/7] Testing network connectivity...${NC}"
if ping -c 2 -W 2 "$NFS_SERVER" &>/dev/null; then
    echo -e "${GREEN}✓ Network connectivity OK${NC}"
else
    echo -e "${RED}✗ Cannot ping $NFS_SERVER${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Test 2: Check if running on the NFS server itself
echo -e "\n${YELLOW}[2/7] Checking execution context...${NC}"
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ "$LOCAL_IP" = "$NFS_SERVER" ]; then
    echo -e "${GREEN}✓ Running on NFS server (local mode)${NC}"
    IS_LOCAL=true
else
    echo -e "${YELLOW}⚠ Running from remote machine ($LOCAL_IP)${NC}"
    IS_LOCAL=false
    # Test SSH connectivity for remote checks
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$NFS_SERVER" "exit" 2>/dev/null; then
        echo -e "${GREEN}✓ SSH connectivity OK${NC}"
        HAS_SSH=true
    else
        echo -e "${YELLOW}⚠ Cannot SSH to $NFS_SERVER${NC}"
        HAS_SSH=false
    fi
fi

# Test 3: NFS server status
echo -e "\n${YELLOW}[3/7] Checking NFS server status...${NC}"
if [ "$IS_LOCAL" = true ]; then
    # Local check - can check directly
    if systemctl is-active --quiet nfs-kernel-server; then
        echo -e "${GREEN}✓ NFS server is running${NC}"
    else
        echo -e "${RED}✗ NFS server is not running${NC}"
        echo -e "${YELLOW}  Try: sudo systemctl start nfs-kernel-server${NC}"
        ERRORS=$((ERRORS + 1))
    fi
elif [ "$HAS_SSH" = true ]; then
    # Remote check via SSH
    if ssh "$NFS_SERVER" "sudo systemctl is-active --quiet nfs-kernel-server" 2>/dev/null; then
        echo -e "${GREEN}✓ NFS server is running${NC}"
    else
        echo -e "${RED}✗ NFS server is not running${NC}"
        echo -e "${YELLOW}  Try: ssh $NFS_SERVER 'sudo systemctl start nfs-kernel-server'${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ Cannot check NFS server status (no local or SSH access)${NC}"
fi

# Test 4: Check for NFS client tools
echo -e "\n${YELLOW}[4/7] Checking NFS client tools...${NC}"
if command -v showmount &>/dev/null; then
    echo -e "${GREEN}✓ showmount command available${NC}"
else
    echo -e "${RED}✗ showmount not found${NC}"
    echo -e "${YELLOW}  Install with: sudo apt-get install -y nfs-common${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Test 5: Check NFS exports
echo -e "\n${YELLOW}[5/7] Checking NFS exports from $NFS_SERVER...${NC}"
if command -v showmount &>/dev/null; then
    if showmount -e "$NFS_SERVER" 2>/dev/null; then
        echo -e "${GREEN}✓ NFS exports are visible${NC}"

        # Check for expected exports
        if showmount -e "$NFS_SERVER" 2>/dev/null | grep -q "/data"; then
            echo -e "${GREEN}✓ /data export found${NC}"
        else
            echo -e "${RED}✗ /data export NOT found${NC}"
            echo -e "${YELLOW}  The NFS provisioner needs /data to be exported${NC}"
            ERRORS=$((ERRORS + 1))
        fi
    else
        echo -e "${RED}✗ Cannot retrieve exports from $NFS_SERVER${NC}"
        echo -e "${YELLOW}  Check if rpcbind is running: ssh $NFS_SERVER 'sudo systemctl status rpcbind'${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ Cannot check exports (showmount not available)${NC}"
fi

# Test 6: Test mount
echo -e "\n${YELLOW}[6/7] Testing NFS mount...${NC}"
TEST_DIR="/tmp/nfs-test-$$"
mkdir -p "$TEST_DIR"

# Check if we can use sudo
if ! sudo -n true 2>/dev/null; then
    echo -e "${YELLOW}⚠ Cannot test mount (sudo password required)${NC}"
    echo -e "${YELLOW}  To test mounting manually, run:${NC}"
    echo -e "${YELLOW}  sudo mount -t nfs $NFS_SERVER:/data $TEST_DIR${NC}"
    rmdir "$TEST_DIR" 2>/dev/null || true
elif sudo mount -t nfs -o soft,timeo=10 "$NFS_SERVER:/data" "$TEST_DIR" 2>/dev/null; then
    echo -e "${GREEN}✓ Successfully mounted $NFS_SERVER:/data${NC}"

    # Try to write a test file
    if sudo touch "$TEST_DIR/test-write-$$" 2>/dev/null; then
        echo -e "${GREEN}✓ Write permissions OK${NC}"
        sudo rm "$TEST_DIR/test-write-$$" 2>/dev/null || true
    else
        echo -e "${RED}✗ Cannot write to NFS mount${NC}"
        if [ "$IS_LOCAL" = true ]; then
            echo -e "${YELLOW}  Check permissions: ls -la /data${NC}"
        else
            echo -e "${YELLOW}  Check permissions: ssh $NFS_SERVER 'ls -la /data'${NC}"
        fi
        ERRORS=$((ERRORS + 1))
    fi

    sudo umount "$TEST_DIR" 2>/dev/null || true
    rmdir "$TEST_DIR" 2>/dev/null || true
else
    echo -e "${RED}✗ Cannot mount $NFS_SERVER:/data${NC}"
    echo -e "${YELLOW}  Possible issues:${NC}"
    echo -e "${YELLOW}  - NFS server not exporting /data properly${NC}"
    echo -e "${YELLOW}  - Firewall blocking NFS ports (111, 2049)${NC}"
    echo -e "${YELLOW}  - RPC services not running${NC}"
    if [ "$IS_LOCAL" = true ]; then
        echo -e "${YELLOW}  Check logs: sudo journalctl -u nfs-kernel-server -n 20${NC}"
        echo -e "${YELLOW}  Verify exports: sudo exportfs -v${NC}"
    else
        echo -e "${YELLOW}  Check logs: ssh $NFS_SERVER 'sudo journalctl -u nfs-kernel-server -n 20'${NC}"
    fi
    ERRORS=$((ERRORS + 1))
    rmdir "$TEST_DIR" 2>/dev/null || true
fi

# Test 7: Check Kubernetes NFS provisioner (if kubectl available)
echo -e "\n${YELLOW}[7/7] Checking Kubernetes NFS provisioner...${NC}"
if command -v kubectl &>/dev/null; then
    if kubectl get deployment -n nfs-provisioner nfs-subdir-external-provisioner &>/dev/null; then
        echo -e "${GREEN}✓ NFS provisioner is deployed${NC}"

        # Check if it's running
        if kubectl get pods -n nfs-provisioner | grep -q "Running"; then
            echo -e "${GREEN}✓ NFS provisioner pod is running${NC}"
        else
            echo -e "${RED}✗ NFS provisioner pod is not running${NC}"
            kubectl get pods -n nfs-provisioner
            ERRORS=$((ERRORS + 1))
        fi

        # Check storage class
        if kubectl get storageclass nfs-client &>/dev/null; then
            echo -e "${GREEN}✓ nfs-client StorageClass exists${NC}"
        else
            echo -e "${RED}✗ nfs-client StorageClass not found${NC}"
            ERRORS=$((ERRORS + 1))
        fi
    else
        echo -e "${YELLOW}⚠ NFS provisioner not deployed${NC}"
        echo -e "${YELLOW}  Install with: ./scripts/install-nfs-provisioner.sh${NC}"
    fi
else
    echo -e "${YELLOW}⚠ kubectl not available, skipping Kubernetes checks${NC}"
fi

# Summary
echo -e "\n${BLUE}========================================================${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! NFS setup is working correctly.${NC}"
else
    echo -e "${RED}✗ Found $ERRORS issue(s) that need attention.${NC}"
    echo -e "\n${YELLOW}Common fixes:${NC}"

    if [ "$IS_LOCAL" = true ]; then
        echo -e "  1. Reinstall/reconfigure NFS server (run on this server):"
        echo -e "     ${BLUE}sudo ./scripts/setup-nfs-server.sh${NC}"
        echo -e ""
        echo -e "  2. Check NFS server logs:"
        echo -e "     ${BLUE}sudo journalctl -u nfs-kernel-server -n 50${NC}"
        echo -e ""
        echo -e "  3. Check firewall:"
        echo -e "     ${BLUE}sudo ufw status${NC}"
        echo -e ""
        echo -e "  4. Verify exports file:"
        echo -e "     ${BLUE}cat /etc/exports${NC}"
        echo -e "     ${BLUE}sudo exportfs -v${NC}"
        echo -e ""
        echo -e "  5. Restart NFS server:"
        echo -e "     ${BLUE}sudo systemctl restart nfs-kernel-server${NC}"
        echo -e ""
        echo -e "  6. Reapply exports:"
        echo -e "     ${BLUE}sudo exportfs -ra${NC}"
    else
        echo -e "  1. Run verification ON the NFS server ($NFS_SERVER):"
        echo -e "     ${BLUE}ssh $NFS_SERVER 'cd /path/to/scripts && ./verify-nfs-setup.sh $NFS_SERVER'${NC}"
        echo -e ""
        echo -e "  2. Reinstall/reconfigure NFS server (run ON the server):"
        echo -e "     ${BLUE}ssh $NFS_SERVER 'cd /path/to/scripts && sudo ./setup-nfs-server.sh'${NC}"
        echo -e ""
        echo -e "  3. Check NFS server logs:"
        echo -e "     ${BLUE}ssh $NFS_SERVER 'sudo journalctl -u nfs-kernel-server -n 50'${NC}"
        echo -e ""
        echo -e "  4. Check firewall on NFS server:"
        echo -e "     ${BLUE}ssh $NFS_SERVER 'sudo ufw status'${NC}"
        echo -e ""
        echo -e "  5. Verify exports file:"
        echo -e "     ${BLUE}ssh $NFS_SERVER 'cat /etc/exports && sudo exportfs -v'${NC}"
        echo -e ""
        echo -e "  6. Restart NFS server:"
        echo -e "     ${BLUE}ssh $NFS_SERVER 'sudo systemctl restart nfs-kernel-server'${NC}"
    fi
fi
echo -e "${BLUE}========================================================${NC}"

exit $ERRORS
