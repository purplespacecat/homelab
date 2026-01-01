# FluxCD Implementation Guide for Homelab

This guide explains how to implement GitOps for this homelab Kubernetes cluster using Flux CD.

## Table of Contents
- [Why Flux CD?](#why-flux-cd)
- [How Flux CD Works](#how-flux-cd-works)
- [Core Concepts](#core-concepts)
- [Architecture Overview](#architecture-overview)
- [Installation Steps](#installation-steps)
- [Migrating Existing Infrastructure](#migrating-existing-infrastructure)
- [Implementation Examples](#implementation-examples)
- [Workflow Comparison](#workflow-comparison)
- [Advanced Features](#advanced-features)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Why Flux CD?

Flux CD is a **pure GitOps** tool that enforces Git as the single source of truth for your infrastructure.

### Key Advantages

| Feature | Benefit |
|---------|---------|
| **Pure GitOps** | Enforces declarative, Git-centric workflows |
| **Lightweight** | ~150-200MB RAM vs Argo's ~500-800MB |
| **Modular Architecture** | Separate controllers for different tasks |
| **Native Image Automation** | Auto-update container images when new versions available |
| **SOPS Integration** | Built-in secrets encryption support |
| **Multi-Tenancy** | Excellent namespace isolation |
| **CNCF Graduated** | Production-ready, widely adopted |

### Flux CD vs Traditional Deployment

**Before:**
```bash
helm install prometheus prometheus-community/kube-prometheus-stack -f values.yaml
# Cluster state diverges from Git over time
# Manual updates required
# No audit trail
```

**After:**
```bash
git commit -m "Update Prometheus retention"
git push
# Flux automatically syncs within 1 minute
# Git is the source of truth
# Full audit trail in Git history
```

## How Flux CD Works

Flux CD uses a **reconciliation loop** architecture with multiple controllers:

```
┌─────────────────────────────────────────────────────────────┐
│                         Git Repository                       │
│  (clusters/, infrastructure/, apps/)                         │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ Polls every 1 min (configurable)
                 ▼
┌─────────────────────────────────────────────────────────────┐
│              Source Controller                               │
│  - Watches Git repos, Helm repos, S3 buckets                │
│  - Creates source artifacts for other controllers           │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ Provides artifacts
                 ▼
┌─────────────────────────────────────────────────────────────┐
│         Kustomize Controller / Helm Controller              │
│  - Applies Kubernetes manifests                             │
│  - Installs/upgrades Helm releases                          │
│  - Reconciles cluster state with Git                        │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ Applies to cluster
                 ▼
┌─────────────────────────────────────────────────────────────┐
│              Kubernetes Cluster                              │
│  (Namespaces, Deployments, Services, etc.)                  │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

1. **Source Controller** - Fetches artifacts from Git, Helm repos, S3
2. **Kustomize Controller** - Applies Kubernetes manifests
3. **Helm Controller** - Manages Helm releases
4. **Notification Controller** - Sends alerts to Slack, Discord, etc.
5. **Image Reflector/Automation Controllers** - Scans for new images, updates Git

## Core Concepts

### GitRepository

Defines a Git repository as a source:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: homelab
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/youruser/homelab
  ref:
    branch: main
```

### HelmRepository

Defines a Helm chart repository:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
spec:
  interval: 1h
  url: https://prometheus-community.github.io/helm-charts
```

### HelmRelease

Declares a Helm release to be installed/upgraded:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: prometheus-stack
  namespace: monitoring
spec:
  interval: 5m
  chart:
    spec:
      chart: kube-prometheus-stack
      version: 55.0.0
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
  values:
    prometheus:
      prometheusSpec:
        retention: 2d
```

### Kustomization

Applies Kubernetes manifests from a source:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: core-infrastructure
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: homelab
  path: ./k8s/core
  prune: true
  wait: true
```

## Architecture Overview

### Proposed Directory Structure

```
homelab/
├── clusters/
│   └── homelab/
│       ├── flux-system/              # Auto-generated by Flux
│       │   ├── gotk-components.yaml  # Flux controllers
│       │   ├── gotk-sync.yaml        # Git sync config
│       │   └── kustomization.yaml
│       ├── infrastructure.yaml       # Kustomization for infrastructure
│       ├── core.yaml                 # Kustomization for core resources
│       └── monitoring.yaml           # Kustomization for monitoring
├── infrastructure/
│   ├── sources/
│   │   ├── prometheus-community.yaml
│   │   ├── ingress-nginx.yaml
│   │   ├── metallb.yaml
│   │   ├── jetstack.yaml
│   │   └── nfs-provisioner.yaml
│   ├── core/
│   │   ├── namespaces.yaml           # Kustomization for namespaces
│   │   ├── storage.yaml              # Kustomization for storage
│   │   └── networking.yaml           # Kustomization for networking
│   ├── networking/
│   │   ├── metallb.yaml              # HelmRelease for MetalLB
│   │   └── ingress-nginx.yaml        # HelmRelease for NGINX
│   ├── security/
│   │   └── cert-manager.yaml         # HelmRelease for cert-manager
│   ├── storage/
│   │   └── nfs-provisioner.yaml      # HelmRelease for NFS provisioner
│   └── monitoring/
│       └── prometheus-stack.yaml     # HelmRelease for Prometheus
└── k8s/                              # EXISTING - Keep as-is
    ├── core/
    │   ├── namespaces/
    │   ├── networking/
    │   ├── storage/
    │   └── security/
    ├── helm/
    │   ├── ingress-nginx/values.yaml
    │   └── prometheus/values.yaml
    └── cert-manager/
```

### Architecture Flow

```
Git Push
    ↓
Source Controller detects change (1 min)
    ↓
Kustomization/HelmRelease reconciles
    ↓
Helm Controller installs/upgrades release
    ↓
Notification Controller sends alert
    ↓
Cluster state matches Git
```

## Installation Steps

### Prerequisites

```bash
# Check you have kubectl access
kubectl get nodes

# Ensure cluster is healthy
kubectl get pods -A
```

### Step 1: Install Flux CLI

```bash
# Linux/macOS
curl -s https://fluxcd.io/install.sh | sudo bash

# Verify installation
flux --version

# Check cluster compatibility
flux check --pre
```

**Expected output:**
```
► checking prerequisites
✔ Kubernetes 1.28.0 >=1.26.0-0
✔ prerequisites checks passed
```

### Step 2: Bootstrap Flux (GitHub)

**Option A: GitHub (Recommended)**

```bash
# Set GitHub token (needs repo permissions)
export GITHUB_TOKEN=<your-token>
export GITHUB_USER=<your-username>

# Bootstrap Flux
flux bootstrap github \
  --owner=${GITHUB_USER} \
  --repository=homelab \
  --branch=main \
  --path=./clusters/homelab \
  --personal
```

**Option B: Generic Git (GitLab, Gitea, self-hosted)**

```bash
flux bootstrap git \
  --url=ssh://git@github.com/${GITHUB_USER}/homelab \
  --branch=main \
  --path=./clusters/homelab \
  --private-key-file=/path/to/ssh/private/key
```

**What bootstrap does:**
1. Installs Flux controllers in `flux-system` namespace
2. Creates `clusters/homelab/flux-system/` directory in your repo
3. Commits and pushes the configuration
4. Sets up Git sync (Flux watches this directory)

### Step 3: Verify Installation

```bash
# Check Flux components
flux check

# View Flux resources
flux get all

# Check pods
kubectl get pods -n flux-system
```

**Expected pods:**
```
NAME                                      READY   STATUS
helm-controller-...                       1/1     Running
kustomize-controller-...                  1/1     Running
notification-controller-...               1/1     Running
source-controller-...                     1/1     Running
```

### Step 4: Configure Notifications (Optional)

Create `clusters/homelab/notifications.yaml`:

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta2
kind: Alert
metadata:
  name: homelab-alert
  namespace: flux-system
spec:
  summary: "Homelab Flux Notifications"
  eventSeverity: info
  eventSources:
    - kind: GitRepository
      name: '*'
    - kind: Kustomization
      name: '*'
    - kind: HelmRelease
      name: '*'
      namespace: '*'
  providerRef:
    name: slack
---
apiVersion: notification.toolkit.fluxcd.io/v1beta2
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  channel: homelab-alerts
  secretRef:
    name: slack-webhook
---
apiVersion: v1
kind: Secret
metadata:
  name: slack-webhook
  namespace: flux-system
stringData:
  address: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

## Migrating Existing Infrastructure

### Strategy: Gradual Migration

We'll migrate in phases to minimize risk:

1. **Phase 1**: Helm repositories (sources)
2. **Phase 2**: Core infrastructure (namespaces, storage)
3. **Phase 3**: Networking (MetalLB, NGINX)
4. **Phase 4**: Security (cert-manager)
5. **Phase 5**: Monitoring (Prometheus stack)

### Phase 1: Create Helm Repository Sources

Create `infrastructure/sources/` directory with Helm repos:

**infrastructure/sources/prometheus-community.yaml:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
spec:
  interval: 1h
  url: https://prometheus-community.github.io/helm-charts
```

**infrastructure/sources/ingress-nginx.yaml:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 1h
  url: https://kubernetes.github.io/ingress-nginx
```

**infrastructure/sources/metallb.yaml:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: metallb
  namespace: flux-system
spec:
  interval: 1h
  url: https://metallb.github.io/metallb
```

**infrastructure/sources/jetstack.yaml:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: jetstack
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.jetstack.io
```

**infrastructure/sources/nfs-provisioner.yaml:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: nfs-subdir-external-provisioner
  namespace: flux-system
spec:
  interval: 1h
  url: https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner
```

**Create Kustomization to deploy sources:**

**clusters/homelab/sources.yaml:**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: sources
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/sources
  prune: true
  wait: true
```

**Commit and push:**
```bash
git add infrastructure/sources clusters/homelab/sources.yaml
git commit -m "Add Helm repository sources"
git push

# Verify
flux get sources helm -A
```

### Phase 2: Core Infrastructure

**infrastructure/core/namespaces.yaml:**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: core-namespaces
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./k8s/core/namespaces
  prune: true
  wait: true
```

**infrastructure/core/storage.yaml:**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: core-storage
  namespace: flux-system
spec:
  interval: 10m
  dependsOn:
    - name: core-namespaces
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./k8s/core/storage
  prune: true
  wait: true
```

**infrastructure/core/security.yaml:**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: core-security
  namespace: flux-system
spec:
  interval: 10m
  dependsOn:
    - name: core-namespaces
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./k8s/core/security
  prune: true
  wait: true
```

**clusters/homelab/core.yaml:**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: core-infrastructure
  namespace: flux-system
spec:
  interval: 10m
  dependsOn:
    - name: sources
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/core
  prune: true
  wait: true
```

**Commit and deploy:**
```bash
git add infrastructure/core clusters/homelab/core.yaml
git commit -m "Add core infrastructure"
git push

# Watch reconciliation
flux get kustomizations -w
```

### Phase 3: NFS Storage Provisioner

**infrastructure/storage/nfs-provisioner.yaml:**
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: nfs-subdir-external-provisioner
  namespace: kube-system
spec:
  interval: 5m
  chart:
    spec:
      chart: nfs-subdir-external-provisioner
      version: 4.0.18
      sourceRef:
        kind: HelmRepository
        name: nfs-subdir-external-provisioner
        namespace: flux-system
  values:
    nfs:
      server: 192.168.100.98
      path: /data
      mountOptions:
        - hard
        - nfsvers=4.1
        - noatime
    storageClass:
      name: nfs-client
      defaultClass: true
      accessModes: ReadWriteMany
      reclaimPolicy: Retain
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
```

**clusters/homelab/storage.yaml:**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: storage
  namespace: flux-system
spec:
  interval: 10m
  dependsOn:
    - name: core-infrastructure
    - name: sources
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/storage
  prune: true
  wait: true
```

### Phase 4: Networking

**infrastructure/networking/metallb.yaml:**
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: metallb
  namespace: metallb-system
spec:
  interval: 5m
  chart:
    spec:
      chart: metallb
      version: 0.13.12
      sourceRef:
        kind: HelmRepository
        name: metallb
        namespace: flux-system
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
---
# Apply MetalLB config after chart installation
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: metallb-config
  namespace: flux-system
spec:
  interval: 10m
  dependsOn:
    - name: networking
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./k8s/core/networking
  prune: true
  wait: true
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: metallb-controller
      namespace: metallb-system
```

**infrastructure/networking/ingress-nginx.yaml:**
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
spec:
  interval: 5m
  chart:
    spec:
      chart: ingress-nginx
      version: 4.8.3
      sourceRef:
        kind: HelmRepository
        name: ingress-nginx
        namespace: flux-system
  values:
    controller:
      hostNetwork: true
      kind: DaemonSet
      service:
        type: ClusterIP
      metrics:
        enabled: true
        serviceMonitor:
          enabled: true
      resources:
        limits:
          cpu: 200m
          memory: 256Mi
        requests:
          cpu: 100m
          memory: 128Mi
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
```

**clusters/homelab/networking.yaml:**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: networking
  namespace: flux-system
spec:
  interval: 10m
  dependsOn:
    - name: core-infrastructure
    - name: sources
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/networking
  prune: true
  wait: true
```

### Phase 5: Security (cert-manager)

**infrastructure/security/cert-manager.yaml:**
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  interval: 5m
  chart:
    spec:
      chart: cert-manager
      version: v1.13.3
      sourceRef:
        kind: HelmRepository
        name: jetstack
        namespace: flux-system
  values:
    installCRDs: true
    prometheus:
      enabled: true
      servicemonitor:
        enabled: true
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
---
# Apply cert-manager issuers after installation
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cert-manager-config
  namespace: flux-system
spec:
  interval: 10m
  dependsOn:
    - name: security
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./k8s/cert-manager
  prune: true
  wait: true
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: cert-manager
      namespace: cert-manager
```

**clusters/homelab/security.yaml:**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: security
  namespace: flux-system
spec:
  interval: 10m
  dependsOn:
    - name: core-infrastructure
    - name: sources
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/security
  prune: true
  wait: true
```

### Phase 6: Monitoring

**infrastructure/monitoring/prometheus-stack.yaml:**
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: prometheus-stack
  namespace: monitoring
spec:
  interval: 5m
  chart:
    spec:
      chart: kube-prometheus-stack
      version: 55.0.0
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
  values:
    # Prometheus configuration
    prometheus:
      prometheusSpec:
        retention: 2d
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: nfs-client
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 10Gi
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
      ingress:
        enabled: true
        ingressClassName: nginx
        hosts:
          - prometheus.192.168.100.98.nip.io
          - prometheus.local

    # Grafana configuration
    grafana:
      enabled: true
      persistence:
        enabled: true
        storageClassName: nfs-client
        size: 10Gi
      adminPassword: admin
      ingress:
        enabled: true
        ingressClassName: nginx
        hosts:
          - grafana.192.168.100.98.nip.io
          - grafana.local

    # Alertmanager configuration
    alertmanager:
      alertmanagerSpec:
        storage:
          volumeClaimTemplate:
            spec:
              storageClassName: nfs-client
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 10Gi
      ingress:
        enabled: true
        ingressClassName: nginx
        hosts:
          - alertmanager.192.168.100.98.nip.io
          - alertmanager.local

    # Disable components not available in some clusters
    kubeScheduler:
      enabled: false
    kubeControllerManager:
      enabled: false
    kubeEtcd:
      enabled: false
    kubeProxy:
      enabled: false

    # Enable exporters
    nodeExporter:
      enabled: true
    kubeStateMetrics:
      enabled: true

    # Prometheus Operator
    prometheusOperator:
      admissionWebhooks:
        enabled: false
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
```

**clusters/homelab/monitoring.yaml:**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: monitoring
  namespace: flux-system
spec:
  interval: 10m
  dependsOn:
    - name: core-infrastructure
    - name: networking
    - name: storage
    - name: sources
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/monitoring
  prune: true
  wait: true
```

### Final Deployment

```bash
# Commit all changes
git add clusters/homelab infrastructure/
git commit -m "Complete Flux CD migration"
git push

# Watch everything deploy
flux get kustomizations -w

# Check Helm releases
flux get helmreleases -A

# Check sources
flux get sources all -A
```

## Implementation Examples

### Example 1: Add a New Application

Let's add a new app (e.g., Grafana Loki for logging):

**1. Add Helm repository source:**

**infrastructure/sources/grafana.yaml:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: grafana
  namespace: flux-system
spec:
  interval: 1h
  url: https://grafana.github.io/helm-charts
```

**2. Create HelmRelease:**

**infrastructure/monitoring/loki.yaml:**
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: loki
  namespace: monitoring
spec:
  interval: 5m
  chart:
    spec:
      chart: loki
      version: 5.41.0
      sourceRef:
        kind: HelmRepository
        name: grafana
        namespace: flux-system
  values:
    loki:
      auth_enabled: false
      commonConfig:
        replication_factor: 1
      storage:
        type: filesystem
    singleBinary:
      replicas: 1
      persistence:
        enabled: true
        storageClass: nfs-client
        size: 10Gi
  install:
    remediation:
      retries: 3
```

**3. Commit and push:**
```bash
git add infrastructure/sources/grafana.yaml infrastructure/monitoring/loki.yaml
git commit -m "Add Grafana Loki for logging"
git push

# Flux automatically deploys within 1 minute
flux get helmreleases -n monitoring
```

### Example 2: Update Configuration

**Scenario:** Increase Prometheus retention from 2 days to 7 days

**1. Edit the HelmRelease:**
```bash
vim infrastructure/monitoring/prometheus-stack.yaml
```

Change:
```yaml
prometheus:
  prometheusSpec:
    retention: 7d  # Changed from 2d
```

**2. Commit and push:**
```bash
git add infrastructure/monitoring/prometheus-stack.yaml
git commit -m "Increase Prometheus retention to 7 days"
git push

# Flux detects change and upgrades Helm release
flux get helmreleases -n monitoring -w
```

### Example 3: Rollback a Change

**Scenario:** The Prometheus change caused issues, need to rollback

```bash
# Option 1: Git revert
git revert HEAD
git push
# Flux automatically applies previous config

# Option 2: Manual reconciliation to specific version
flux reconcile helmrelease prometheus-stack -n monitoring

# Option 3: Suspend auto-sync, manually fix
flux suspend helmrelease prometheus-stack -n monitoring
helm rollback prometheus-stack -n monitoring
flux resume helmrelease prometheus-stack -n monitoring
```

### Example 4: Using Kustomize Overlays

For environment-specific configs (dev/staging/prod):

```
infrastructure/
├── base/
│   └── app/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── kustomization.yaml
├── overlays/
│   ├── dev/
│   │   └── kustomization.yaml
│   └── prod/
│       └── kustomization.yaml
```

**infrastructure/base/app/kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
```

**infrastructure/overlays/prod/kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
  - ../../base/app
patchesStrategicMerge:
  - replica-patch.yaml
```

**Flux Kustomization:**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: app-prod
  namespace: flux-system
spec:
  path: ./infrastructure/overlays/prod
  sourceRef:
    kind: GitRepository
    name: flux-system
```

## Workflow Comparison

### Before Flux (Manual)

```bash
# 1. Update values file
vim k8s/helm/prometheus/values.yaml

# 2. Manual Helm upgrade
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f k8s/helm/prometheus/values.yaml

# 3. Hope you didn't make a mistake
# 4. No clear rollback path
# 5. Cluster state drifts from Git
```

**Problems:**
- Manual execution prone to errors
- No automatic sync
- Cluster drift from Git
- Difficult rollbacks
- No audit trail

### After Flux (GitOps)

```bash
# 1. Update HelmRelease
vim infrastructure/monitoring/prometheus-stack.yaml

# 2. Commit and push
git add infrastructure/monitoring/prometheus-stack.yaml
git commit -m "Update Prometheus config"
git push

# 3. Flux automatically:
#    - Detects change (within 1 min)
#    - Validates manifest
#    - Upgrades Helm release
#    - Reports status

# 4. Rollback if needed
git revert HEAD && git push
```

**Benefits:**
- Git is source of truth
- Automatic synchronization
- Full audit trail in Git
- Easy rollbacks via Git
- Declarative, reproducible

## Advanced Features

### 1. Image Automation

Automatically update container image tags when new versions are available.

**Install image automation controllers:**
```bash
flux install --components-extra=image-reflector-controller,image-automation-controller
```

**Example: Auto-update nginx image:**

**infrastructure/apps/nginx-deployment.yaml:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  template:
    spec:
      containers:
      - name: nginx
        image: nginx:1.21.0 # {"$imagepolicy": "flux-system:nginx"}
```

**infrastructure/apps/nginx-policy.yaml:**
```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: nginx
  namespace: flux-system
spec:
  image: nginx
  interval: 1m
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: nginx
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: nginx
  policy:
    semver:
      range: 1.21.x
---
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: nginx
  namespace: flux-system
spec:
  interval: 1m
  sourceRef:
    kind: GitRepository
    name: flux-system
  git:
    commit:
      author:
        email: fluxcdbot@users.noreply.github.com
        name: fluxcdbot
  update:
    path: ./infrastructure/apps
    strategy: Setters
```

**Result:** Flux automatically updates `nginx:1.21.0` → `nginx:1.21.6` when available.

### 2. Secrets Management with SOPS

Encrypt secrets in Git using Mozilla SOPS.

**Install SOPS:**
```bash
# Install SOPS
curl -LO https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops

# Install age (encryption tool)
sudo apt install age
age-keygen -o age.key
```

**Create encrypted secret:**
```bash
# Create secret
cat <<EOF > secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: default
stringData:
  username: admin
  password: supersecret
EOF

# Encrypt with SOPS
export SOPS_AGE_KEY_FILE=age.key
sops --encrypt --age $(age-keygen -y age.key) secret.yaml > secret-encrypted.yaml

# Commit encrypted version
git add secret-encrypted.yaml
git commit -m "Add encrypted secret"
git push
```

**Configure Flux to decrypt:**
```bash
# Create secret with age key
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.key

# Update Kustomization to decrypt
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age
  path: ./apps
  sourceRef:
    kind: GitRepository
    name: flux-system
```

### 3. Multi-Cluster Management

Manage multiple clusters from one Git repo:

```
clusters/
├── production/
│   ├── flux-system/
│   ├── infrastructure.yaml
│   └── apps.yaml
├── staging/
│   ├── flux-system/
│   ├── infrastructure.yaml
│   └── apps.yaml
└── homelab/
    ├── flux-system/
    ├── infrastructure.yaml
    └── apps.yaml
```

Bootstrap each cluster:
```bash
# Production cluster
kubectl config use-context production
flux bootstrap github --path=./clusters/production ...

# Staging cluster
kubectl config use-context staging
flux bootstrap github --path=./clusters/staging ...

# Homelab cluster
kubectl config use-context homelab
flux bootstrap github --path=./clusters/homelab ...
```

### 4. Health Checks and Dependencies

**Wait for dependencies:**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
spec:
  dependsOn:
    - name: infrastructure
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: nginx
      namespace: default
```

**Retry on failure:**
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: prometheus
spec:
  install:
    remediation:
      retries: 5
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true
  rollback:
    recreate: true
```

## Troubleshooting

### HelmRelease Not Installing

```bash
# Check HelmRelease status
flux get helmreleases -A

# Describe for detailed events
kubectl describe helmrelease prometheus-stack -n monitoring

# Check Helm controller logs
kubectl logs -n flux-system deploy/helm-controller -f

# Force reconciliation
flux reconcile helmrelease prometheus-stack -n monitoring --with-source
```

**Common issues:**
- Chart version doesn't exist
- Values syntax error
- Namespace doesn't exist (add `createNamespace: true`)
- HelmRepository not synced yet

### Kustomization Out of Sync

```bash
# Check Kustomization status
flux get kustomizations

# View detailed status
kubectl describe kustomization core-infrastructure -n flux-system

# Check kustomize controller logs
kubectl logs -n flux-system deploy/kustomize-controller -f

# Force reconciliation
flux reconcile kustomization core-infrastructure --with-source
```

**Common issues:**
- Invalid YAML syntax
- Resource already exists (not managed by Flux)
- Dependency not ready yet
- Path doesn't exist in repo

### Source Not Updating

```bash
# Check Git repository status
flux get sources git

# Force fetch
flux reconcile source git flux-system

# Check source controller logs
kubectl logs -n flux-system deploy/source-controller -f
```

**Common issues:**
- Git authentication failure (check deploy key)
- Branch doesn't exist
- Network connectivity issues
- Rate limiting (GitHub API)

### Suspend and Resume

```bash
# Suspend reconciliation (for maintenance)
flux suspend kustomization apps
flux suspend helmrelease prometheus-stack -n monitoring

# Resume
flux resume kustomization apps
flux resume helmrelease prometheus-stack -n monitoring
```

### Debug Mode

```bash
# Enable verbose logging
kubectl -n flux-system set env deployment/kustomize-controller LOG_LEVEL=debug
kubectl -n flux-system set env deployment/helm-controller LOG_LEVEL=debug
```

### Export Current Config

```bash
# Export existing Helm release to Flux format
flux create helmrelease prometheus-stack \
  --namespace=monitoring \
  --source=HelmRepository/prometheus-community \
  --chart=kube-prometheus-stack \
  --chart-version=55.0.0 \
  --export > prometheus-stack.yaml
```

## Best Practices

### 1. Repository Structure

✅ **DO:**
- Separate clusters, infrastructure, apps
- Use meaningful directory names
- Keep manifests small and focused
- Use Kustomize overlays for environments

❌ **DON'T:**
- Put everything in one directory
- Mix different resource types
- Use overly nested structures

### 2. Version Control

✅ **DO:**
- Pin Helm chart versions (`version: 1.2.3`)
- Use semantic versioning
- Tag releases in Git
- Use branches for testing changes

❌ **DON'T:**
- Use `latest` or `*` for chart versions
- Commit directly to main branch
- Skip Git commit messages

### 3. Reconciliation

✅ **DO:**
- Use `prune: true` to clean up deleted resources
- Set reasonable intervals (5-10min for apps)
- Use `wait: true` for critical dependencies
- Add health checks for important resources

❌ **DON'T:**
- Set interval too low (< 1min) - wastes resources
- Disable pruning unless necessary
- Ignore failed reconciliations

### 4. Dependencies

✅ **DO:**
```yaml
spec:
  dependsOn:
    - name: infrastructure
    - name: networking
```

❌ **DON'T:**
- Create circular dependencies
- Deploy apps before infrastructure

### 5. Secrets

✅ **DO:**
- Use SOPS or Sealed Secrets
- Encrypt secrets before committing
- Rotate encryption keys regularly
- Use external secret stores (Vault)

❌ **DON'T:**
- Commit plain-text secrets to Git
- Share encryption keys via Git
- Store credentials in values files

### 6. Notifications

✅ **DO:**
- Set up alerts for failures
- Monitor reconciliation status
- Use Slack/Discord webhooks
- Alert on drift detection

### 7. Disaster Recovery

✅ **DO:**
- Keep bootstrap command documented
- Backup encryption keys separately
- Test recovery procedures
- Document manual intervention steps

### 8. Resource Limits

```yaml
# Set limits for Flux controllers
apiVersion: v1
kind: ResourceQuota
metadata:
  name: flux-system
  namespace: flux-system
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
```

## Migration Checklist

- [ ] Install Flux CLI
- [ ] Bootstrap Flux to cluster
- [ ] Create directory structure
- [ ] Add Helm repository sources
- [ ] Migrate core infrastructure (namespaces, storage)
- [ ] Migrate networking (MetalLB, NGINX)
- [ ] Migrate security (cert-manager)
- [ ] Migrate monitoring (Prometheus)
- [ ] Test rollback procedure
- [ ] Set up notifications (Slack/Discord)
- [ ] Document any manual steps
- [ ] Remove old Helm releases (optional)
- [ ] Update README with Flux workflows

## Quick Reference

### Common Commands

```bash
# Check Flux health
flux check

# View all resources
flux get all

# View specific resource types
flux get sources all
flux get kustomizations
flux get helmreleases -A

# Force reconciliation
flux reconcile kustomization <name>
flux reconcile helmrelease <name> -n <namespace>
flux reconcile source git flux-system

# Suspend/Resume
flux suspend kustomization <name>
flux resume kustomization <name>

# Export existing resource
flux export kustomization <name>
flux export helmrelease <name> -n <namespace>

# Logs
flux logs --follow --all-namespaces
kubectl logs -n flux-system deploy/helm-controller -f
kubectl logs -n flux-system deploy/kustomize-controller -f

# Uninstall Flux
flux uninstall
```

### Resource Hierarchy

```
GitRepository
    ↓
Kustomization → Kustomization (child)
    ↓
HelmRelease
    ↓
Kubernetes Resources (Deployments, Services, etc.)
```

## Next Steps

1. **Install Flux** - Bootstrap to your cluster
2. **Migrate one component** - Start with namespaces
3. **Test reconciliation** - Make a change, watch it sync
4. **Expand gradually** - Add more infrastructure
5. **Set up notifications** - Get alerts on failures
6. **Learn image automation** - Auto-update container images
7. **Implement secrets encryption** - Use SOPS
8. **Document workflows** - Update team knowledge base

## Comparison with Argo CD

| Feature | **Flux CD** | **Argo CD** |
|---------|------------|-------------|
| UI | ❌ No (CLI only) | ✅ Full web UI |
| RAM Usage | ~150-200MB | ~500-800MB |
| Multi-Source | ❌ No | ✅ Yes |
| Image Automation | ✅ Built-in | ❌ Requires plugin |
| Secrets Encryption | ✅ SOPS native | ❌ Requires plugin |
| GitOps Enforcement | ✅ Pure GitOps | ⚠️ Optional |
| Learning Curve | Steeper | Gentler |
| Day-to-Day | CLI-based | UI-based |

**When to use Flux:**
- You prefer pure GitOps
- Resource constraints (RAM)
- Image automation needed
- Comfortable with CLI
- SOPS integration required

**When to use Argo:**
- You want a web UI
- Learning GitOps
- Multi-source needed (Helm chart + Git values)
- Manual control desired

## References

- [Flux Documentation](https://fluxcd.io/docs/)
- [Flux GitHub](https://github.com/fluxcd/flux2)
- [Flux Best Practices](https://fluxcd.io/flux/guides/)
- [SOPS Documentation](https://github.com/mozilla/sops)
- [GitOps Principles](https://opengitops.dev/)
- [Flux Slack Community](https://cloud-native.slack.com/messages/flux)

---

**Pro Tip:** Start with a single application (e.g., namespaces) before migrating everything. This lets you understand Flux workflows before managing critical infrastructure.
