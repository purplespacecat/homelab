#!/bin/bash
# Install Ollama using Helm

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="ollama"
RELEASE_NAME="ollama"
CHART_REPO="otwld"
CHART_NAME="ollama"

echo "======================================"
echo "Ollama Helm Installation"
echo "======================================"
echo ""

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "Error: helm not found. Please install Helm first."
    echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found. Please install kubectl first."
    exit 1
fi

# Add Helm repository
echo "Adding Helm repository..."
helm repo add $CHART_REPO https://helm.otwld.com/ 2>/dev/null || true
helm repo update

echo ""
echo "Checking for existing installation..."
if helm status $RELEASE_NAME -n $NAMESPACE &> /dev/null; then
    echo "Found existing installation of $RELEASE_NAME in namespace $NAMESPACE"
    read -p "Do you want to upgrade it? [y/N]: " UPGRADE
    if [[ "$UPGRADE" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Upgrading Ollama..."
        helm upgrade $RELEASE_NAME $CHART_REPO/$CHART_NAME \
            -f "$SCRIPT_DIR/values.yaml" \
            --namespace $NAMESPACE

        echo ""
        echo "✓ Upgrade complete!"
    else
        echo "Aborted."
        exit 0
    fi
else
    echo "No existing installation found."
    echo ""

    # Prompt for ingress IP
    echo "Detecting ingress controller IP..."
    INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ -z "$INGRESS_IP" ]; then
        echo "Could not detect ingress IP automatically."
        read -p "Enter your ingress controller IP (or press Enter to use 192.168.100.202): " INGRESS_IP
        INGRESS_IP=${INGRESS_IP:-192.168.100.202}
    fi

    echo "Using ingress IP: $INGRESS_IP"
    echo ""

    # Update values.yaml with ingress IP
    sed -i.bak "s|ollama\.[0-9.]*\.nip\.io|ollama.$INGRESS_IP.nip.io|g" "$SCRIPT_DIR/values.yaml"

    # Ask about GPU support
    echo "GPU Support:"
    read -p "Do you have NVIDIA/AMD GPUs available? [y/N]: " HAS_GPU

    # Ask about models to pre-load
    echo ""
    echo "Model Pre-loading:"
    echo "Would you like to pre-load any models? (leave empty to skip)"
    echo "Available models: llama2, mistral, codellama, phi, etc."
    read -p "Enter model names (comma-separated): " MODELS

    # Create temp values file with customizations
    TEMP_VALUES=$(mktemp)
    cp "$SCRIPT_DIR/values.yaml" "$TEMP_VALUES"

    if [[ "$HAS_GPU" =~ ^[Yy]$ ]]; then
        read -p "GPU type? [nvidia/amd]: " GPU_TYPE
        GPU_TYPE=${GPU_TYPE:-nvidia}
        sed -i "s|enabled: false|enabled: true|g" "$TEMP_VALUES"
        sed -i "s|type: 'nvidia'|type: '$GPU_TYPE'|g" "$TEMP_VALUES"
    fi

    # Install Ollama
    echo ""
    echo "Installing Ollama..."
    helm install $RELEASE_NAME $CHART_REPO/$CHART_NAME \
        -f "$TEMP_VALUES" \
        --namespace $NAMESPACE \
        --create-namespace

    rm -f "$TEMP_VALUES"

    echo ""
    echo "✓ Installation complete!"
fi

# Wait for deployment
echo ""
echo "Waiting for Ollama to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment -n $NAMESPACE -l app.kubernetes.io/name=ollama || true

# Display status
echo ""
echo "======================================"
echo "Deployment Status"
echo "======================================"
helm status $RELEASE_NAME -n $NAMESPACE

echo ""
echo "======================================"
echo "Access Information"
echo "======================================"
echo ""
echo "Get LoadBalancer IP:"
echo "  kubectl get svc -n $NAMESPACE $RELEASE_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
echo ""

EXTERNAL_IP=$(kubectl get svc -n $NAMESPACE $RELEASE_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending...")
echo "LoadBalancer: http://$EXTERNAL_IP:11434"

INGRESS_HOST=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "not configured")
echo "Ingress: http://$INGRESS_HOST"
echo ""

echo "Test the API:"
echo "  curl http://$EXTERNAL_IP:11434/api/tags"
echo ""
echo "Pull a model:"
echo "  curl http://$EXTERNAL_IP:11434/api/pull -d '{\"name\": \"llama2\"}'"
echo ""
echo "View logs:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=ollama -f"
echo ""
echo "======================================"
