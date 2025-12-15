#!/bin/bash

# Master script to install all Helm charts for the kubeadm cluster
# This script orchestrates the complete installation of the homelab stack

set -e

# Colors for formatting output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${CYAN}========================================================${NC}"
echo -e "${CYAN}  Homelab Kubeadm Cluster - Complete Installation${NC}"
echo -e "${CYAN}========================================================${NC}"
echo ""
echo -e "${YELLOW}This script will install the following components:${NC}"
echo -e "  1. NFS Subdir External Provisioner (dynamic storage)"
echo -e "  2. MetalLB (LoadBalancer service type support)"
echo -e "  3. Cert-Manager (TLS certificate management)"
echo -e "  4. NGINX Ingress Controller"
echo -e "  5. Prometheus Stack (Prometheus, Grafana, Alertmanager)"
echo ""

# Ask for confirmation
read -p "Do you want to proceed with the installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Installation cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Step 1: Installing NFS Subdir External Provisioner${NC}"
echo -e "${BLUE}========================================================${NC}"

if [ -f "${SCRIPT_DIR}/install-nfs-provisioner.sh" ]; then
    bash "${SCRIPT_DIR}/install-nfs-provisioner.sh"
else
    echo -e "${RED}Error: install-nfs-provisioner.sh not found${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Step 2: Installing MetalLB${NC}"
echo -e "${BLUE}========================================================${NC}"

echo -e "${YELLOW}Installing MetalLB native manifests...${NC}"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

echo -e "${YELLOW}Waiting for MetalLB controller to be ready...${NC}"
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=300s || true

echo -e "${YELLOW}Applying MetalLB configuration...${NC}"
sleep 10  # Wait for CRDs to be established
kubectl apply -f "${SCRIPT_DIR}/../k8s/core/networking/metallb-config.yaml"

echo -e "${GREEN}✓ MetalLB installation complete${NC}"

echo ""
echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Step 3: Installing Cert-Manager${NC}"
echo -e "${BLUE}========================================================${NC}"

if [ -f "${SCRIPT_DIR}/install-cert-manager.sh" ]; then
    bash "${SCRIPT_DIR}/install-cert-manager.sh"
else
    echo -e "${RED}Error: install-cert-manager.sh not found${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Step 4: Installing NGINX Ingress Controller${NC}"
echo -e "${BLUE}========================================================${NC}"

# Create namespace
echo -e "${YELLOW}Creating ingress-nginx namespace...${NC}"
kubectl apply -f "${SCRIPT_DIR}/../k8s/core/namespaces/ingress-nginx-namespace.yaml"

# Add Helm repository
echo -e "${YELLOW}Adding NGINX Ingress Helm repository...${NC}"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress
echo -e "${YELLOW}Installing NGINX Ingress Controller...${NC}"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  -f "${SCRIPT_DIR}/../k8s/helm/ingress-nginx/values.yaml"

echo -e "${YELLOW}Waiting for NGINX Ingress Controller to be ready...${NC}"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo -e "${GREEN}✓ NGINX Ingress Controller installation complete${NC}"

# Display the external IP
echo ""
echo -e "${YELLOW}Getting LoadBalancer external IP...${NC}"
EXTERNAL_IP=""
for i in {1..30}; do
    EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -n "$EXTERNAL_IP" ]; then
        break
    fi
    echo -e "${YELLOW}Waiting for external IP... attempt $i/30${NC}"
    sleep 2
done

if [ -n "$EXTERNAL_IP" ]; then
    echo -e "${GREEN}NGINX Ingress Controller external IP: ${EXTERNAL_IP}${NC}"
    echo -e "${YELLOW}You can access services using: http://servicename.${EXTERNAL_IP}.nip.io${NC}"
else
    echo -e "${RED}Failed to get external IP. Check MetalLB configuration.${NC}"
fi

echo ""
echo -e "${BLUE}========================================================${NC}"
echo -e "${BLUE}  Step 5: Installing Prometheus Stack${NC}"
echo -e "${BLUE}========================================================${NC}"

# Create monitoring namespace
echo -e "${YELLOW}Creating monitoring namespace...${NC}"
kubectl apply -f "${SCRIPT_DIR}/../k8s/core/namespaces/monitoring-namespaces.yaml"

# Create monitoring storage (static PVs)
echo -e "${YELLOW}Creating monitoring storage (PVs)...${NC}"
kubectl apply -f "${SCRIPT_DIR}/../k8s/core/storage/monitoring-storage.yaml"

# Generate Grafana credentials if script exists
if [ -f "${SCRIPT_DIR}/generate-grafana-creds.sh" ]; then
    echo -e "${YELLOW}Generating Grafana credentials...${NC}"
    bash "${SCRIPT_DIR}/generate-grafana-creds.sh"
fi

# Add Prometheus Helm repository
echo -e "${YELLOW}Adding Prometheus Helm repository...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus stack
echo -e "${YELLOW}Installing Prometheus stack (Prometheus, Grafana, Alertmanager)...${NC}"
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f "${SCRIPT_DIR}/../k8s/helm/prometheus/values.yaml"

echo -e "${YELLOW}Waiting for Prometheus stack to be ready...${NC}"
kubectl wait --namespace monitoring \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=prometheus \
  --timeout=300s || true

echo -e "${GREEN}✓ Prometheus stack installation complete${NC}"

echo ""
echo -e "${CYAN}========================================================${NC}"
echo -e "${CYAN}  Installation Complete!${NC}"
echo -e "${CYAN}========================================================${NC}"
echo ""
echo -e "${GREEN}All components have been successfully installed.${NC}"
echo ""
echo -e "${YELLOW}Access your services:${NC}"

if [ -n "$EXTERNAL_IP" ]; then
    echo -e "  Prometheus:    http://prometheus.${EXTERNAL_IP}.nip.io"
    echo -e "  Grafana:       http://grafana.${EXTERNAL_IP}.nip.io"
    echo -e "  Alertmanager:  http://alertmanager.${EXTERNAL_IP}.nip.io"
else
    echo -e "  Run: ${SCRIPT_DIR}/verify-exposure.sh"
fi

echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo -e "  kubectl get pods --all-namespaces"
echo -e "  kubectl get svc --all-namespaces"
echo -e "  kubectl get ingress --all-namespaces"
echo -e "  kubectl get pvc --all-namespaces"
echo ""
echo -e "${YELLOW}Verify installation:${NC}"
echo -e "  ${SCRIPT_DIR}/verify-exposure.sh"
echo ""
echo -e "${CYAN}========================================================${NC}"
