# Ollama Helm Deployment

This directory contains Helm chart customizations for deploying Ollama to your homelab Kubernetes cluster.

## Overview

Ollama is deployed using the community-maintained `otwld/ollama-helm` chart with custom values to match the homelab configuration.

## Prerequisites

1. **Helm 3.x** installed
2. **Kubernetes cluster** with:
   - MetalLB for LoadBalancer services
   - Ingress-nginx controller
   - NFS storage provisioner (nfs-client StorageClass)
3. **Optional**: NVIDIA/AMD GPU support (if using GPU acceleration)

## Installation

### 1. Add Helm Repository

```bash
helm repo add otwld https://helm.otwld.com/
helm repo update
```

### 2. Review and Customize Values

Edit `values.yaml` to match your environment:

- **Ingress hostname** (line ~51): Update to your ingress controller IP
  ```yaml
  hosts:
    - host: ollama.YOUR_INGRESS_IP.nip.io
  ```

- **Storage size** (line ~66): Adjust based on model requirements
  ```yaml
  size: 50Gi  # Larger if using many/large models
  ```

- **GPU support** (line ~17): Enable if you have GPUs
  ```yaml
  gpu:
    enabled: true
    type: 'nvidia'  # or 'amd'
    number: 1
  ```

- **Pre-load models** (line ~24): Add models to download on startup
  ```yaml
  models:
    - llama2
    - mistral
    - codellama
  ```

### 3. Install with Helm

```bash
cd /home/spacecrab/repos/homelab/k8s/helm/ollama

# Install Ollama
helm install ollama otwld/ollama \
  -f values.yaml \
  --namespace ollama \
  --create-namespace

# Or use the install script
./install.sh
```

### 4. Verify Deployment

```bash
# Check installation status
helm status ollama -n ollama

# Watch pods
kubectl get pods -n ollama -w

# Check service
kubectl get svc -n ollama

# View logs
kubectl logs -n ollama -l app.kubernetes.io/name=ollama -f
```

## Access Ollama

Once deployed, access Ollama via:

- **LoadBalancer IP**:
  ```bash
  kubectl get svc -n ollama ollama -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  # Access at http://EXTERNAL_IP:11434
  ```

- **Ingress**: `http://ollama.YOUR_INGRESS_IP.nip.io`

- **From within cluster**: `http://ollama.ollama.svc.cluster.local:11434`

## Testing Ollama

Test the installation with curl:

```bash
# Get external IP
OLLAMA_IP=$(kubectl get svc -n ollama ollama -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Check API
curl http://$OLLAMA_IP:11434/api/tags

# Pull a model
curl http://$OLLAMA_IP:11434/api/pull -d '{
  "name": "llama2"
}'

# Run a prompt
curl http://$OLLAMA_IP:11434/api/generate -d '{
  "model": "llama2",
  "prompt": "Why is the sky blue?"
}'
```

## Using Ollama CLI

If you have the Ollama CLI installed locally, point it to your cluster:

```bash
# Set environment variable
export OLLAMA_HOST=http://ollama.YOUR_INGRESS_IP.nip.io

# Or for LoadBalancer IP
export OLLAMA_HOST=http://$OLLAMA_IP:11434

# List models
ollama list

# Pull a model
ollama pull llama2

# Run a model
ollama run llama2
```

## Configuration Options

### GPU Support

If you have NVIDIA GPUs:

```yaml
ollama:
  gpu:
    enabled: true
    type: 'nvidia'
    number: 1  # Number of GPUs to use

nodeSelector:
  nvidia.com/gpu: "true"
```

For AMD GPUs, set `type: 'amd'`.

### Model Management

Pre-pull models on startup:

```yaml
ollama:
  models:
    - llama2
    - mistral
    - codellama:7b
    - phi
```

Models are downloaded to persistent storage on first container start.

### Resource Allocation

Adjust based on your workload:

```yaml
resources:
  requests:
    memory: "8Gi"   # Larger models need more RAM
    cpu: "4000m"
  limits:
    memory: "16Gi"
    cpu: "8000m"
```

**Note**: LLMs are memory-intensive. Ensure your cluster has sufficient resources.

### Storage

Storage requirements vary by model:
- Small models (7B): ~4-8 GB
- Medium models (13B): ~8-16 GB
- Large models (70B): ~40-80 GB

Adjust PVC size accordingly:

```yaml
persistence:
  size: 100Gi  # For multiple large models
```

## Updating Ollama

### Update Chart Values

Edit `values.yaml` and upgrade:

```bash
helm upgrade ollama otwld/ollama \
  -f values.yaml \
  --namespace ollama
```

### Update to New Chart Version

```bash
# Update repo
helm repo update

# Check available versions
helm search repo otwld/ollama --versions

# Upgrade to latest
helm upgrade ollama otwld/ollama \
  -f values.yaml \
  --namespace ollama
```

### Update Container Image

```yaml
image:
  tag: "0.1.47"  # Specific version
```

Then upgrade:
```bash
helm upgrade ollama otwld/ollama -f values.yaml -n ollama
```

## Troubleshooting

### Pod not starting

```bash
kubectl describe pod -n ollama -l app.kubernetes.io/name=ollama
kubectl logs -n ollama -l app.kubernetes.io/name=ollama
```

### Storage issues

Check PVC status:
```bash
kubectl get pvc -n ollama
kubectl describe pvc -n ollama ollama
```

### GPU not detected

Verify GPU operator is installed:
```bash
kubectl get pods -n gpu-operator
```

Check node has GPU:
```bash
kubectl describe node <node-name> | grep -i gpu
```

### Model download fails

Check pod logs for network/storage issues:
```bash
kubectl logs -n ollama -l app.kubernetes.io/name=ollama -f
```

Increase timeout in values.yaml:
```yaml
livenessProbe:
  initialDelaySeconds: 120  # Longer for large models
  timeoutSeconds: 10
```

## Uninstalling

Remove the Helm release:

```bash
# Uninstall Ollama
helm uninstall ollama -n ollama

# Optionally delete namespace and data
kubectl delete namespace ollama
```

**Warning**: This will delete all downloaded models unless you preserve the PVC.

To keep the data:
```bash
# Just uninstall the release
helm uninstall ollama -n ollama

# PVC remains - reinstall will reuse existing data
```

## Migrating from YAML Deployment

If you have an existing Ollama deployment using raw YAML:

1. **Backup your data** (models are in the PVC)
2. **Delete old deployment**:
   ```bash
   kubectl delete -f ../applications/ollama/ollama-deployment.yaml
   ```
3. **Install with Helm** (using existing PVC):
   ```yaml
   persistence:
     existingClaim: ollama-data  # Reuse existing PVC
   ```
4. **Deploy**:
   ```bash
   helm install ollama otwld/ollama -f values.yaml -n ollama
   ```

## Integration with Open WebUI

To use Ollama with Open WebUI (formerly Ollama WebUI):

```bash
# Add Open WebUI Helm repo (if available)
# Or deploy Open WebUI and point it to Ollama service:
# OLLAMA_API_BASE_URL=http://ollama.ollama.svc.cluster.local:11434
```

## Resources

- **Helm Chart**: https://github.com/otwld/ollama-helm
- **Ollama Docs**: https://ollama.ai/
- **Ollama Models**: https://ollama.ai/library
- **Community Forum**: https://github.com/ollama/ollama/discussions

## Notes

- The `Recreate` update strategy ensures only one pod runs at a time
- MetalLB assigns a local network IP for external access
- Ingress provides hostname-based access through nginx
- Models persist across pod restarts via NFS-backed PVC
- Resource limits prevent OOM kills for large models
