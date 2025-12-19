#!/bin/bash
# Script to install Helm and deploy all necessary charts for the monitoring stack
# Usage: ./install-helm-charts.sh

set -e

# Colors for formatting output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Helm and Charts Installation Script for Kubernetes Homelab${NC}"
echo -e "${BLUE}========================================================${NC}"

# Check if kubectl is installed
echo -e "\n${BLUE}Checking if kubectl is installed...${NC}"
if command -v kubectl &> /dev/null; then
    echo -e "${GREEN}✓ kubectl is installed${NC}"
    kubectl version --client
else
    echo -e "${RED}✗ kubectl is not installed. Please install kubectl first.${NC}"
    echo -e "${YELLOW}You can install it with:${NC}"
    echo -e "curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
    echo -e "chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
    exit 1
fi

# Check if connected to a Kubernetes cluster
echo -e "\n${BLUE}Checking connection to Kubernetes cluster...${NC}"
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓ Connected to Kubernetes cluster${NC}"
    kubectl cluster-info
else
    echo -e "${RED}✗ Not connected to a Kubernetes cluster. Please configure kubeconfig.${NC}"
    exit 1
fi

# Install Helm if not already installed
echo -e "\n${BLUE}Checking if Helm is installed...${NC}"
if command -v helm &> /dev/null; then
    echo -e "${GREEN}✓ Helm is installed${NC}"
    helm version
else
    echo -e "${YELLOW}Helm is not installed. Installing Helm...${NC}"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Helm installed successfully${NC}"
        helm version
    else
        echo -e "${RED}✗ Failed to install Helm${NC}"
        exit 1
    fi
fi

# Create Kubernetes namespaces
echo -e "\n${BLUE}Creating Kubernetes namespaces...${NC}"
echo -e "${YELLOW}Creating monitoring namespace...${NC}"
kubectl apply -f ../k8s/core/namespaces/monitoring-namespaces.yaml
echo -e "${YELLOW}Creating ingress-nginx namespace...${NC}"
kubectl apply -f ../k8s/core/namespaces/ingress-nginx-namespace.yaml

# Install MetalLB
echo -e "\n${BLUE}Installing MetalLB...${NC}"
METALLB_VERSION="v0.14.9"
echo -e "${YELLOW}Applying MetalLB manifests (${METALLB_VERSION})...${NC}"
if kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml; then
    echo -e "${GREEN}✓ MetalLB manifests applied${NC}"
else
    echo -e "${RED}✗ Failed to apply MetalLB manifests${NC}"
    echo -e "${YELLOW}Check if the URL is accessible and the version is correct${NC}"
    exit 1
fi

# Create memberlist secret if it doesn't exist (required for MetalLB speaker nodes)
echo -e "${YELLOW}Creating MetalLB memberlist secret...${NC}"
if ! kubectl get secret memberlist -n metallb-system &>/dev/null; then
    kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
    echo -e "${GREEN}✓ Memberlist secret created${NC}"
else
    echo -e "${GREEN}✓ Memberlist secret already exists${NC}"
fi

echo -e "${YELLOW}Waiting for MetalLB controller to be ready...${NC}"
if kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb,component=controller \
  --timeout=120s; then
    echo -e "${GREEN}✓ MetalLB controller is ready${NC}"
else
    echo -e "${RED}✗ MetalLB controller failed to become ready${NC}"
    echo -e "${YELLOW}Checking pod status...${NC}"
    kubectl get pods -n metallb-system
    kubectl describe pods -n metallb-system
fi

echo -e "${YELLOW}Waiting for MetalLB speaker to be ready...${NC}"
if kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb,component=speaker \
  --timeout=120s; then
    echo -e "${GREEN}✓ MetalLB speaker is ready${NC}"
else
    echo -e "${YELLOW}⚠ MetalLB speaker may still be starting${NC}"
fi

echo -e "${YELLOW}Applying MetalLB configuration...${NC}"
# Wait a bit for CRDs to be fully established
sleep 5
if kubectl apply -f ../k8s/core/networking/metallb-config.yaml; then
    echo -e "${GREEN}✓ MetalLB configuration applied${NC}"
else
    echo -e "${RED}✗ Failed to apply MetalLB configuration${NC}"
    echo -e "${YELLOW}This might be a CRD timing issue. Retrying in 10 seconds...${NC}"
    sleep 10
    kubectl apply -f ../k8s/core/networking/metallb-config.yaml
fi
echo -e "${GREEN}✓ MetalLB installed${NC}"

# Setup storage for monitoring stack
echo -e "\n${BLUE}Setting up storage for monitoring stack...${NC}"
echo -e "${YELLOW}Creating PersistentVolumes...${NC}"
kubectl apply -f ../k8s/core/storage/monitoring-storage.yaml
echo -e "${GREEN}✓ PersistentVolumes created${NC}"
echo -e "${YELLOW}Verifying PersistentVolumes...${NC}"
kubectl get pv

