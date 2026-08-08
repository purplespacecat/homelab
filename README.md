# Homelab

A single-node Kubernetes homelab, fully GitOps'd: K3s on a repurposed laptop,
FluxCD syncing everything in this repo to the cluster within a minute of
`git push`. Monitoring, logging, tracing, alerting to Telegram, and a
Jellyfin media server — declared here, reconciled automatically.

## The cluster

| | |
|---|---|
| Node | `spaceship` — i7 laptop, 8GB RAM, Ubuntu 22.04, WiFi |
| Distribution | K3s v1.33 (single node, control-plane + workloads) |
| Node IP | 192.168.100.98 (also the NFS server) |
| GitOps | FluxCD, syncing from this repo's `main` |
| Storage | NFS dynamic provisioning (`nfs-client` StorageClass) |
| Ingress | NGINX in hostNetwork mode (WiFi makes MetalLB L2 unreliable) |
| TLS | Private homelab CA via cert-manager (LAN-only, so no ACME) |

## What runs on it

| Component | Chart | Namespace |
|---|---|---|
| Prometheus + Grafana + Alertmanager | kube-prometheus-stack 82.17.1 | monitoring |
| Loki + Promtail (logs) | 6.55.0 / 6.17.1 | monitoring |
| Tempo (traces) | 1.24.4 | monitoring |
| Jellyfin (media) | 3.2.0 | media |
| NGINX Ingress | 4.15.1 | ingress-nginx |
| cert-manager | v1.20.1 | cert-manager |
| MetalLB | 0.15.3 | metallb-system |
| NFS provisioner | 4.0.18 | kube-system |

Alerts flow Prometheus → Alertmanager → Telegram; the pipeline is traced
end-to-end in [docs/alerting.md](docs/alerting.md).

**Access:**

- Grafana: `https://grafana.192.168.100.98.nip.io` — TLS from the homelab
  CA, credentials in the `grafana-admin-credentials` Secret
- Jellyfin: `http://jellyfin.192.168.100.98.nip.io`
- Prometheus / Alertmanager: no ingress on purpose (unauthenticated UIs stay
  off the LAN) — port-forward on demand:

  ```bash
  kubectl -n monitoring port-forward svc/prometheus-stack-kube-prom-prometheus 9090:9090
  kubectl -n monitoring port-forward svc/prometheus-stack-kube-prom-alertmanager 9093:9093
  ```

## How changes work

Git is the only write path. Edit a manifest, commit, push — Flux applies it
within a minute. No `kubectl apply`, no `helm install`; manual changes get
reverted on the next sync, and many files contain `${VAR}` placeholders that
only Flux substitutes.

```bash
vim infrastructure/monitoring/prometheus-stack.yaml
git commit -am "Raise Prometheus retention"
git push
flux get helmreleases -A        # watch it land
```

The full workflow — adding charts, debugging failed releases, suspend/resume,
the sync graph — is in [docs/flux.md](docs/flux.md).

## Repository layout

| Path | Contents |
|---|---|
| `clusters/homelab/` | Flux sync points: Kustomizations, `cluster-config.yaml` (all cluster-specific values: node IP, NFS server, MetalLB range, Telegram chat) |
| `infrastructure/` | HelmReleases by category: `sources/`, `storage/`, `networking/`, `security/`, `monitoring/`, `media/` |
| `k8s/` | Raw manifests: namespaces, MetalLB config, NetworkPolicies, the homelab CA |
| `scripts/` | Cluster bootstrap and utilities — see [scripts/README.md](scripts/README.md) |
| `docs/` | The guides listed below |

## Documentation

- [docs/flux.md](docs/flux.md) — operating the GitOps loop
- [docs/NETWORKING.md](docs/NETWORKING.md) — ingress, nip.io, hostNetwork,
  NetworkPolicy sharp edges
- [docs/alerting.md](docs/alerting.md) — metric → Telegram, hop by hop
- [docs/loki.md](docs/loki.md) — log collection, LogQL, retention status
- [docs/gitops-comparison.md](docs/gitops-comparison.md) — why Flux and not
  Argo (decision record)

## Rebuilding from scratch

The repo is the disaster-recovery plan. On a fresh Ubuntu install:

```bash
# 1. K3s
sudo ./scripts/k3s/setup-k3s-master.sh

# 2. NFS export (the node serves its own storage)
./scripts/common/setup-nfs-server.sh

# 3. Media HDD mount for Jellyfin (fstab entry + guards)
./scripts/common/mount-media-hdd.sh

# 4. The two out-of-band Secrets (Grafana admin, Telegram bot token)
./scripts/common/bootstrap-secrets.sh

# 5. Flux — needs a GitHub PAT with read access to this repo
./scripts/flux/install-flux-cli.sh
./scripts/flux/bootstrap-flux.sh

# Then watch everything deploy:
flux get kustomizations -w
```

Persistent data under `/data` on the NFS export and the media HDD contents
are the only things Git can't restore.

Adapting to a different network means editing one file:
`clusters/homelab/cluster-config.yaml` (`NODE_IP`, `NFS_SERVER`,
`METALLB_IP_RANGE`, `NETWORK_INTERFACE`, `TELEGRAM_CHAT_ID`).

## Trusting the homelab CA

Grafana's certificate chains to a private CA. One-time, per device:

```bash
./scripts/common/extract-ca-cert.sh
# import homelab-ca.crt:
#   Linux: /usr/local/share/ca-certificates/ + sudo update-ca-certificates
#   macOS: Keychain → Always Trust
#   Windows: Trusted Root Certification Authorities
```

## Troubleshooting entry points

| Symptom | Start here |
|---|---|
| Change pushed, nothing happened | `flux get kustomization flux-system` — compare its revision against `git rev-parse origin/main`. Matching-but-stale means the GitHub token expired (see [docs/flux.md](docs/flux.md#debugging)) |
| HelmRelease not Ready | `kubectl describe helmrelease <name> -n <ns>` |
| Service unreachable | `ping 192.168.100.98` first — the node is a laptop. Then [docs/NETWORKING.md](docs/NETWORKING.md#troubleshooting) |
| Pod-to-pod connection refused in monitoring | NetworkPolicy — the namespace is default-deny; see the sharp edges in [docs/NETWORKING.md](docs/NETWORKING.md) |
| PVC stuck Pending | `./scripts/common/verify-nfs-setup.sh` |
| No Telegram alerts | Inject a synthetic alert — [docs/alerting.md](docs/alerting.md#testing-the-pipe) |

## Notes

- The repo is public; it holds no secrets. The three credentials
  (Grafana admin, Telegram token, Flux's GitHub PAT) live only in the
  cluster — deliberately no SOPS at this scale.
- `scripts/kubeadm/` contains an alternative kubeadm-based bootstrap kept
  from earlier experiments; the live cluster is K3s.
- Prometheus metric retention is 2 days (single-node disk economy). Grafana
  runs stateless — dashboards are provisioned from this repo, and anything
  built only in the UI vanishes on pod restart.
