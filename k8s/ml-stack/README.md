# ML Stack for Homelab with Ollama

This guide covers integrating popular ML tools with your self-hosted Ollama deployment to build a complete MLOps workflow in your homelab.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      ML Stack Architecture                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐     │
│  │  Open WebUI  │    │  JupyterHub  │    │   Trackster  │     │
│  │  (Chat UI)   │    │ (Development)│    │ (Note-taking)│     │
│  └──────┬───────┘    └──────┬───────┘    └──────────────┘     │
│         │                   │                                   │
│         └───────────┬───────┘                                   │
│                     │                                           │
│         ┌───────────▼────────────┐                              │
│         │      Ollama Server     │ ◄──── Core LLM Runtime      │
│         │  (LLM Inference API)   │                              │
│         └───────────┬────────────┘                              │
│                     │                                           │
│         ┌───────────▼────────────┐                              │
│         │       MLflow           │ ◄──── Experiment Tracking   │
│         │ (Track, Log, Compare)  │                              │
│         └────────────────────────┘                              │
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐     │
│  │  Chroma DB   │    │   Qdrant     │    │  PostgreSQL  │     │
│  │  (Vectors)   │    │  (Vectors)   │    │  (Metadata)  │     │
│  └──────────────┘    └──────────────┘    └──────────────┘     │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Prometheus + Grafana                        │   │
│  │              (Monitoring & Observability)                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Component Stack

### 🎯 Essential Tools (Start Here)

1. **[Ollama](../helm/ollama/)** - Already deployed ✅
   - Core LLM inference server
   - Runs models locally

2. **Open WebUI** - ChatGPT-like interface
   - Web UI for Ollama
   - RAG support, document uploads
   - Multi-user support
   - **Status**: Deployment below

3. **JupyterHub** - Development environment
   - Interactive notebooks for ML experiments
   - Direct Ollama API access
   - **Status**: Deployment below

### 📊 ML Workflow Tools (Add as Needed)

4. **MLflow** - Experiment tracking
   - Native Ollama tracing support
   - Track prompts, responses, metrics
   - Model comparison
   - **Status**: Deployment below

5. **Vector Databases** - RAG applications
   - **Chroma** - Simple, Python-friendly
   - **Qdrant** - Fast, production-ready
   - Store embeddings for retrieval
   - **Status**: Deployment below

### 🚀 Advanced MLOps (Optional)

6. **Kubeflow** - Full MLOps platform
   - Pipelines, training, serving
   - Heavy (3-5GB RAM overhead)
   - Best for serious ML workflows
   - **Status**: Guide below

7. **KServe** - Model serving
   - Production model deployment
   - Canary rollouts, autoscaling
   - Can be used standalone
   - **Status**: Guide below

## Quick Start Recommendations

### For LLM Usage & Experimentation
```bash
# 1. Ollama (already deployed)
# 2. Open WebUI - Essential for using Ollama
# 3. JupyterHub - For development
```

### For RAG Applications
```bash
# Add to above:
# 4. Chroma or Qdrant - Vector storage
# 5. PostgreSQL - Metadata storage
```

### For ML Experiments & Tracking
```bash
# Add to above:
# 6. MLflow - Track experiments
```

### For Production MLOps
```bash
# Full stack:
# All of the above + Kubeflow/KServe
```

## Deployment Guides

### 1. Open WebUI (Essential)

Open WebUI provides a ChatGPT-like interface for Ollama with RAG support.

**Files**: [`open-webui/`](open-webui/)

**Quick Install**:
```bash
cd ml-stack/open-webui
./install.sh
```

**Access**: `http://open-webui.YOUR_IP.nip.io`

**Features**:
- ChatGPT-like UI
- Document uploads (RAG)
- Multi-user with authentication
- Prompt management
- Model switching

---

### 2. JupyterHub (Development)

JupyterHub for team collaboration and ML development.

**Files**: [`jupyterhub/`](jupyterhub/)

**Quick Install**:
```bash
cd ml-stack/jupyterhub
./install.sh
```

**Access**: `http://jupyter.YOUR_IP.nip.io`

**Use Cases**:
- Python notebooks for Ollama
- LangChain development
- Data analysis
- Model testing

**Example Notebook**:
```python
import requests

# Connect to Ollama
OLLAMA_HOST = "http://ollama.ollama.svc.cluster.local:11434"

def chat(prompt, model="llama2"):
    response = requests.post(
        f"{OLLAMA_HOST}/api/generate",
        json={"model": model, "prompt": prompt, "stream": False}
    )
    return response.json()["response"]

# Use it
result = chat("Explain Kubernetes in simple terms")
print(result)
```

---

### 3. MLflow (Experiment Tracking)

