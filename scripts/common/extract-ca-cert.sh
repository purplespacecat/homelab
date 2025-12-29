#!/bin/bash

# Colors for formatting output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Extract Homelab CA Certificate for Browser Import${NC}"
echo -e "${BLUE}========================================================${NC}"

# Create output directory
mkdir -p ~/homelab-ca

# Wait for the CA secret to be created
echo -e "\n${YELLOW}Waiting for CA certificate to be created...${NC}"
kubectl wait --for=condition=Ready clusterissuer homelab-ca-issuer --timeout=60s
if [ $? -ne 0 ]; then
    echo -e "${RED}Timed out waiting for CA issuer. Make sure you've applied local-ca.yaml${NC}"
    echo -e "${RED}Run: kubectl apply -f k8s/cert-manager/local-ca.yaml${NC}"
    exit 1
fi

# Extract CA certificate from secret
echo -e "\n${YELLOW}Extracting CA certificate from secret...${NC}"
kubectl get secret homelab-ca-key-pair -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > ~/homelab-ca/homelab-ca.crt
kubectl get secret homelab-ca-key-pair -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > ~/homelab-ca/homelab-tls.crt

# Create a .pem file as well (some systems prefer this format)
cp ~/homelab-ca/homelab-ca.crt ~/homelab-ca/homelab-ca.pem

# Verify certificate was extracted
if [ -s ~/homelab-ca/homelab-ca.crt ]; then
    echo -e "${GREEN}✓ CA Certificate extracted successfully to ~/homelab-ca/homelab-ca.crt${NC}"
    echo -e "${GREEN}✓ Also saved as ~/homelab-ca/homelab-ca.pem${NC}"
else
    echo -e "${RED}Failed to extract CA certificate${NC}"
    exit 1
fi

echo -e "\n${BLUE}========================================================${NC}"
echo -e "${GREEN}✓ CA Certificate ready for import!${NC}"
echo -e "${BLUE}========================================================${NC}"
echo -e "${YELLOW}Import instructions:${NC}"
echo -e "1. ${YELLOW}Chrome/Edge:${NC} Settings → Privacy and security → Security → Manage certificates → Authorities → Import"
echo -e "2. ${YELLOW}Firefox:${NC} Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import"
echo -e "3. ${YELLOW}Safari:${NC} Import into Keychain Access app, then trust the certificate"

echo -e "\n${YELLOW}When importing, ensure you select 'Trust this CA to identify websites'${NC}"

# Show certificate details
echo -e "\n${YELLOW}Certificate details:${NC}"
openssl x509 -in ~/homelab-ca/homelab-ca.crt -text -noout | grep -E 'Subject:|Issuer:|Not Before:|Not After :|Subject Alternative Name:'

echo -e "\n${GREEN}Don't forget to update your app ingresses to use homelab-ca-issuer instead of selfsigned-issuer${NC}"