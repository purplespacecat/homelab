#!/bin/bash

# Script to clean up duplicated files after repository reorganization
# This script removes the original files that have been moved to new subdirectories

echo "Cleaning up duplicated files after repository reorganization..."

# Remove cert-manager files from k8s/core that are now in k8s/cert-manager
echo "Removing cert-manager files from original location..."
rm -f /home/flnv/Documents/repos/homelab/k8s/core/cert-manager.yaml
rm -f /home/flnv/Documents/repos/homelab/k8s/core/cert-manager-issuers.yaml
rm -f /home/flnv/Documents/repos/homelab/k8s/core/local-ca.yaml

# Remove files from k8s/core that are now in k8s/core/networking
echo "Removing networking files from original location..."
rm -f /home/flnv/Documents/repos/homelab/k8s/core/metallb-config.yaml

# Remove files from k8s/core that are now in k8s/core/security
echo "Removing security files from original location..."
rm -f /home/flnv/Documents/repos/homelab/k8s/core/network-policies.yaml

# Remove files from k8s/core that are now in k8s/core/storage
echo "Removing storage files from original location..."
rm -f /home/flnv/Documents/repos/homelab/k8s/core/monitoring-storage.yaml
rm -f /home/flnv/Documents/repos/homelab/k8s/core/nfs-config.yaml
rm -f /home/flnv/Documents/repos/homelab/k8s/core/nfs-subdir-external-provisioner.yaml

# Remove data-apps files that are now in applications directory
echo "Removing application files from original location..."
rm -f /home/flnv/Documents/repos/homelab/k8s/helm/data-apps/crypto-data-app-deployment.yaml

echo "Cleanup complete!"
echo "Repository structure has been successfully reorganized."