MLflow provides experiment tracking with native Ollama support.

**Files**: [`mlflow/`](mlflow/)

**Quick Install**:
```bash
cd ml-stack/mlflow
./install.sh
```

**Access**: `http://mlflow.YOUR_IP.nip.io`

**Features**:
- Track Ollama API calls
- Compare prompts and responses
- Log metrics and parameters
- Model versioning

**Example Usage**:
```python
import mlflow
from mlflow.openai import autolog

# Enable automatic logging for Ollama
autolog()

# Your Ollama code gets automatically tracked
import openai
client = openai.OpenAI(
    base_url="http://ollama.ollama.svc.cluster.local:11434/v1",
    api_key="ollama"  # Required but unused
)

response = client.chat.completions.create(
    model="llama2",
    messages=[{"role": "user", "content": "Hello!"}]
)
# Automatically logged to MLflow!
```

---

### 4. Vector Databases (RAG)

Choose between Chroma (simple) or Qdrant (production).

#### Chroma DB

**Files**: [`chroma/`](chroma/)

**Quick Install**:
```bash
cd ml-stack/chroma
./install.sh
```

**Use Case**: Simple RAG, prototyping

#### Qdrant

**Files**: [`qdrant/`](qdrant/)

**Quick Install**:
```bash
cd ml-stack/qdrant
./install.sh
```

**Use Case**: Production RAG, high performance

**RAG Example with LangChain**:
```python
from langchain_community.llms import Ollama
from langchain_community.vectorstores import Chroma
from langchain.embeddings import OllamaEmbeddings
from langchain.chains import RetrievalQA

# Setup
llm = Ollama(
    base_url="http://ollama.ollama.svc.cluster.local:11434",
    model="llama2"
)

embeddings = OllamaEmbeddings(
    base_url="http://ollama.ollama.svc.cluster.local:11434",
    model="llama2"
)

vectorstore = Chroma(
    collection_name="my_docs",
    embedding_function=embeddings,
    persist_directory="/data/chroma"
)

# RAG chain
qa_chain = RetrievalQA.from_chain_type(
    llm=llm,
    retriever=vectorstore.as_retriever()
)

result = qa_chain.run("What is in my documents?")
```

---

### 5. Kubeflow (Full MLOps Platform)

**When to use**: Serious ML workflows, multiple team members, complex pipelines

**Resource Requirements**:
- 8+ CPU cores
- 16GB+ RAM
- 100GB+ storage

**Installation**:
```bash
# Using Kubeflow manifests
kubectl apply -k "github.com/kubeflow/manifests/example?ref=v1.8.0"

# Or using kustomize
git clone https://github.com/kubeflow/manifests.git
cd manifests
kubectl apply -k example
```

**Components**:
- **Notebooks**: JupyterHub alternative
- **Pipelines**: ML workflow orchestration
- **KServe**: Model serving
- **Katib**: Hyperparameter tuning
- **Training Operators**: Distributed training

**Integrating with Ollama**:
- Use Kubeflow notebooks to connect to Ollama
- Build pipelines that use Ollama for inference
- Serve fine-tuned models alongside Ollama

---

### 6. KServe (Model Serving)

**When to use**: Production model deployment, A/B testing, auto-scaling

**Lightweight Alternative to Full Kubeflow**

**Installation**:
```bash
# Install KServe (standalone)
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.12.0/kserve.yaml
```

**Why use with Ollama**:
- Ollama for inference, KServe for orchestration
- Canary deployments
- Traffic splitting
- Advanced scaling

---

## Integration Patterns

### Pattern 1: Simple LLM Usage
```
User → Open WebUI → Ollama → Response
```
**Tools**: Ollama + Open WebUI

### Pattern 2: Development Workflow
```
Developer → JupyterHub → Ollama → MLflow (tracking)
```
**Tools**: Ollama + JupyterHub + MLflow

### Pattern 3: RAG Application
```
User → Open WebUI → Ollama + Vector DB → Response with context
```
**Tools**: Ollama + Open WebUI + Chroma/Qdrant

### Pattern 4: Full MLOps
```
Data → Kubeflow Pipeline → Training → MLflow → KServe → Production
                            ↓
                         Ollama (inference)
```
**Tools**: Full stack

## Monitoring & Observability

### Already Available
- **Prometheus + Grafana** (in your homelab)
- Monitor all ML services

### Dashboards to Create
1. **Ollama Metrics**: Request rate, latency, model usage
2. **MLflow Tracking**: Experiment trends
3. **Resource Usage**: GPU/CPU/Memory per service

**Grafana Dashboard Config**:
```yaml
# Add to prometheus scrape configs
- job_name: 'ollama'
  static_configs:
    - targets: ['ollama.ollama.svc.cluster.local:11434']

- job_name: 'mlflow'
  static_configs:
    - targets: ['mlflow.mlflow.svc.cluster.local:5000']
```

