# Alerting Architecture

How an alert travels from a metric on the cluster to a Telegram message on the
phone. The pipeline is kube-prometheus-stack (Prometheus + Alertmanager +
exporters, `infrastructure/monitoring/prometheus-stack.yaml`) with Telegram as
the only paging channel. This doc walks the full path once, using the
certificate-expiry alarm as the worked example, then catalogs the pieces.

## The pipeline at a glance

```
   metric sources                Prometheus                  Alertmanager                Telegram
┌──────────────────┐   scrape  ┌─────────────┐   firing    ┌───────────────┐   HTTPS   ┌──────────┐
│ apiserver        │──(30s)───▶│ evaluates   │──alerts────▶│ route by      │──(bot)───▶│ chat     │
│ kubelet/cAdvisor │           │ Prometheus- │  (API 9093) │ severity,     │           │ 🔴 firing │
│ node-exporter    │           │ Rules       │             │ group,        │           │ ✅ resolved│
│ kube-state-      │           │ (defaults + │             │ inhibit       │           └──────────┘
│  metrics (+gotk) │           │  homelab +  │             │               │
│ flux controllers │           │  flux)      │             │ telegram      │
│ cert-manager     │           └─────────────┘             │ receiver      │
└──────────────────┘                 │                     └───────────────┘
                                     ▼
                              Grafana (read path:
                              dashboards over the
                              same metrics)
```

