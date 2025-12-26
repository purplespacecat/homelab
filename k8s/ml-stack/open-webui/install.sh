#!/bin/bash
# Install Open WebUI using Helm

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="open-webui"
RELEASE_NAME="open-webui"
CHART_REPO="open-webui"
CHART_NAME="open-webui"

echo "======================================"
echo "Open WebUI Installation"
echo "======================================"
echo ""

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "Error: helm not found. Please install Helm first."
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if Ollama is deployed
echo "Checking for Ollama deployment..."
if ! kubectl get deployment ollama -n ollama &> /dev/null; then
    echo "Warning: Ollama deployment not found in 'ollama' namespace."
    echo "Open WebUI requires Ollama to function."
    read -p "Do you want to continue anyway? [y/N]: " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo "Please deploy Ollama first:"
        echo "  cd ../helm/ollama && ./install.sh"
        exit 1
    fi
fi

# Add Helm repository
echo "Adding Helm repository..."
helm repo add $CHART_REPO https://helm.openwebui.com/ 2>/dev/null || true
helm repo update

echo ""
echo "Checking for existing installation..."
if helm status $RELEASE_NAME -n $NAMESPACE &> /dev/null; then
    echo "Found existing installation of $RELEASE_NAME in namespace $NAMESPACE"
    echo ""
    echo "⚠️  IMPORTANT: Scaling down to 1 replica before upgrade"
    echo "   (Prevents database corruption)"
    kubectl scale deployment $RELEASE_NAME -n $NAMESPACE --replicas=1 2>/dev/null || true
    sleep 5

    read -p "Do you want to upgrade it? [y/N]: " UPGRADE
    if [[ "$UPGRADE" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Upgrading Open WebUI..."
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
    sed -i.bak "s|open-webui\.[0-9.]*\.nip\.io|open-webui.$INGRESS_IP.nip.io|g" "$SCRIPT_DIR/values.yaml"

    # Install Open WebUI
    echo ""
    echo "Installing Open WebUI..."
    helm install $RELEASE_NAME $CHART_REPO/$CHART_NAME \
        -f "$SCRIPT_DIR/values.yaml" \
        --namespace $NAMESPACE \
        --create-namespace

    echo ""
    echo "✓ Installation complete!"
fi

# Wait for deployment
echo ""
echo "Waiting for Open WebUI to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment -n $NAMESPACE -l app.kubernetes.io/name=open-webui || true

# Display status
echo ""
echo "======================================"
echo "Deployment Status"
echo "======================================"
kubectl get all -n $NAMESPACE

echo ""
echo "======================================"
echo "Access Information"
echo "======================================"
echo ""

INGRESS_HOST=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "not configured")
EXTERNAL_IP=$(kubectl get svc -n $NAMESPACE $RELEASE_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending...")

echo "Web Interface:"
echo "  Via Ingress: http://$INGRESS_HOST"
echo "  Via LoadBalancer: http://$EXTERNAL_IP"
echo ""
echo "First Time Setup:"
echo "  1. Open the web interface"
echo "  2. Create your admin account (first user = admin)"
echo "  3. Log in and start chatting with Ollama!"
echo ""
echo "Features:"
echo "  ✓ ChatGPT-like interface"
echo "  ✓ Document upload (RAG)"
echo "  ✓ Multi-user support"
echo "  ✓ Model switching"
echo "  ✓ Prompt management"
echo ""
echo "Connected to Ollama:"
echo "  http://ollama.ollama.svc.cluster.local:11434"
echo ""
echo "View logs:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=open-webui -f"
echo ""
echo "======================================"
