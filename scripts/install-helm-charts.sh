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
echo -e "${YELLOW}Applying MetalLB manifests...${NC}"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb-operator/v0.13.12/config/manifests/metallb-native.yaml
echo -e "${YELLOW}Waiting for MetalLB resources to be created...${NC}"
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s || true
echo -e "${YELLOW}Applying MetalLB configuration...${NC}"
kubectl apply -f ../k8s/core/networking/metallb-config.yaml
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
echo -e "${YELLOW}Adding grafana repository...${NC}"
helm repo add grafana https://grafana.github.io/helm-charts
echo -e "${YELLOW}Updating Helm repositories...${NC}"
helm repo update
echo -e "${GREEN}✓ Helm repositories added and updated${NC}"

# Install NGINX Ingress Controller
echo -e "\n${BLUE}Installing NGINX Ingress Controller...${NC}"
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  -f ../k8s/helm/ingress-nginx/values.yaml
echo -e "${YELLOW}Waiting for NGINX Ingress Controller to be ready...${NC}"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s || true
echo -e "${GREEN}✓ NGINX Ingress Controller installed${NC}"

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
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f ../k8s/helm/prometheus/values.yaml
echo -e "${YELLOW}Waiting for Prometheus resources to be created...${NC}"
kubectl wait --namespace monitoring \
  --for=condition=ready pod \
  --selector=app=prometheus \
  --timeout=120s || true
echo -e "${GREEN}✓ Prometheus Stack installed${NC}"

# Install Loki Stack
echo -e "\n${BLUE}Installing Loki Stack...${NC}"
helm install loki grafana/loki \
  --namespace monitoring \
  -f ../k8s/helm/loki/values.yaml
echo -e "${YELLOW}Waiting for Loki resources to be created...${NC}"
kubectl wait --namespace monitoring \
  --for=condition=ready pod \
  --selector=app=loki \
  --timeout=120s || true
echo -e "${GREEN}✓ Loki Stack installed${NC}"

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
  echo -e "Loki: ${GREEN}http://loki.$EXTERNAL_IP.nip.io${NC}"
else
  echo -e "${YELLOW}The External IP of the NGINX Ingress Controller could not be detected.${NC}"
  echo -e "${YELLOW}Run the following command to get the External IP:${NC}"
  echo -e "kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
  echo -e "${YELLOW}Then, you can access the services at:${NC}"
  echo -e "Prometheus: http://prometheus.<EXTERNAL_IP>.nip.io"
  echo -e "Grafana: http://grafana.<EXTERNAL_IP>.nip.io (default credentials: admin/admin)"
  echo -e "Alertmanager: http://alertmanager.<EXTERNAL_IP>.nip.io"
  echo -e "Loki: http://loki.<EXTERNAL_IP>.nip.io"
fi