Everything left of Telegram is declared in this repo and reconciled by Flux.
The only out-of-band pieces are two manually created Secrets (bot token,
Grafana admin) — see [Secrets](#secrets-and-substitution).

## Worked example: certificate expiry → Telegram

The cluster has a family of certificate-expiry alarms out of the box (chart
default rules): `KubeClientCertificateExpiration` (client certs presented to
the apiserver) and `KubeletClientCertificateExpiration` /
`KubeletServerCertificateExpiration` (kubelet's own certs). They matter on
k3s specifically: k3s issues 1-year certificates and rotates them **only when
the k3s process restarts** within 90 days of expiry — a node that runs
uninterrupted for a year hits hard expiry and the whole control plane locks
up. This alarm is the early warning. Hop by hop:

**1. The metric.** The apiserver observes the expiry time of every client
certificate used against it and exposes it as a histogram on its own
`/metrics` endpoint:

```
apiserver_client_certificate_expiration_seconds_bucket{le="..."} ...
```

(Kubelet equivalents: `kubelet_certificate_manager_client_ttl_seconds`,
`kubelet_certificate_manager_server_ttl_seconds`.)

**2. The scrape.** kube-prometheus-stack ships a ServiceMonitor for the
apiserver (`job="apiserver"`); Prometheus scrapes it every 30s. Note the
network-policy subtlety: the monitoring namespace is default-deny and
`allow-prometheus` grants no explicit egress to 443/6443 — the scrape works
anyway because the k3s apiserver is **host-network**, and kube-router does not
police host-network endpoints. Convenient here, but it also masks missing
allow rules (see [Network layer](#the-network-layer-default-deny)).

**3. Rule evaluation.** The chart's default PrometheusRule
(`prometheus-stack-kube-prom-kubernetes-system-apiserver`) defines the alert
in two tiers — the standard severity ladder used across the stack:

```yaml
- alert: KubeClientCertificateExpiration   # < 7 days
  expr: histogram_quantile(0.01, sum without (namespace, service, endpoint)
          (rate(apiserver_client_certificate_expiration_seconds_bucket{job="apiserver"}[5m]))) < 604800
        and on (job, cluster, instance)
          apiserver_client_certificate_expiration_seconds_count{job="apiserver"} > 0
  for: 5m
  labels: {severity: warning}

- alert: KubeClientCertificateExpiration   # < 24 hours — same expr with < 86400
  labels: {severity: critical}
```

Reading the expr: "the 1st percentile of client-cert expiries seen by the
apiserver is under 7 days" — i.e. *some* client is presenting a nearly-dead
certificate. Once true for 5 minutes, Prometheus fires the alert to
Alertmanager (in-cluster, port 9093 — admitted by the `allow-alertmanager`
NetworkPolicy).

**4. Routing.** Alertmanager config lives inline in `prometheus-stack.yaml`:

```yaml
route:
  receiver: "null"                     # default: drop (Watchdog, info-level)
  group_by: ["alertname", "namespace"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  routes:
    - receiver: telegram
      matchers:
        - severity =~ "warning|critical"
inhibit_rules:
  - source_matchers: ['severity = "critical"']
    target_matchers: ['severity = "warning"']
    equal: ["alertname", "namespace"]
```

The **severity label is the delivery contract**: `warning`/`critical` page
Telegram; everything else dies on the null receiver. The inhibit rule keeps
the two-tier cert alarm polite — once the <24h critical fires, the <7d warning
for the same alertname+namespace is suppressed instead of double-paging.

**5. Delivery.** The telegram receiver:

```yaml
telegram_configs:
  - bot_token_file: /etc/alertmanager/secrets/alertmanager-telegram/token
    chat_id: ${TELEGRAM_CHAT_ID}      # substituted by Flux from cluster-config
    parse_mode: HTML
    send_resolved: true
```

Alertmanager calls `api.telegram.org` over HTTPS (the catch-all `- {}` egress
rule in `allow-alertmanager` covers DNS + 443) and the bot posts to the chat.
End-to-end latency for this alarm: ~6 minutes from the condition becoming true
(5m `for:` + 30s `group_wait` + scrape/eval intervals).

**6. On the phone:**

```
🔴 KubeClientCertificateExpiration (firing)
Client certificate is about to expire.
A client certificate used to authenticate to kubernetes apiserver is
expiring in less than 7.0 days on cluster .
```

…and a matching `✅ (resolved)` message when it clears (`send_resolved`).

## Rule sources

Three places define alerts; the operator only loads PrometheusRules labeled
`release: prometheus-stack` (chart default selector), so **custom rule files
must carry that label** or they are silently ignored.

| Source | Where | Covers |
|---|---|---|
| Chart default rules (~30 groups) | Rendered by kube-prometheus-stack | Cert expiry (this doc's example), apiserver SLOs, kubelet, node-exporter, KSM health, Prometheus/Alertmanager self-monitoring, Watchdog. Scheduler/controller-manager/etcd/kube-proxy groups are disabled — k3s doesn't expose them separately. |
| `homelab-alerts` | `infrastructure/monitoring/alerts.yaml` | Node resources (CPU/mem/disk >85%, NFS >80%), pod crash-looping, pod not-ready, PVC almost full. All `warning`. |
| `flux-alerts` | `infrastructure/monitoring/flux-alerts.yaml` | `FluxGitSourceNotReady` (**critical**, 5m) — the GitHub-token-expiry alarm, same "credential silently rots" family as cert expiry; `FluxReconciliationFailure` (warning, 15m); `FluxMetricsAbsent` (meta-alert: the Flux metrics themselves vanished, alerting is blind). |

## Metric sources

| Source | Discovered via | Notes |
|---|---|---|
| apiserver | chart ServiceMonitor | host-network; carries the cert-expiry histograms |
| kubelet / cAdvisor | chart ServiceMonitor | node + container metrics, kubelet cert TTLs |
| node-exporter | chart ServiceMonitor | host CPU/mem/disk/NFS for `homelab-alerts` |
| kube-state-metrics | chart ServiceMonitor | object states (`kube_*`) **plus** Flux CR readiness as `gotk_resource_info` via `customResourceState` (needs the RBAC `extraRules` in prometheus-stack.yaml) |
| Flux controllers | `PodMonitor` `flux-controllers` (`infrastructure/monitoring/flux-monitoring.yaml`) | PodMonitor, not ServiceMonitor: Flux Services don't expose the `http-prom` port — ServiceMonitors matched nothing, silently |
| cert-manager | chart-managed ServiceMonitor (`prometheus.servicemonitor.enabled`) | `certmanager_certificate_expiration_timestamp_seconds` is scraped but has **no alert rule yet** (cert-manager auto-renews; a rule would catch renewal *failure*) — known gap |

## Secrets and substitution

- **Telegram bot token** — the only real credential in the pipeline. Lives in
  the manually created `alertmanager-telegram` Secret (monitoring ns, key
  `token`), mounted by `alertmanagerSpec.secrets` and referenced via
  `bot_token_file`. It never appears in this (public) repo. Rotation: BotFather
  `/revoke` → update the Secret → delete the alertmanager pod.
- **Telegram chat id** — not a credential (useless without the token), so it
  lives in `clusters/homelab/cluster-config.yaml` and reaches the Alertmanager
  config as `${TELEGRAM_CHAT_ID}` via Flux `postBuild.substituteFrom`. As
  always: never `kubectl apply` files containing `${VAR}` — only Flux
  substitutes them.

## The network layer (default-deny)

The monitoring namespace denies all ingress and egress by default
(`k8s/core/security/network-policies.yaml`); the alerting path is carved out
explicitly:

- `allow-prometheus` — egress to scrape targets (9100 node-exporter, 8080
  KSM/Flux, 10250 kubelet), ingress 9090 for UI/Grafana.
- `allow-kube-state-metrics` — ingress 8080/8081 from Prometheus. This policy
  was originally missing: default-deny rejected every scrape and `kube_*` /
  `gotk_*` metrics silently never existed.
- `allow-alertmanager` — ingress 9093 from Prometheus, catch-all egress for
  Telegram/DNS. Its selectors originally used the legacy `app=` label that
  modern chart pods don't carry, so the policy **matched nothing** and
  Alertmanager sat mute behind default-deny for months.

Lessons encoded here (2026-07-05 incident): a NetworkPolicy with a wrong
selector fails silently — it just never applies; "connection refused"
pod-to-pod on k3s means kube-router netpol REJECT; and host-network paths
(apiserver, ingress-nginx) bypass netpol entirely, which can hide a broken
allow rule until a pod-network path needs it.

## Testing the pipe

Don't wait for a real expiry to learn the channel is dead. Inject a synthetic
alert straight into Alertmanager:

```bash
kubectl -n monitoring port-forward svc/prometheus-stack-kube-prom-alertmanager 9093:9093 &
curl -XPOST localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[{
  "labels": {"alertname": "PipeTest", "severity": "warning", "namespace": "monitoring"},
  "annotations": {"summary": "Synthetic test alert", "description": "Verifying Alertmanager → Telegram delivery"}
}]'
```

A 🔴 PipeTest message should reach Telegram within ~30s (`group_wait`), and a
✅ resolved follow-up a few minutes after the alert times out. If nothing
arrives, check delivery attempts in the logs:

```bash
kubectl -n monitoring logs alertmanager-prometheus-stack-kube-prom-alertmanager-0 | grep -i notify
```

UIs: only Grafana is exposed via ingress (`https://grafana.local` /
`https://grafana.${NODE_IP}.nip.io` — TLS from the homelab CA, login
required). Prometheus and Alertmanager deliberately have **no ingress**:
their UIs/APIs are unauthenticated, and LAN exposure would let anyone read
full cluster state, silence real alerts, or inject fakes into the Telegram
pipe. Port-forward on demand:

```bash
kubectl -n monitoring port-forward svc/prometheus-stack-kube-prom-prometheus 9090:9090
kubectl -n monitoring port-forward svc/prometheus-stack-kube-prom-alertmanager 9093:9093
```

Alertmanager's UI (localhost:9093) shows active alerts, silences, and the
rendered routing tree.

## Known gaps

- **No dead-man's switch.** The chart's always-firing `Watchdog` alert routes
  to null; nothing external notices if the whole monitoring stack (or the
  cluster, or the Telegram path) goes down — silence looks like health.
  `FluxMetricsAbsent` guards one internal blind spot only. Fix would be
  routing Watchdog to an external heartbeat service (e.g. healthchecks.io).
- **cert-manager certificates are unruled.** Expiry timestamps are scraped
  but no PrometheusRule watches them, so a stuck renewal (ACME failure, etc.)
  would only surface when clients start failing TLS.
