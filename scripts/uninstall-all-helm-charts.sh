#!/bin/bash

# Script to uninstall all Helm charts and cleanup the homelab cluster
# WARNING: This will remove all applications and their data!

set -e

# Colors for formatting output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${RED}========================================================${NC}"
echo -e "${RED}  WARNING: Homelab Cluster Cleanup${NC}"
echo -e "${RED}========================================================${NC}"
echo ""
echo -e "${YELLOW}This script will REMOVE the following components:${NC}"
echo -e "  1. Prometheus Stack (Prometheus, Grafana, Alertmanager)"
echo -e "  2. NGINX Ingress Controller"
echo -e "  3. Cert-Manager (TLS certificate management)"
echo -e "  4. MetalLB (LoadBalancer service type support)"
echo -e "  5. NFS Subdir External Provisioner (dynamic storage)"
echo ""
echo -e "${RED}WARNING: This will DELETE all monitoring data and configurations!${NC}"
echo -e "${RED}PersistentVolumes will be retained but PVCs will be deleted.${NC}"
echo ""

# Ask for confirmation
read -p "Are you ABSOLUTELY SURE you want to proceed? Type 'yes' to continue: " -r
echo
if [[ ! $REPLY == "yes" ]]; then
    echo -e "${GREEN}Cleanup cancelled. No changes were made.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Step 1: Uninstalling Prometheus Stack${NC}"
echo -e "${BLUE}========================================================${NC}"

if helm list -n monitoring | grep -q prometheus; then
    echo -e "${YELLOW}Uninstalling Prometheus stack...${NC}"
    helm uninstall prometheus -n monitoring
    echo -e "${GREEN}✓ Prometheus stack uninstalled${NC}"
else
    echo -e "${YELLOW}Prometheus stack not found, skipping...${NC}"
fi

# Delete PVCs (PVs will be retained)
echo -e "${YELLOW}Deleting PVCs in monitoring namespace...${NC}"
kubectl delete pvc --all -n monitoring --ignore-not-found=true

echo ""
echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Step 2: Uninstalling NGINX Ingress Controller${NC}"
echo -e "${BLUE}========================================================${NC}"

if helm list -n ingress-nginx | grep -q ingress-nginx; then
    echo -e "${YELLOW}Uninstalling NGINX Ingress Controller...${NC}"
    helm uninstall ingress-nginx -n ingress-nginx
    echo -e "${GREEN}✓ NGINX Ingress Controller uninstalled${NC}"
else
    echo -e "${YELLOW}NGINX Ingress Controller not found, skipping...${NC}"
fi

echo ""
echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Step 3: Uninstalling Cert-Manager${NC}"
echo -e "${BLUE}========================================================${NC}"

# Delete certificate issuers first
echo -e "${YELLOW}Deleting ClusterIssuers...${NC}"
kubectl delete clusterissuers --all --ignore-not-found=true

echo -e "${YELLOW}Deleting Certificate resources...${NC}"
kubectl delete certificates --all --all-namespaces --ignore-not-found=true

if helm list -n cert-manager | grep -q cert-manager; then
    echo -e "${YELLOW}Uninstalling cert-manager...${NC}"
    helm uninstall cert-manager -n cert-manager
    echo -e "${GREEN}✓ Cert-manager uninstalled${NC}"
else
    echo -e "${YELLOW}Cert-manager not found, skipping...${NC}"
fi

# Delete CRDs
echo -e "${YELLOW}Deleting cert-manager CRDs...${NC}"
kubectl delete crd \
  certificates.cert-manager.io \
  certificaterequests.cert-manager.io \
  challenges.acme.cert-manager.io \
  clusterissuers.cert-manager.io \
  issuers.cert-manager.io \
  orders.acme.cert-manager.io \
  --ignore-not-found=true

echo ""
echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Step 4: Uninstalling MetalLB${NC}"
echo -e "${BLUE}========================================================${NC}"

echo -e "${YELLOW}Deleting MetalLB configuration...${NC}"
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml --ignore-not-found=true

