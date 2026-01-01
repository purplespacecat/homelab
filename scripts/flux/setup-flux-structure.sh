#!/bin/bash
#
# FluxCD Directory Structure Setup
# Creates the necessary directory structure and template files for Flux CD
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "======================================"
echo "FluxCD Directory Structure Setup"
echo "======================================"
echo ""
echo "This script will create the following structure:"
echo ""
echo "clusters/"
echo "  └── homelab/"
echo "      ├── sources.yaml"
echo "      ├── core.yaml"
echo "      ├── storage.yaml"
echo "      ├── networking.yaml"
echo "      ├── security.yaml"
echo "      └── monitoring.yaml"
echo "infrastructure/"
echo "  ├── sources/"
echo "  ├── core/"
echo "  ├── storage/"
echo "  ├── networking/"
echo "  ├── security/"
echo "  └── monitoring/"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

cd "$REPO_ROOT"

# Create directory structure
echo "Creating directory structure..."
mkdir -p clusters/homelab
mkdir -p infrastructure/sources
mkdir -p infrastructure/core
mkdir -p infrastructure/storage
mkdir -p infrastructure/networking
mkdir -p infrastructure/security
mkdir -p infrastructure/monitoring

echo "✓ Directory structure created"

# Create Helm repository sources
echo ""
echo "Creating Helm repository sources..."

cat > infrastructure/sources/prometheus-community.yaml <<'EOF'
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
spec:
  interval: 1h
  url: https://prometheus-community.github.io/helm-charts
EOF

cat > infrastructure/sources/ingress-nginx.yaml <<'EOF'
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 1h
  url: https://kubernetes.github.io/ingress-nginx
EOF

cat > infrastructure/sources/metallb.yaml <<'EOF'
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: metallb
  namespace: flux-system
spec:
  interval: 1h
  url: https://metallb.github.io/metallb
EOF

cat > infrastructure/sources/jetstack.yaml <<'EOF'
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: jetstack
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.jetstack.io
EOF

cat > infrastructure/sources/nfs-provisioner.yaml <<'EOF'
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: nfs-subdir-external-provisioner
  namespace: flux-system
spec:
  interval: 1h
  url: https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner
EOF

echo "✓ Helm repository sources created"

# Create cluster Kustomizations
echo ""
echo "Creating cluster-level Kustomizations..."

cat > clusters/homelab/sources.yaml <<'EOF'
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
EOF

cat > clusters/homelab/core.yaml <<'EOF'
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
EOF

cat > clusters/homelab/storage.yaml <<'EOF'
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
EOF

cat > clusters/homelab/networking.yaml <<'EOF'
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
EOF

cat > clusters/homelab/security.yaml <<'EOF'
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
EOF

cat > clusters/homelab/monitoring.yaml <<'EOF'
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
EOF

echo "✓ Cluster-level Kustomizations created"

# Create infrastructure Kustomizations
echo ""
echo "Creating infrastructure-level Kustomizations..."

cat > infrastructure/core/namespaces.yaml <<'EOF'
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
EOF

cat > infrastructure/core/storage.yaml <<'EOF'
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
EOF

cat > infrastructure/core/security.yaml <<'EOF'
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
EOF

echo "✓ Infrastructure-level Kustomizations created"

# Detect NFS server IP
echo ""
echo "Detecting NFS server IP..."
NFS_SERVER=$(grep -r "server:" k8s/core/storage/nfs-config.yaml 2>/dev/null | awk '{print $2}' || echo "192.168.100.98")
echo "Using NFS server: $NFS_SERVER"

# Create NFS provisioner HelmRelease
cat > infrastructure/storage/nfs-provisioner.yaml <<EOF
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
      server: $NFS_SERVER
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
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
EOF

echo "✓ NFS provisioner HelmRelease created"

# Create NGINX Ingress HelmRelease
cat > infrastructure/networking/ingress-nginx.yaml <<'EOF'
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
EOF

