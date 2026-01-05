# OpenTelemetry Observability Demo Guide

This guide explains the observability stack setup in your homelab and how to experiment with it.

## What Was Deployed

### 1. Grafana Tempo (Distributed Tracing)
- **Location**: `infrastructure/monitoring/tempo.yaml`
- **Purpose**: Collects and stores distributed traces
- **Access**: Internal only (via Grafana)
- **Storage**: NFS-backed persistent volume (10Gi, 7-day retention)

### 2. OpenTelemetry Demo Application
- **Location**: `infrastructure/applications/otel-demo.yaml`
- **Purpose**: Realistic microservices application with full observability
- **Namespace**: `otel-demo`
- **Components**:
  - 11 microservices (Go, Python, Java, Node.js, .NET)
  - OpenTelemetry Collector (aggregates telemetry)
  - Load generator (creates realistic traffic)
  - Kafka (for async messaging)

### 3. Updated Grafana Configuration
- **Location**: `infrastructure/monitoring/prometheus-stack.yaml`
- **Changes**:
  - Added Prometheus as explicit data source
  - Added Tempo as data source
  - Configured trace-to-log correlation
  - Configured trace-to-metrics correlation

### 4. Network Policies
- **Location**:
  - `k8s/core/security/network-policies.yaml` (monitoring namespace)
  - `k8s/core/security/otel-demo-network-policies.yaml` (otel-demo namespace)
- **Purpose**: Secure communication between components

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     OpenTelemetry Demo App                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ Frontend │  │   Cart   │  │ Checkout │  │ Payment  │  │
│  │ (Go)     │→ │ (Redis)  │→ │ (Go)     │→ │ (Node.js)│  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
│       ↓              ↓              ↓              ↓        │
│  ┌────────────────────────────────────────────────────┐   │
│  │        OpenTelemetry Collector                     │   │
│  │   (Receives traces/metrics from all services)      │   │
│  └─────────────────┬──────────────────────────────────┘   │
└────────────────────┼──────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        ↓            ↓            ↓
   ┌────────┐  ┌─────────┐  ┌──────────┐
   │ Tempo  │  │Prometheus│ │   Loki   │
   │(Traces)│  │(Metrics) │ │  (Logs)  │
   └────┬───┘  └─────┬────┘ └────┬─────┘
        │            │            │
        └────────────┼────────────┘
                     ↓
              ┌──────────┐
              │ Grafana  │
              │  (UI)    │
              └──────────┘
```

## How It Works

### Distributed Tracing Flow

1. **User action** (e.g., "Add to cart")
   - Frontend receives HTTP request
   - Generates a unique `trace_id`

2. **Service calls**
   - Frontend → Cart Service (trace_id propagated)
   - Cart Service → Product Service (same trace_id)
   - Each service creates "spans" (units of work)

3. **Trace collection**
   - Each service sends spans to OpenTelemetry Collector (OTLP protocol)
   - Collector batches and forwards to Tempo

4. **Storage**
   - Tempo stores complete trace
   - Indexed by trace_id, service, operation

5. **Query in Grafana**
   - Search traces by service, duration, errors
   - Visualize entire request flow
   - Jump from trace → logs → metrics

## Hands-On Experiments

### Experiment 1: View Your First Trace

1. Access Grafana: `http://grafana.192.168.100.98.nip.io`
2. Navigate to **Explore** (compass icon)
3. Select **Tempo** data source
4. Click **Search** tab
5. Select service: `frontend`
6. Click **Run query**
7. Click on any trace to see the full waterfall view

**What to observe:**
- Total request duration
- Individual span durations
- Service dependencies
- Error spans (red)

### Experiment 2: Correlate Traces with Logs

1. In a trace view, click on any span
2. Click **Logs for this span**
3. Grafana automatically queries Loki with the trace_id
4. See logs from that exact request

**What this shows:**
- How trace context appears in logs
- Debugging a request end-to-end
- Finding the root cause of errors

### Experiment 3: Correlate Traces with Metrics

1. In Grafana, go to **Explore**
2. Select **Prometheus** data source
3. Query: `rate(http_server_duration_bucket{service_name="frontend"}[5m])`
4. Click on a data point
5. Click **Exemplars** (if available)
6. Jump directly to traces for that time period

**What this shows:**
- Metrics tell you "what" is slow
- Traces tell you "why" it's slow

### Experiment 4: Generate Load and Observe

The load generator continuously creates traffic. Let's watch it:

1. Check load generator logs:
   ```bash
   kubectl logs -n otel-demo -l app.kubernetes.io/component=loadgenerator --tail=50
   ```

2. In Grafana, create a dashboard:
   - **Metrics**: Request rate, latency, error rate
   - **Traces**: Recent traces filtered by high duration
   - **Logs**: Error logs from services

