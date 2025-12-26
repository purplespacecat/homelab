#!/bin/bash
# Quick deployment script for Trackster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKSTER_REPO="/home/spacecrab/repos/trackster"

echo "======================================"
echo "Trackster Homelab Deployment Script"
echo "======================================"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: docker not found. Please install docker first."
    exit 1
fi

# Prompt for registry
echo "Select Docker registry option:"
echo "  1) Docker Hub (spacecrab/trackster:latest) [default]"
echo "  2) Local registry (localhost:5000)"
echo "  3) Custom registry"
echo "  4) Skip build (image already available)"
read -p "Enter option [1-4]: " REGISTRY_OPTION

if [ -z "$REGISTRY_OPTION" ] || [ "$REGISTRY_OPTION" = "1" ]; then
    IMAGE="spacecrab/trackster:latest"
elif [ "$REGISTRY_OPTION" = "2" ]; then
    IMAGE="localhost:5000/trackster:latest"
elif [ "$REGISTRY_OPTION" = "3" ]; then
    read -p "Enter registry URL (e.g., ghcr.io/username): " CUSTOM_REGISTRY
    IMAGE="$CUSTOM_REGISTRY/trackster:latest"
elif [ "$REGISTRY_OPTION" = "4" ]; then
    read -p "Enter image name: " IMAGE
else
    echo "Invalid option"
    exit 1
fi

# Build and push if not skipped
if [ "$REGISTRY_OPTION" != "4" ]; then
    echo ""
    echo "Building Docker image..."
    cd "$TRACKSTER_REPO"
    docker build -t trackster:latest .

    echo ""
    echo "Tagging image as $IMAGE..."
    docker tag trackster:latest "$IMAGE"

    # Check if pushing to Docker Hub and ensure login
    if [[ "$IMAGE" == spacecrab/* ]]; then
        echo ""
        echo "Checking Docker Hub authentication..."
        if ! docker info | grep -q "Username: spacecrab"; then
            echo "Please log in to Docker Hub:"
            docker login
        fi
    fi

    echo ""
    echo "Pushing image to registry..."
    docker push "$IMAGE"

    cd "$SCRIPT_DIR"
fi

# Check for API key
echo ""
if kubectl get secret trackster-secrets -n trackster &> /dev/null; then
    echo "✓ Secret 'trackster-secrets' already exists"
    read -p "Do you want to update it? [y/N]: " UPDATE_SECRET
    if [[ "$UPDATE_SECRET" =~ ^[Yy]$ ]]; then
        read -sp "Enter your GEMINI_API_KEY: " API_KEY
        echo ""
        ./create-secret.sh "$API_KEY"
    fi
else
    echo "Secret 'trackster-secrets' not found"
    read -sp "Enter your GEMINI_API_KEY (get it at https://aistudio.google.com/apikey): " API_KEY
    echo ""
    ./create-secret.sh "$API_KEY"
fi

# Update deployment YAML with image
echo ""
echo "Updating deployment configuration..."
sed -i.bak "s|image:.*trackster.*|image: $IMAGE|g" trackster-deployment.yaml

# Get ingress IP
echo ""
echo "Detecting ingress controller IP..."
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -z "$INGRESS_IP" ]; then
    echo "Could not detect ingress IP automatically."
    read -p "Enter your ingress controller IP (or press Enter to use 192.168.100.202): " INGRESS_IP
    INGRESS_IP=${INGRESS_IP:-192.168.100.202}
fi

echo "Using ingress IP: $INGRESS_IP"
sed -i.bak "s|trackster\.[0-9.]*\.nip\.io|trackster.$INGRESS_IP.nip.io|g" trackster-deployment.yaml

# Deploy
echo ""
echo "Deploying to Kubernetes..."
kubectl apply -f trackster-deployment.yaml

# Wait for deployment
echo ""
echo "Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/trackster -n trackster || true

# Display status
echo ""
echo "======================================"
echo "Deployment Status"
echo "======================================"
kubectl get all -n trackster

echo ""
echo "======================================"
echo "Access Information"
echo "======================================"
echo ""
echo "Web UI (via Ingress):"
echo "  http://trackster.$INGRESS_IP.nip.io"
echo ""
echo "Web UI (via LoadBalancer):"
EXTERNAL_IP=$(kubectl get svc -n trackster trackster-web-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending...")
echo "  http://$EXTERNAL_IP:3000"
echo ""
echo "API Documentation:"
echo "  http://trackster.$INGRESS_IP.nip.io/api/docs"
echo ""
echo "View logs:"
echo "  kubectl logs -n trackster -l app=trackster -f"
echo ""
echo "======================================"
