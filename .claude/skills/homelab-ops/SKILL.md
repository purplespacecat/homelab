---
name: homelab-ops
description: Operational playbook for working on the spaceship homelab cluster — use whenever debugging cluster problems (crashloops, alerts firing, services unreachable, Flux not syncing), making infrastructure changes (HelmReleases, NetworkPolicies, alerts, storage, ingress), or verifying that a change actually worked. Covers the triage ladder, per-change-type verification steps, this cluster's recurring failure classes, and live-state checks that the repo's YAML cannot tell you. Use it even for small changes — most incidents here came from small changes that skipped verification.
---

# Homelab ops playbook

CLAUDE.md holds the conventions, structure, and pitfalls list. This skill is
the *how*: diagnosis order, verification per change type, and the failure
classes this cluster actually produces. When they overlap, CLAUDE.md wins.

## Before anything else

Two checks that cost seconds and prevent whole classes of wasted work:

```bash
ping -c1 -W2 192.168.100.98
```

The node is a laptop on WiFi. If it doesn't answer, nothing else is
diagnosable — tell the user the node is down instead of interpreting
connection errors as cluster problems. (`kubectl` errors like "no route to
host" mean exactly this, and the local `df`/`free` you run are the laptop's,
not the node's.)

```bash
flux get kustomization flux-system   # revision sha
git rev-parse origin/main            # must match
```

"Ready" with a stale revision means Flux stopped syncing — usually the
GitHub token expired (2026-07: every fetch failed for days while all status
fields stayed green). Everything you push during that state silently goes
nowhere.

Also: local `main` may be ahead of `origin/main` with unpushed commits.
Flux syncs from origin. When "the change didn't apply", check `git log
origin/main..main` before debugging the cluster.

## Triage ladder

For "something is broken", in order — each step gates the next:

1. **Narrow to one object.** `kubectl get pods -A | grep -v Running`,
   `flux get helmrelease -A`, `flux get kustomization -A`. Alert storms here
   are almost always one root cause fanned out: dedupe the Alertmanager
   alert list by pod/object before treating alerts as separate problems.
   Same-age restarts across many pods = node reboot; the one pod that
   didn't recover is the target.
2. **Read the first error, and the previous crash.** `kubectl logs` +
   `--previous` + `describe`. A container dying in under a second with a
   network error is a reachability problem, not an application problem.
3. **Check the destination it couldn't reach.** For the API server: the
   `kubernetes` Service DNATs to the **node IP on 6443**, not a pod IP on
   443 — `kubectl get endpointslice -n default` shows this. Many "can't
   reach X" bugs on this cluster are really "the rule can't match X's real
   address".
4. **Check the selector matches anything.** `kubectl get pod --show-labels`
   vs the policy/monitor/service selector — live labels, not what the YAML
   implies. Zero-match selectors fail silently and have caused months-long
   outages here (allow-alertmanager, kube-state-metrics scraping).
5. **Compare against a working peer.** The strongest tool on this cluster:
   another pod in the same namespace under the same default-deny that CAN
   do the thing. Diff its policy/config shape against the broken one.
6. **Prove the theory empirically before writing the fix.** Exec into a pod
   and test. Read failure modes precisely: from inside the mesh,
   `401 Unauthorized` = connectivity works (auth is the only missing
   piece); `connection refused` on k3s pod-to-pod = kube-router enforcing a
   NetworkPolicy; timeout = routing/host down.
7. **Bound the blast radius of the fix.** `kubectl diff -f <file>` before
   committing — it shows the server-side merged result and catches edits
   that touch more than intended.

## Verification per change type

A change is not done when Flux applies it; it's done when verified. What
"verified" means here, by type:

**NetworkPolicy** — exec into the affected pod and exercise the path.
Beware two traps: hostNetwork pods (NGINX, apiserver) bypass netpol
entirely, so they can't validate a rule; and established connections
survive policy changes — a running pod's working connection proves nothing
about a *new* connection (conntrack masked a broken operator rule here for
4 weeks until a reboot exposed it). Test with a fresh connection.

**Alert rule** — run the expression as an instant query in Prometheus and
confirm it returns series (or that its `absent()` logic is exercised).
Three separate alerts in this repo's history matched nothing and provided
false assurance. Also confirm the PrometheusRule carries the
`release: prometheus-stack` label or the operator ignores the whole file
silently. For delivery, inject a synthetic alert (docs/alerting.md has the
curl).

**Helm values** — after the release upgrades, check the value actually
landed: `helm get values <release> -n <ns>` and inspect the rendered
workload. Mis-nested values are accepted silently (Tempo ran 102 days with
its resource limits at the wrong indentation, applying nothing).

**Storage** — PVC `size` on nfs-client is advisory; the provisioner
enforces no quota. Real bound = free space on the node's `/data`. Before
sizing anything, measure current usage instead of trusting the PVC number.
Never assume deleting a PVC is safe: check `persistentVolumeReclaimPolicy`
and whether data under `/data/<pv-dir>` matters.

**ServiceMonitor / scraping** — after adding one, check Prometheus targets
(port-forward 9090 → Targets page, or query `up{job="..."}`). Flux
controllers needed a PodMonitor because their Services don't expose the
metrics port — a ServiceMonitor matched nothing, silently.

**Ingress** — `curl` it from the LAN side with the real hostname. Remember
only Grafana gets TLS; Prometheus/Alertmanager must not get ingresses at
all.

## This cluster's failure signature

Recurring classes, so you recognize the shape on sight:

- **Silent zero-match** — selectors/labels that match nothing: no error,
  the intent just never happens. Seen in NetworkPolicies (legacy `app=`
  labels), ServiceMonitors, alert rules, Grafana datasource uids.
- **Broken reporting channel** — the failure disables the thing that would
  have reported it (Prometheus blind → no alerts about being blind; Flux
  token dead → no sync including of the alert that would catch it). When a
  guard exists, ask what guards the guard.
- **Config accepted, meaning lost** — YAML that parses and applies but is
  semantically inert: mis-nested Helm values, `${VAR}` files applied
  outside Flux, netpol rules whose destination can't exist (pod-selector
  for a node-IP target).