3. Refresh and watch live data

### Experiment 5: Simulate a Failure

1. Kill a service pod:
   ```bash
   kubectl delete pod -n otel-demo -l app.kubernetes.io/component=cartService
   ```

2. Observe in Grafana:
   - Traces showing errors (red spans)
   - Metrics showing increased error rate
   - Logs showing connection failures

3. Watch Kubernetes restart the pod
4. See traces return to normal

### Experiment 6: Explore the Service Graph

1. In Grafana, go to **Explore**
2. Select **Tempo** data source
3. Click **Service Graph** tab
4. See visual representation of service dependencies

**What to observe:**
- Request rates between services
- Error rates on edges
- Latency distribution

### Experiment 7: Search for Slow Requests

1. In Grafana → Explore → Tempo
2. Set search criteria:
   - Service: `checkoutService`
   - Min duration: `500ms`
3. Find traces that took longer than 500ms
4. Investigate which spans are slow

## PromQL Queries for Observability

Try these in Grafana (Prometheus data source):

```promql
# Request rate by service
sum(rate(http_server_duration_count[5m])) by (service_name)

# 95th percentile latency
histogram_quantile(0.95, sum(rate(http_server_duration_bucket[5m])) by (le, service_name))

# Error rate
sum(rate(http_server_duration_count{status_code=~"5.."}[5m])) by (service_name)

# Pod CPU usage
rate(container_cpu_usage_seconds_total{namespace="otel-demo"}[5m])

# Pod memory usage
container_memory_working_set_bytes{namespace="otel-demo"}
```

## LogQL Queries for Logs

Try these in Grafana (Loki data source):

```logql
# All logs from otel-demo
{namespace="otel-demo"}

# Errors only
{namespace="otel-demo"} |= "error" or "ERROR"

# Logs from a specific service
{namespace="otel-demo", app_kubernetes_io_component="frontend"}

# Logs for a specific trace
{namespace="otel-demo"} | json | trace_id="<paste-trace-id-here>"

# Count errors per service
sum(count_over_time({namespace="otel-demo"} |= "error" [5m])) by (app_kubernetes_io_component)
```

## Understanding the Components

### OpenTelemetry Collector
- **What**: Central hub for telemetry data
- **Why**: Decouples instrumentation from backends
- **Location**: Runs as sidecar in each pod
- **Config**: `infrastructure/applications/otel-demo.yaml` (lines 16-39)

### Tempo
- **What**: Distributed tracing backend
- **Storage**: Local disk (backed by NFS)
- **Retention**: 7 days (168h)
- **Query**: Via Grafana only (no UI)

### ServiceMonitor
- **What**: Tells Prometheus which services to scrape
- **How**: Prometheus Operator watches for these CRDs
- **Demo**: Automatically created for otel-demo services

## Cleanup (Optional)

To remove the demo (keep Tempo for future use):

```bash
# Delete just the demo app
kubectl delete helmrelease otel-demo -n otel-demo
kubectl delete namespace otel-demo

# To also remove Tempo
kubectl delete helmrelease tempo -n monitoring
```

To remove everything:

```bash
git checkout main
git branch -D observability-demo-setup
```

## Next Steps

1. **Custom Instrumentation**: Add OpenTelemetry to your own apps
2. **Custom Dashboards**: Create dashboards for specific services
3. **Alerting**: Set up alerts on high latency or error rates
4. **Distributed Tracing in Practice**: Deploy a real microservice
5. **Add Grafana Tempo UI**: Deploy tempo-query for standalone UI

## Troubleshooting

### Traces not appearing in Tempo

1. Check collector logs:
   ```bash
   kubectl logs -n otel-demo -l app.kubernetes.io/component=opentelemetry-collector
   ```

2. Check Tempo logs:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=tempo
   ```

3. Verify network connectivity:
   ```bash
   kubectl exec -n otel-demo <collector-pod> -- wget -O- http://tempo.monitoring.svc.cluster.local:4317
   ```

### Tempo data source not working in Grafana

1. Check Tempo service:
   ```bash
   kubectl get svc -n monitoring tempo
   ```

2. Test from Grafana pod:
   ```bash
   kubectl exec -n monitoring <grafana-pod> -- wget -qO- http://tempo:3100/ready
   ```

3. Check network policies:
   ```bash
   kubectl get networkpolicy -n monitoring allow-tempo -o yaml
   ```

## Resources

- [OpenTelemetry Demo Documentation](https://opentelemetry.io/docs/demo/)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Distributed Tracing Guide](https://opentelemetry.io/docs/concepts/observability-primer/#distributed-traces)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
- [LogQL Cheat Sheet](https://megamorf.gitlab.io/cheat-sheets/loki/)
