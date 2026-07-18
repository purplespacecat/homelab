#!/bin/bash

# Script to secure NFS server permissions
# Run this on the NFS server (192.168.100.98)

echo "Securing NFS server permissions..."
echo "This script must be run on the NFS server (192.168.100.98) as root"

# Create data directory if it doesn't exist
mkdir -p /data

# Create subdirectories with proper permissions
for dir in prometheus grafana alertmanager-0 alertmanager-1; do
    mkdir -p /data/$dir
    
    # Set ownership to nobody:nogroup (common for NFS)
    chown 65534:65534 /data/$dir
    
    # Set more secure permissions (755 instead of 777)
    chmod 755 /data/$dir
    
    echo "Secured /data/$dir"
done

# Allowed NFS clients. Was "*" (ANY LAN host could mount /data as root over the
# WiFi). NFS is only consumed in-cluster — restrict to the k3s node + pod CIDR.
NFS_ALLOWED="${NFS_ALLOWED:-192.168.100.98 10.42.0.0/16}"

# Emit "<path> host1(opts) host2(opts) ..." for one export line.
export_line() {
    local path="$1" opts="$2" spec=""
    for host in $NFS_ALLOWED; do
        spec="${spec} ${host}(${opts})"
    done
    echo "${path}${spec}"
}

# Update exports file with more secure options (restricted clients + squash)
SQUASH="rw,sync,no_subtree_check,all_squash,anonuid=65534,anongid=65534"
{
    echo "# Restricted to the k3s node + pod CIDR (was '*'). Clients: ${NFS_ALLOWED}"
    export_line /data                "rw,sync,no_subtree_check,no_root_squash"
    export_line /data/prometheus     "$SQUASH"
    export_line /data/grafana        "$SQUASH"
    export_line /data/alertmanager-0 "$SQUASH"
    export_line /data/alertmanager-1 "$SQUASH"
} > /etc/exports

# Re-export NFS shares
exportfs -ra

echo "NFS permissions updated successfully"
echo "Check exports with: showmount -e localhost"