- **State vs. provisioning drift** — the live object predates the current
  config and holds stale state: Grafana's persisted DB crashlooping against
  newer provisioning (74 days), k3s re-defaulting the local-path
  StorageClass on every restart, PVs surviving their HelmRelease.
- **Masked by an old connection** — conntrack keeps a pre-change flow
  alive; the bug appears only on reconnect/reboot, long after the commit
  that caused it.

When you fix an instance, grep for the pattern's siblings — the operator
netpol fix found four correct policies and one outlier in the same file.

## Making changes

- Branch from `origin/main`, PR, let the user merge — never commit to
  `main` directly. The user is risk-averse about breaking running services
  (Jellyfin, storage): prefer compensating controls and PRs over risky
  in-place edits, and say so when a change carries service risk.
- One concern per PR. Docs-only changes and behavior changes travel
  separately.
- After merge, verify the sync landed (`flux get kustomization` revision)
  and then run the per-type verification above. Report what you ran and
  what it showed, not just "done".

## Fast map

Where changes go (details in CLAUDE.md):

| Change | File |
|---|---|
| Cluster-specific values | `clusters/homelab/cluster-config.yaml` |
| Chart versions / Helm values | `infrastructure/<category>/<name>.yaml` (inline values) |
| Custom alerts | `infrastructure/monitoring/alerts.yaml` (+ `flux-alerts.yaml`, `jellyfin-alerts.yaml`) |
| NetworkPolicies | `k8s/core/security/network-policies.yaml` (NOT var-substituted) |
| Namespaces | `infrastructure/core/namespaces.yaml` + `k8s/core/namespaces/` |
| Secrets (out-of-band) | `scripts/common/bootstrap-secrets.sh` — never in Git |

Docs for humans: `docs/flux.md` (GitOps loop), `docs/NETWORKING.md`,
`docs/alerting.md`, `docs/loki.md`. Keep them true when changing what they
describe — doc drift here has actively misled debugging before.
