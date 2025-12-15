#!/bin/bash

# Script to install cert-manager using Helm
# cert-manager provides TLS certificate management for Kubernetes

set -e

# Colors for formatting output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Cert-Manager Installation Script for Homelab${NC}"
echo -e "${BLUE}========================================================${NC}"

# Configuration
NAMESPACE="${NAMESPACE:-cert-manager}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.13.1}"

echo -e "\n${YELLOW}Configuration:${NC}"
echo -e "  Namespace: ${NAMESPACE}"
echo -e "  Version: ${CERT_MANAGER_VERSION}"
echo ""

# Step 1: Add Helm repository
echo -e "${YELLOW}Adding cert-manager Helm repository...${NC}"
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Step 2: Create namespace
echo -e "\n${YELLOW}Creating namespace ${NAMESPACE}...${NC}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Step 3: Install cert-manager
echo -e "\n${YELLOW}Installing cert-manager Helm chart...${NC}"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace ${NAMESPACE} \
  --version ${CERT_MANAGER_VERSION} \
  --set installCRDs=true \
  --set podSecurityPolicy.enabled=false

# Step 4: Wait for cert-manager to be ready
echo -e "\n${YELLOW}Waiting for cert-manager to be ready...${NC}"
echo -e "${YELLOW}This may take a minute or two...${NC}"

kubectl -n ${NAMESPACE} wait --for=condition=available deployment --all --timeout=300s

if [ $? -ne 0 ]; then
    echo -e "${RED}Timed out waiting for cert-manager deployments. Check status with 'kubectl get pods -n ${NAMESPACE}'${NC}"
    exit 1
fi

# Step 5: Verify webhook is working
echo -e "\n${YELLOW}Verifying cert-manager webhook is active...${NC}"
WEBHOOK_READY=false
for i in {1..10}; do
    if kubectl get pods -n ${NAMESPACE} | grep -q "webhook.*Running"; then
        WEBHOOK_READY=true
        break
    fi
    echo -e "${YELLOW}Waiting for webhook to be ready... attempt $i/10${NC}"
    sleep 5
done

if [ "$WEBHOOK_READY" = "false" ]; then
    echo -e "${RED}Webhook is not running. Check status with 'kubectl get pods -n ${NAMESPACE}'${NC}"
    exit 1
fi

echo -e "${GREEN}Cert-manager is running. Waiting 10 more seconds for CRDs to be fully established...${NC}"
sleep 10

# Step 6: Apply local CA configuration
echo -e "\n${YELLOW}Creating local CA for homelab...${NC}"
kubectl apply -f k8s/cert-manager/local-ca.yaml

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create local CA. Check the configuration.${NC}"
    exit 1
fi

# Step 7: Apply ClusterIssuers
echo -e "\n${YELLOW}Creating ClusterIssuers...${NC}"
kubectl apply -f k8s/cert-manager/cert-manager-issuers.yaml

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create ClusterIssuers. Check if CRDs are fully installed.${NC}"
    echo -e "${RED}You may need to wait a bit longer and run: kubectl apply -f k8s/cert-manager/cert-manager-issuers.yaml${NC}"
    exit 1
fi

# Step 8: Verify ClusterIssuers
echo -e "\n${YELLOW}Verifying ClusterIssuers...${NC}"
sleep 5
kubectl get clusterissuers

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to get ClusterIssuers. Something went wrong.${NC}"
    exit 1
fi

echo -e "\n${GREEN}✓ Cert-manager installation successful!${NC}"
echo -e "${BLUE}========================================================${NC}"
echo -e "${GREEN}Available certificate issuers:${NC}"
echo -e "  - selfsigned-ca-issuer (self-signed root CA)"
echo -e "  - homelab-ca-issuer (certificates signed by homelab CA)"
echo -e "  - homelab-issuer (Let's Encrypt for public certificates)"
echo ""
echo -e "${YELLOW}Usage in ingress resources:${NC}"
echo -e "  cert-manager.io/cluster-issuer: \"homelab-ca-issuer\""
echo ""
echo -e "${YELLOW}Don't forget to update the email address in homelab-issuer:${NC}"
echo -e "  kubectl edit clusterissuer homelab-issuer"
echo -e "${BLUE}========================================================${NC}"
