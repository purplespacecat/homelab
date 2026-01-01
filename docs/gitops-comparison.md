# GitOps Comparison: ArgoCD vs FluxCD

Quick reference guide comparing ArgoCD and FluxCD for homelab GitOps implementation.

## TL;DR - Which Should I Choose?

### Choose **FluxCD** if:
- ✅ Your company/team uses FluxCD (learn what you'll use at work)
- ✅ You want pure GitOps enforcement (no manual overrides)
- ✅ Resource constraints matter (~150MB RAM vs ~500MB)
- ✅ You prefer CLI workflows
- ✅ You need built-in image automation
- ✅ SOPS secret encryption is important

### Choose **ArgoCD** if:
- ✅ You want a visual web UI for learning
- ✅ You need flexibility (manual + automatic sync)
- ✅ You prefer point-and-click operations
- ✅ Multi-source support is critical (cleaner for Helm + values)
- ✅ You're new to GitOps and want easier debugging

---

## Side-by-Side Comparison

### Architecture & Philosophy

| Aspect | **FluxCD** | **ArgoCD** |
|--------|-----------|-----------|
| **Philosophy** | Pure GitOps - Git is THE source of truth | GitOps + flexibility - manual control available |
| **Components** | 5 controllers (modular) | 4+ components (monolithic) |
| **RAM Usage** | ~150-200MB | ~500-800MB |
| **Git Model** | Pull-based (controllers pull from Git) | Pull-based (controllers watch Git) |
| **Reconciliation** | Continuous (default 1min) | Continuous (default 3min) or manual |

### User Experience

| Feature | **FluxCD** | **ArgoCD** |
|---------|-----------|-----------|
| **Web UI** | ❌ No (CLI only) <br> *3rd party: Weave GitOps ($)* | ✅ **Full web UI** <br> *Visualize apps, diffs, sync status* |
| **CLI** | ✅ Excellent `flux` CLI | ✅ Good `argocd` CLI |
| **Debugging** | CLI + kubectl logs | **Web UI with visual diffs** + CLI |
| **Day-to-Day** | `flux get`, `flux reconcile` | **Browse web UI** or CLI |
| **Learning Curve** | **Steeper** (must learn CRDs) | **Gentler** (UI guides you) |

### GitOps Features

| Feature | **FluxCD** | **ArgoCD** |
|---------|-----------|-----------|
| **Auto-Sync** | ✅ Always on (pure GitOps) | ⚠️ Optional (can disable) |
| **Manual Sync** | ❌ Must suspend first | ✅ **Built-in** (great for testing) |
| **Pruning** | ✅ `prune: true` | ✅ `prune: true` in syncPolicy |
| **Multi-Source** | ❌ **No** (one source per resource) | ✅ **Yes** (Helm chart + Git values) |
| **Sync Waves** | Via Kustomize dependencies | ✅ **Native sync waves** |
| **Health Checks** | ✅ Custom health checks | ✅ Built-in health assessments |

### Helm Chart Management

| Aspect | **FluxCD** | **ArgoCD** |
|--------|-----------|-----------|
| **Helm Support** | Via `HelmRelease` CRD | **Native** Application manifest |
| **Values Files** | ConfigMap or inline | **Reference from Git** (multi-source) |
| **Your Prometheus Setup** | Requires learning HelmRelease CRD | **Cleaner** - chart + Git values |
| **Complexity** | Medium (new CRD concepts) | **Low** (familiar patterns) |

**Example: Prometheus with custom values from Git**

**FluxCD:**
```yaml
# Requires HelmRelease CRD
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: prometheus
spec:
  chart:
    spec:
      chart: kube-prometheus-stack
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
  # Must inline or use ConfigMap/Secret for values
  valuesFrom:
    - kind: ConfigMap
      name: prometheus-values
```

**ArgoCD:**
```yaml
# Simpler multi-source approach
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
spec:
  sources:
    - repoURL: https://prometheus-community.github.io/helm-charts
      chart: kube-prometheus-stack
      helm:
        valueFiles: [$values/k8s/helm/prometheus/values.yaml]
    - repoURL: https://github.com/you/homelab
      ref: values
```

### Advanced Features

| Feature | **FluxCD** | **ArgoCD** |
|---------|-----------|-----------|
| **Image Automation** | ✅ **Built-in** (image-automation-controller) | ❌ Requires plugin |
| **Secret Encryption** | ✅ **SOPS native** | ❌ Requires plugin (argocd-vault-plugin) |
| **Notifications** | ✅ Built-in (notification-controller) | ✅ Built-in |
| **Multi-Tenancy** | ✅ Namespace isolation | ✅ Projects + RBAC |
| **SSO/Auth** | Via external (oauth2-proxy) | ✅ **Built-in** (OIDC, SAML, GitHub) |

### Operational

| Aspect | **FluxCD** | **ArgoCD** |
|--------|-----------|-----------|
| **Installation** | `flux bootstrap` (creates structure in Git) | `kubectl apply` + manual setup |
| **Disaster Recovery** | ✅ **Simple**: `flux bootstrap` rebuilds | Re-install + restore apps |
| **Upgrade** | `flux install` (can be GitOps managed) | Helm upgrade or kubectl apply |
| **Monitoring** | Prometheus metrics + CLI | Prometheus + **Web UI** + CLI |
| **Troubleshooting** | CLI + logs | **Web UI** + CLI + logs |

### Community & Ecosystem

| Aspect | **FluxCD** | **ArgoCD** |
|--------|-----------|-----------|
| **Adoption** | Growing | **Very Popular** |
| **CNCF Status** | Graduated | Graduated |
| **GitHub Stars** | ~6k | ~18k |
| **Documentation** | Excellent | Excellent |
| **Community Size** | Smaller but active | **Larger, very active** |

---

## Workflow Comparison

### Deploying Prometheus Stack

#### **FluxCD Workflow:**

**1. Create HelmRepository source:**
```yaml
# infrastructure/sources/prometheus-community.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
spec:
  url: https://prometheus-community.github.io/helm-charts
```

**2. Create HelmRelease:**
```yaml
# infrastructure/monitoring/prometheus.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: prometheus-stack
  namespace: monitoring
spec:
  chart:
    spec:
      chart: kube-prometheus-stack
      version: 55.0.0
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
  values:
    prometheus:
      retention: 2d
```

**3. Commit & push:**
```bash
git add infrastructure/
git commit -m "Add Prometheus"
git push
# Flux syncs automatically within 1 min
```

**4. Verify:**
```bash
flux get helmreleases -A
kubectl get pods -n monitoring
```

#### **ArgoCD Workflow:**

**1. Create Application manifest:**
```yaml
# argocd/monitoring/prometheus.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-stack
  namespace: argocd
spec:
  sources:
    - repoURL: https://prometheus-community.github.io/helm-charts
      chart: kube-prometheus-stack
      targetRevision: 55.0.0
      helm:
        valueFiles: [$values/k8s/helm/prometheus/values.yaml]
    - repoURL: https://github.com/you/homelab
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
```

**2. Commit & push:**
```bash
git add argocd/monitoring/prometheus.yaml
git commit -m "Add Prometheus"
git push
# Argo syncs automatically or manually via UI
```

**3. Verify:**
```bash
# Option 1: Web UI
# Navigate to https://argocd.your-domain.com

# Option 2: CLI
argocd app get prometheus-stack
kubectl get pods -n monitoring
```

---

## Making Changes

### **Scenario:** Update Prometheus retention from 2 days to 7 days

#### **FluxCD:**
```bash
# 1. Edit HelmRelease
vim infrastructure/monitoring/prometheus.yaml
# Change: retention: 7d

# 2. Commit & push
git commit -am "Increase Prometheus retention"
git push

# 3. Flux auto-syncs (wait ~1 min)
# Or force sync:
flux reconcile helmrelease prometheus-stack -n monitoring --with-source

# 4. Verify
flux get helmreleases -n monitoring
```

#### **ArgoCD:**
```bash
# 1. Edit values file (multi-source setup)
vim k8s/helm/prometheus/values.yaml
# Change retention: 7d

# 2. Commit & push
git commit -am "Increase Prometheus retention"
git push

# 3. Argo auto-syncs (wait ~3 min)
# Or sync via UI: Click "Sync" button
# Or CLI:
argocd app sync prometheus-stack

# 4. Verify in Web UI or:
argocd app get prometheus-stack
```

---

## Rollbacks

### **FluxCD:**
```bash
# Option 1: Git revert (recommended)
git revert HEAD
git push
# Flux automatically applies previous config

# Option 2: Suspend + manual Helm rollback
flux suspend helmrelease prometheus-stack -n monitoring
helm rollback prometheus-stack -n monitoring
flux resume helmrelease prometheus-stack -n monitoring
```

### **ArgoCD:**
```bash
# Option 1: Git revert
git revert HEAD
git push
# Argo syncs to reverted state

# Option 2: UI rollback
# Web UI → Select app → History → Rollback to previous revision

# Option 3: CLI rollback
argocd app rollback prometheus-stack <revision-id>
```

---

## Troubleshooting

### **FluxCD:**
```bash
# Check overall status
flux check
flux get all

# Check specific resource
flux get helmreleases -A
kubectl describe helmrelease prometheus-stack -n monitoring

# View logs
flux logs --all-namespaces --follow
kubectl logs -n flux-system deploy/helm-controller -f

# Force reconciliation
flux reconcile helmrelease prometheus-stack -n monitoring --with-source
flux reconcile kustomization infrastructure --with-source
```

### **ArgoCD:**
```bash
# Web UI (easiest)
# Navigate to app → View events, logs, diffs visually

# CLI
argocd app get prometheus-stack
argocd app diff prometheus-stack
argocd app sync prometheus-stack

# Logs
kubectl logs -n argocd deploy/argocd-application-controller
```

---

## Directory Structure Comparison

### **FluxCD Structure:**
```
homelab/
├── clusters/
│   └── homelab/
│       ├── flux-system/         # Auto-generated by Flux
│       ├── sources.yaml         # Kustomization for Helm repos
│       ├── core.yaml            # Kustomization for core
│       └── monitoring.yaml      # Kustomization for monitoring
├── infrastructure/
│   ├── sources/
│   │   └── prometheus-community.yaml   # HelmRepository
│   ├── core/
│   │   └── namespaces.yaml             # Kustomization
│   └── monitoring/
│       └── prometheus-stack.yaml       # HelmRelease
└── k8s/                         # Existing manifests (kept as-is)
```

### **ArgoCD Structure:**
```
homelab/
├── argocd/
│   ├── bootstrap/
│   │   └── root-app.yaml        # App of Apps
│   ├── projects/
│   │   └── homelab-project.yaml # AppProject
│   ├── core/
│   │   └── namespaces.yaml      # Application
│   └── monitoring/
│       └── prometheus-stack.yaml # Application
└── k8s/                         # Existing manifests (kept as-is)
```

---

## Resource Requirements

### **FluxCD:**
```
Namespace: flux-system
Pods:
  - source-controller       ~30MB RAM
  - kustomize-controller    ~40MB RAM
  - helm-controller         ~50MB RAM
  - notification-controller ~30MB RAM
Total: ~150MB RAM, ~100m CPU
```

### **ArgoCD:**
```
Namespace: argocd
Pods:
  - argocd-server              ~150MB RAM
  - argocd-repo-server         ~200MB RAM
  - argocd-application-controller ~150MB RAM
  - argocd-redis               ~50MB RAM
Total: ~550MB RAM, ~200m CPU
```

**Verdict:** FluxCD uses **~70% less RAM** than ArgoCD

---

## Learning Resources

### **FluxCD:**
- **Official Docs:** https://fluxcd.io/docs/
- **GitHub:** https://github.com/fluxcd/flux2
- **Slack:** #flux channel in CNCF Slack
- **Tutorials:** https://fluxcd.io/flux/guides/

### **ArgoCD:**
- **Official Docs:** https://argo-cd.readthedocs.io/
- **GitHub:** https://github.com/argoproj/argo-cd
- **Slack:** #argo-cd in CNCF Slack
- **Tutorials:** https://argo-cd.readthedocs.io/en/stable/getting_started/

---

## Migration Effort

### **To FluxCD:**
**Time:** ~4-6 hours
**Complexity:** Medium-High
- Learn new CRDs (HelmRelease, Kustomization, HelmRepository)
- Restructure values (ConfigMaps or inline)
- More CLI-based workflow

### **To ArgoCD:**
**Time:** ~3-4 hours
**Complexity:** Medium
- Learn Application CRD
- Simpler for Helm charts (multi-source)
- UI makes debugging easier

---

## Recommendation for Your Homelab

### **Go with FluxCD because:**
1. ✅ **Company uses it** - Learn what you'll use professionally
2. ✅ **Pure GitOps** - Better practice/discipline
3. ✅ **Lower resource usage** - Fits homelab constraints
4. ✅ **Image automation** - Auto-update containers
5. ✅ **Future-proof skills** - Industry trend toward Flux

### **Consider ArgoCD if:**
- Learning GitOps concepts (UI helps visualize)
- Want quick wins with less learning curve
- Prefer visual debugging
- Need manual sync for testing

---

## Quick Start Commands

### **FluxCD:**
```bash
# Install CLI
curl -s https://fluxcd.io/install.sh | sudo bash

# Bootstrap
flux bootstrap github \
  --owner=<user> \
  --repository=homelab \
  --branch=main \
  --path=./clusters/homelab

# Common commands
flux check
flux get all
flux reconcile kustomization <name>
```

### **ArgoCD:**
```bash
# Install
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d

# Common commands
argocd app list
argocd app get <name>
argocd app sync <name>
```

---

## Final Verdict

| Criteria | **FluxCD** | **ArgoCD** | **Winner** |
|----------|-----------|-----------|-----------|
| Learning Curve | Steeper | Gentler | **ArgoCD** |
| Resource Usage | 150MB | 550MB | **FluxCD** |
| UI | No | Yes | **ArgoCD** |
| Pure GitOps | Yes | Optional | **FluxCD** |
| Helm + Git Values | Complex | Simple (multi-source) | **ArgoCD** |
| Image Automation | Built-in | Plugin needed | **FluxCD** |
| Professional Use | **Your company uses it** | More popular overall | **FluxCD** (for you) |
| Day-to-Day Ops | CLI | UI + CLI | **ArgoCD** |

**For your situation:** **FluxCD** is the right choice since your company uses it. You'll gain practical skills and the guide in `docs/fluxcd-guide.md` will help you master it.

---

See also:
- **FluxCD Guide:** [docs/fluxcd-guide.md](fluxcd-guide.md)
- **ArgoCD Guide:** [docs/gitops-guide.md](gitops-guide.md)
