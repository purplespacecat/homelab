#!/bin/bash

# Script to secure NFS server permissions
# Run this on the NFS server (192.168.100.98)

echo "Securing NFS server permissions..."
echo "This script must be run on the NFS server (192.168.100.98) as root"

# Create data directory if it doesn't exist
mkdir -p /data

# Create subdirectories with proper permissions
for dir in prometheus grafana alertmanager-0 alertmanager-1 loki; do
    mkdir -p /data/$dir
    
    # Set ownership to nobody:nogroup (common for NFS)
    chown 65534:65534 /data/$dir
    
    # Set more secure permissions (755 instead of 777)
    chmod 755 /data/$dir
    
    echo "Secured /data/$dir"
done

# Update exports file with more secure options
cat > /etc/exports <<EOF
/data           *(rw,sync,no_subtree_check,no_root_squash)
/data/prometheus *(rw,sync,no_subtree_check,all_squash,anonuid=65534,anongid=65534)
/data/grafana    *(rw,sync,no_subtree_check,all_squash,anonuid=65534,anongid=65534)
/data/alertmanager-0 *(rw,sync,no_subtree_check,all_squash,anonuid=65534,anongid=65534)
/data/alertmanager-1 *(rw,sync,no_subtree_check,all_squash,anonuid=65534,anongid=65534)
/data/loki       *(rw,sync,no_subtree_check,all_squash,anonuid=65534,anongid=65534)
EOF

# Re-export NFS shares
exportfs -ra

echo "NFS permissions updated successfully"
echo "Check exports with: showmount -e localhost"