# Add Helm repositories
echo -e "\n${BLUE}Adding Helm repositories...${NC}"
echo -e "${YELLOW}Adding ingress-nginx repository...${NC}"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
echo -e "${YELLOW}Adding prometheus-community repository...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
echo -e "${YELLOW}Updating Helm repositories...${NC}"
helm repo update
echo -e "${GREEN}✓ Helm repositories added and updated${NC}"

# Install NGINX Ingress Controller
echo -e "\n${BLUE}Installing NGINX Ingress Controller...${NC}"
# Disable admission webhooks to avoid installation failures
# Schedule on control plane to avoid worker node connectivity issues
if helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  -f ../k8s/helm/ingress-nginx/values.yaml \
  --set controller.admissionWebhooks.enabled=false \
  --set controller.nodeSelector."kubernetes\.io/hostname"=spaceship \
  --wait --timeout=3m; then
  echo -e "${GREEN}✓ NGINX Ingress Controller installed successfully${NC}"
else
  echo -e "${RED}✗ NGINX Ingress Controller installation had issues${NC}"
  echo -e "${YELLOW}Checking status...${NC}"
  kubectl get pods -n ingress-nginx
  echo -e "${YELLOW}Continuing with installation...${NC}"
fi

# Verify the controller is running
if kubectl get deployment -n ingress-nginx ingress-nginx-controller &>/dev/null; then
  echo -e "${GREEN}✓ Ingress controller deployment exists${NC}"
else
  echo -e "${RED}✗ Ingress controller deployment not found${NC}"
fi

# Get the External IP of the NGINX Ingress Controller
echo -e "\n${YELLOW}Getting External IP of NGINX Ingress Controller...${NC}"
EXTERNAL_IP=""
ATTEMPTS=0
MAX_ATTEMPTS=30

while [ -z "$EXTERNAL_IP" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -z "$EXTERNAL_IP" ]; then
    echo -e "${YELLOW}Waiting for External IP to be assigned... (Attempt $((ATTEMPTS+1))/$MAX_ATTEMPTS)${NC}"
    ATTEMPTS=$((ATTEMPTS+1))
    sleep 5
  fi
done

if [ -z "$EXTERNAL_IP" ]; then
  echo -e "${RED}✗ Failed to get External IP for NGINX Ingress Controller${NC}"
  echo -e "${YELLOW}Continuing with installation. You will need to manually update the nip.io domains.${NC}"
else
  echo -e "${GREEN}✓ External IP of NGINX Ingress Controller: $EXTERNAL_IP${NC}"
  
  # Update the Prometheus values.yaml file with the correct External IP for nip.io domains
  echo -e "\n${YELLOW}Updating Prometheus values.yaml with correct External IP for nip.io domains...${NC}"
  sed -i "s/192\.168\.100\.[0-9]\+\.nip\.io/$EXTERNAL_IP.nip.io/g" ../k8s/helm/prometheus/values.yaml
  echo -e "${GREEN}✓ Prometheus values.yaml updated with correct External IP${NC}"
fi

# Install Prometheus Stack
echo -e "\n${BLUE}Installing Prometheus Stack...${NC}"
if helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f ../k8s/helm/prometheus/values.yaml \
  --wait --timeout=5m; then
  echo -e "${GREEN}✓ Prometheus Stack installed successfully${NC}"
else
  echo -e "${RED}✗ Prometheus Stack installation had issues${NC}"
  echo -e "${YELLOW}Checking status...${NC}"
  kubectl get pods -n monitoring
  echo -e "${YELLOW}The installation may still be in progress. Check with: kubectl get pods -n monitoring${NC}"
fi

# Verify the deployment
echo -e "\n${BLUE}Verifying deployment...${NC}"
echo -e "${YELLOW}Checking Ingress resources...${NC}"
kubectl get ingress -n monitoring
echo -e "${YELLOW}Checking PersistentVolumeClaims...${NC}"
kubectl get pvc -n monitoring
echo -e "${YELLOW}Checking Pods...${NC}"
kubectl get pods -n monitoring

# Print access information
echo -e "\n${BLUE}========================================================${NC}"
echo -e "${GREEN}✓ Installation complete!${NC}"
echo -e "${BLUE}========================================================${NC}"
echo -e "You can access the services at the following URLs:"
if [ ! -z "$EXTERNAL_IP" ]; then
  echo -e "Prometheus: ${GREEN}http://prometheus.$EXTERNAL_IP.nip.io${NC}"
  echo -e "Grafana: ${GREEN}http://grafana.$EXTERNAL_IP.nip.io${NC} (default credentials: admin/admin)"
  echo -e "Alertmanager: ${GREEN}http://alertmanager.$EXTERNAL_IP.nip.io${NC}"
else
  echo -e "${YELLOW}The External IP of the NGINX Ingress Controller could not be detected.${NC}"
  echo -e "${YELLOW}Run the following command to get the External IP:${NC}"
  echo -e "kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
  echo -e "${YELLOW}Then, you can access the services at:${NC}"
  echo -e "Prometheus: http://prometheus.<EXTERNAL_IP>.nip.io"
  echo -e "Grafana: http://grafana.<EXTERNAL_IP>.nip.io (default credentials: admin/admin)"
  echo -e "Alertmanager: http://alertmanager.<EXTERNAL_IP>.nip.io"
fi