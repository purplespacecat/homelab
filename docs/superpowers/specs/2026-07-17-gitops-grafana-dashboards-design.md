# GitOps'd Grafana dashboards + export workflow

**Date:** 2026-07-17
**Status:** Approved

## Problem

Grafana runs stateless (`persistence.enabled: false`) — dashboards created in the
UI live only in the pod's ephemeral `grafana.db` and vanish on pod recreation.
Everything else in the cluster is declarative; UI-drafted dashboards need a path
into git before they evaporate.

Investigation findings (2026-07-17):

- All 29 current dashboards are provisioned (25 chart defaults, 4 grafana.com
  `gnetId` downloads in the Homelab folder, 1 in-repo ConfigMap). Zero UI-created
  dashboards exist right now — any previously made were already lost.
- Grafana 12 stores dashboards in unified storage (`resource` tables), not the
  legacy `dashboard` table.
- The `grafana-admin-credentials` secret does **not** authenticate against the
  running Grafana (401) — the live admin password was changed after pod start.
  It reverts to the secret value on the next pod recreation. Not fixed here;
  the export script takes a `GRAFANA_PASSWORD` override for the interim.

## Decision

Approach A: export script + sidecar ConfigMaps, following the existing
`flux-dashboard.yaml` pattern. Rejected: manual-export-only docs (tedious,
forgettable) and Grafana Operator CRDs (an extra operator is overkill for a
single-node cluster with a working sidecar).

## Components

### 1. Folder routing via sidecar annotation (`infrastructure/monitoring/prometheus-stack.yaml`)

Add to the `grafana:` values:

```yaml
sidecar:
  dashboards:
    folderAnnotation: grafana_folder
    provider:
      foldersFromFilesStructure: true
```

- ConfigMaps annotated `grafana_folder: Homelab` land in the Homelab folder.
- Unannotated ConfigMaps (the 25 chart defaults) stay in General.
- Also annotate the existing `flux-dashboard.yaml` ConfigMap so Flux Cluster
  Stats moves General → Homelab.

### 2. Export script (`scripts/common/export-dashboards.sh`)

- Port-forwards to `svc/prometheus-stack-grafana` in `monitoring`.
- Auth: admin user/password from the `grafana-admin-credentials` secret;
  `GRAFANA_PASSWORD` env var overrides (needed while the live password differs
  from the secret).
- `GET /api/search?type=dash-db`, then `GET /api/dashboards/uid/<uid>` per hit;
  skips dashboards where `meta.provisioned == true`.
- Writes each UI-created dashboard as a ConfigMap YAML to
  `infrastructure/monitoring/dashboards/<slug>.yaml`:
  - label `grafana_dashboard: "1"`, annotation `grafana_folder: <its live
    folder, else Homelab>`
  - dashboard JSON under a `<slug>.json` data key, top-level `id` stripped,
    `uid` preserved so re-exports diff cleanly.
- Idempotent: re-running overwrites files. Update loop is: edit a copy in the
  UI → re-export → review diff → commit.
- No kustomization wiring needed: Flux auto-generates a kustomization for
  `infrastructure/monitoring/` and scans recursively, so `dashboards/` is
  picked up automatically.

### 3. Test dashboard (`infrastructure/monitoring/dashboards/services-resource-usage.yaml`)

Hand-built "Services / Resource Usage" ConfigMap proving the pipeline
end-to-end. Homelab folder. Template variables `namespace` (default `media`)
and `pod`. Panels, all per-pod within the selected namespace:

- CPU usage (`container_cpu_usage_seconds_total` rate) with request/limit lines
- Memory working set with request/limit lines
- Network receive/transmit
- Container restarts

### 4. Docs

Short section (new `docs/grafana-dashboards.md` or folded into the existing
monitoring doc) covering: the export workflow, the provisioned-dashboards-are-
read-only caveat (Save As copy → edit → export → commit), folder routing, and
a note on the admin-password mismatch behavior.

## Error handling

- Script fails loudly if kubectl can't reach the cluster, auth fails (hint
  about `GRAFANA_PASSWORD`), or the port-forward doesn't come up.
- Slug collisions between distinct UIDs abort with an error rather than
  silently overwriting.

## Verification

1. Commit, push, `flux reconcile kustomization monitoring --with-source`.
2. Confirm via Grafana API/db: test dashboard present in Homelab, Flux Cluster
   Stats moved to Homelab, chart defaults untouched in General.
3. Run the export script against a throwaway UI dashboard; confirm it produces
   a valid ConfigMap that provisions after commit (then delete the throwaway).

## Out of scope

- Fixing the admin-password mismatch (self-heals on pod recreation; flagged in
  docs).
- Vendoring the 4 grafana.com `gnetId` dashboards or the chart defaults into
  the repo.
- Grafana Operator / CRDs.
