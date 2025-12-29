#!/bin/bash

# Script to generate secure Grafana admin credentials
# This script creates and applies a Kubernetes secret with random admin password

echo "Generating secure Grafana credentials..."

# Set username
ADMIN_USER="admin"

# Generate a secure random password
ADMIN_PASSWORD=$(openssl rand -base64 15)

# Create a temporary file for the secret
cat << EOF > /tmp/grafana-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin-credentials
  namespace: monitoring
type: Opaque
stringData:
  admin-user: ${ADMIN_USER}
  admin-password: ${ADMIN_PASSWORD}
EOF

# Apply the secret
kubectl apply -f /tmp/grafana-secret.yaml

# Clean up the temporary file
rm /tmp/grafana-secret.yaml

echo "Grafana admin credentials created successfully!"
echo "Username: ${ADMIN_USER}"
echo "Password: ${ADMIN_PASSWORD}"
echo ""
echo "IMPORTANT: Please store this password securely. It will not be shown again."
echo "If you lose this password, you can rerun this script to generate a new one."