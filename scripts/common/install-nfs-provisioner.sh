#!/bin/bash

# Script to install NFS Subdir External Provisioner using Helm
# This provisioner dynamically creates PersistentVolumes on an NFS server

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Installing NFS Subdir External Provisioner...${NC}"

# Configuration
NFS_SERVER="${NFS_SERVER:-192.168.100.98}"
NFS_PATH="${NFS_PATH:-/data}"
STORAGE_CLASS_NAME="${STORAGE_CLASS_NAME:-nfs-client}"
NAMESPACE="${NAMESPACE:-nfs-provisioner}"
DEFAULT_STORAGE_CLASS="${DEFAULT_STORAGE_CLASS:-true}"

echo -e "\n${YELLOW}Configuration:${NC}"
echo "  NFS Server: ${NFS_SERVER}"
echo "  NFS Path: ${NFS_PATH}"
echo "  Storage Class: ${STORAGE_CLASS_NAME}"
echo "  Namespace: ${NAMESPACE}"
echo "  Set as default: ${DEFAULT_STORAGE_CLASS}"
echo ""

# Pre-flight checks
echo -e "${YELLOW}Running pre-flight checks...${NC}"

# Check 1: Verify NFS server is accessible
echo -n "  Checking NFS server connectivity... "
if ping -c 1 -W 2 "$NFS_SERVER" &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}ERROR: Cannot reach NFS server at $NFS_SERVER${NC}"
    exit 1
fi

# Check 2: Verify NFS exports are visible
echo -n "  Checking NFS exports... "
if showmount -e "$NFS_SERVER" &>/dev/null; then
    if showmount -e "$NFS_SERVER" 2>/dev/null | grep -q "$NFS_PATH"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo -e "${RED}ERROR: $NFS_PATH is not exported on $NFS_SERVER${NC}"
        echo "Available exports:"
        showmount -e "$NFS_SERVER"
        exit 1
    fi
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}ERROR: Cannot retrieve NFS exports from $NFS_SERVER${NC}"
    exit 1
fi

# Check 3: Warn about nfs-common requirement on worker nodes
echo -e "\n${YELLOW}⚠ IMPORTANT: All worker nodes must have 'nfs-common' installed${NC}"
echo -e "${YELLOW}  If pods get stuck in ContainerCreating state, install nfs-common on worker nodes:${NC}"
echo -e "${YELLOW}    ssh <worker-node> 'sudo apt-get install -y nfs-common'${NC}"
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."
echo ""

# Add Helm repository
echo -e "${YELLOW}Adding NFS provisioner Helm repository...${NC}"
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

# Create namespace if it doesn't exist
echo -e "\n${YELLOW}Creating namespace ${NAMESPACE}...${NC}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Install the Helm chart
echo -e "\n${YELLOW}Installing NFS provisioner Helm chart...${NC}"
helm upgrade --install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace ${NAMESPACE} \
  --set nfs.server=${NFS_SERVER} \
  --set nfs.path=${NFS_PATH} \
  --set storageClass.name=${STORAGE_CLASS_NAME} \
  --set storageClass.defaultClass=${DEFAULT_STORAGE_CLASS} \
  --set storageClass.archiveOnDelete=false \
  --version 4.0.18

echo ""
echo -e "${YELLOW}Waiting for NFS provisioner to be ready...${NC}"
if kubectl wait --for=condition=available --timeout=300s deployment/nfs-subdir-external-provisioner -n ${NAMESPACE} 2>&1; then
    echo -e "${GREEN}✓ NFS provisioner is ready!${NC}"
else
    echo -e "${RED}✗ NFS provisioner failed to become ready${NC}"
    echo -e "${YELLOW}Checking pod status...${NC}"
    kubectl get pods -n ${NAMESPACE}
    echo -e "\n${YELLOW}Pod details:${NC}"
    kubectl describe pods -n ${NAMESPACE}
    echo -e "\n${RED}Common issue: Worker nodes missing nfs-common package${NC}"
    echo -e "${YELLOW}Fix by running on each worker node:${NC}"
    echo -e "${YELLOW}  sudo apt-get install -y nfs-common${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ NFS Subdir External Provisioner installation complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Verify the installation:${NC}"
echo -e "  ${BLUE}kubectl get deployment -n ${NAMESPACE}${NC}"
echo -e "  ${BLUE}kubectl get storageclass ${STORAGE_CLASS_NAME}${NC}"
echo ""
echo -e "${YELLOW}Test with a PVC:${NC}"
echo "  kubectl apply -f - <<EOF"
echo "  apiVersion: v1"
echo "  kind: PersistentVolumeClaim"
echo "  metadata:"
echo "    name: test-pvc"
echo "  spec:"
echo "    storageClassName: ${STORAGE_CLASS_NAME}"
echo "    accessModes:"
echo "      - ReadWriteOnce"
echo "    resources:"
echo "      requests:"
echo "        storage: 1Gi"
echo "  EOF"
