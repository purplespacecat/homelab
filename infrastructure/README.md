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