## Common Workflows

### 1. Chat & Exploration
```bash
# Open WebUI for casual use
open http://open-webui.YOUR_IP.nip.io

# Switch models, upload documents, chat
```

### 2. Development
```bash
# JupyterHub for coding
open http://jupyter.YOUR_IP.nip.io

# Write Python code to interact with Ollama
# Test LangChain applications
# Develop RAG pipelines
```

### 3. Experiment Tracking
```bash
# Run experiments with MLflow tracking
python my_llm_experiment.py

# View results
open http://mlflow.YOUR_IP.nip.io

# Compare prompts, models, parameters
```

### 4. RAG Application Development
```bash
# 1. Develop in JupyterHub
# 2. Store embeddings in Chroma/Qdrant
# 3. Query via Ollama
# 4. Track with MLflow
# 5. Deploy via Open WebUI or custom app
```

## Cost-Benefit Analysis

| Tool | Resource Cost | Benefit | Priority |
|------|--------------|---------|----------|
| Ollama | Medium (4-8GB RAM) | Essential - LLM runtime | ✅ Required |
| Open WebUI | Low (512MB RAM) | User-friendly interface | ⭐⭐⭐ High |
| JupyterHub | Medium (2-4GB RAM) | Development environment | ⭐⭐ Medium |
| MLflow | Low (1GB RAM) | Experiment tracking | ⭐⭐ Medium |
| Chroma | Low (512MB RAM) | Simple RAG | ⭐ Low |
| Qdrant | Medium (1-2GB RAM) | Production RAG | ⭐ Low |
| Kubeflow | High (8GB+ RAM) | Full MLOps | ⚠️ Optional |

## Next Steps

### Immediate (Do Now)
1. Deploy Open WebUI - Get a ChatGPT-like interface
2. Test Ollama integration
3. Upload documents, try RAG

### Short-term (This Week)
1. Deploy JupyterHub
2. Create notebooks for LLM experiments
3. Set up MLflow tracking

### Long-term (As Needed)
1. Add vector database for RAG apps
2. Consider Kubeflow if scaling up
3. Build production pipelines

## Resources & Documentation

### Ollama Integration
- [MLflow Tracing for Ollama](https://mlflow.org/docs/latest/genai/tracing/integrations/listing/ollama/)
- [Ollama API Documentation](https://github.com/ollama/ollama/blob/main/docs/api.md)

### Open WebUI
- [Open WebUI Helm Chart](https://github.com/open-webui/helm-charts)
- [Open WebUI Documentation](https://docs.openwebui.com/)

### Kubeflow
- [Kubeflow Official Docs](https://www.kubeflow.org/)
- [Deploying Llama with Kubeflow](https://www.civo.com/learn/deploy-llama3-kubeflow-kubernetes-cpu-serverless)

### MLOps Patterns
- [Building AI Architecture on Kubernetes](https://medium.com/h7w/building-a-modular-ai-micro-agent-architecture-on-kubernetes-from-ollama-to-kserve-and-beyond-25e19217defa)
- [MLflow + Ollama Integration](https://medium.com/@hitorunajp/bringing-observability-to-local-llms-first-experiments-with-mlflow-tracing-and-ollama-8f2f18cf9968)

## Support & Community

- **Homelab ML Stack**: `/home/spacecrab/repos/homelab/k8s/ml-stack/`
- **Ollama Discord**: https://discord.gg/ollama
- **Kubeflow Slack**: https://www.kubeflow.org/docs/about/community/

## Sources

- [Ollama & Open WebUI on Kubernetes](https://medium.com/@arslankhanali/ollama-open-webui-on-kubernetes-3c18497a3ed2)
- [Open WebUI Helm Charts](https://github.com/open-webui/helm-charts)
- [MLflow Tracing for Ollama](https://mlflow.org/docs/latest/genai/tracing/integrations/listing/ollama/)
- [Bringing Observability to Local LLMs with MLflow](https://medium.com/@hitorunajp/bringing-observability-to-local-llms-first-experiments-with-mlflow-tracing-and-ollama-8f2f18cf9968)
- [Building Modular AI Architecture on Kubernetes](https://medium.com/h7w/building-a-modular-ai-micro-agent-architecture-on-kubernetes-from-ollama-to-kserve-and-beyond-25e19217defa)
- [Deploying Llama 3.1 with Kubeflow](https://www.civo.com/learn/deploy-llama3-kubeflow-kubernetes-cpu-serverless)

---

Ready to build your ML stack! Start with Open WebUI for immediate value, then add tools as your needs grow. 🚀