echo "✓ NGINX Ingress HelmRelease created"

# Create MetalLB HelmRelease
cat > infrastructure/networking/metallb.yaml <<'EOF'
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
EOF

echo "✓ MetalLB HelmRelease created"

# Create cert-manager HelmRelease
cat > infrastructure/security/cert-manager.yaml <<'EOF'
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
EOF

echo "✓ cert-manager HelmRelease created"

# Detect node IP for Prometheus ingress
echo ""
echo "Detecting node IP for ingress..."
NODE_IP=$(grep -r "prometheus\." k8s/helm/prometheus/values.yaml 2>/dev/null | grep "nip.io" | head -1 | sed 's/.*prometheus\.\(.*\)\.nip\.io.*/\1/' || echo "192.168.100.98")
echo "Using node IP: $NODE_IP"

# Create Prometheus stack HelmRelease
cat > infrastructure/monitoring/prometheus-stack.yaml <<EOF
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
          - prometheus.$NODE_IP.nip.io
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
          - grafana.$NODE_IP.nip.io
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
          - alertmanager.$NODE_IP.nip.io
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
EOF

echo "✓ Prometheus stack HelmRelease created"

# Create README
cat > infrastructure/README.md <<'EOF'
# Infrastructure

This directory contains FluxCD resources for managing the homelab infrastructure.

## Structure

- `sources/` - Helm repository sources
- `core/` - Core infrastructure (namespaces, storage, security)
- `storage/` - Storage provisioners (NFS)
- `networking/` - Network components (MetalLB, NGINX Ingress)
- `security/` - Security components (cert-manager)
- `monitoring/` - Monitoring stack (Prometheus, Grafana, Alertmanager)

## Deployment Order

Flux automatically handles dependencies, but the logical order is:

1. Sources (Helm repositories)
2. Core (namespaces, storage configs, network policies)
3. Storage (NFS provisioner)
4. Networking (MetalLB, NGINX Ingress)
5. Security (cert-manager + issuers)
6. Monitoring (Prometheus stack)

## Modifying Resources

All changes should be made via Git:

1. Edit the HelmRelease or Kustomization file
2. Commit and push to Git
3. Flux automatically syncs within 1 minute

## Manual Sync

Force immediate reconciliation:

```bash
# Sync a specific Kustomization
flux reconcile kustomization <name> -n flux-system

# Sync a HelmRelease
flux reconcile helmrelease <name> -n <namespace> --with-source

# Sync all
flux reconcile kustomization flux-system --with-source
```
EOF

echo "✓ Infrastructure README created"

echo ""
echo "======================================"
echo "Setup Complete!"
echo "======================================"
echo ""
echo "Directory structure created successfully."
echo ""
echo "Next steps:"
echo ""
echo "1. Review the generated files and adjust as needed"
echo "   - Check NFS server IP in infrastructure/storage/nfs-provisioner.yaml"
echo "   - Check node IP in infrastructure/monitoring/prometheus-stack.yaml"
echo ""
echo "2. Install Flux CLI (if not already installed):"
echo "   curl -s https://fluxcd.io/install.sh | sudo bash"
echo ""
echo "3. Bootstrap Flux to your cluster:"
echo "   export GITHUB_TOKEN=<your-token>"
echo "   flux bootstrap github \\"
echo "     --owner=<your-github-user> \\"
echo "     --repository=homelab \\"
echo "     --branch=main \\"
echo "     --path=./clusters/homelab \\"
echo "     --personal"
echo ""
echo "4. Commit and push the changes:"
echo "   git add clusters/ infrastructure/"
echo "   git commit -m 'Add FluxCD configuration'"
echo "   git push"
echo ""
echo "5. Watch Flux deploy everything:"
echo "   flux get kustomizations -w"
echo "   flux get helmreleases -A"
echo ""
echo "For detailed instructions, see docs/fluxcd-guide.md"
echo ""
