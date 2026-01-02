# Loki Logging Setup Guide for Homelab

## Current Status

### ✅ Working
- **Flux CD**: GitOps sync is working, all Kustomizations reconciling
- **Prometheus Stack**: Successfully deployed
  - Prometheus: Collecting metrics
  - Alertmanager: Running
  - Grafana: Deployed (pending ConfigMap creation by operator)
  - Prometheus Operator: Running
  - Node Exporter & Kube State Metrics: Running
- **Flux Metrics**: ServiceMonitors created for Flux controllers
- **NFS Storage**: Dynamic provisioning working after fixes

### ⚠️ Issues Encountered
- **Loki**: Configuration not applying correctly (retention config error)
- **Grafana**: Waiting for Prometheus Operator to create ConfigMaps

## Lessons Learned

### 1. NFS Storage Issues

**Problem**: PVCs couldn't bind due to missing `/data/persistentvolumes` directory.

**Solution**:
```bash
# On NFS server (192.168.100.98)
sudo rm -f /data/persistentvolumes
sudo mkdir -p /data/persistentvolumes
sudo chmod 777 /data/persistentvolumes

# Restart NFS provisioner to pick up changes
kubectl delete pod -n kube-system -l app=nfs-subdir-external-provisioner
```

### 2. Circular Dependencies in Flux

**Problem**: `metallb-config` and `cert-manager-config` Kustomizations had circular dependencies with their parent Kustomizations.

**Fix**: Removed `dependsOn` from nested Kustomizations in:
- `infrastructure/networking/metallb.yaml`
- `infrastructure/security/cert-manager.yaml`

### 3. MetalLB Webhook Issues

**Problem**: Stale webhook service from old installation.

**Solution**:
```bash
kubectl delete svc metallb-webhook-service -n metallb-system
kubectl delete validatingwebhookconfiguration metallb-webhook-configuration
flux reconcile helmrelease metallb -n metallb-system
```

## Loki Setup - Recommended Approach

### Option 1: Minimal Loki (Recommended for Homelab)

Use a simpler Loki deployment without retention enabled to avoid config complexity:

```yaml
# infrastructure/monitoring/loki-simple.yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: loki
  namespace: monitoring
spec:
  interval: 5m
  chart:
    spec:
      chart: loki
      version: 6.24.0
      sourceRef:
        kind: HelmRepository
        name: grafana
        namespace: flux-system
  values:
    deploymentMode: SingleBinary

    loki:
      auth_enabled: false
      commonConfig:
        replication_factor: 1
        path_prefix: /var/loki

      storage:
        type: filesystem

      schemaConfig:
        configs:
          - from: "2024-01-01"
            store: tsdb
            object_store: filesystem
            schema: v13
            index:
              prefix: index_
              period: 24h

    singleBinary:
      replicas: 1
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 500m
          memory: 512Mi
      persistence:
        enabled: true
        storageClass: nfs-client
        size: 10Gi

    # Disable resource-heavy components
    chunksCache:
      enabled: false
    resultsCache:
      enabled: false
    lokiCanary:
      enabled: false
    backend:
      replicas: 0
    read:
      replicas: 0
    write:
      replicas: 0

    gateway:
      enabled: true
      replicas: 1

    monitoring:
      serviceMonitor:
        enabled: true
```

### Option 2: Loki with Retention (Advanced)

For proper retention, you need to configure the compactor correctly:

```yaml
loki:
  compactor:
    working_directory: /var/loki/compactor
    retention_enabled: true
    retention_delete_delay: 2h
    delete_request_store: filesystem  # Critical for retention!

  limits_config:
    retention_period: 48h
    retention_delete_enabled: true
```

### Promtail Configuration

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: promtail
  namespace: monitoring
