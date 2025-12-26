# ML Stack Quick Start Guide

Get your ML tools up and running with Ollama in minutes.

## Prerequisites

✅ Ollama deployed (see `../helm/ollama/`)
✅ MetalLB configured
✅ Ingress-nginx installed
✅ NFS storage provisioner

## Step 1: Deploy Open WebUI (5 minutes)

**Why**: ChatGPT-like interface for Ollama

```bash
cd open-webui
./install.sh
```

**Access**: `http://open-webui.YOUR_IP.nip.io`

**First Steps**:
1. Create admin account (first user)
2. Select a model (llama2, mistral, etc.)
3. Start chatting!
4. Upload documents for RAG

---

## Step 2: Deploy JupyterHub (10 minutes)

**Why**: Development environment for ML experiments

```bash
# Generate secret token
SECRET_TOKEN=$(openssl rand -hex 32)

# Add Helm repo
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update

# Update values.yaml with your ingress IP
cd jupyterhub
# Edit values.yaml: Change line 48 to your ingress IP
# Edit values.yaml: Add secret token to line 9

# Install
helm install jupyterhub jupyterhub/jupyterhub \
  -f values.yaml \
  --namespace jupyterhub \
  --create-namespace
```

**Access**: `http://jupyter.YOUR_IP.nip.io`
**Default Password**: `jupyter` (change in values.yaml)

**First Notebook**:
```python
import requests

OLLAMA_HOST = "http://ollama.ollama.svc.cluster.local:11434"

def chat(prompt, model="llama2"):
    response = requests.post(
        f"{OLLAMA_HOST}/api/generate",
        json={"model": model, "prompt": prompt, "stream": False}
    )
    return response.json()["response"]

# Try it
result = chat("Explain Docker in simple terms")
print(result)
```

---

## Step 3: Deploy MLflow (5 minutes)

**Why**: Track experiments and compare results

```bash
cd mlflow
kubectl apply -f mlflow-deployment.yaml
```

**Access**: `http://mlflow.YOUR_IP.nip.io`

**Track an Experiment**:
```python
import mlflow
import requests

mlflow.set_tracking_uri("http://mlflow.mlflow.svc.cluster.local:5000")
mlflow.set_experiment("my-llm-tests")

with mlflow.start_run():
    mlflow.log_param("model", "llama2")
    mlflow.log_param("prompt", "Test prompt")

    # Your Ollama code here
    response = requests.post(
        "http://ollama.ollama.svc.cluster.local:11434/api/generate",
        json={"model": "llama2", "prompt": "Hello!", "stream": False}
    )

    mlflow.log_metric("response_length", len(response.json()["response"]))
```

---

## Step 4: Optional - Vector Database for RAG

### Option A: Chroma (Simple)

```bash
cd chroma
kubectl apply -f chroma-deployment.yaml
```

### Option B: Qdrant (Production)

```bash
cd qdrant
kubectl apply -f qdrant-deployment.yaml
```

**Use with LangChain**:
```python
from langchain_community.llms import Ollama
from langchain_community.vectorstores import Chroma
from langchain.embeddings import OllamaEmbeddings

llm = Ollama(
    base_url="http://ollama.ollama.svc.cluster.local:11434",
    model="llama2"
)

embeddings = OllamaEmbeddings(
    base_url="http://ollama.ollama.svc.cluster.local:11434"
)

vectorstore = Chroma(
    embedding_function=embeddings,
    persist_directory="/data/chroma"
)
```

---

## What You Now Have

✅ **Ollama** - LLM inference server
✅ **Open WebUI** - ChatGPT-like interface
✅ **JupyterHub** - Development notebooks
✅ **MLflow** - Experiment tracking
✅ **Chroma/Qdrant** - Vector storage (optional)

## Common Workflows

### Workflow 1: Quick Chat
```
User → Open WebUI → Ollama → Response
```

### Workflow 2: Development
```
Developer → JupyterHub → Ollama → Experiments
                              ↓
                          MLflow (tracking)
```

### Workflow 3: RAG Application
```
User → Open WebUI → Ollama + Vector DB → Contextual Response
```

## Next Steps

1. **Explore Open WebUI**: Upload documents, try different models
2. **Create Notebooks**: Develop LLM applications in JupyterHub
3. **Track Experiments**: Use MLflow to compare prompts and models
4. **Build RAG Apps**: Connect vector databases for context-aware responses

## Troubleshooting

### Can't access services?
```bash
# Check ingress IP
kubectl get svc -n ingress-nginx

# Check service status
kubectl get svc -n open-webui
kubectl get svc -n jupyterhub
kubectl get svc -n mlflow
```

### Ollama connection fails?
```bash
# Verify Ollama is running
kubectl get pods -n ollama

# Test from another pod
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://ollama.ollama.svc.cluster.local:11434/api/tags
```

### Out of resources?
```bash
# Check cluster resources
kubectl top nodes
kubectl top pods -A

# Scale down unused services
kubectl scale deployment <name> -n <namespace> --replicas=0
```

## Resource Usage Summary

| Service | CPU | Memory | Storage | Priority |
|---------|-----|---------|---------|----------|
| Ollama | 2-4 cores | 4-8GB | 50GB | ⭐⭐⭐ Essential |
| Open WebUI | 0.5-2 cores | 512MB-2GB | 10GB | ⭐⭐⭐ Essential |
| JupyterHub | 0.5-1 core | 512MB-1GB | 5GB/user | ⭐⭐ Recommended |
| MLflow | 0.25-1 core | 512MB-2GB | 20GB | ⭐⭐ Recommended |
| Chroma | 0.25-0.5 core | 512MB-1GB | 10GB | ⭐ Optional |

**Total for Essential Stack**: ~3-6 CPU cores, 5-11GB RAM, 60GB storage

## Getting Help

- **Main Guide**: [README.md](README.md)
- **Ollama Docs**: https://ollama.ai/
- **Open WebUI Docs**: https://docs.openwebui.com/
- **MLflow Docs**: https://mlflow.org/docs/latest/

---

Ready to build ML applications! 🚀
