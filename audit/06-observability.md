# Observability & eBPF Monitoring

## Обзор

Данный документ описывает подход к observability в платформе, включая eBPF-based мониторинг через Cilium Hubble и интеграцию с Prometheus/Grafana.

---

## Три столпа Observability

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     THREE PILLARS OF OBSERVABILITY                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐   │
│  │      METRICS      │  │      LOGS         │  │      TRACES       │   │
│  │                   │  │                   │  │                   │   │
│  │  • Prometheus     │  │  • stdout/stderr  │  │  • (Future)       │   │
│  │  • Hubble metrics │  │  • Structured JSON│  │  • OpenTelemetry  │   │
│  │  • Grafana        │  │  • kubectl logs   │  │  • Jaeger         │   │
│  │                   │  │                   │  │                   │   │
│  │  Quantitative     │  │  Qualitative      │  │  Request flow     │   │
│  │  data points      │  │  events           │  │  across services  │   │
│  │                   │  │                   │  │                   │   │
│  └───────────────────┘  └───────────────────┘  └───────────────────┘   │
│                                                                          │
│  Current Implementation:                                                 │
│  • Metrics: Prometheus + Hubble ✓                                       │
│  • Logs: kubectl logs ✓                                                  │
│  • Traces: Not implemented (roadmap)                                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## eBPF и Cilium Hubble

### Что такое eBPF

**eBPF (extended Berkeley Packet Filter)** — технология выполнения программ в Linux kernel без изменения исходного кода ядра.

**Преимущества для networking:**
- Packet processing на уровне kernel
- Минимальный overhead
- Глубокая видимость без sidecar
- Динамическое программирование

### Cilium Hubble

**Hubble** — observability платформа, встроенная в Cilium, использующая eBPF для сбора данных.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        HUBBLE ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Kubernetes Node                                                         │
│  ───────────────                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                                                                  │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐           │   │
│  │  │  Pod A  │  │  Pod B  │  │  Pod C  │  │  Pod D  │           │   │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘           │   │
│  │       │            │            │            │                  │   │
│  │       └────────────┴────────────┴────────────┘                  │   │
│  │                         │                                        │   │
│  │                         ▼                                        │   │
│  │  ┌─────────────────────────────────────────────────────────┐   │   │
│  │  │                   Linux Kernel                           │   │   │
│  │  │  ┌─────────────────────────────────────────────────────┐│   │   │
│  │  │  │                    eBPF Programs                     ││   │   │
│  │  │  │  • Packet inspection                                ││   │   │
│  │  │  │  • L3/L4 flow tracking                             ││   │   │
│  │  │  │  • L7 protocol parsing (HTTP, gRPC, DNS)           ││   │   │
│  │  │  │  • Network policy enforcement                       ││   │   │
│  │  │  └─────────────────────────────────────────────────────┘│   │   │
│  │  └─────────────────────────────────────────────────────────┘   │   │
│  │                         │                                        │   │
│  │                         ▼                                        │   │
│  │  ┌─────────────────────────────────────────────────────────┐   │   │
│  │  │                 Cilium Agent (DaemonSet)                 │   │   │
│  │  │  • Collects flow events from eBPF                       │   │   │
│  │  │  • Exposes Hubble gRPC API                              │   │   │
│  │  │  • Exports Prometheus metrics                           │   │   │
│  │  └─────────────────────────────────────────────────────────┘   │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Cluster-wide                                                            │
│  ────────────                                                            │
│  ┌───────────────────┐           ┌───────────────────┐                  │
│  │  hubble-relay     │ ◄─────────│  hubble-ui        │                  │
│  │  (Deployment)     │           │  (Service Map)     │                  │
│  │                   │           │                   │                  │
│  │  Aggregates flows │           │  Visualizes       │                  │
│  │  from all nodes   │           │  dependencies     │                  │
│  └───────────────────┘           └───────────────────┘                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источник:** [`docs/embodiment/cni-comparison-cilium-vs-calico.md:356-382`](../docs/embodiment/cni-comparison-cilium-vs-calico.md)

