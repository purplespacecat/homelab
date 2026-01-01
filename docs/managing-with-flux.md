# Managing Your Homelab with FluxCD

This guide explains how to manage your Kubernetes cluster now that FluxCD GitOps is active.

## Table of Contents
- [Core Principle: Git as Source of Truth](#core-principle-git-as-source-of-truth)
- [Daily Workflow](#daily-workflow)
- [Adding Resources](#adding-resources)
- [Modifying Resources](#modifying-resources)
- [Removing Resources](#removing-resources)
- [Common Operations](#common-operations)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Core Principle: Git as Source of Truth

**IMPORTANT:** With FluxCD active, you should **never** use `kubectl apply`, `helm install`, or `helm upgrade` directly on the cluster. Instead:

1. ✅ **Make changes in Git** (edit manifests, commit, push)
2. ✅ **Let Flux sync** (automatic within 1 minute)
3. ❌ **Don't use kubectl/helm** directly (defeats GitOps)

### Why?

```
Manual kubectl/helm → Cluster state differs from Git → Drift → Confusion
Git commit → Flux syncs → Cluster matches Git → Single source of truth
```

## Daily Workflow

### Basic Workflow

```bash
# 1. Pull latest changes
git pull origin main

# 2. Make your changes
vim infrastructure/monitoring/prometheus-stack.yaml

# 3. Test locally (optional - validate YAML)
kubectl apply --dry-run=server -f infrastructure/monitoring/prometheus-stack.yaml

# 4. Commit with descriptive message
git add infrastructure/monitoring/prometheus-stack.yaml
git commit -m "Increase Prometheus retention to 7 days"

# 5. Push to GitHub
git push origin main

# 6. Watch Flux sync (automatic in ~1 min)
flux get kustomizations -w

# Or force immediate sync
flux reconcile kustomization monitoring --with-source
```

### Verification

```bash
# Check if change was applied
kubectl get helmrelease prometheus-stack -n monitoring -o yaml | grep retention

# Check Flux reconciliation status
flux get helmreleases -A

# View events
kubectl describe helmrelease prometheus-stack -n monitoring
```

---

## Adding Resources

### 1. Adding a New Helm Chart Application

**Example:** Add Grafana Loki for log aggregation

#### Step 1: Add Helm Repository Source

Create `infrastructure/sources/grafana.yaml`:

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

#### Step 2: Create HelmRelease

Create `infrastructure/monitoring/loki.yaml`:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
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
        storageClassName: nfs-client
        size: 10Gi
  install:
    createNamespace: false  # monitoring namespace already exists
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
```

#### Step 3: Commit and Push

```bash
git add infrastructure/sources/grafana.yaml infrastructure/monitoring/loki.yaml
git commit -m "Add Grafana Loki for log aggregation"
git push origin main

# Watch deployment
flux get helmreleases -n monitoring -w
```

#### Step 4: Verify

```bash
# Check HelmRelease
flux get helmrelease loki -n monitoring

# Check pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# Check logs
kubectl logs -n monitoring -l app.kubernetes.io/name=loki -f
```

---

### 2. Adding a Simple Kubernetes Manifest

**Example:** Add a ConfigMap for application configuration

#### Step 1: Create Manifest

Create `k8s/applications/myapp-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-config
  namespace: default
data:
  app.conf: |
    server {
      listen 8080;
      location / {
        root /usr/share/nginx/html;
      }
    }
```

#### Step 2: Create Kustomization (if needed)

If this is a new directory, create a Kustomization to track it.

Create `clusters/homelab/applications.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: applications
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./k8s/applications
  prune: true
  wait: true
```

#### Step 3: Commit and Push

```bash
git add k8s/applications/myapp-config.yaml clusters/homelab/applications.yaml
git commit -m "Add myapp configuration"
git push origin main

# Verify
flux get kustomizations
kubectl get configmap myapp-config -n default
```

---

### 3. Adding a Complete Application Stack

**Example:** Deploy a full application with Deployment, Service, Ingress

#### Step 1: Create Application Directory

```bash
mkdir -p k8s/applications/myapp
```

#### Step 2: Create Manifests

**k8s/applications/myapp/deployment.yaml:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
```

**k8s/applications/myapp/service.yaml:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: default
spec:
  type: ClusterIP
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 80
```

**k8s/applications/myapp/ingress.yaml:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: homelab-issuer
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.192.168.100.98.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
  tls:
  - hosts:
    - myapp.192.168.100.98.nip.io
    secretName: myapp-tls
```

#### Step 3: Commit and Push

```bash
git add k8s/applications/myapp/
git commit -m "Deploy myapp application"
git push origin main

# Watch deployment
kubectl get pods -n default -l app=myapp -w
```

---

## Modifying Resources

### 1. Update Helm Chart Values

**Example:** Increase Prometheus retention

```bash
# Edit the HelmRelease
vim infrastructure/monitoring/prometheus-stack.yaml
```

Change:
```yaml
values:
  prometheus:
    prometheusSpec:
      retention: 7d  # Changed from 2d
```

```bash
# Commit and push
git commit -am "Increase Prometheus retention to 7 days"
git push origin main

# Force immediate sync (optional)
flux reconcile helmrelease prometheus-stack -n monitoring

# Verify
kubectl get statefulset prometheus-prometheus-stack-kube-prom-prometheus -n monitoring -o yaml | grep retention
```

---

### 2. Upgrade Helm Chart Version

**Example:** Upgrade cert-manager to newer version

```bash
# Edit the HelmRelease
vim infrastructure/security/cert-manager.yaml
```

Change:
```yaml
chart:
  spec:
    version: v1.14.0  # Upgraded from v1.13.3
```

```bash
# Commit and push
git commit -am "Upgrade cert-manager to v1.14.0"
git push origin main

# Watch upgrade
flux get helmrelease cert-manager -n cert-manager -w

# Check version
kubectl get deployment cert-manager -n cert-manager -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

### 3. Scale Deployments

**Example:** Increase replicas for high availability

```bash
# Edit deployment
vim k8s/applications/myapp/deployment.yaml
```

Change:
```yaml
spec:
  replicas: 5  # Increased from 2
```

```bash
git commit -am "Scale myapp to 5 replicas for HA"
git push origin main

# Verify
kubectl get deployment myapp -n default
```

---

### 4. Update Container Images

**Example:** Deploy new application version

**Option A: Manual Update (Simple)**

```bash
vim k8s/applications/myapp/deployment.yaml
```

Change:
```yaml
containers:
- name: myapp
  image: myapp:v2.0.0  # Updated from v1.0.0
```

```bash
git commit -am "Deploy myapp v2.0.0"
git push origin main
```

**Option B: Image Automation (Advanced)**

FluxCD can automatically update images when new versions are available.

Create `infrastructure/image-automation/myapp-policy.yaml`:

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: myapp
  namespace: flux-system
spec:
  image: docker.io/myorg/myapp
  interval: 1m
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: myapp
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: myapp
  policy:
    semver:
      range: 1.x.x  # Auto-update to latest 1.x version
---
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: myapp
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
      messageTemplate: |
        Update myapp to {{range .Updated.Images}}{{println .}}{{end}}
  update:
    path: ./k8s/applications/myapp
    strategy: Setters
```

Update deployment with marker:

```yaml
containers:
- name: myapp
  image: myapp:1.0.0  # {"$imagepolicy": "flux-system:myapp"}
```

Now Flux automatically updates the image tag when new versions are released!

---

## Removing Resources

### 1. Remove a HelmRelease

**Example:** Remove Loki

```bash
# Delete the HelmRelease file
git rm infrastructure/monitoring/loki.yaml

# Commit and push
git commit -m "Remove Loki - no longer needed"
git push origin main

# Flux automatically uninstalls the Helm release and deletes resources
# due to `prune: true` in the Kustomization

# Verify removal
flux get helmreleases -n monitoring
kubectl get pods -n monitoring | grep loki
```

**Note:** The HelmRelease is deleted, and Flux uninstalls the chart. All resources are removed.

---

### 2. Remove Kubernetes Manifests

**Example:** Remove myapp

```bash
# Delete the directory or files
git rm -r k8s/applications/myapp/

# Commit and push
git commit -m "Remove myapp application"
git push origin main

# Flux automatically deletes the resources
# Verify
kubectl get all -n default -l app=myapp
```

---

### 3. Temporarily Suspend Reconciliation

**Example:** Pause Flux for manual troubleshooting

```bash
# Suspend a specific HelmRelease
flux suspend helmrelease prometheus-stack -n monitoring

# Now you can make manual changes for debugging
kubectl scale statefulset prometheus-prometheus-stack-kube-prom-prometheus -n monitoring --replicas=0

# Resume when done
flux resume helmrelease prometheus-stack -n monitoring

# Flux will reconcile back to Git state
```

**Suspend entire Kustomization:**

```bash
# Suspend monitoring stack
flux suspend kustomization monitoring

# Make manual changes...
# ...

# Resume
flux resume kustomization monitoring
```

---

## Common Operations

### 1. Add a New Namespace

Create `k8s/core/namespaces/development-namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: development
  labels:
    environment: dev
```

```bash
git add k8s/core/namespaces/development-namespace.yaml
git commit -m "Add development namespace"
git push origin main
```

---

### 2. Add Network Policies

Create `k8s/core/security/development-network-policy.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress
  namespace: development
spec:
  podSelector:
    matchLabels:
      app: webapp
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
```

```bash
git add k8s/core/security/development-network-policy.yaml
git commit -m "Add network policy for development namespace"
git push origin main
```

---

### 3. Add Persistent Storage

Create `k8s/applications/myapp/pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: myapp-data
  namespace: default
spec:
  storageClassName: nfs-client
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
```

```bash
git add k8s/applications/myapp/pvc.yaml
git commit -m "Add persistent storage for myapp"
git push origin main
```

---

### 4. Update Ingress (Add New Route)

```bash
vim k8s/applications/myapp/ingress.yaml
```

Add new rule:
```yaml
rules:
- host: myapp.192.168.100.98.nip.io
  # ... existing
- host: myapp-api.192.168.100.98.nip.io  # NEW
  http:
    paths:
    - path: /api
      pathType: Prefix
      backend:
        service:
          name: myapp-api
          port:
            number: 8080
```

```bash
git commit -am "Add API route to myapp ingress"
git push origin main
```

---

### 5. Add Secrets (Encrypted with SOPS)

**Note:** Never commit plain-text secrets to Git!

**Setup SOPS (first time):**

```bash
# Install SOPS
curl -LO https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops

# Install age (encryption tool)
sudo apt install age

# Generate encryption key
age-keygen -o ~/.config/sops/age/keys.txt

# Get public key
age-keygen -y ~/.config/sops/age/keys.txt
# Output: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

**Create encrypted secret:**

```bash
# Create secret file
cat > k8s/applications/myapp/secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: myapp-credentials
  namespace: default
stringData:
  username: admin
  password: supersecret123
EOF

# Encrypt with SOPS
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops --encrypt \
  --age age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p \
  k8s/applications/myapp/secret.yaml > k8s/applications/myapp/secret-encrypted.yaml

# Remove plain-text version
rm k8s/applications/myapp/secret.yaml

# Commit encrypted version (safe!)
git add k8s/applications/myapp/secret-encrypted.yaml
git commit -m "Add encrypted credentials for myapp"
git push origin main
```

**Configure Flux to decrypt:**

```bash
# Create secret with age key in cluster
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=~/.config/sops/age/keys.txt

# Update Kustomization to use decryption
```

Edit `clusters/homelab/applications.yaml`:
```yaml
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age
  # ... rest of spec
```

Now Flux automatically decrypts secrets before applying them!

---

## Troubleshooting

### 1. Resource Not Syncing

**Problem:** Changes pushed to Git but not appearing in cluster

```bash
# Check GitRepository sync
flux get sources git

# Check if Kustomization is reconciling
flux get kustomizations

# Check for errors
kubectl describe kustomization <name> -n flux-system

# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization <name>
```

---

### 2. HelmRelease Failing

**Problem:** Helm chart installation/upgrade failing

```bash
# Check HelmRelease status
flux get helmrelease <name> -n <namespace>

# View detailed error
kubectl describe helmrelease <name> -n <namespace>

# Check Helm controller logs
kubectl logs -n flux-system deploy/helm-controller -f

# Suspend and debug manually
flux suspend helmrelease <name> -n <namespace>
helm list -n <namespace>
helm get values <release> -n <namespace>

# Resume
flux resume helmrelease <name> -n <namespace>
```

---

### 3. Dependency Issues

**Problem:** Kustomization stuck waiting for dependencies

```bash
# Check dependency status
flux get kustomizations

# Look for dependency in manifest
kubectl get kustomization <name> -n flux-system -o yaml | grep -A 5 "dependsOn"

# Check if dependency is ready
flux get kustomization <dependency-name>

# Fix: Ensure dependency is ready, or remove dependency if not needed
```

---

### 4. Prune Not Working

**Problem:** Deleted files not removed from cluster

```bash
# Check if prune is enabled
kubectl get kustomization <name> -n flux-system -o yaml | grep prune

# Should show: prune: true

# Force reconciliation with prune
flux reconcile kustomization <name> --with-source
```

---

### 5. Image Not Updating

**Problem:** New image pushed but deployment not updating

```bash
# Check if ImagePolicy exists
flux get images policy -A

# Check ImageRepository
flux get images repository -A

# Check if image marker is correct in manifest
cat k8s/applications/myapp/deployment.yaml | grep imagepolicy

# Force reconciliation
flux reconcile image update <name>
```

---

## Best Practices

### 1. Git Workflow

✅ **DO:**
- Use feature branches for major changes
- Write descriptive commit messages
- Test changes in staging first (if available)
- Keep commits small and focused
- Use Pull Requests for review

❌ **DON'T:**
- Commit directly to main for critical changes
- Use generic commit messages ("update", "fix")
- Make multiple unrelated changes in one commit

**Example branch workflow:**

```bash
# Create feature branch
git checkout -b add-redis

# Make changes
vim infrastructure/databases/redis.yaml

# Commit
git add infrastructure/databases/redis.yaml
git commit -m "Add Redis for session storage"

# Push feature branch
git push origin add-redis

# Create PR on GitHub
# After approval, merge to main
# Flux syncs automatically from main
```

---

### 2. Resource Organization

**Recommended structure:**

```
homelab/
├── clusters/
│   └── homelab/              # Cluster-specific Kustomizations
├── infrastructure/
│   ├── sources/              # Helm repositories
│   ├── core/                 # Namespaces, storage, security
│   ├── networking/           # Ingress, MetalLB
│   ├── security/             # cert-manager, policies
│   ├── monitoring/           # Prometheus, Grafana
│   └── databases/            # PostgreSQL, Redis, etc.
└── k8s/
    ├── core/                 # Core manifests (namespaces, etc.)
    ├── applications/         # Your applications
    │   ├── app1/
    │   │   ├── deployment.yaml
    │   │   ├── service.yaml
    │   │   └── ingress.yaml
    │   └── app2/
    └── cert-manager/         # cert-manager configs
```

---

### 3. Version Pinning

✅ **DO:** Pin Helm chart versions

```yaml
chart:
  spec:
    version: 1.2.3  # Specific version
```

❌ **DON'T:** Use wildcards or latest

```yaml
chart:
  spec:
    version: "*"     # Bad - unpredictable
    version: latest  # Bad - no version control
```

---

### 4. Resource Limits

✅ **DO:** Always set resource limits

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

---

### 5. Health Checks

✅ **DO:** Configure liveness and readiness probes

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

---

### 6. Secrets Management

✅ **DO:**
- Use SOPS for encrypting secrets
- Store encryption keys outside Git
- Rotate secrets regularly

❌ **DON'T:**
- Commit plain-text secrets
- Use base64 encoding as "encryption" (it's not!)
- Store passwords in ConfigMaps

---

### 7. Monitoring Changes

**Set up notifications:**

Create `clusters/homelab/notifications.yaml`:

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta2
kind: Alert
metadata:
  name: homelab-alerts
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

---

## Quick Reference

### Common Commands

```bash
# Health check
flux check

# View all resources
flux get all

# View specific resource types
flux get sources git
flux get sources helm
flux get kustomizations
flux get helmreleases -A

# Force sync
flux reconcile source git flux-system
flux reconcile kustomization <name>
flux reconcile helmrelease <name> -n <namespace>

# Suspend/Resume
flux suspend kustomization <name>
flux resume kustomization <name>

# Logs
flux logs --follow
flux logs --kind=HelmRelease --name=<name> -n <namespace>

# Export resources
flux export source git flux-system
flux export kustomization <name>
flux export helmrelease <name> -n <namespace>

# Uninstall Flux (nuclear option)
flux uninstall --silent
```

---

## Emergency: Reverting to Manual Mode

If you need to temporarily disable GitOps and manage manually:

```bash
# 1. Suspend all Kustomizations
flux suspend kustomization --all

# 2. Now you can use kubectl/helm directly
kubectl apply -f manifest.yaml
helm upgrade ...

# 3. When ready, resume GitOps
flux resume kustomization --all

# 4. Reconcile to Git state (overwrites manual changes)
flux reconcile kustomization flux-system --with-source
```

**WARNING:** Manual changes will be overwritten when you resume GitOps!

---

## Summary

**The GitOps Workflow:**

1. 📝 **Edit** manifests in Git
2. 💾 **Commit** with descriptive message
3. 🚀 **Push** to GitHub
4. ⏱️ **Wait** ~1 minute (or force sync)
5. ✅ **Verify** resources deployed

**Golden Rules:**

- ✅ Git is the source of truth
- ✅ All changes go through Git
- ❌ Never use kubectl apply directly
- ❌ Never use helm install/upgrade directly
- ✅ Encrypt secrets with SOPS
- ✅ Pin chart versions
- ✅ Test in branches, deploy from main

**Need Help?**

```bash
# Check Flux documentation
flux --help
flux <command> --help

# View FluxCD docs
# https://fluxcd.io/docs/

# View your setup guide
cat docs/fluxcd-guide.md
```

---

**Congratulations!** You now know how to manage your homelab cluster with GitOps. Remember: **Git is truth, Flux is the enforcer.** 🎯
