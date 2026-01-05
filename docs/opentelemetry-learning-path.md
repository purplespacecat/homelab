# OpenTelemetry Learning Path: Hands-On Guide

A structured, hands-on approach to learning distributed tracing, metrics, and logs correlation using your homelab OpenTelemetry Demo.

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Level 1: Understanding the Basics](#level-1-understanding-the-basics)
   - [Exercise 1.1: View Your First Trace](#exercise-11-view-your-first-trace)
   - [Exercise 1.2: Understanding Trace Structure](#exercise-12-understanding-trace-structure)
   - [Exercise 1.3: Reading the Service Graph](#exercise-13-reading-the-service-graph)
3. [Level 2: Correlating Observability Signals](#level-2-correlating-observability-signals)
   - [Exercise 2.1: From Trace to Logs](#exercise-21-from-trace-to-logs)
   - [Exercise 2.2: From Metrics to Traces](#exercise-22-from-metrics-to-traces)
   - [Exercise 2.3: Full Investigation Flow](#exercise-23-full-investigation-flow)
4. [Level 3: Performance Analysis](#level-3-performance-analysis)
   - [Exercise 3.1: Finding Slow Requests](#exercise-31-finding-slow-requests)
   - [Exercise 3.2: Identifying Bottlenecks](#exercise-32-identifying-bottlenecks)
   - [Exercise 3.3: Analyzing Latency Patterns](#exercise-33-analyzing-latency-patterns)
5. [Level 4: Error Investigation](#level-4-error-investigation)
   - [Exercise 4.1: Finding Error Traces](#exercise-41-finding-error-traces)
   - [Exercise 4.2: Root Cause Analysis](#exercise-42-root-cause-analysis)
   - [Exercise 4.3: Error Rate Monitoring](#exercise-43-error-rate-monitoring)
6. [Level 5: Advanced Topics](#level-5-advanced-topics)
   - [Exercise 5.1: Understanding Context Propagation](#exercise-51-understanding-context-propagation)
   - [Exercise 5.2: Analyzing Kafka Message Flow](#exercise-52-analyzing-kafka-message-flow)
   - [Exercise 5.3: Creating Custom Dashboards](#exercise-53-creating-custom-dashboards)
7. [Level 6: Chaos Engineering](#level-6-chaos-engineering)
   - [Exercise 6.1: Pod Failure Scenario](#exercise-61-pod-failure-scenario)
   - [Exercise 6.2: Cascading Failures](#exercise-62-cascading-failures)
   - [Exercise 6.3: Recovery Observation](#exercise-63-recovery-observation)
8. [Reference Material](#reference-material)
9. [Troubleshooting](#troubleshooting)
10. [Next Steps](#next-steps)

---

## Getting Started

### Prerequisites

- ✅ Grafana accessible at: `http://grafana.192.168.100.98.nip.io`
- ✅ OTel Demo pods running in `otel-demo` namespace
- ✅ Tempo, Prometheus, and Loki configured as data sources

### Quick Check

Verify everything is running:

```bash
# Check all pods are ready
kubectl get pods -n otel-demo

# You should see ~24 pods, most with status Running
# If some are still starting, wait a few minutes
```

### Access Grafana

1. Open: `http://grafana.192.168.100.98.nip.io`
2. Login: `admin` / `admin`
3. Navigate to **Explore** (compass icon on left sidebar)

---

## Level 1: Understanding the Basics

**Goal**: Understand what a distributed trace is and how to read it.

### Exercise 1.1: View Your First Trace

**What you'll learn**: How to find and view traces in Grafana.

**Steps**:

1. In Grafana **Explore**, select **Tempo** data source (top dropdown)
2. Click the **Search** tab
3. Click **Service Name** dropdown → Select `frontend`
4. Click **Run query** (top right)
5. You'll see a list of traces - click on any one

**What to observe**:

- **Trace ID**: Unique identifier for this request (e.g., `a7f3b2c...`)
- **Duration**: Total time from start to finish
- **Spans**: Number of operations in this trace
- **Waterfall view**: Timeline showing when each service was called

**Questions to answer**:

- Q: How long did this request take end-to-end?
- Q: How many different services were involved?
- Q: Which service took the longest?

**Success criteria**: You can see a waterfall diagram showing multiple services.

---

### Exercise 1.2: Understanding Trace Structure

**What you'll learn**: How traces are composed of spans.

**Steps**:

1. In the trace you opened, look at the waterfall view
2. Click on the first span (usually `frontend`)
3. Expand it to see child spans
4. Click on different spans to see their details

**What to observe**:

- **Parent-child relationships**: Indentation shows which service called which
- **Span attributes**: Tags like `http.method`, `http.status_code`
- **Timing**: Start time and duration of each operation
- **Service names**: Which microservice handled this span

**Key concepts**:

```
Trace: Complete request journey
  └─ Span: Single operation (e.g., "GET /cart")
      └─ Child Span: Operation called by parent (e.g., "Redis GET")
```

**Example trace structure**:

```
frontend: GET /cart (100ms)
  ├─ cartservice: getCart() (50ms)
  │   └─ redis: GET user:123 (10ms)
  └─ recommendationservice: getRecommendations() (40ms)
      └─ productcatalogservice: listProducts() (30ms)
```

**Questions to answer**:

- Q: What HTTP method was used? (Look at `http.method` attribute)
- Q: What was the response status code?
- Q: Which span had the longest self-time (excluding children)?

**Success criteria**: You understand that spans represent operations and form a tree structure.

---

### Exercise 1.3: Reading the Service Graph

**What you'll learn**: Visualize how services communicate.

**Steps**:

1. In Grafana **Explore**, select **Tempo** data source
2. Click the **Service Graph** tab
3. Observe the visual representation of service dependencies

**What to observe**:

- **Nodes**: Each circle is a service
- **Arrows**: Show direction of communication (A → B means A calls B)
- **Colors**: May indicate error rates or latency
- **Request rates**: Numbers on arrows show requests per second

**Questions to answer**:

- Q: Which service is called most frequently?
- Q: Which services talk directly to the database/redis?
- Q: Can you identify the "entry point" service (most incoming, few outgoing)?

**Success criteria**: You can identify the main request flow through the system.

---

## Level 2: Correlating Observability Signals

**Goal**: Learn to jump between traces, logs, and metrics.

### Exercise 2.1: From Trace to Logs

**What you'll learn**: How to find logs related to a specific trace.

**Steps**:

1. In a trace view, click on any span
2. In the span details panel, click **Logs for this span**
3. Grafana will automatically query Loki with the trace ID
4. You'll see logs from that exact request

**What to observe**:

- **Trace context in logs**: Look for `trace_id` field in logs
- **Automatic filtering**: Loki query includes the trace ID
- **Time correlation**: Logs are from the same timeframe as the span

**Example LogQL query** (auto-generated):

```logql
{namespace="otel-demo"} | json | trace_id="a7f3b2c..."
```

**Practical scenario**:

You see an error span in a trace. Jump to logs to see:
- Error messages
- Stack traces
- Debug information

**Questions to answer**:

- Q: What log level appears most? (INFO, ERROR, DEBUG)
- Q: Can you find the trace_id in the raw log output?

**Success criteria**: You can navigate from a trace to its logs in one click.

---

### Exercise 2.2: From Metrics to Traces

**What you'll learn**: Use metrics to find interesting traces.

**Steps**:

1. In Grafana **Explore**, select **Prometheus** data source
2. Run this query:
   ```promql
   histogram_quantile(0.95,
     sum(rate(http_server_duration_bucket{service_name="frontend"}[5m])) by (le)
   )
   ```
3. This shows 95th percentile latency for the frontend
4. Look for **Exemplars** (small dots on the graph)
5. Click an exemplar to jump to its trace

**What to observe**:

- **Metrics show patterns**: Overall performance trends
- **Exemplars link to traces**: Sample traces for that metric value
- **Representative examples**: See actual requests behind the metric

**Key concept**: Exemplars are traces that Prometheus stores alongside metrics.

**Questions to answer**:

- Q: What's the 95th percentile latency?
- Q: When you click an exemplar, does that trace match the latency shown?

**Success criteria**: You can jump from a metric spike to an example trace.

---

### Exercise 2.3: Full Investigation Flow

**What you'll learn**: Real-world debugging workflow.

**Scenario**: Users report the site is slow.

**Investigation steps**:

1. **Start with metrics** (Prometheus):
   ```promql
   # Request rate
   sum(rate(http_server_duration_count{service_name="frontend"}[5m]))

   # Error rate
   sum(rate(http_server_duration_count{http_status_code=~"5.."}[5m]))

   # Latency
   histogram_quantile(0.95, sum(rate(http_server_duration_bucket[5m])) by (le, service_name))
   ```

2. **Find slow traces** (Tempo):
   - Service: `frontend`
   - Min duration: `500ms`
   - Find traces exceeding normal latency

3. **Analyze the trace**:
   - Which service is slow?
   - Which span has the highest duration?

4. **Check logs** (Loki):
   - Click "Logs for this span"
   - Look for errors, warnings, or slow queries

5. **Correlate**:
   - Does this happen at a specific time?
   - Is it affecting all requests or just some?

**Success criteria**: You can go from "site is slow" to identifying which specific operation is causing the slowdown.

---

## Level 3: Performance Analysis

**Goal**: Learn to identify and diagnose performance issues.

### Exercise 3.1: Finding Slow Requests

**What you'll learn**: Use TraceQL to find performance problems.

**Steps**:

1. In Grafana **Explore** → **Tempo**
2. Click **Search** tab
3. Set filters:
   - Service: `checkoutservice`
   - Min duration: `1000ms` (1 second)
4. Run query

**What to observe**:

- **Outliers**: Requests much slower than average
- **Common patterns**: Do slow requests share attributes?

**Advanced TraceQL query**:

```traceql
{ duration > 1s && service.name="checkoutservice" }
```

**Questions to investigate**:

- Q: What percentage of requests are slow?
- Q: Do they all hit the same endpoint?
- Q: Do they all have similar span structures?

**Success criteria**: You can filter traces by duration to find performance issues.

---

### Exercise 3.2: Identifying Bottlenecks

**What you'll learn**: Find which service or operation is the slowest.

**Steps**:

1. Find a slow trace (duration > 1s)
2. Look at the waterfall view
3. Calculate each span's **self-time** (duration minus children)

**What to observe**:

- **Long spans**: Which operations take the most time?
- **Sequential vs parallel**: Are services called in series or parallel?
- **Database calls**: Look for Redis, database query spans

**Example analysis**:

```
Total request: 2.5s
├─ frontend: 2.5s (10ms self-time)
├─ checkoutservice: 2.4s (50ms self-time)
│   ├─ paymentservice: 1.5s (self-time: 1.5s) ← BOTTLENECK!
│   └─ shippingservice: 800ms
```

**The bottleneck is paymentservice** - it took 1.5s with no external calls.

**Questions to answer**:

- Q: Which service has the highest self-time?
- Q: Could any operations be parallelized?
- Q: Are there unnecessary repeated calls?

**Success criteria**: You can identify which specific operation is causing slowness.

---

### Exercise 3.3: Analyzing Latency Patterns

**What you'll learn**: Use metrics to see performance trends over time.

**Steps**:

1. In Grafana **Explore** → **Prometheus**
2. Create a dashboard with these queries:

```promql
# P50, P95, P99 latency
histogram_quantile(0.50, sum(rate(http_server_duration_bucket[5m])) by (le, service_name))
histogram_quantile(0.95, sum(rate(http_server_duration_bucket[5m])) by (le, service_name))
histogram_quantile(0.99, sum(rate(http_server_duration_bucket[5m])) by (le, service_name))
```

**What to observe**:

- **Baseline performance**: Normal latency range
- **Spikes**: Sudden increases in latency
- **Trends**: Gradual degradation over time

**Questions to investigate**:

- Q: Which service has the most variable latency?
- Q: Is the P99 much higher than P95? (indicates outliers)
- Q: Do latency spikes correlate across services?

**Success criteria**: You understand how to monitor latency distributions.

---

## Level 4: Error Investigation

**Goal**: Learn to find and debug errors using observability data.

### Exercise 4.1: Finding Error Traces

**What you'll learn**: Filter traces by error status.

**Steps**:

1. In Grafana **Explore** → **Tempo** → **Search**
2. Set filters:
   - Service: `frontend`
   - Status: `error`
3. Run query

**What to observe**:

- **Red spans**: Errors are highlighted in red
- **Error attributes**: Look for `error=true`, `http.status_code=500`
- **Error messages**: Check span attributes for details

**Alternative: Find errors in logs**:

```logql
{namespace="otel-demo"} |= "error" or "ERROR" or "exception"
```

**Questions to answer**:

- Q: What's the most common error?
- Q: Which service generates the most errors?
- Q: Are errors isolated or cascading?

**Success criteria**: You can quickly find all error traces.

---

### Exercise 4.2: Root Cause Analysis

**What you'll learn**: Trace errors back to their source.

**Scenario**: You see a 500 error on the frontend.

**Investigation steps**:

1. **Open the error trace**
2. **Find the red span** (error indicator)
3. **Look at parent spans**: Where did the error originate?
4. **Check span attributes**:
   - `exception.type`
   - `exception.message`
   - `exception.stacktrace`
5. **Jump to logs**: Click "Logs for this span"

**Example trace**:

```
frontend: GET /checkout [500 ERROR]
  └─ checkoutservice: placeOrder() [500 ERROR]
      └─ paymentservice: charge() [500 ERROR] ← ROOT CAUSE
          └─ Error: "Credit card declined"
```

**Questions to answer**:

- Q: Which service first encountered the error?
- Q: Is it a code error or external dependency failure?
- Q: What was the error message?

**Success criteria**: You can trace an error from symptom to root cause.

---

### Exercise 4.3: Error Rate Monitoring

**What you'll learn**: Monitor and alert on error rates.

**Steps**:

1. In Grafana **Explore** → **Prometheus**
2. Calculate error rate:

```promql
# Error rate per service
sum(rate(http_server_duration_count{http_status_code=~"5.."}[5m])) by (service_name)
/
sum(rate(http_server_duration_count[5m])) by (service_name)
* 100
```

**What to observe**:

- **Baseline error rate**: Normal error percentage
- **Error spikes**: Sudden increases
- **Per-service breakdown**: Which services are most error-prone

**Create an alert**:

When error rate > 5% for 5 minutes, trigger alert.

**Questions to answer**:

- Q: What's the normal error rate?
- Q: Which service has the highest error rate?
- Q: Are errors correlated with high load?

**Success criteria**: You can monitor error rates and set meaningful alerts.

---

## Level 5: Advanced Topics

### Exercise 5.1: Understanding Context Propagation

**What you'll learn**: How trace context flows through systems.

**Concept**: Each request carries a `trace_id` and `span_id` through HTTP headers or message metadata.

**Steps**:

1. Find a trace with multiple services
2. Look at span attributes for context propagation:
   - `trace_id`: Same across all spans
   - `parent_span_id`: Links child to parent
3. In logs, search for the trace_id:
   ```logql
   {namespace="otel-demo"} | json | trace_id="<your-trace-id>"
   ```

**What to observe**:

- **Trace ID consistency**: Same ID in frontend, backend, logs
- **Header propagation**: Look for `traceparent` HTTP header
- **Context loss**: If trace ID is missing, context wasn't propagated

**Key concept**:

```
Request flow:
Browser → Frontend (generates trace_id)
       → Cart Service (receives trace_id in header)
       → Database (logs include trace_id)
```

**Success criteria**: You understand how trace context is propagated across services.

---

### Exercise 5.2: Analyzing Kafka Message Flow

**What you'll learn**: Tracing asynchronous messaging.

**Steps**:

1. Find a trace involving Kafka
2. Look for spans like:
   - `kafka.producer.send`
   - `kafka.consumer.receive`
3. Observe the timing gap between producer and consumer

**What to observe**:

- **Async nature**: Producer completes before consumer starts
- **Message lag**: Time between send and receive
- **Trace continuity**: How trace context is preserved in messages

**Kafka tracing challenges**:

- Traces may be split across multiple trace IDs
- Consumer creates new spans linked to producer
- Lag can make traces appear "broken"

**Questions to answer**:

- Q: How long did the message sit in Kafka?
- Q: Did the consumer process successfully?
- Q: Are there any consumer errors?

**Success criteria**: You can trace requests through asynchronous message queues.

---

### Exercise 5.3: Creating Custom Dashboards

**What you'll learn**: Build dashboards combining traces, metrics, and logs.

**Steps**:

1. Go to **Dashboards** → **New Dashboard**
2. Add panels:

**Panel 1: Request Rate**
```promql
sum(rate(http_server_duration_count[5m])) by (service_name)
```

**Panel 2: Error Rate**
```promql
sum(rate(http_server_duration_count{http_status_code=~"5.."}[5m])) by (service_name)
```

**Panel 3: P95 Latency**
```promql
histogram_quantile(0.95, sum(rate(http_server_duration_bucket[5m])) by (le, service_name))
```

**Panel 4: Recent Error Logs**
```logql
{namespace="otel-demo"} |= "error" | json
```

**Panel 5: Service Graph** (link to Tempo service graph)

**Success criteria**: You have a single dashboard showing the health of your demo application.

---

## Level 6: Chaos Engineering

**Goal**: Learn how observability helps during incidents.

### Exercise 6.1: Pod Failure Scenario

**What you'll learn**: Observe system behavior when a service fails.

**Steps**:

1. **Before**: Open Grafana and watch metrics in real-time
2. **Kill a pod**:
   ```bash
   kubectl delete pod -n otel-demo -l app.kubernetes.io/component=cartservice
   ```
3. **Observe**:
   - Traces start showing errors
   - Error rate spikes in Prometheus
   - Error logs appear in Loki
4. **Recovery**: Watch Kubernetes restart the pod
5. **After**: Observe metrics return to normal

**What to observe**:

- **Error traces**: Requests to cartservice fail
- **Cascading failures**: Frontend returns errors to users
- **Recovery time**: How long until service is healthy
- **Kubernetes resilience**: Automatic pod restart

**Questions to answer**:

- Q: How long was the service down?
- Q: Did all requests fail or just some?
- Q: How did upstream services handle the failure?

**Success criteria**: You can observe a failure in real-time across all three signals (traces, metrics, logs).

---

### Exercise 6.2: Cascading Failures

**What you'll learn**: How failures propagate through microservices.

**Steps**:

1. Kill a core service (e.g., redis):
   ```bash
   kubectl delete pod -n otel-demo -l app.kubernetes.io/component=redis
   ```
2. Observe which services start failing
3. Look at traces to see error propagation

**What to observe**:

- **Primary failure**: Redis is down
- **Secondary failures**: Services that depend on Redis fail
- **Error handling**: Do services return errors gracefully or timeout?

**Example trace during cascade**:

```
frontend: GET /cart [500 ERROR]
  └─ cartservice: getCart() [500 ERROR]
      └─ redis: GET user:123 [Connection refused] ← PRIMARY FAILURE
```

**Questions to answer**:

- Q: Which services were affected?
- Q: Did the failure cascade to unrelated services?
- Q: How did each service handle the downstream failure?

**Success criteria**: You understand how failures propagate and can identify dependencies.

---

### Exercise 6.3: Recovery Observation

**What you'll learn**: Monitor service recovery patterns.

**Steps**:

1. After a pod is killed, watch it restart:
   ```bash
   kubectl get pods -n otel-demo -w
   ```
2. In Grafana, watch:
   - Error rate decrease
   - Latency return to normal
   - Traces become successful

**What to observe**:

- **Startup time**: How long until pod is Ready
- **Warmup period**: Initial requests may be slow (cold start)
- **Connection pool recovery**: Services reconnect to database/cache

**Questions to answer**:

- Q: Was recovery immediate or gradual?
- Q: Were there any retry storms during recovery?
- Q: Did any requests fail during the recovery period?

**Success criteria**: You can monitor and validate service recovery.

---

## Reference Material

### Common PromQL Queries

```promql
# Request rate per service
sum(rate(http_server_duration_count[5m])) by (service_name)

# Error rate percentage
sum(rate(http_server_duration_count{http_status_code=~"5.."}[5m]))
/
sum(rate(http_server_duration_count[5m]))
* 100

# Latency percentiles
histogram_quantile(0.95, sum(rate(http_server_duration_bucket[5m])) by (le))

# Top 5 slowest services
topk(5,
  histogram_quantile(0.95,
    sum(rate(http_server_duration_bucket[5m])) by (le, service_name)
  )
)

# CPU usage per pod
rate(container_cpu_usage_seconds_total{namespace="otel-demo"}[5m])

# Memory usage per pod
container_memory_working_set_bytes{namespace="otel-demo"}
```

### Common LogQL Queries

```logql
# All demo logs
{namespace="otel-demo"}

# Errors only
{namespace="otel-demo"} |= "error" or "ERROR"

# Logs for specific service
{namespace="otel-demo", app_kubernetes_io_component="frontend"}

# Logs for a trace
{namespace="otel-demo"} | json | trace_id="<trace-id>"

# Count errors per service
sum(count_over_time({namespace="otel-demo"} |= "error" [5m])) by (app_kubernetes_io_component)

# Find slow operations
{namespace="otel-demo"} | json | duration > 1000 | line_format "{{.service}} took {{.duration}}ms"
```

### TraceQL Queries

```traceql
# Traces longer than 1 second
{ duration > 1s }

# Error traces
{ status = error }

# Traces from specific service
{ service.name = "frontend" }

# Complex query
{
  service.name = "checkoutservice" &&
  duration > 500ms &&
  http.status_code >= 400
}

# Find traces with specific attribute
{ span.http.route = "/cart" }
```

---

## Troubleshooting

### Traces Not Appearing

**Check OpenTelemetry Collector**:
```bash
kubectl logs -n otel-demo -l app.kubernetes.io/component=opentelemetry-collector --tail=50
```

Look for:
- Export errors
- Connection refused to Tempo
- Authentication failures

**Check Tempo**:
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=tempo --tail=50
```

**Test connectivity**:
```bash
kubectl exec -n otel-demo <otel-collector-pod> -- wget -O- --timeout=5 http://tempo.monitoring.svc.cluster.local:4317
```

---

### High Memory Usage

You're at 83% memory. Consider:

**Option 1: Reduce load generator**
```bash
kubectl scale deployment -n otel-demo otel-demo-loadgenerator --replicas=0
```

**Option 2: Disable some services**

Edit `infrastructure/applications/otel-demo.yaml`:
```yaml
components:
  kafka:
    enabled: false  # Kafka uses significant memory
  opensearch:
    enabled: false  # If not using search features
```

**Option 3: Monitor memory**:
```bash
# Watch memory usage
kubectl top pods -n otel-demo

# See which pods use most memory
kubectl top pods -n otel-demo --sort-by=memory
```

---

### Tempo Queries Timing Out

If Tempo searches are slow:

**1. Reduce trace retention**

Edit `infrastructure/monitoring/tempo.yaml`:
```yaml
tempo:
  retention: 24h  # Instead of 168h (7 days)
```

**2. Use more specific queries**

Instead of:
```traceql
{ }  # All traces (slow!)
```

Use:
```traceql
{ service.name = "frontend" && duration > 100ms }  # Filtered (fast!)
```

---

## Next Steps

### After Completing This Guide

You now understand:
✅ Distributed tracing fundamentals
✅ How to correlate traces, metrics, and logs
✅ Performance analysis techniques
✅ Error investigation workflows
✅ Chaos engineering basics

### What's Next?

**1. Add Observability to Your Own Apps**

Resources:
- [OpenTelemetry Instrumentation Guide](https://opentelemetry.io/docs/instrumentation/)
- Language-specific SDKs: Python, Go, Java, Node.js, .NET

**2. Set Up Production-Ready Observability**

- Add alerting rules (Prometheus Alertmanager)
- Create SLO dashboards (error budgets)
- Implement sampling strategies (reduce trace volume)
- Add trace-based alerts (alert on slow traces)

**3. Explore Advanced Tracing**

- Distributed context propagation
- Baggage (passing metadata through traces)
- Trace sampling strategies
- Span events and links

**4. Experiment with Real Workloads**

Deploy a real application with:
- OpenTelemetry SDK
- Auto-instrumentation
- Custom spans and attributes
- Business metrics (e.g., "checkout completed")

### Recommended Reading

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Distributed Tracing in Practice](https://learning.oreilly.com/library/view/distributed-tracing-in/9781492056621/)
- [Observability Engineering](https://www.oreilly.com/library/view/observability-engineering/9781492076438/)

---

## Feedback and Questions

If you have questions or suggestions for this guide, create an issue in the repository or reach out to your homelab community!

Happy tracing! 🔍