---

## Hubble Capabilities

### Flow Visibility

| Layer | What is Captured | Use Case |
|-------|------------------|----------|
| **L3/L4** | Source/Dest IP, Port, Protocol | Network debugging |
| **L7 HTTP** | URL, Method, Status Code, Latency | API monitoring |
| **L7 gRPC** | Service, Method, Status | gRPC debugging |
| **DNS** | Query, Response, Latency | DNS troubleshooting |

### Hubble CLI Examples

```bash
# Real-time flow monitoring
hubble observe --namespace poc-dev

# HTTP requests only
hubble observe --http

# Dropped packets (network policy issues)
hubble observe --verdict DROPPED

# DNS queries
hubble observe --protocol DNS

# Specific source pod
hubble observe --from-pod poc-dev/api-gateway-xxx

# Export to JSON for analysis
hubble observe -o json | jq
```

### Hubble UI

**Service Dependency Map** — визуальное представление связей между сервисами:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        HUBBLE UI - SERVICE MAP                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                    ┌─────────────────┐                                  │
│                    │   api-gateway   │                                  │
│                    └────────┬────────┘                                  │
│                             │                                            │
│            ┌────────────────┼────────────────┐                          │
│            │                │                │                          │
│            ▼                ▼                ▼                          │
│  ┌─────────────────┐ ┌─────────────┐ ┌─────────────────┐               │
│  │  user-service   │ │ game-engine │ │ payment-service │               │
│  └────────┬────────┘ └──────┬──────┘ └────────┬────────┘               │
│           │                 │                 │                         │
│           ▼                 ▼                 ▼                         │
│  ┌─────────────────┐ ┌─────────────┐ ┌─────────────────┐               │
│  │    MongoDB      │ │    Redis    │ │   RabbitMQ      │               │
│  │  (infra-dev)    │ │ (infra-dev) │ │   (infra-dev)   │               │
│  └─────────────────┘ └─────────────┘ └─────────────────┘               │
│                                                                          │
│  Features:                                                               │
│  • Real-time flow visualization                                         │
│  • Click to filter by service                                           │
│  • View L7 request details                                              │
│  • Network policy verdict                                                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Доступ:** `make hubble-ui` (Makefile)

**Источник:** [`Makefile`](../Makefile)

---

## Cilium Configuration

### Helm Values

```yaml
# infrastructure/cilium/helm-values.yaml

kubeProxyReplacement: true      # Replace kube-proxy with eBPF

gatewayAPI:
  enabled: true                  # Gateway API controller

hubble:
  enabled: true

  metrics:
    enabled: "{dns,tcp,flow,httpV2}"
    serviceMonitor:
      enabled: true              # Prometheus integration
    dashboards:
      enabled: true
      namespace: monitoring
      labelKey: grafana_dashboard

  relay:
    enabled: true

  ui:
    enabled: true

l7Proxy: true                    # Enable L7 visibility

prometheus:
  enabled: true                  # Cilium metrics to Prometheus
```

**Источник:** [`infrastructure/cilium/helm-values.yaml`](../infrastructure/cilium/helm-values.yaml)

---

## Prometheus Integration

### Metrics Stack

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PROMETHEUS METRICS STACK                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    kube-prometheus-stack                         │   │
│  │                                                                  │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │   │
│  │  │ Prometheus  │  │ Grafana     │  │ AlertManager            │ │   │
│  │  │             │  │             │  │                         │ │   │
│  │  │ Scrape      │  │ Dashboards  │  │ Alert routing           │ │   │
│  │  │ targets     │  │ Visualization│ │ Notifications           │ │   │
│  │  └──────┬──────┘  └──────┬──────┘  └─────────────────────────┘ │   │
│  │         │                │                                       │   │
│  └─────────┼────────────────┼───────────────────────────────────────┘   │
│            │                │                                            │
│  Scrape Targets:           Dashboard Sources:                           │
│  ───────────────           ──────────────────                           │
│  • ServiceMonitor (apps)   • Hubble (network)                           │
│  • PodMonitor              • Node Exporter (system)                     │
│  • Hubble metrics          • kube-state-metrics (K8s)                   │
│  • Node Exporter           • Custom app metrics                         │
│  • kube-state-metrics                                                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Hubble Metrics