echo -e "${YELLOW}Deleting MetalLB CRDs...${NC}"
kubectl delete crd \
  addresspools.metallb.io \
  bfdprofiles.metallb.io \
  bgpadvertisements.metallb.io \
  bgppeers.metallb.io \
  communities.metallb.io \
  ipaddresspools.metallb.io \
  l2advertisements.metallb.io \
  --ignore-not-found=true

echo -e "${GREEN}✓ MetalLB uninstalled${NC}"

echo ""
echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Step 5: Uninstalling NFS Subdir External Provisioner${NC}"
echo -e "${BLUE}========================================================${NC}"

if helm list -n nfs-provisioner | grep -q nfs-subdir-external-provisioner; then
    echo -e "${YELLOW}Uninstalling NFS provisioner...${NC}"
    helm uninstall nfs-subdir-external-provisioner -n nfs-provisioner
    echo -e "${GREEN}✓ NFS provisioner uninstalled${NC}"
else
    echo -e "${YELLOW}NFS provisioner not found, skipping...${NC}"
fi

# Delete the storage class
echo -e "${YELLOW}Deleting nfs-client StorageClass...${NC}"
kubectl delete storageclass nfs-client --ignore-not-found=true

echo ""
echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Step 6: Cleaning up namespaces${NC}"
echo -e "${BLUE}========================================================${NC}"

echo -e "${YELLOW}Deleting namespaces...${NC}"
kubectl delete namespace monitoring --ignore-not-found=true
kubectl delete namespace ingress-nginx --ignore-not-found=true
kubectl delete namespace cert-manager --ignore-not-found=true
kubectl delete namespace nfs-provisioner --ignore-not-found=true
kubectl delete namespace metallb-system --ignore-not-found=true

echo -e "${GREEN}✓ Namespaces deleted${NC}"

echo ""
echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Step 7: Cleaning up PersistentVolumes${NC}"
echo -e "${BLUE}========================================================${NC}"

echo -e "${YELLOW}Available PersistentVolumes:${NC}"
kubectl get pv

echo ""
read -p "Do you want to delete all PersistentVolumes? This will delete all data! (yes/n) " -r
echo
if [[ $REPLY == "yes" ]]; then
    echo -e "${YELLOW}Deleting PersistentVolumes...${NC}"
    kubectl delete pv prometheus-server-pv grafana-pv alertmanager-pv-0 alertmanager-pv-1 --ignore-not-found=true
    echo -e "${GREEN}✓ PersistentVolumes deleted${NC}"
else
    echo -e "${YELLOW}Keeping PersistentVolumes. You can delete them manually later.${NC}"
fi

echo ""
echo -e "${CYAN}========================================================${NC}"
echo -e "${CYAN}  Cleanup Complete!${NC}"
echo -e "${CYAN}========================================================${NC}"
echo ""
echo -e "${GREEN}All Helm charts and resources have been removed.${NC}"
echo ""
echo -e "${YELLOW}What was removed:${NC}"
echo -e "  ✓ All Helm releases"
echo -e "  ✓ All PersistentVolumeClaims"
echo -e "  ✓ All namespaces"
echo -e "  ✓ All custom resource definitions"
echo -e "  ✓ All storage classes"
echo ""

if [[ $REPLY != "yes" ]]; then
    echo -e "${YELLOW}What was kept:${NC}"
    echo -e "  ✓ PersistentVolumes (data still on NFS server)"
    echo ""
    echo -e "${YELLOW}To manually delete PVs:${NC}"
    echo -e "  kubectl delete pv prometheus-server-pv grafana-pv alertmanager-pv-0 alertmanager-pv-1"
fi

echo ""
echo -e "${YELLOW}Verify cleanup:${NC}"
echo -e "  kubectl get pods --all-namespaces"
echo -e "  kubectl get pvc --all-namespaces"
echo -e "  kubectl get pv"
echo -e "  helm list --all-namespaces"
echo ""
echo -e "${CYAN}========================================================${NC}"
