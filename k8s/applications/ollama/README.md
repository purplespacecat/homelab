# Ollama LLM on Kubernetes

This deployment runs [Ollama](https://ollama.ai/), a local LLM server, on your Kubernetes homelab cluster and exposes it to your home network.

## What is Ollama?

Ollama allows you to run large language models locally. It supports models like:
- Llama 3.2 (1B, 3B parameters - very fast on CPU)
- Phi-3 (3.8B parameters - Microsoft's efficient model)
- Mistral (7B parameters)
- And many more

## Prerequisites

- Kubernetes cluster with kubeadm
- MetalLB configured for LoadBalancer services
- NGINX Ingress Controller installed
- NFS storage provisioner (nfs-client StorageClass)

## Installation

### 1. Deploy Ollama

```bash
kubectl apply -f ollama-deployment.yaml
```

This creates:
- `ollama` namespace
- 50Gi PersistentVolumeClaim for model storage
- Ollama deployment with resource limits (4-8Gi RAM, 2-4 CPU cores)
- LoadBalancer service for direct network access
- Ingress for HTTP access via nip.io domain

### 2. Get the Service IP

Wait for MetalLB to assign an external IP:

```bash
kubectl get svc -n ollama ollama-service
```

Look for the `EXTERNAL-IP` column. This is your Ollama server's IP on your home network.

### 3. Verify the Deployment

Check that the pod is running:

```bash
kubectl get pods -n ollama
```

Check the logs:

```bash
kubectl logs -n ollama -l app=ollama
```

## Usage

### Access Methods

You can access Ollama via:

1. **Direct IP access** (fastest):
   ```bash
   # Replace with your service's external IP
   curl http://192.168.100.203:11434
   ```

2. **Via Ingress/nip.io**:
   ```bash
   curl http://ollama.192.168.100.202.nip.io
   ```

### Download and Run a Model

From any machine on your home network:

```bash
# Set the Ollama host (replace with your service IP)
export OLLAMA_HOST=http://192.168.100.203:11434

# Download a small model (recommended to start)
ollama pull llama3.2:1b

# Or download Phi-3 (3.8B parameters, good quality)
ollama pull phi3

# Run the model
ollama run llama3.2:1b
```

### Using Ollama from Code

#### Python Example

```python
import requests
import json

OLLAMA_HOST = "http://192.168.100.203:11434"  # Replace with your IP

def generate(prompt, model="llama3.2:1b"):
    url = f"{OLLAMA_HOST}/api/generate"
    data = {
        "model": model,
        "prompt": prompt,
        "stream": False
    }

    response = requests.post(url, json=data)
    return response.json()["response"]

# Example usage
result = generate("Why is the sky blue?")
print(result)
```

#### JavaScript Example

```javascript
async function generate(prompt, model = "llama3.2:1b") {
    const OLLAMA_HOST = "http://192.168.100.203:11434";  // Replace with your IP

    const response = await fetch(`${OLLAMA_HOST}/api/generate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            model: model,
            prompt: prompt,
            stream: false
        })
    });

    const data = await response.json();
    return data.response;
}

// Example usage
generate("Why is the sky blue?").then(console.log);
```

### Using the Ollama CLI

Install the Ollama CLI on your local machine:

```bash
# Linux
curl -fsSL https://ollama.ai/install.sh | sh

# macOS
brew install ollama

# Windows
# Download from https://ollama.ai/download
```

Then configure it to use your remote server:

```bash
export OLLAMA_HOST=http://192.168.100.203:11434
ollama list  # List downloaded models
ollama run llama3.2:1b  # Interactive chat
```

## Recommended Models for Homelab

Small models that run well on CPU:

| Model | Size | Parameters | Use Case |
|-------|------|------------|----------|
| `llama3.2:1b` | ~1.3GB | 1B | Very fast, good for simple tasks |
| `phi3:mini` | ~2.3GB | 3.8B | Best quality for size, Microsoft |
| `gemma2:2b` | ~1.6GB | 2B | Google's efficient model |
| `qwen2:1.5b` | ~1GB | 1.5B | Alibaba's fast model |

Download a model:

```bash
export OLLAMA_HOST=http://192.168.100.203:11434
ollama pull llama3.2:1b
```

## API Documentation

### Generate Endpoint

```bash
curl http://192.168.100.203:11434/api/generate -d '{
  "model": "llama3.2:1b",
  "prompt": "Why is the sky blue?",
  "stream": false
}'
```

### Chat Endpoint

```bash
curl http://192.168.100.203:11434/api/chat -d '{
  "model": "llama3.2:1b",
  "messages": [
    {
      "role": "user",
      "content": "Why is the sky blue?"
    }
  ],
  "stream": false
}'
```

### List Models

```bash
curl http://192.168.100.203:11434/api/tags
```

## Resource Requirements

The deployment is configured with:
- **Memory**: 4Gi requested, 8Gi limit
- **CPU**: 2 cores requested, 4 cores limit
- **Storage**: 50Gi for models

Adjust these in `ollama-deployment.yaml` based on your cluster resources:

```yaml
resources:
  requests:
    memory: "4Gi"
    cpu: "2000m"
  limits:
    memory: "8Gi"
    cpu: "4000m"
```

## Troubleshooting

### Pod not starting

Check pod status and logs:

```bash
kubectl describe pod -n ollama -l app=ollama
kubectl logs -n ollama -l app=ollama
```

### No external IP assigned

Verify MetalLB is running and configured:

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
```

### Model download fails

Check if you have enough storage:

```bash
kubectl get pvc -n ollama
```

Connect to the pod and check disk space:

```bash
kubectl exec -it -n ollama deployment/ollama -- df -h
```

### Slow performance

Small models (1-3B parameters) should run acceptably on CPU. For better performance:
1. Ensure CPU limits are not too restrictive
2. Use smaller models (1B-3B parameters)
3. Consider adding GPU support if available

## Uninstallation

```bash
kubectl delete -f ollama-deployment.yaml
```

This removes all resources including the namespace and PVC.

## Security Notes

- Ollama is exposed to your home network via LoadBalancer
- No authentication is configured by default
- Consider adding network policies if you want to restrict access
- The service is only accessible from your local network (not the internet)

## Links

- [Ollama Official Site](https://ollama.ai/)
- [Ollama GitHub](https://github.com/ollama/ollama)
- [Available Models](https://ollama.ai/library)
- [API Documentation](https://github.com/ollama/ollama/blob/main/docs/api.md)
