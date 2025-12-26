# MLflow Deployment

MLflow is an open-source platform for managing the ML lifecycle, including experimentation, reproducibility, and deployment.

## Installation

Since there isn't a widely-adopted official Helm chart, we provide a simple YAML deployment:

```bash
# Deploy MLflow
kubectl apply -f mlflow-deployment.yaml

# Check status
kubectl get all -n mlflow

# Get access URL
kubectl get ingress -n mlflow
```

## Access

- **LoadBalancer**: `kubectl get svc -n mlflow mlflow`
- **Ingress**: `http://mlflow.YOUR_IP.nip.io`

## Using with Ollama

### Example 1: Automatic Tracing

```python
import mlflow
from mlflow.openai import autolog
import openai

# Enable auto-logging
autolog()

# Connect to Ollama (OpenAI-compatible API)
client = openai.OpenAI(
    base_url="http://ollama.ollama.svc.cluster.local:11434/v1",
    api_key="ollama"  # Required but unused
)

# This will be automatically logged to MLflow
response = client.chat.completions.create(
    model="llama2",
    messages=[{"role": "user", "content": "Hello!"}]
)

print(response.choices[0].message.content)
```

### Example 2: Manual Logging

```python
import mlflow
import requests

# Set tracking URI
mlflow.set_tracking_uri("http://mlflow.mlflow.svc.cluster.local:5000")

# Start experiment
mlflow.set_experiment("ollama-experiments")

with mlflow.start_run():
    # Log parameters
    mlflow.log_param("model", "llama2")
    mlflow.log_param("temperature", 0.7)
    mlflow.log_param("prompt", "Explain Kubernetes")

    # Call Ollama
    response = requests.post(
        "http://ollama.ollama.svc.cluster.local:11434/api/generate",
        json={
            "model": "llama2",
            "prompt": "Explain Kubernetes in simple terms",
            "temperature": 0.7,
            "stream": False
        }
    )

    result = response.json()

    # Log metrics
    mlflow.log_metric("response_length", len(result["response"]))
    mlflow.log_metric("eval_count", result.get("eval_count", 0))

    # Log the response as artifact
    mlflow.log_text(result["response"], "response.txt")
```

## Features

- ✓ Track experiments with Ollama
- ✓ Compare different prompts and models
- ✓ Log metrics and artifacts
- ✓ Version models
- ✓ Collaborate with team

## Uninstall

```bash
kubectl delete -f mlflow-deployment.yaml
```
