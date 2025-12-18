# Plex Media Server Deployment

Kubernetes deployment for Plex Media Server based on the official [plexinc/pms-docker](https://github.com/plexinc/pms-docker) image.

## Prerequisites

1. A Kubernetes cluster with NFS storage provisioner
2. NFS server configured with `/data` exported (see `scripts/setup-nfs-server.sh`)
3. Media files accessible at `192.168.100.98:/data/media`
4. Plex claim token from https://www.plex.tv/claim

## Configuration Required

Before deploying, update the following in `plex-deployment.yaml`:

### 1. Claim Token
```yaml
- name: PLEX_CLAIM
  value: "claim-YOUR_CLAIM_TOKEN_HERE"  # Get from https://www.plex.tv/claim (valid 4 minutes)
```

### 2. Timezone
```yaml
- name: TZ
  value: "America/New_York"  # Change to your timezone
```

### 3. User/Group IDs
```yaml
- name: PLEX_UID
  value: "1000"  # Match your user ID
- name: PLEX_GID
  value: "1000"  # Match your group ID
```

### 4. Media Path
```yaml
volumes:
  - name: media
    nfs:
      server: "192.168.100.98"
      path: "/data/media"  # Update to your media location
```

## Storage Configuration

This deployment uses two types of storage:

### 1. Config Storage (Dynamic NFS)
Plex configuration is stored using the `nfs-client` StorageClass:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: plex-config
spec:
  storageClassName: nfs-client  # Dynamic provisioning via NFS
  resources:
    requests:
      storage: 50Gi
```

The NFS provisioner automatically creates a directory on your NFS server at:
`192.168.100.98:/data/media-plex-config-pvc-xxxxx`

### 2. Media Storage (Direct NFS Mount)
Media files are mounted directly from NFS (read-only):
```yaml
volumes:
  - name: media
    nfs:
      server: "192.168.100.98"
      path: "/data/media"
```

Place your media files on the NFS server at `/data/media/`.

## Deployment

```bash
# Deploy Plex
kubectl apply -f plex-deployment.yaml

# Check deployment status
kubectl get pods -n media

# Check service status
kubectl get svc -n media

# View logs
kubectl logs -n media -l app=plex -f
```

## Accessing Plex

### Using hostNetwork (Current Configuration)
Access Plex directly at: `http://<node-ip>:32400/web`

### Using LoadBalancer/NodePort
If you remove `hostNetwork: true`, access via the LoadBalancer IP or NodePort:
```bash
kubectl get svc -n media plex-service
```

## Important Notes

### Storage Setup
Before deploying Plex, ensure your NFS server is properly configured:

```bash
# Setup NFS server with required directories
./scripts/setup-nfs-server.sh 192.168.100.98

# Verify NFS is working
./scripts/verify-nfs-setup.sh

# Install NFS provisioner in Kubernetes
./scripts/install-nfs-provisioner.sh

# Add your media files to the NFS server
ssh 192.168.100.98
sudo mkdir -p /data/media
# Copy your movies, TV shows, etc. to /data/media/
```

### Networking Options
Current setup uses `hostNetwork: true` for simplicity. This means:
- Plex runs on the host's network
- Port 32400 must be available on the node
- Easiest setup with fewest issues

Alternative: Remove `hostNetwork: true` and use the Service with LoadBalancer/NodePort.

### Hardware Transcoding (Intel Quick Sync)
If you have Intel Quick Sync and Plex Pass, add device mapping:
```yaml
securityContext:
  privileged: true
volumeMounts:
  - name: dri
    mountPath: /dev/dri
volumes:
  - name: dri
    hostPath:
      path: /dev/dri
```

## Troubleshooting

```bash
# Check pod events
kubectl describe pod -n media -l app=plex

# Check persistent volume
kubectl get pvc -n media

# Access pod shell
kubectl exec -it -n media deployment/plex -- /bin/bash

# Check Plex logs inside container
kubectl exec -it -n media deployment/plex -- cat /config/Library/Application\ Support/Plex\ Media\ Server/Logs/Plex\ Media\ Server.log
```

## Resource Limits

Current configuration:
- Memory: 2Gi request, 4Gi limit
- CPU: 1 core request, 2 cores limit

Adjust based on your transcoding needs and available resources.

## Uninstall

```bash
kubectl delete -f plex-deployment.yaml
```

Note: This will NOT delete the PersistentVolume data. To remove all data:
```bash
kubectl delete pvc -n media plex-config
```
