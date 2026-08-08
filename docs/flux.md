# Flux on this cluster

How this repo's GitOps loop works day to day: making changes, watching them
land, and debugging when they don't. Replaces the old `fluxcd-guide.md`,
`managing-with-flux.md`, and `flux-cheatsheet.md`, which triplicated generic
Flux material — this doc covers this repo only. For upstream concepts, use
[fluxcd.io/docs](https://fluxcd.io/docs/).

## The one rule

All changes go through Git. Never `kubectl apply` or `helm install` against
the cluster — Flux reverts manual changes on its next sync, and files here
contain `${VAR}` placeholders that only Flux substitutes (applying them raw
breaks the resource). The two exceptions are the out-of-band secrets
(`scripts/common/bootstrap-secrets.sh`) and read-only commands.

## What syncs what

Flux bootstraps from `clusters/homelab/flux-system/` and fans out through
Kustomizations, each pointing at a directory:

```
sources (Helm repos)
  └─ core-infrastructure (namespaces, configs, policies)
       ├─ storage (NFS provisioner)
       │    └─ networking (MetalLB, NGINX Ingress)
       │         └─ monitoring (Prometheus, Grafana, Loki, Promtail, Tempo)
       │              └─ media (Jellyfin — ordered after monitoring only
       │                        for the ServiceMonitor CRD)
       └─ security (cert-manager)
```

Sync intervals are 1–10 minutes per Kustomization. Cluster-specific values
(`NODE_IP`, `NFS_SERVER`, `METALLB_IP_RANGE`, `NETWORK_INTERFACE`,
`TELEGRAM_CHAT_ID`) live in `clusters/homelab/cluster-config.yaml` and reach
manifests via `postBuild.substituteFrom`.

## Daily workflow

```bash
git pull origin main
vim infrastructure/monitoring/prometheus-stack.yaml   # make the change
git add -p && git commit -m "..."
git push

# Flux picks it up within ~1 min. To skip the wait:
flux reconcile kustomization monitoring --with-source

# Verify it landed:
flux get helmreleases -A
kubectl get pods -n monitoring
```

Helm values are inline in each HelmRelease spec — there are no separate
values files.

## Adding a Helm chart

1. If the chart repo is new, add a `HelmRepository` in
   `infrastructure/sources/` (copy an existing one).
2. Create the `HelmRelease` in the matching `infrastructure/<category>/`
   directory, referencing that source. Existing releases are the best
   templates — `infrastructure/media/jellyfin.yaml` is a compact example.
3. New namespace? Add it in `infrastructure/core/namespaces.yaml` and
   `k8s/core/namespaces/`.
4. Commit and push.

Single-node cautions that bite here: charts that default to pod anti-affinity
(Loki, Tempo did) need it disabled, and workloads with a PVC usually need
`Recreate` strategy or rolling updates deadlock on the volume.

## Adding raw manifests

Drop the YAML in the right `k8s/` subdirectory — an existing Kustomization
already tracks each of them. Use `${NODE_IP}`-style variables where the file
is substituted (check whether sibling files use them; not every path gets
substitution — `k8s/core/security/network-policies.yaml` notably does not,
which is why the node IP is hardcoded there with a comment).

## Removing things

`git rm` the file, commit, push. Kustomizations run with `prune: true`, so
Flux deletes the cluster objects. Two caveats:

- Removing a HelmRelease uninstalls the chart, but PVCs created by it can
  survive and keep their PVs `Bound`. Check `kubectl get pvc -A` afterwards
  if storage matters.
- A pruned-while-bound PV is armed, not gone — its retention policy fires
  when the PVC is later deleted. This has destroyed data here before; see
  the PV lifecycle notes in the vault before pruning anything stateful.

## Suspend and resume

For debugging a resource without Flux fighting you:

```bash
flux suspend helmrelease loki -n monitoring
# poke at things manually...
flux resume helmrelease loki -n monitoring   # reconciles back to Git state
```

Anything you changed manually is overwritten on resume. If the manual state
is the one you want, put it in Git first.

## Debugging

### Is Flux even syncing?

The failure mode that bit hardest (2026-07): the GitHub token expired, the
GitRepository failed every fetch, and **everything still reported Ready** —
at a stale revision. Ready means "last applied revision is healthy", so
always compare revisions, never trust the status column alone:

```bash
flux get kustomization flux-system     # note the revision sha
git rev-parse origin/main              # should match
```

The `FluxGitSourceNotReady` alert (Telegram) now fires within ~5 minutes of
this. On token rotation, update the `flux-system` Secret in the flux-system
namespace — a fine-grained PAT with read-only Contents on this repo is
enough.

### A HelmRelease is failing

```bash
flux get helmrelease -A                        # which one, what message
kubectl describe helmrelease <name> -n <ns>    # full error text
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -20
flux logs --kind=HelmRelease --name=<name>
```

If the release is stuck upgrading, `flux suspend` + `flux resume` often
clears it. Both install and upgrade carry `remediation.retries: 3`, so a
transient failure retries and a persistent one rolls back — read the
describe output before assuming the new version is live.

### A Kustomization is stuck on a dependency

```bash
flux get kustomizations                        # find the not-Ready ancestor
```

The dependency chain above means a broken `core-infrastructure` blocks
everything downstream — when several Kustomizations go not-Ready at once,
fix the topmost one and the rest usually clear on their own.

### Controller logs

```bash
kubectl logs -n flux-system deploy/source-controller -f
kubectl logs -n flux-system deploy/kustomize-controller -f
kubectl logs -n flux-system deploy/helm-controller -f
```

## Secrets

Deliberately no SOPS, no sealed-secrets: at two secrets, manual creation
beats encryption machinery, and it keeps this repo safely public. The two
out-of-band secrets are `grafana-admin-credentials` and
`alertmanager-telegram` (both in monitoring), created or rotated with:

```bash
./scripts/common/bootstrap-secrets.sh
```

The third credential is Flux's own GitHub token (`flux-system` Secret),
created at bootstrap and rotated as described above. It expires — that's
what `FluxGitSourceNotReady` watches for.

## Chart upgrades

Pin exact versions. Bump incrementally rather than jumping majors — CRD
changes across big jumps have required manual surgery here. After a bump:

```bash
flux get helmrelease <name> -n <ns>      # upgrade succeeded?
kubectl get pods -n <ns>                 # workload actually healthy?
```

A succeeded upgrade with a crashlooping pod is a values problem, not a chart
problem — check `helm get values <release> -n <ns>` against the chart's
current schema. Mis-nested values fail silently (Tempo ran 102 days without
resource limits because of one wrong indentation level).
