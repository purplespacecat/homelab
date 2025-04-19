#!/bin/bash
# Script to verify exposure of monitoring services
# and provide access information

echo "Checking ingress-nginx controller status..."
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Capture the external IP
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -z "$EXTERNAL_IP" ]; then
  echo "❌ No external IP found for ingress-nginx-controller"
  echo "MetalLB might not be properly configured or working"
  
  echo "Checking MetalLB pods..."
  kubectl get pods -n metallb-system
  
  echo "Checking MetalLB configuration..."
  kubectl get ipaddresspool -n metallb-system -o yaml
  kubectl get l2advertisement -n metallb-system -o yaml
else
  echo "✅ ingress-nginx-controller has external IP: $EXTERNAL_IP"
  
  # Add hosts entries suggestion
  echo ""
  echo "To access your services, you can either:"
  echo "1. Use nip.io domains (no host file changes required):"
  echo "   • Prometheus: http://prometheus.$EXTERNAL_IP.nip.io"
  echo "   • Grafana: http://grafana.$EXTERNAL_IP.nip.io"
  echo "   • Alertmanager: http://alertmanager.$EXTERNAL_IP.nip.io"
  echo ""
  echo "2. Add the following entries to your /etc/hosts file (requires admin privileges):"
  echo "   $EXTERNAL_IP prometheus.local grafana.local alertmanager.local"
  
  # Check that ingress resources exist
  echo ""
  echo "Checking ingress resources in the monitoring namespace..."
  kubectl get ingress -n monitoring
fi

# Check monitoring service status
echo ""
echo "Checking monitoring services status..."
kubectl get pods -n monitoring

# Check specific PVC issue with alertmanager
echo ""
echo "Checking Alertmanager PVC status..."
kubectl get pvc -n monitoring | grep alertmanager
echo ""
echo "Alertmanager PVC details:"
kubectl describe pvc -n monitoring $(kubectl get pvc -n monitoring | grep alertmanager | awk '{print $1}' | head -1) || echo "No Alertmanager PVCs found"

# Verify that the PVs exist
echo ""
echo "Checking PersistentVolumes for Alertmanager..."
kubectl get pv | grep alertmanager