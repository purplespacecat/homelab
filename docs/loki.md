# Loki: logs on this cluster

Loki and Promtail collect logs from every pod and serve them through Grafana.
Everything is defined in `infrastructure/monitoring/loki-stack.yaml`.

This file replaces the old `loki-setup-guide.md`, which was a diary of the
original deployment (its "Current Status: Loki broken" section outlived the
problem by half a year — that history is in git if you need it).

## Current shape

| | |
|---|---|
| Loki | chart 6.55.0, `SingleBinary` mode, one replica |
| Storage | 10Gi PVC on `nfs-client`, TSDB v13 schema, filesystem store |
| Gateway | NGINX pod in front of Loki (`loki-gateway`), `Recreate` strategy |
| Promtail | DaemonSet, tails `/var/log/pods`, pushes to `loki-gateway` |
| Retention | **None yet** — see below |
| Query limits | 30-day lookback, 4MB/s ingest per stream |

Caches, canary, and the read/write/backend split are all disabled — they
exist for multi-node Loki and only cost memory here.

## Retention status

Retention was never enabled: the compactor runs but only compacts, so every
log line since deployment is still on disk. The 10Gi PVC size does not bound
this — the NFS provisioner creates plain subdirectories and enforces no
quota, so the real limit is free space on the node's `/data` export.

A spec for enabling 7-day retention (compactor config, aligned query
lookback, a retention-stall alert, and the capacity measurement to run
first) lives at `docs/superpowers/specs/2026-08-08-loki-retention-design.md`.

## Querying logs

Grafana → Explore → Loki data source.

```logql
{namespace="monitoring"}                        # everything from a namespace
{namespace="monitoring", pod="loki-0"}          # one pod
{namespace="media"} |= "error"                  # substring filter
{namespace="flux-system"} |~ "(?i)failed|error" # regex, case-insensitive

# Aggregations
sum(rate({namespace="monitoring"} |= "error" [1m])) by (pod)
sum(count_over_time({namespace="media"}[5m])) by (pod)
```

Labels available on every stream: `namespace`, `pod`, `container`, plus pod
labels — minus a deliberate blocklist. Promtail drops `pod_template_hash`,
`controller_revision_hash`, chart/heritage labels and friends at the source,
because they change on every rollout (index bloat) and once pushed a stream
over Loki's 15-label limit, at which point Loki **silently rejected its
logs with 400s**. If a pod's logs are missing, count its labels before
suspecting anything else.

## Troubleshooting

### Loki won't start

```bash
kubectl logs -n monitoring loki-0 -c loki | head -30
```

The config error is always in the first lines. Known one: enabling
retention without `delete_request_store` fails with
`compactor.delete-request-store should be configured` — add
`delete_request_store: filesystem` to the compactor block.

### Promtail runs but logs don't arrive

```bash
# Is Promtail shipping?
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=20

# Can it reach the gateway?
kubectl exec -n monitoring daemonset/promtail -- \
  wget -qO- http://loki-gateway/ready
```

Then check the label count issue above — Promtail can be shipping happily
while Loki rejects specific streams.

### PVC stuck Pending

NFS provisioner problem, not a Loki problem:

```bash
kubectl logs -n kube-system -l app=nfs-subdir-external-provisioner --tail=20
```

### Disk usage

```bash
kubectl exec -n monitoring loki-0 -c loki -- du -sh /var/loki/chunks /var/loki/index
kubectl top pod -n monitoring loki-0
```

Never delete files under `/var/loki` by hand — chunks and index are one
consistent unit, and Loki corrupts if they diverge. Retention (once enabled)
is the only safe deletion path.

## Useful references

- LogQL: https://grafana.com/docs/loki/latest/query/
- Chart: https://github.com/grafana/loki/tree/main/production/helm/loki
