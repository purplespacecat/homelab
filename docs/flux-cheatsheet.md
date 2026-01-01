# FluxCD Cheat Sheet

Quick reference for managing your homelab cluster with FluxCD.

## 🚨 Golden Rule

**NEVER use `kubectl apply` or `helm install/upgrade` directly!**
**ALWAYS make changes in Git and let Flux sync.**

---

## 📋 Basic Workflow

```bash
# 1. Edit manifests
vim infrastructure/monitoring/prometheus-stack.yaml

# 2. Commit
git commit -am "Increase Prometheus retention"

# 3. Push
git push

# 4. Flux syncs automatically in ~1 min
# Or force sync:
flux reconcile kustomization monitoring --with-source
```

---

## 🔍 Checking Status

```bash
# Overall health
flux check

# All resources
flux get all

# Specific resources
flux get sources git              # Git repositories
flux get sources helm -A          # Helm repositories
flux get kustomizations           # Kustomizations
flux get helmreleases -A          # Helm releases

# Watch mode
flux get kustomizations -w
```

---

## ➕ Adding Resources

### Add Helm Chart

1. **Add Helm repository source:**
   ```bash
   cat > infrastructure/sources/grafana.yaml <<EOF
   apiVersion: source.toolkit.fluxcd.io/v1beta2
   kind: HelmRepository
   metadata:
     name: grafana
     namespace: flux-system
   spec:
     interval: 1h
     url: https://grafana.github.io/helm-charts
   EOF
   ```

2. **Create HelmRelease:**
   ```bash
   cat > infrastructure/monitoring/loki.yaml <<EOF
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
       # Your custom values here
   EOF
   ```

3. **Commit and push:**
   ```bash
   git add infrastructure/
   git commit -m "Add Loki"
   git push
   ```

### Add Kubernetes Manifest

```bash
# Create manifest
cat > k8s/applications/myapp.yaml <<EOF
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
EOF

# Commit and push
git add k8s/applications/myapp.yaml
git commit -m "Add myapp"
git push
```

---

## ✏️ Modifying Resources

### Update Helm Values

```bash
# Edit HelmRelease
vim infrastructure/monitoring/prometheus-stack.yaml

# Change values:
# values:
#   prometheus:
#     retention: 7d  # Changed from 2d

# Commit and push
git commit -am "Increase Prometheus retention"
git push

# Force sync (optional)
flux reconcile helmrelease prometheus-stack -n monitoring
```

### Upgrade Chart Version

```bash
# Edit HelmRelease
vim infrastructure/security/cert-manager.yaml

# Update version:
# version: v1.14.0  # Upgraded from v1.13.3

# Commit and push
git commit -am "Upgrade cert-manager to v1.14.0"
git push
```

### Scale Deployment

```bash
# Edit manifest
vim k8s/applications/myapp.yaml

# Change replicas:
# spec:
#   replicas: 5  # Increased from 2

# Commit and push
git commit -am "Scale myapp to 5 replicas"
git push
```

---

## ➖ Removing Resources

```bash
# Delete the file
git rm infrastructure/monitoring/loki.yaml

# Commit and push
git commit -m "Remove Loki"
git push

# Flux automatically removes resources due to prune: true
```

---

## ⏸️ Suspend/Resume

```bash
# Suspend (pause sync)
flux suspend kustomization monitoring
flux suspend helmrelease prometheus-stack -n monitoring

# Resume (restart sync)
flux resume kustomization monitoring
flux resume helmrelease prometheus-stack -n monitoring
```

---

## 🔄 Force Reconciliation

```bash
# Reconcile Git source
flux reconcile source git flux-system

# Reconcile Kustomization
flux reconcile kustomization monitoring --with-source

# Reconcile HelmRelease
flux reconcile helmrelease prometheus-stack -n monitoring --with-source
```

---

## 📊 Logs & Debugging

```bash
# View Flux logs
flux logs --follow
flux logs --all-namespaces

# View specific controller logs
kubectl logs -n flux-system deploy/helm-controller -f
kubectl logs -n flux-system deploy/kustomize-controller -f
kubectl logs -n flux-system deploy/source-controller -f

# Describe resources
kubectl describe kustomization <name> -n flux-system
kubectl describe helmrelease <name> -n <namespace>
kubectl describe gitrepository flux-system -n flux-system
```