| Metric | Description | Use Case |
|--------|-------------|----------|
| `hubble_flows_processed_total` | Total flows processed | Traffic volume |
| `hubble_dns_queries_total` | DNS queries by response code | DNS monitoring |
| `hubble_http_requests_total` | HTTP requests by status | API monitoring |
| `hubble_tcp_connections_total` | TCP connections | Connection tracking |
| `hubble_http_request_duration_seconds` | HTTP latency histogram | Performance |

### Prometheus Configuration

```yaml
# infrastructure/monitoring/helm-values.yaml

prometheus:
  prometheusSpec:
    serviceMonitorSelector: {}      # Scrape all ServiceMonitors
    podMonitorSelector: {}
    ruleSelector: {}

    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

grafana:
  adminPassword: "admin"           # Change in production!

  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          folder: ''
          type: file
          options:
            path: /var/lib/grafana/dashboards

  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
```

**Источник:** [`infrastructure/monitoring/helm-values.yaml`](../infrastructure/monitoring/helm-values.yaml)

---

## k8app ServiceMonitor

### Automatic Metrics Collection

k8app автоматически создаёт ServiceMonitor когда `metrics.enabled: true`:

```yaml
# services/my-service/.cicd/default.yaml
metrics:
  enabled: true
  port: 9090
  path: /metrics
  interval: 30s
```

**Generated ServiceMonitor:**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-service
  namespace: poc-dev
  labels:
    app: my-service
