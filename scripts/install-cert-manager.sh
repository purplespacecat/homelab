#!/bin/bash

# Colors for formatting output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Cert-Manager Installation Script for Homelab${NC}"
echo -e "${BLUE}========================================================${NC}"

# Step 1: Install cert-manager (namespace and Helm chart only)
echo -e "\n${YELLOW}Installing cert-manager namespace and Helm chart...${NC}"
kubectl apply -f k8s/cert-manager/cert-manager.yaml
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to install cert-manager. Exiting.${NC}"
    exit 1
fi

# Step 2: Wait for cert-manager and webhook to be ready
echo -e "\n${YELLOW}Waiting for cert-manager to be ready...${NC}"
echo -e "${YELLOW}This may take a minute or two...${NC}"
echo -e "${YELLOW}Waiting for cert-manager deployment...${NC}"
kubectl -n cert-manager wait --for=condition=available deployment --all --timeout=180s
if [ $? -ne 0 ]; then
    echo -e "${RED}Timed out waiting for cert-manager deployments. Check status with 'kubectl get pods -n cert-manager'${NC}"
    exit 1
fi

# Step 3: Verify webhook is working
echo -e "\n${YELLOW}Verifying cert-manager webhook is active...${NC}"
WEBHOOK_READY=false
for i in {1..10}; do
    if kubectl get pods -n cert-manager | grep -q "webhook.*Running"; then
        WEBHOOK_READY=true
        break
    fi
    echo -e "${YELLOW}Waiting for webhook to be ready... attempt $i/10${NC}"
    sleep 5
done

if [ "$WEBHOOK_READY" = "false" ]; then
    echo -e "${RED}Webhook is not running. Check status with 'kubectl get pods -n cert-manager'${NC}"
    exit 1
fi

echo -e "${GREEN}Cert-manager is running. Waiting 10 more seconds for CRDs to be fully established...${NC}"
sleep 10

# Step 4: Apply ClusterIssuers
echo -e "\n${YELLOW}Creating ClusterIssuers...${NC}"
kubectl apply -f k8s/cert-manager/cert-manager-issuers.yaml
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create ClusterIssuers. Check if CRDs are fully installed.${NC}"
    echo -e "${RED}You may need to wait a bit longer and run: kubectl apply -f k8s/cert-manager/cert-manager-issuers.yaml${NC}"
    exit 1
fi

# Step 5: Verify ClusterIssuers
echo -e "\n${YELLOW}Verifying ClusterIssuers...${NC}"
kubectl get clusterissuers
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to get ClusterIssuers. Something went wrong.${NC}"
    exit 1
fi

echo -e "\n${GREEN}✓ Cert-manager installation successful!${NC}"
echo -e "${BLUE}========================================================${NC}"
echo -e "${GREEN}You can now use the following issuers in your ingress resources:${NC}"
echo -e "  - selfsigned-issuer (for development/testing)"
echo -e "  - homelab-issuer (for your homelab environment)"
echo -e "\n${YELLOW}Don't forget to update the email address in the homelab-issuer:${NC}"
echo -e "  kubectl edit clusterissuer homelab-issuer"
echo -e "${BLUE}========================================================${NC}"