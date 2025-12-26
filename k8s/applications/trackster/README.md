# Trackster Homelab Deployment

This directory contains Kubernetes manifests for deploying the Trackster note-taking application to your homelab.

## Overview

Trackster is a personal note-taking journal application with:
- FastAPI backend with REST API
- Reflex UI (Python-based reactive web framework)
- SQLite database for persistent storage
- AI-powered note summaries using Google Gemini 2.5

## Prerequisites

Before deploying, ensure you have:

1. **Kubernetes cluster** with:
   - MetalLB for LoadBalancer services
   - Ingress-nginx controller
   - NFS storage provisioner (nfs-client StorageClass)
   - cert-manager (optional, for TLS)

2. **Google Gemini API Key**:
   - Get your API key at https://aistudio.google.com/apikey
   - Required for AI summary features

3. **Docker registry** (local or remote) to host the Trackster image

## Deployment Steps

### 1. Build and Push Docker Image

The deployment uses the public Docker Hub image `spacecrab/trackster:latest`.

**Option A: Use the pre-built image (recommended)**

The deployment YAML is already configured to use `spacecrab/trackster:latest`. You can skip the build step if the image is already available on Docker Hub.

**Option B: Build and push your own image**

From the trackster repository root, use the provided script:

```bash
cd /home/spacecrab/repos/trackster

# Build and push to Docker Hub (default: spacecrab/trackster:latest)
./build-and-push.sh

# Or with a specific tag
./build-and-push.sh v1.0.0
```

The script will:
- Build the Docker image
- Tag it as `spacecrab/trackster:TAG` and `spacecrab/trackster:latest`
- Prompt for Docker Hub login if needed
- Push both tags to Docker Hub

**Option C: Manual build and push**

```bash
cd /home/spacecrab/repos/trackster

# Build the image
docker build -t trackster:latest .

# Tag for Docker Hub
docker tag trackster:latest spacecrab/trackster:latest
docker push spacecrab/trackster:latest

# Or use a different registry
docker tag trackster:latest your-registry/trackster:latest
docker push your-registry/trackster:latest
# Then update the image in trackster-deployment.yaml
```

### 2. Create Kubernetes Secret

Use the helper script to create the secret with your Gemini API key:

```bash
cd /home/spacecrab/repos/homelab/k8s/applications/trackster

# Make script executable
chmod +x create-secret.sh

# Create secret
./create-secret.sh YOUR_GEMINI_API_KEY_HERE
```

Or create it manually:

```bash
kubectl create namespace trackster
kubectl create secret generic trackster-secrets \
    --from-literal=GEMINI_API_KEY="YOUR_KEY_HERE" \
    --namespace=trackster
```

### 3. Update Deployment Configuration (Optional)

The deployment is pre-configured with `spacecrab/trackster:latest`. If you're using a different image or registry, edit `trackster-deployment.yaml`:

1. **Image reference** (line ~47) - only if using a different image:
   ```yaml
   image: spacecrab/trackster:latest  # Change if needed
   ```

2. **Ingress hostname** (line ~88):
   ```yaml
   - host: trackster.YOUR_INGRESS_IP.nip.io
   ```
   Replace `YOUR_INGRESS_IP` with your ingress controller's external IP.

3. **Storage size** (optional, line ~23):
   ```yaml
   storage: 5Gi  # Adjust if needed
   ```

### 4. Deploy to Kubernetes

Apply the deployment manifest:

```bash
kubectl apply -f trackster-deployment.yaml
```

### 5. Verify Deployment

Check the deployment status:

```bash
# Check pods
kubectl get pods -n trackster

# Check services
kubectl get svc -n trackster

# Check ingress
kubectl get ingress -n trackster

# View logs
kubectl logs -n trackster -l app=trackster -f
```

### 6. Access the Application

Once deployed, access Trackster via:

- **Web UI**: `http://trackster.YOUR_INGRESS_IP.nip.io` (via Ingress)
- **LoadBalancer**: Check the external IP assigned by MetalLB:
  ```bash
  kubectl get svc -n trackster trackster-web-service
  ```
  Access at `http://EXTERNAL_IP:3000`

- **API Documentation**: `http://trackster.YOUR_INGRESS_IP.nip.io/api/docs`

## Architecture

The deployment includes:

- **Namespace**: `trackster` - Isolated namespace for the application
- **Deployment**: Single replica running both FastAPI backend (port 8000) and Reflex frontend (port 3000)
- **PersistentVolumeClaim**: 5Gi for SQLite database persistence
- **Services**:
  - `trackster-api-service` (ClusterIP) - Internal API access
  - `trackster-web-service` (LoadBalancer) - External web access
- **Ingress**: NGINX ingress with optional TLS
- **Secret**: Stores GEMINI_API_KEY securely

## Resource Allocation

Default resource limits:
- **Memory**: 512Mi request, 1Gi limit
- **CPU**: 250m request, 1000m limit
- **Storage**: 5Gi (NFS)

Adjust in `trackster-deployment.yaml` based on your usage.

## Troubleshooting

### Pod not starting
```bash
kubectl describe pod -n trackster -l app=trackster
kubectl logs -n trackster -l app=trackster
```

### Database issues
The SQLite database is stored in the PVC at `/app/data/notes.db`. To inspect:
```bash
kubectl exec -n trackster -it <pod-name> -- ls -la /app/data/
```

### API key not working
Verify the secret:
```bash
kubectl get secret -n trackster trackster-secrets -o yaml
```

### Ingress not accessible
Check ingress controller and DNS:
```bash
kubectl get ingress -n trackster
kubectl describe ingress -n trackster trackster-ingress
```

## Updating the Application

To update to a new version:

1. Build and push new image with a version tag:
   ```bash
   docker build -t trackster:v1.1.0 .
   docker tag trackster:v1.1.0 your-registry/trackster:v1.1.0
   docker push your-registry/trackster:v1.1.0
   ```

2. Update the deployment:
   ```bash
   kubectl set image deployment/trackster trackster=your-registry/trackster:v1.1.0 -n trackster
   ```

3. Or edit the YAML and reapply:
   ```bash
   kubectl apply -f trackster-deployment.yaml
   ```

## Backup and Restore

### Backup database
```bash
kubectl exec -n trackster <pod-name> -- sqlite3 /app/data/notes.db .dump > trackster-backup.sql
```

### Restore database
```bash
cat trackster-backup.sql | kubectl exec -n trackster -i <pod-name> -- sqlite3 /app/data/notes.db
```

## Uninstalling

To remove the entire deployment:

```bash
kubectl delete -f trackster-deployment.yaml
```

To keep the data (PVC):
```bash
kubectl delete deployment,service,ingress -n trackster --all
# PVC will remain - delete manually if needed:
# kubectl delete pvc -n trackster trackster-data
```

## Notes

- The deployment uses a `Recreate` strategy to ensure only one pod runs at a time (SQLite limitation)
- Health checks probe the `/hello` endpoint on the FastAPI backend
- The container runs both backend and frontend processes using a startup script
- TLS is optional - remove the `tls` section in ingress if not using cert-manager

## References

- Trackster repository: `/home/spacecrab/repos/trackster`
- API documentation: http://trackster.YOUR_IP.nip.io/api/docs
- Gemini API: https://aistudio.google.com/apikey
