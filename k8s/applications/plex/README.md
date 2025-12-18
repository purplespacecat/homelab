# Plex Media Server Deployment

Kubernetes deployment for Plex Media Server based on the official [plexinc/pms-docker](https://github.com/plexinc/pms-docker) image.

## Prerequisites

1. A Kubernetes cluster with storage provisioner
2. NFS server with media files (currently configured: `192.168.100.98:/data/media`)
3. Local storage class for Plex configuration (NOT NFS - file locking required)
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

### 5. Storage Class (Optional)
If you have a specific StorageClass for local storage:
```yaml
spec:
  storageClassName: your-local-storage-class
```

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

### Storage Warning
- **DO NOT use NFS for `/config` volume** - this will corrupt the Plex database
- Use local storage or a storage class that supports file locking
- Media (`/data`) can safely use NFS as it's read-only

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
