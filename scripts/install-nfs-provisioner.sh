#!/bin/bash

# Script to install NFS Subdir External Provisioner using Helm
# This provisioner dynamically creates PersistentVolumes on an NFS server

set -e

echo "Installing NFS Subdir External Provisioner..."

# Configuration
NFS_SERVER="${NFS_SERVER:-192.168.100.98}"
NFS_PATH="${NFS_PATH:-/data}"
STORAGE_CLASS_NAME="${STORAGE_CLASS_NAME:-nfs-client}"
NAMESPACE="${NAMESPACE:-nfs-provisioner}"
DEFAULT_STORAGE_CLASS="${DEFAULT_STORAGE_CLASS:-true}"

echo "Configuration:"
echo "  NFS Server: ${NFS_SERVER}"
echo "  NFS Path: ${NFS_PATH}"
echo "  Storage Class: ${STORAGE_CLASS_NAME}"
echo "  Namespace: ${NAMESPACE}"
echo "  Set as default: ${DEFAULT_STORAGE_CLASS}"
echo ""

# Add Helm repository
echo "Adding NFS provisioner Helm repository..."
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

# Create namespace if it doesn't exist
echo "Creating namespace ${NAMESPACE}..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Install the Helm chart
echo "Installing NFS provisioner Helm chart..."
helm upgrade --install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace ${NAMESPACE} \
  --set nfs.server=${NFS_SERVER} \
  --set nfs.path=${NFS_PATH} \
  --set storageClass.name=${STORAGE_CLASS_NAME} \
  --set storageClass.defaultClass=${DEFAULT_STORAGE_CLASS} \
  --set storageClass.archiveOnDelete=false \
  --version 4.0.18

echo ""
echo "Waiting for NFS provisioner to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/nfs-subdir-external-provisioner \
  -n ${NAMESPACE} || true

echo ""
echo "NFS Subdir External Provisioner installation complete!"
echo ""
echo "Verify the installation:"
echo "  kubectl get deployment -n ${NAMESPACE}"
echo "  kubectl get storageclass ${STORAGE_CLASS_NAME}"
echo ""
echo "Test with a PVC:"
echo "  kubectl apply -f - <<EOF"
echo "  apiVersion: v1"
echo "  kind: PersistentVolumeClaim"
echo "  metadata:"
echo "    name: test-pvc"
echo "  spec:"
echo "    storageClassName: ${STORAGE_CLASS_NAME}"
echo "    accessModes:"
echo "      - ReadWriteOnce"
echo "    resources:"
echo "      requests:"
echo "        storage: 1Gi"
echo "  EOF"
