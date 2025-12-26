#!/bin/bash
# Script to create Kubernetes secret for Trackster GEMINI_API_KEY

set -e

# Check if API key is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <GEMINI_API_KEY>"
    echo ""
    echo "Example:"
    echo "  $0 AIzaSyA..."
    echo ""
    echo "Get your API key at: https://aistudio.google.com/apikey"
    exit 1
fi

GEMINI_API_KEY="$1"

# Create namespace if it doesn't exist
kubectl create namespace trackster --dry-run=client -o yaml | kubectl apply -f -

# Create or update the secret
kubectl create secret generic trackster-secrets \
    --from-literal=GEMINI_API_KEY="$GEMINI_API_KEY" \
    --namespace=trackster \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Secret created successfully in trackster namespace"
echo ""
echo "You can now deploy trackster using:"
echo "  kubectl apply -f trackster-deployment.yaml"