---

## 🔐 Secrets (SOPS)

### Setup (one-time)

```bash
# Install tools
curl -LO https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
sudo apt install age

# Generate key
age-keygen -o ~/.config/sops/age/keys.txt

# Get public key
age-keygen -y ~/.config/sops/age/keys.txt
```

### Encrypt Secret

```bash
# Create secret
cat > secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: myapp-creds
stringData:
  username: admin
  password: secret123
EOF

# Encrypt
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops --encrypt --age <PUBLIC_KEY> secret.yaml > secret-encrypted.yaml

# Commit encrypted version
git add secret-encrypted.yaml
git commit -m "Add encrypted credentials"
git push
```

### Configure Flux to Decrypt

```bash
# Create secret in cluster
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=~/.config/sops/age/keys.txt

# Add to Kustomization:
# spec:
#   decryption:
#     provider: sops
#     secretRef:
#       name: sops-age
```

---

## 🚨 Troubleshooting

### Resource Not Syncing

```bash
flux get sources git                    # Check Git sync
flux get kustomizations                 # Check Kustomization
kubectl describe kustomization <name>   # View errors
flux reconcile source git flux-system   # Force sync
```

### HelmRelease Failed

```bash
flux get helmrelease <name> -n <ns>           # Check status
kubectl describe helmrelease <name> -n <ns>   # View error
kubectl logs -n flux-system deploy/helm-controller -f  # Check logs
```

### Dependency Stuck

```bash
flux get kustomizations                 # Check deps
kubectl get kustomization <name> -o yaml | grep -A 5 "dependsOn"
```

### Manual Changes Not Syncing

```bash
# Flux overwrites manual changes!
# If you made kubectl changes, Flux will revert them
# To keep manual changes, update Git first
```

---

## 📁 Directory Structure

```
homelab/
├── clusters/homelab/         # Cluster Kustomizations
│   ├── flux-system/
│   ├── sources.yaml
│   ├── core.yaml
│   ├── networking.yaml
│   ├── security.yaml
│   ├── storage.yaml
│   └── monitoring.yaml
├── infrastructure/
│   ├── sources/              # Helm repos
│   ├── core/                 # Namespaces, storage, security
│   ├── networking/           # Ingress, MetalLB
│   ├── security/             # cert-manager
│   ├── storage/              # NFS provisioner
│   └── monitoring/           # Prometheus
└── k8s/
    ├── core/                 # Core manifests
    ├── applications/         # Your apps
    └── cert-manager/         # cert-manager configs
```

---

## 🎯 Best Practices

✅ **DO:**
- Pin Helm chart versions (`version: 1.2.3`)
- Use feature branches for major changes
- Write descriptive commit messages
- Set resource limits
- Encrypt secrets with SOPS
- Enable `prune: true` in Kustomizations

❌ **DON'T:**
- Use `kubectl apply` directly
- Use `helm install/upgrade` directly
- Commit plain-text secrets
- Use `latest` or `*` for versions
- Make multiple unrelated changes in one commit

---

## 🆘 Emergency: Disable GitOps

```bash
# Suspend all Kustomizations
flux suspend kustomization --all

# Now you can use kubectl/helm directly
kubectl apply -f file.yaml

# Resume GitOps (overwrites manual changes!)
flux resume kustomization --all
flux reconcile kustomization flux-system --with-source
```

---

## 📚 More Help

```bash
# Command help
flux --help
flux <command> --help

# Documentation
cat docs/managing-with-flux.md        # Full guide
cat docs/fluxcd-guide.md               # Setup guide
cat docs/gitops-comparison.md          # Flux vs Argo

# Official docs
# https://fluxcd.io/docs/
```

---

## 🎓 Remember

**Git → Flux → Cluster**

1. Make changes in Git
2. Commit and push
3. Flux syncs automatically
4. Verify deployment

**That's it!** No kubectl, no helm - just Git! 🚀
