# CLAUDE.md - Homelab GitOps Repository

## Overview

Single-node K3s homelab cluster managed by FluxCD GitOps. All infrastructure is declaratively defined in this repo and auto-synced to the cluster. The node is called **spaceship** running Ubuntu 22.04 over WiFi.

## Repository Structure

```
clusters/homelab/          # FluxCD Kustomization entrypoints (sync points)
  flux-system/             # Flux bootstrap (GitRepository + root Kustomization)
  cluster-config.yaml      # ConfigMap with cluster variables (NODE_IP, NFS_SERVER, etc.)
  sources.yaml             # Helm repo sources
  core.yaml                # Namespaces, configs, policies
  storage.yaml             # NFS provisioner
  networking.yaml          # MetalLB + NGINX Ingress
  security.yaml            # cert-manager
  monitoring.yaml          # Prometheus, Grafana, Loki, Promtail, Tempo

infrastructure/            # Actual HelmRelease and Kustomize definitions
  sources/                 # HelmRepository CRDs (6 repos)
  core/                    # Namespace + config Kustomizations
  storage/                 # nfs-subdir-external-provisioner HelmRelease
  networking/              # MetalLB + ingress-nginx HelmReleases
  security/                # cert-manager HelmRelease
  monitoring/              # prometheus-stack, loki, promtail, tempo HelmReleases + alerts

k8s/                       # Raw Kubernetes manifests
  core/                    # Namespaces, MetalLB config, NFS config, NetworkPolicies
  cert-manager/            # ClusterIssuers (Let's Encrypt, self-signed CA)

scripts/                   # Setup and utility scripts
  k3s/                     # K3s install/teardown
  kubeadm/                 # Kubeadm install/teardown
  flux/                    # Flux CLI install, bootstrap, rebuild
  common/                  # NFS, Helm, cert-manager, verification utilities

docs/                      # Guides (networking, Flux management, Loki setup, etc.)
```

## FluxCD Dependency Chain

```
sources (Helm repos)
  -> core-infrastructure (namespaces, configs, policies)
    -> storage (NFS provisioner)
      -> networking (MetalLB, NGINX Ingress)
        -> monitoring (Prometheus, Grafana, Loki, Promtail, Tempo)
    -> security (cert-manager)
```

All Kustomizations sync from the `flux-system` GitRepository every 1-10 minutes.

## Variable Substitution

Cluster-specific values are centralized in `clusters/homelab/cluster-config.yaml` (ConfigMap) and injected via Flux `postBuild.substituteFrom`. Variables:
- `${NODE_IP}` -- Node IP (used in ingress hosts, NFS server)
- `${NFS_SERVER}` -- NFS server address
- `${METALLB_IP_RANGE}` -- MetalLB IP address pool
- `${NETWORK_INTERFACE}` -- Network interface for L2 advertisement

**Important:** Variable substitution only works through Flux Kustomizations. Never `kubectl apply` files containing `${VAR}` directly -- the variables won't be replaced and will cause failures.

## Key Conventions

- **All changes via Git** -- never `kubectl apply` or `helm install` directly. Commit to `main`, Flux syncs within 1 minute.
- **HelmRelease values are inline** in the HelmRelease spec (e.g., `infrastructure/monitoring/prometheus-stack.yaml`). There are no separate values files.
- **Namespaces** are created in `infrastructure/core/namespaces.yaml` and `k8s/core/namespaces/`.
- **NetworkPolicies** use default-deny in the monitoring namespace with explicit allow rules. Grafana needs K8s API + DNS egress for sidecars.
- **Storage** uses NFS with dynamic provisioning via `nfs-client` StorageClass.
- **Ingress** uses `hostNetwork: true` on NGINX (WiFi workaround -- MetalLB L2 is unreliable over WiFi). Service type is ClusterIP, not LoadBalancer.
- **Single-node considerations:** Disable pod anti-affinity in chart values (e.g., Loki `gateway.affinity: {}`), use `Recreate` deployment strategy where rolling updates would deadlock.

## Deployed Stack

| Component | Chart Version | Namespace | Notes |
|-----------|---------------|-----------|-------|
| NFS Provisioner | 4.0.18 | kube-system | StorageClass: nfs-client (default) |
| MetalLB | 0.15.3 | metallb-system | L2 mode, WiFi interface |
| NGINX Ingress | 4.15.1 | ingress-nginx | hostNetwork, DaemonSet |
| cert-manager | v1.20.1 | cert-manager | Let's Encrypt + self-signed CA |
| Prometheus Stack | 82.17.1 | monitoring | Prometheus, Grafana, Alertmanager, Node Exporter, KSM |
| Loki | 6.55.0 | monitoring | SingleBinary mode, 10Gi NFS |
| Promtail | 6.17.1 | monitoring | DaemonSet, collects all pod logs |
| Tempo | 1.24.4 | monitoring | Distributed tracing, 7d retention |

## Prerequisites for Cluster Rebuild

Before Flux can fully deploy, these must exist:
1. **Grafana credentials Secret** -- `kubectl create secret generic grafana-admin-credentials -n monitoring --from-literal=admin-user=admin --from-literal=admin-password=<password>`
2. **Flux GitHub token** -- Created during `flux bootstrap`
3. **NFS server** running at the configured `NFS_SERVER` IP with `/data` exported

## Common Tasks

### Add a new HelmRelease

1. Add `HelmRepository` source in `infrastructure/sources/` (if new chart repo)
2. Create `HelmRelease` in appropriate `infrastructure/<category>/` directory
3. Reference the source in the HelmRelease spec
4. If new namespace needed, add to `infrastructure/core/namespaces.yaml`
5. Commit and push -- Flux applies automatically

### Debug a failing HelmRelease

```bash
flux get helmrelease -A                          # Status overview
kubectl describe helmrelease <name> -n <ns>      # Detailed error
kubectl get events -n <ns> --sort-by=.lastTimestamp
flux logs --kind=HelmRelease --name=<name>
```

### Force reconciliation

```bash
flux reconcile kustomization flux-system --with-source  # Full sync
flux reconcile helmrelease <name> -n <ns> --with-source # Single release
```

## Resource Constraints

Single-node homelab -- be conservative with resources. Current allocations:
- Prometheus: 500m/512Mi request, 1/1Gi limit
- Grafana: within prometheus-stack
- Loki: 256Mi request (SingleBinary mode)
- Promtail: 50m/64Mi request
- Tempo: 100m/256Mi request
- NGINX Ingress: 100m/128Mi request, 500m/512Mi limit

## Secrets

- Grafana credentials: `grafana-admin-credentials` Secret in monitoring namespace (must be created manually before deploy)
- Flux GitHub token: `flux-system` Secret in flux-system namespace (created during bootstrap)
- Let's Encrypt account key: managed by cert-manager
- No SOPS or sealed-secrets currently configured

## Known Pitfalls

- **Never `kubectl apply` files with `${VAR}` variables** -- only Flux substitutes them
- **Chart upgrades with big version jumps** can break CRDs and require manual intervention. Bump incrementally.
- **Loki/Tempo charts** add pod anti-affinity by default -- must be disabled for single-node
- **Grafana sidecars** in kube-prometheus-stack need K8s API egress (NetworkPolicy must allow it)
- **NFS PV ownership** -- new chart versions may run as different UIDs. Delete PVC and let it recreate if permissions break.
