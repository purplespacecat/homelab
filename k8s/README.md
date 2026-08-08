# Raw Kubernetes manifests

Everything in this directory is plain YAML applied by Flux Kustomizations
(no Helm). Chart-based components live in `../infrastructure/` as
HelmReleases with inline values.

## Layout

```
k8s/
├── core/
│   ├── namespaces/            # ingress-nginx, monitoring, media, diagnostics
│   ├── networking/
│   │   └── metallb-config.yaml    # IP pool + L2Advertisement (${VAR}-substituted)
│   ├── storage/
│   │   ├── nfs-config.yaml            # NFS server address ConfigMap
│   │   └── local-path-storageclass.yaml   # pins k3s local-path non-default
│   └── security/
│       └── network-policies.yaml  # default-deny + allow rules, monitoring ns
└── cert-manager/
    └── local-ca.yaml          # self-signed root → homelab-ca-issuer
```

## The pieces

**Namespaces** — created here (and in `infrastructure/core/namespaces.yaml`)
so Kustomizations can depend on them existing before charts install into
them.

**MetalLB config** — pool `${METALLB_IP_RANGE}` advertised on
`${NETWORK_INTERFACE}`. Values come from `clusters/homelab/cluster-config.yaml`
through Flux substitution, so this file must never be applied by hand.

**Storage** — the NFS ConfigMap points at the export; the StorageClass file
exists because k3s re-marks `local-path` as default on every restart, and
Flux owning the annotation pins it back to `"false"`. The file must mirror
the live spec exactly — StorageClass spec fields are immutable.

**NetworkPolicies** — the monitoring namespace is default-deny both
directions, with per-workload allow policies. This file is not
`${VAR}`-substituted, which is why the node IP appears literally in the
`ipBlock` rules (with a comment). The two recurring mistakes when editing
here: `namespaceSelector` egress can never reach node-IP destinations
(apiserver DNAT, node-exporter, kubelet — use port-only rules or `ipBlock`),
and a selector that matches no pods fails silently. After any change,
verify from inside a pod, and remember established connections keep working
until restart — a broken rule can hide behind conntrack for weeks.

**Homelab CA** — a self-signed root feeding `homelab-ca-issuer`, which signs
Grafana's certificate. There is no public/ACME issuer: the cluster is
LAN-only and can't answer HTTP-01 challenges. Jellyfin's ingress is plain
HTTP by choice.

## Making changes

Edit, commit, push — Flux applies within a minute. See
[../docs/flux.md](../docs/flux.md) for the workflow and
[../docs/NETWORKING.md](../docs/NETWORKING.md) for ingress and NetworkPolicy
details.