spec:
  interval: 5m
  chart:
    spec:
      chart: promtail
      version: 6.16.6
      sourceRef:
        kind: HelmRepository
        name: grafana
        namespace: flux-system
  dependsOn:
    - name: loki
  values:
    config:
      clients:
        - url: http://loki-gateway/loki/api/v1/push

      snippets:
        scrapeConfigs: |
          - job_name: kubernetes-pods
            pipeline_stages:
              - cri: {}
            kubernetes_sd_configs:
              - role: pod
            relabel_configs:
              - source_labels: [__meta_kubernetes_pod_node_name]
                target_label: __host__
              - action: labelmap
                regex: __meta_kubernetes_pod_label_(.+)
              - source_labels: [__meta_kubernetes_namespace]
                target_label: namespace
              - source_labels: [__meta_kubernetes_pod_name]
                target_label: pod
              - source_labels: [__meta_kubernetes_pod_container_name]
                target_label: container
              - replacement: /var/log/pods/*$1/*.log
                separator: /
                source_labels:
                  - __meta_kubernetes_pod_uid
                  - __meta_kubernetes_pod_container_name
                target_label: __path__

    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 128Mi

    serviceMonitor:
      enabled: true
```

## Network Policies

Ensure you have network policies allowing log collection:

```yaml
# Already in k8s/core/security/network-policies.yaml
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-loki
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: loki
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    ports:
    - protocol: TCP
      port: 3100
  egress:
  - {}  # Allow all egress for storage access
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-promtail
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: promtail
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: loki
    ports:
    - protocol: TCP
      port: 3100
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
```

## Grafana Datasource Configuration

Add Loki to Grafana (already configured in prometheus-stack.yaml):

```yaml
grafana:
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki-gateway:80
      access: proxy
      isDefault: false
      jsonData:
        maxLines: 1000
```

## Troubleshooting Guide

### Loki Won't Start

1. **Check config error**:
   ```bash
   kubectl logs -n monitoring loki-0 -c loki
   ```

2. **Common errors**:
   - `compactor.delete-request-store should be configured`: Add `delete_request_store: filesystem` to compactor config
   - `failed to create directory`: Check NFS permissions and paths

3. **Restart Loki**:
   ```bash
   kubectl delete pod loki-0 -n monitoring
   ```

### PVC Not Binding

1. **Check NFS provisioner**:
   ```bash
   kubectl logs -n kube-system -l app=nfs-subdir-external-provisioner
   ```

2. **Verify NFS directories exist**:
   ```bash
   ls -la /data/persistentvolumes/
   ```

3. **Restart NFS provisioner**:
   ```bash
   kubectl delete pod -n kube-system -l app=nfs-subdir-external-provisioner
   ```

### Promtail Not Collecting Logs

1. **Check Promtail logs**:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=promtail
   ```

2. **Verify connectivity to Loki**:
   ```bash
   kubectl exec -n monitoring -l app.kubernetes.io/name=promtail -- wget -O- http://loki-gateway/ready
   ```

### Grafana ConfigMaps Missing

This is normal during initial deployment - Prometheus Operator creates them. Wait for operator to be fully ready:

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-operator
```

## Useful LogQL Queries

### Basic Queries

```logql
# All logs from a namespace
{namespace="flux-system"}

# Logs from specific pod
{namespace="monitoring", pod="loki-0"}

# Search for errors
{namespace="monitoring"} |= "error"

# Exclude info logs
{namespace="monitoring"} != "info"
```

### Advanced Queries

```logql
# Count errors per minute by pod
sum(rate({namespace="monitoring"} |= "error" [1m])) by (pod)

# Failed reconciliations in Flux
{namespace="flux-system"} |~ "(?i)failed|error" | json | status="Failed"

# Container restarts
{namespace="monitoring"} |= "restarting" | pattern `<_> <pod> <_> restarts=<restarts>`
```

## Maintenance

### Manual Log Cleanup

Without retention enabled, clean up old logs manually:

```bash
# On NFS server
find /data/persistentvolumes -name "*.log" -mtime +7 -delete
```

### Check Resource Usage

```bash
# Check Loki storage usage
kubectl exec -n monitoring loki-0 -- df -h /var/loki

# Check pod resource usage
kubectl top pod -n monitoring -l app.kubernetes.io/name=loki
```

## Next Steps

1. **Fix current Loki deployment**: The config changes aren't applying due to Helm chart caching or incorrect structure
2. **Alternative**: Delete current Loki and redeploy with simplified config above
3. **Add Grafana dashboards**: Import Loki dashboard (ID: 13639) in Grafana
4. **Set up alerts**: Create PrometheusRules for log-based alerts

## Clean Slate Deployment

If all else fails, start fresh:

```bash
# 1. Suspend and delete Loki
flux suspend helmrelease loki -n monitoring
kubectl delete helmrelease loki -n monitoring
kubectl delete pod loki-0 -n monitoring
kubectl delete pvc storage-loki-0 -n monitoring

# 2. Update the HelmRelease YAML with simplified config above
# 3. Resume
flux resume helmrelease loki -n monitoring
```

## Summary of What Works

- ✅ Flux CD GitOps
- ✅ Prometheus metrics collection
- ✅ Flux controller metrics via ServiceMonitors
- ✅ Network policies for monitoring
- ✅ NFS dynamic provisioning (after fixes)
- ✅ Prometheus Operator
- ⏳ Loki (needs config fix or clean redeploy)
- ⏳ Grafana (waiting for operator ConfigMaps)

## Resources

- Loki Helm Chart: https://github.com/grafana/loki/tree/main/production/helm/loki
- LogQL Documentation: https://grafana.com/docs/loki/latest/query/
- Grafana Loki Dashboard: https://grafana.com/grafana/dashboards/13639
