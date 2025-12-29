#!/bin/bash
# Setup NFS server on remote host
set -e

NFS_SERVER="${1:-192.168.100.98}"

# Test SSH
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$NFS_SERVER" "exit" 2>/dev/null || {
    echo "Error: Cannot connect to $NFS_SERVER via SSH"
    exit 1
}

# Remote setup script
REMOTE_SCRIPT='#!/bin/bash
set -e
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nfs-kernel-server 2>&1 | grep -i error || true
mkdir -p /data /data/media /data/plex
chmod 777 /data
chmod 755 /data/media /data/plex
cat > /etc/exports <<EOF
/data *(rw,sync,no_subtree_check,no_root_squash)
/data/media *(rw,sync,no_subtree_check,no_root_squash)
/data/plex *(rw,sync,no_subtree_check,no_root_squash)
EOF
exportfs -ra
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server >/dev/null 2>&1
if command -v ufw &>/dev/null && ufw status | grep -q active; then
    ufw allow from 192.168.100.0/24 to any port nfs >/dev/null 2>&1 || true
    ufw allow from 192.168.100.0/24 to any port 111 >/dev/null 2>&1 || true
    ufw allow from 192.168.100.0/24 to any port 2049 >/dev/null 2>&1 || true
fi
systemctl is-active --quiet nfs-kernel-server || { echo "Error: NFS server not running"; exit 1; }
'

# Execute on remote
ssh -t "$NFS_SERVER" "cat > /tmp/nfs-setup.sh && chmod +x /tmp/nfs-setup.sh && sudo /tmp/nfs-setup.sh && rm /tmp/nfs-setup.sh" <<< "$REMOTE_SCRIPT" 2>&1 | grep -iE "error|password" || true

# Verify
echo ""
echo "=== NFS Server Setup Complete ==="
echo "Server: $NFS_SERVER"
ssh "$NFS_SERVER" "showmount -e localhost"
echo ""
echo "Next: ./scripts/common/verify-nfs-setup.sh $NFS_SERVER"
