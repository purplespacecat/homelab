# GitOps Implementation Guide for Homelab

This guide explains how to implement GitOps for this homelab Kubernetes cluster using Argo CD.

## Table of Contents
- [Why GitOps?](#why-gitops)
- [Why Argo CD?](#why-argo-cd)
- [How Argo CD Works with Mixed Deployments](#how-argo-cd-works-with-mixed-deployments)
- [Architecture Overview](#architecture-overview)
- [Implementation Examples](#implementation-examples)
- [Workflow Comparison](#workflow-comparison)
- [Installation Steps](#installation-steps)
- [Alternative: Flux CD](#alternative-flux-cd)

## Why GitOps?

GitOps provides:
- **Version Control** - All infrastructure changes tracked in Git
- **Automatic Synchronization** - Cluster state matches Git repository
- **Easy Rollbacks** - Git revert = infrastructure rollback
- **Audit Trail** - Complete history of who changed what and when
- **Declarative** - Desired state in Git, controllers ensure actual state matches
- **Consistency** - Single source of truth for cluster configuration

## Why Argo CD?

For a homelab environment, **Argo CD** is recommended because:

| Feature | Benefit |
|---------|---------|
| **Web UI** | Visualize deployments, sync status, health, and diffs |
| **Flexibility** | Manual sync option while learning, then enable automation |
| **App-of-Apps Pattern** | Manage all components hierarchically |
| **Self-hosted** | Runs entirely in your cluster |
| **Multi-source Support** | Handle Helm charts + custom values + raw YAML in one app |
| **Popular** | Strong community, extensive documentation |

## How Argo CD Works with Mixed Deployments

This repository uses a combination of:
1. **Helm charts with custom values** (Prometheus, NGINX Ingress, etc.)
2. **Raw Kubernetes YAML manifests** (applications, core configs, etc.)

Argo CD natively supports both! Here's how:

### 1. Helm Charts with Custom Values Files

Argo CD can deploy Helm charts from chart repositories while using **your custom values files from Git**.

**Example: Prometheus Stack**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-stack
  namespace: argocd
spec:
  project: default
  sources:
    # Source 1: Helm chart from upstream repository
    - repoURL: https://prometheus-community.github.io/helm-charts
      chart: kube-prometheus-stack
      targetRevision: 55.0.0
      helm:
        valueFiles:
          - $values/k8s/helm/prometheus/values.yaml
    # Source 2: Your Git repository containing custom values
    - repoURL: https://github.com/youruser/homelab.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**How it works:**
- Argo pulls the Helm chart from `prometheus-community` repository
- Uses your custom `values.yaml` from your Git repository
- Any changes to `k8s/helm/prometheus/values.yaml` trigger automatic sync
- Combines the best of both: upstream charts + your customizations

### 2. Raw YAML Manifests

For directories containing standard Kubernetes YAML files, Argo CD applies them directly.

**Example: Core Infrastructure**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: core-infrastructure
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/youruser/homelab.git
    targetRevision: main
    path: k8s/core
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**How it works:**
- Argo CD monitors the `k8s/core/` directory
- Applies all YAML files recursively (namespaces, metallb-config, storage, etc.)
- Any changes to files in this directory trigger automatic sync
- Equivalent to `kubectl apply -f k8s/core/ -R`

### 3. Combined Approach for Complex Deployments

Some components need both Helm installation AND additional raw manifests.

**Example: MetalLB (Helm chart + config)**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: metallb
  namespace: argocd
spec:
  project: default
  sources:
    # Source 1: MetalLB Helm chart
    - repoURL: https://metallb.github.io/metallb
      chart: metallb
      targetRevision: 0.13.12
    # Source 2: Custom configuration from your repo
    - repoURL: https://github.com/youruser/homelab.git
      targetRevision: main
      path: k8s/core/networking
  destination:
    server: https://kubernetes.default.svc
    namespace: metallb-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Architecture Overview

Here's how your current repository structure maps to Argo CD Applications:

```
Argo CD Application Hierarchy:
├── bootstrap (App of Apps)
    ├── core-infrastructure
    │   ├── core-namespaces        → k8s/core/namespaces/*.yaml
    │   ├── core-storage           → k8s/core/storage/*.yaml
    │   └── core-security          → k8s/core/security/*.yaml
    ├── networking
    │   ├── metallb                → Helm chart + k8s/core/networking/metallb-config.yaml
    │   └── ingress-nginx          → Helm chart + k8s/helm/ingress-nginx/values.yaml
    ├── security
    │   └── cert-manager           → Helm chart + k8s/cert-manager/*.yaml
    └── monitoring
        └── prometheus-stack       → Helm chart + k8s/helm/prometheus/values.yaml
```

### Proposed Directory Structure

Add an `argocd/` directory to your repository:

```
homelab/
├── k8s/
│   ├── core/               # Existing - no changes needed
│   ├── applications/       # Existing - no changes needed
│   ├── ml-stack/          # Existing - no changes needed
│   ├── cert-manager/      # Existing - no changes needed
│   └── helm/              # Existing - no changes needed
└── argocd/                # NEW - Argo CD configurations
    ├── bootstrap/
    │   └── root-app.yaml  # App of Apps - manages all other apps
    ├── projects/
    │   └── homelab-project.yaml
    ├── core/
    │   ├── namespaces.yaml
    │   ├── storage.yaml
    │   ├── security.yaml
    │   ├── metallb.yaml
    │   └── ingress-nginx.yaml
    ├── security/
    │   └── cert-manager.yaml
    └── monitoring/
        └── prometheus-stack.yaml
```

## Implementation Examples

### Example 1: NGINX Ingress Controller

**File:** `argocd/core/ingress-nginx.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ingress-nginx
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: homelab
  sources:
    - repoURL: https://kubernetes.github.io/ingress-nginx
      chart: ingress-nginx
      targetRevision: 4.8.3
      helm:
        valueFiles:
          - $values/k8s/helm/ingress-nginx/values.yaml
    - repoURL: https://github.com/youruser/homelab.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: ingress-nginx
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### Example 2: App of Apps (Bootstrap)

**File:** `argocd/bootstrap/root-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: homelab-bootstrap
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/youruser/homelab.git
    targetRevision: main
    path: argocd
    directory:
      recurse: true
      exclude: 'bootstrap/*'
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

This single Application manages all other Applications!

## Workflow Comparison

### Before GitOps (Current Manual Process)

```bash
# Install Helm chart with custom values
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f k8s/helm/prometheus/values.yaml

# Apply raw YAML manifests
kubectl apply -f k8s/core/namespaces/
kubectl apply -f k8s/cert-manager/

# Update configuration
vim k8s/helm/prometheus/values.yaml
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f k8s/helm/prometheus/values.yaml
```

**Issues:**
- Manual steps prone to errors
- No automatic sync between Git and cluster
- Easy to have cluster drift from Git
- Need to remember which commands to run

### After GitOps (Argo CD)

```bash
# Make changes
vim k8s/helm/prometheus/values.yaml

# Commit and push
git add k8s/helm/prometheus/values.yaml
git commit -m "Increase Prometheus retention to 60 days"
git push

# Argo CD automatically:
# 1. Detects the change
# 2. Syncs the new configuration
# 3. Updates the deployment
# 4. Shows status in UI
```

**Benefits:**
- Single workflow for all changes
- Automatic synchronization
- Git is the source of truth
- Full audit trail
- Easy rollbacks via Git

### Viewing Status

```bash
# CLI
argocd app list
argocd app get prometheus-stack
argocd app sync prometheus-stack  # Manual sync if needed

# Web UI
# Navigate to https://argocd.yourdomain.com
# Visual dashboard showing all apps, health, sync status
```

## Installation Steps

### 1. Install Argo CD

```bash
# Create namespace
kubectl create namespace argocd

# Install Argo CD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for rollout
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

### 2. Expose Argo CD UI

**Option A: Port Forward (Quick)**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Access at https://localhost:8080
```

**Option B: Ingress (Recommended)**

Create `k8s/argocd/argocd-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.<NODE-IP>.nip.io  # Replace with your node IP
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: https
```

Apply it:
```bash
kubectl apply -f k8s/argocd/argocd-ingress.yaml
```

### 3. Install Argo CD CLI (Optional)

```bash
# Linux
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# Login (replace <NODE-IP> with your actual node IP)
argocd login argocd.<NODE-IP>.nip.io --username admin --password <password>
```

### 4. Create Argo CD Project

Create `argocd/projects/homelab-project.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: homelab
  namespace: argocd
spec:
  description: Homelab infrastructure and applications
  sourceRepos:
    - 'https://github.com/youruser/homelab.git'
    - 'https://prometheus-community.github.io/helm-charts'
    - 'https://kubernetes.github.io/ingress-nginx'
    - 'https://metallb.github.io/metallb'
    - 'https://charts.jetstack.io'
  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
```

Apply it:
```bash
kubectl apply -f argocd/projects/homelab-project.yaml
```

### 5. Deploy Bootstrap Application

Update `argocd/bootstrap/root-app.yaml` with your Git repository URL, then:

```bash
kubectl apply -f argocd/bootstrap/root-app.yaml
```

This will create all Applications which will then sync your entire infrastructure!

### 6. Migration Strategy

**Gradual Migration (Recommended):**

1. **Phase 1: Monitoring** (Low Risk)
   - Create Argo Application for Prometheus stack
   - Let both manual and GitOps coexist
   - Verify sync works correctly

2. **Phase 2: Core Infrastructure**
   - Migrate networking, storage, cert-manager
   - Test rollbacks and sync

3. **Phase 3: Full GitOps**
   - All infrastructure managed by Argo CD
   - Keep scripts as backup for disaster recovery

4. **Phase 4: Add New Applications**
   - Deploy new apps via Argo CD as needed
   - Follow the same GitOps workflow

**Quick Migration:**
1. Create Application manifests for existing infrastructure
2. Deploy bootstrap app
3. Let Argo CD take over management
4. Keep installation scripts as backup for disaster recovery

## Alternative: Flux CD

If you prefer a more lightweight, CLI-focused approach:

### Flux CD Characteristics

| Feature | Flux CD | Argo CD |
|---------|---------|---------|
| UI | No (CLI only) | Yes (full web UI) |
| Resource Usage | Lighter | Heavier |
| Learning Curve | Steeper | Gentler (UI helps) |
| Automation | Pure GitOps only | Flexible (manual + auto) |
| Helm Support | Via HelmRelease CRD | Native |
| Multi-tenancy | Good | Excellent |

### Quick Flux Setup

```bash
# Install Flux CLI
curl -s https://fluxcd.io/install.sh | sudo bash

# Bootstrap (connects your Git repo)
flux bootstrap github \
  --owner=youruser \
  --repository=homelab \
  --branch=main \
  --path=./clusters/homelab \
  --personal

# Flux creates its own directory structure in your repo
```

### Flux Directory Structure

```
homelab/
├── clusters/
│   └── homelab/
│       ├── flux-system/          # Generated by Flux
│       ├── infrastructure.yaml   # Kustomization for infra
│       └── apps.yaml            # Kustomization for apps
├── infrastructure/
│   ├── sources/                 # Helm repositories
│   ├── metallb/
│   ├── cert-manager/
│   └── ingress-nginx/
└── apps/
    ├── base/
    └── production/
```

## Recommendations

**Choose Argo CD if:**
- You want a web UI for visibility
- You're learning GitOps
- You want flexibility (manual + automatic sync)
- You prefer a gentler learning curve

**Choose Flux CD if:**
- You want pure GitOps automation
- You prefer CLI over UI
- You want lighter resource usage
- You're comfortable with Kubernetes concepts

For this homelab setup, **Argo CD is recommended** due to its UI and flexibility while learning.

## Troubleshooting

### Application Not Syncing

```bash
# Check application status
argocd app get <app-name>

# View sync status
kubectl get application -n argocd

# Force sync
argocd app sync <app-name>

# View logs
kubectl logs -n argocd deployment/argocd-application-controller
```

### Out of Sync Issues

```bash
# Compare desired vs actual state
argocd app diff <app-name>

# View app details
argocd app get <app-name> --refresh

# Hard refresh (ignore cache)
argocd app get <app-name> --hard-refresh
```

### Helm Chart Issues

```bash
# View helm parameters
argocd app get <app-name> -o yaml

# Check helm template rendering
argocd app manifests <app-name>
```

## Best Practices

1. **Use App of Apps Pattern**
   - Single root application manages all others
   - Easier to bootstrap new clusters

2. **Enable Auto-Sync with Prune**
   - Keeps cluster in sync with Git
   - Automatically removes deleted resources

3. **Use Projects for Organization**
   - Separate projects for different environments
   - Control permissions and allowed resources

4. **Version Pin Helm Charts**
   - Use specific chart versions, not `latest`
   - Prevents unexpected updates

5. **Keep Secrets Out of Git**
   - Use External Secrets Operator or Sealed Secrets
   - Never commit sensitive data

6. **Monitor Sync Status**
   - Set up alerts for sync failures
   - Regular audits of out-of-sync applications

7. **Git Workflow**
   - Use branches for changes
   - PR review before merging to main
   - Main branch = production deployment

## Next Steps

1. Install Argo CD in your cluster
2. Create Application manifests for existing deployments
3. Test with one application (e.g., Prometheus)
4. Gradually migrate remaining applications
5. Configure auto-sync once comfortable
6. Set up monitoring and alerts for Argo CD

## References

- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Argo CD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Flux CD Documentation](https://fluxcd.io/docs/)
- [GitOps Principles](https://opengitops.dev/)
