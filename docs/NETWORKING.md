# Networking

How traffic reaches services on this cluster: DNS, ingress, and the WiFi
constraint that shaped the whole design.

## The short version

The node (`spaceship`, 192.168.100.98) is on WiFi. MetalLB's L2 mode is
unreliable over WiFi — L2 advertisement depends on ARP behavior that WiFi
adapters often mangle — so NGINX Ingress runs with `hostNetwork: true`
instead, binding ports 80/443 directly on the node IP. HTTP(S) services need
no LoadBalancer at all. Hostnames use nip.io, so nothing needs a DNS server.

```
browser → grafana.192.168.100.98.nip.io
        → nip.io DNS answers 192.168.100.98
        → node ports 80/443 (NGINX, hostNetwork DaemonSet)
        → routes by hostname to a ClusterIP Service
        → pod
```

MetalLB stays installed for non-HTTP services (databases and the like) with
the pool `192.168.100.200-250`, but nothing currently uses it.

## nip.io

`anything.192.168.100.98.nip.io` resolves to `192.168.100.98` — the nip.io
DNS servers parse the IP out of the hostname. No configuration anywhere, and
it works from any device on the LAN.

If nip.io is ever blocked (some networks filter it):

- **sslip.io** is the same idea: `grafana.192-168-100-98.sslip.io` (dashes).
- **hosts-file entries** work per device: `192.168.100.98 grafana.local`.
  The Grafana ingress already answers to `grafana.local` as a second host.
- A local DNS server (Pi-hole, dnsmasq) with a wildcard record is the
  permanent fix if this becomes a real problem.

## What's exposed today

| Service | URL | TLS |
|---|---|---|
| Grafana | `https://grafana.192.168.100.98.nip.io` (also `grafana.local`) | homelab CA, login required |
| Jellyfin | `http://jellyfin.192.168.100.98.nip.io` | none (LAN-only, by choice) |
| Prometheus | no ingress | — |
| Alertmanager | no ingress | — |

Prometheus and Alertmanager deliberately have no ingress: their UIs are
unauthenticated, and LAN exposure would let any device read cluster state or
silence alerts. Reach them with a port-forward when needed:

```bash
kubectl -n monitoring port-forward svc/prometheus-stack-kube-prom-prometheus 9090:9090
kubectl -n monitoring port-forward svc/prometheus-stack-kube-prom-alertmanager 9093:9093
```

Don't add ingresses for them.

## Configuration lives in

- **NGINX Ingress:** `infrastructure/networking/ingress-nginx.yaml` —
  `hostNetwork: true`, DaemonSet, ClusterIP service. Values are inline in
  the HelmRelease.
- **MetalLB pool + L2Advertisement:** `k8s/core/networking/metallb-config.yaml`,
  parameterized by `${METALLB_IP_RANGE}` and `${NETWORK_INTERFACE}` from
  `clusters/homelab/cluster-config.yaml`. Change it there and push — never
  `kubectl apply` this file; the `${VAR}` placeholders only resolve through
  Flux.
- **Ingress rules:** inline in each HelmRelease's values (see the `ingress:`
  blocks in `prometheus-stack.yaml` and `jellyfin.yaml`).

## Adding an ingress for a new service

HTTP-only (the Jellyfin pattern):

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: myservice.${NODE_IP}.nip.io
      paths:
        - path: /
          pathType: Prefix
```

HTTPS with the homelab CA (the Grafana pattern) — add the issuer annotation
and a `tls:` block:

```yaml
annotations:
  cert-manager.io/cluster-issuer: homelab-ca-issuer
tls:
  - hosts:
      - myservice.${NODE_IP}.nip.io
    secretName: myservice-tls   # cert-manager creates this
```

`${NODE_IP}` works only in files Flux substitutes — raw-manifest ingresses
outside those paths need the literal IP.

There is no public-certificate issuer. The cluster is LAN-only, so ACME
HTTP-01 challenges can't reach it; the old Let's Encrypt issuer was removed.
Browsers trust the homelab CA after a one-time import:

```bash
./scripts/common/extract-ca-cert.sh   # then import homelab-ca.crt
# Linux: /usr/local/share/ca-certificates/ + sudo update-ca-certificates
# macOS: Keychain → Always Trust    Windows: Trusted Root CAs store
```

## Non-HTTP services

Give the Service `type: LoadBalancer`; MetalLB assigns an IP from
192.168.100.200-250 and advertises it over L2 on `wlp2s0`. Expect this to be
flaky over WiFi — it's why the HTTP path avoids MetalLB entirely. If a
non-HTTP service matters, wired ethernet for the node is the real fix.

## Troubleshooting

**Nothing loads.** Is it DNS or the node? `ping 192.168.100.98` first — the
node is a laptop and is sometimes just off. Then
`nslookup grafana.192.168.100.98.nip.io` (should echo the IP back).

**DNS fine, connection refused.** Check NGINX is up and actually bound to
the node ports:

```bash
kubectl get pods -n ingress-nginx
# on the node:
sudo ss -tlnp | grep -E ':80|:443'
```

**NGINX up, wrong response.** Route problem:

```bash
kubectl get ingress -A                    # host registered?
kubectl describe ingress <name> -n <ns>   # backend healthy?
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=30
```

**Pod-to-pod connection refused in monitoring.** That namespace is
default-deny — a NetworkPolicy is rejecting it, and on k3s the REJECT comes
from kube-router. See `k8s/core/security/network-policies.yaml`. Two sharp
edges that have each caused a silent outage here:

- An egress rule with `namespaceSelector` matches pod IPs only. The API
  server, node-exporter, and the kubelet all live on the **node IP** — those
  need a port-only rule (API) or an explicit `ipBlock` (node ports).
- hostNetwork pods (NGINX, the apiserver) bypass NetworkPolicy entirely, so
  a broken allow rule can hide until a pod-network path exercises it.

**MetalLB not assigning.** `kubectl get ipaddresspool,l2advertisement -n
metallb-system`, then remember the WiFi caveat above.