spec:
  selector:
    matchLabels:
      app: my-service
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
```

---

## Golden Signals

### RED Method (Request-based)

| Signal | Metric | Description |
|--------|--------|-------------|
| **R**ate | `rate(http_requests_total[5m])` | Requests per second |
| **E**rrors | `rate(http_requests_total{status=~"5.."}[5m])` | Error rate |
| **D**uration | `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))` | Latency P99 |

### Hubble-based Dashboards

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     GOLDEN SIGNALS DASHBOARD                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  REQUEST RATE                                                    │   │
│  │  ──────────────                                                  │   │
│  │  sum(rate(hubble_http_requests_total{destination_pod=~".*"}[5m]))│   │
│  │                                                                  │   │
│  │  [═══════════════════════════════════════════]  1.2k req/s      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  ERROR RATE                                                      │   │
│  │  ──────────                                                      │   │
│  │  sum(rate(hubble_http_requests_total{http_status=~"5.."}[5m]))  │   │
│  │  / sum(rate(hubble_http_requests_total[5m]))                    │   │
│  │                                                                  │   │
│  │  [═══]  0.2%                                                     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  LATENCY (P99)                                                   │   │
│  │  ─────────────                                                   │   │
│  │  histogram_quantile(0.99, rate(                                 │   │
│  │    hubble_http_request_duration_seconds_bucket[5m]))            │   │
│  │                                                                  │   │
│  │  [═══════════════════════════]  45ms                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источник:** [`docs/monitoring-audit.md`](../docs/monitoring-audit.md)

---

## Alerting

### AlertManager Configuration

```yaml
# Example alert rules
groups:
  - name: application-alerts
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(hubble_http_requests_total{http_status=~"5.."}[5m]))
          / sum(rate(hubble_http_requests_total[5m])) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is above 5% for 5 minutes"

      - alert: HighLatency
        expr: |
          histogram_quantile(0.99, rate(hubble_http_request_duration_seconds_bucket[5m])) > 0.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High latency detected"
          description: "P99 latency is above 500ms"

      - alert: ServiceDown
        expr: up{job="kubernetes-pods"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Service is down"
```

### Alert Routing

```yaml
route:
  receiver: 'default'
  routes:
    - match:
        env: prod
        severity: critical
      receiver: 'sre-pagerduty'

    - match:
        env: prod
      receiver: 'sre-slack'

    - match:
        env: staging
      receiver: 'tech-leads-slack'

    - match:
        env: dev
      receiver: 'dev-slack'
```

---

## Debugging Workflow

### Network Issues

```bash
# 1. Check connectivity
hubble observe --from-pod poc-dev/my-pod

# 2. Check dropped packets
hubble observe --verdict DROPPED --from-pod poc-dev/my-pod

# 3. Check DNS resolution
hubble observe --protocol DNS --from-pod poc-dev/my-pod

# 4. Check network policies
kubectl describe ciliumnetworkpolicy -n poc-dev
```

### Application Issues

```bash
# 1. Check HTTP errors
hubble observe --http --to-pod poc-dev/my-pod | grep "HTTP/500"

# 2. Check latency
hubble observe --http --to-pod poc-dev/my-pod -o json | \
  jq '.flow.l7.latency_ns'

# 3. Check metrics
kubectl port-forward -n poc-dev svc/my-service 9090:9090
curl localhost:9090/metrics

# 4. Check Grafana dashboard
make proxy-grafana  # Opens Grafana on :3000
```

---

## Access to Observability Tools

### Port Forwards (Makefile)

```bash
# ArgoCD UI
make proxy-argocd      # http://localhost:8081

# Grafana
make proxy-grafana     # http://localhost:3000

# Prometheus
make proxy-prometheus  # http://localhost:9090

# Vault UI
make proxy-vault       # http://localhost:8200

# Hubble UI
make hubble-ui         # Opens Hubble service map

# All proxies
make proxy-all
```

**Источник:** [`Makefile`](../Makefile)

---

## Comparison: Hubble vs Traditional APM

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     HUBBLE vs TRADITIONAL APM                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                    Hubble (eBPF)              Traditional APM           │
│                    ─────────────              ───────────────           │
│  Architecture:     Kernel-level              Application-level         │
│                    No sidecar                Sidecar or agent          │
│                                                                          │
│  Overhead:         ~1-2% CPU                 ~5-10% CPU                 │
│                    Minimal memory            Per-pod memory             │
│                                                                          │
│  Visibility:       L3/L4/L7                  L7 only                    │
│                    All traffic               Instrumented only          │
│                                                                          │
│  Setup:            CNI enabled               Per-service config         │
│                    Zero app changes          Code instrumentation       │
│                                                                          │
│  Cost:             Open Source               Often commercial          │
│                    Part of Cilium            Separate product          │
│                                                                          │
│  Best For:         Network visibility        Deep app tracing          │
│                    Service mesh              Business transactions     │
│                    Security audit            User journeys             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Roadmap

### Current State

| Component | Status |
|-----------|--------|
| Prometheus metrics | ✅ Implemented |
| Hubble flows | ✅ Implemented |
| Grafana dashboards | ✅ Implemented |
| AlertManager | ✅ Configured |
| Hubble UI | ✅ Enabled |

### Future Enhancements

| Component | Status | Description |
|-----------|--------|-------------|
| Distributed Tracing | Planned | OpenTelemetry + Jaeger |
| Log Aggregation | Planned | Loki or ELK |
| SLO/SLI Dashboard | Planned | Error budgets |
| Custom Alerts | Planned | Per-service alerts |

---

## Связанные документы

- [Executive Summary](./00-executive-summary.md)
- [Platform Architecture](./01-platform-architecture.md)
- [CNI Comparison](../docs/embodiment/cni-comparison-cilium-vs-calico.md)

---

*Документ создан на основе аудита кодовой базы GitOps POC*
*Дата: 2025-12-21*
