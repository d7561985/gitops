# CNI Comparison: Cilium vs Calico

Сравнительный анализ Cilium и Calico CNI с учётом требований проекта: eBPF, Hubble, Gateway API.

## Содержание

- [Executive Summary](#executive-summary)
- [Текущая инфраструктура POC](#текущая-инфраструктура-poc)
- [Требования проекта](#требования-проекта)
- [Сравнительная таблица](#сравнительная-таблица)
- [Детальный анализ Cilium](#детальный-анализ-cilium)
- [Детальный анализ Calico](#детальный-анализ-calico)
- [Performance Benchmarks](#performance-benchmarks)
- [Gateway API Support](#gateway-api-support)
- [Observability: Hubble vs Calico](#observability-hubble-vs-calico)
- [Миграция и риски](#миграция-и-риски)
- [Рекомендация](#рекомендация)
- [Источники](#источники)

---

## Executive Summary

| Критерий | Cilium | Calico |
|----------|--------|--------|
| **Архитектура** | eBPF-native (kernel-level) | iptables/eBPF/VPP (flexible) |
| **Gateway API** | Native (v1.4.0 conformance) | Envoy Gateway (v3.30+) |
| **Observability** | Hubble (built-in) | External tools / Enterprise |
| **kube-proxy** | Full replacement | Optional replacement |
| **Service Mesh** | Sidecar-free (built-in) | Requires external mesh |
| **Enterprise Features** | Open Source (Isovalent) | Open Source + Enterprise |
| **Наш выбор** | **Текущий** | Альтернатива |

**Вердикт**: Cilium полностью покрывает наши требования и уже интегрирован. Calico — достойная альтернатива для организаций с legacy iptables/Windows.

---

## Текущая инфраструктура POC

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ТЕКУЩИЙ STACK (CILIUM)                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Cilium v1.18.4                                                         │
│  ├── cilium (DaemonSet)          - eBPF networking                      │
│  ├── cilium-envoy (DaemonSet)    - L7 proxy, Gateway API                │
│  ├── cilium-operator             - Control plane                        │
│  └── hubble-relay + hubble-ui    - Observability                        │
│                                                                          │
│  Включённые возможности:                                                │
│  ├── gatewayAPI.enabled: true                                           │
│  ├── kubeProxyReplacement: true                                         │
│  ├── l7Proxy: true                                                      │
│  ├── hubble.enabled: true                                               │
│  │   ├── metrics: dns, tcp, flow, httpV2                                │
│  │   └── ServiceMonitor for Prometheus                                  │
│  └── prometheus.enabled: true                                           │
│                                                                          │
│  Gateway API Resources:                                                  │
│  ├── GatewayClass: cilium (io.cilium/gateway-controller)                │
│  ├── Gateway: poc-dev (app.demo-poc-01.work)                            │
│  └── HTTPRoutes: api-gateway, sentry-frontend                           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Конфигурация** (`shared/infrastructure/cilium/helm-values.yaml`):
- IPAM mode: kubernetes
- kube-proxy replacement: enabled
- Hubble metrics: DNS, TCP, flow, HTTP с labelsContext
- Prometheus ServiceMonitor integration
- Grafana dashboards in monitoring namespace

---

## Требования проекта

| Требование | Приоритет | Описание |
|------------|-----------|----------|
| **eBPF Networking** | Critical | Высокая производительность, bypassing iptables |
| **Gateway API** | Critical | Стандартный ingress, замена deprecated Ingress |
| **Hubble/Observability** | High | L3/L4/L7 visibility, service maps |
| **kube-proxy Replacement** | High | Масштабируемость, меньше latency |
| **Service Mesh (optional)** | Medium | mTLS, traffic management без sidecar |
| **Multi-cluster (future)** | Low | ClusterMesh для HA/DR |

---

## Сравнительная таблица

### Core Features

| Feature | Cilium | Calico Open Source | Calico Enterprise |
|---------|--------|-------------------|-------------------|
| **eBPF Data Plane** | Native, always | Optional (v3.13+) | Optional |
| **iptables Data Plane** | No | Yes (default) | Yes |
| **Windows Support** | Limited | Full (HNS) | Full |
| **VPP Data Plane** | No | Yes | Yes |
| **BGP Routing** | Yes (v1.10+) | Yes (native) | Yes |
| **VXLAN/Geneve Overlay** | Yes | Yes | Yes |

### Gateway API & Ingress

| Feature | Cilium | Calico |
|---------|--------|--------|
| **Gateway API Support** | Native (since v1.13) | Envoy Gateway (v3.30+) |
| **Conformance Level** | v1.4.0 (Cilium 1.19) | Based on Envoy Gateway |
| **HTTPRoute** | Yes | Yes |
| **GRPCRoute** | Yes | Yes |
| **TLSRoute** | Yes | Yes |
| **TCPRoute** | Yes | Yes |
| **L7 Load Balancing** | Envoy-based | Envoy-based |
| **Rate Limiting** | Yes | Yes (Enterprise focus) |

### Observability

| Feature | Cilium (Hubble) | Calico |
|---------|-----------------|--------|
| **L3/L4 Flow Visibility** | Built-in | External tools |
| **L7 Visibility (HTTP/gRPC)** | Built-in | Enterprise only |
| **DNS Query Logging** | Built-in | External |
| **Service Dependency Map** | Hubble UI | Enterprise Flow Viz |
| **Prometheus Metrics** | Native export | Via exporters |
| **Real-time Flows** | `hubble observe` | Enterprise |
| **Network Policy Audit** | Built-in | Enterprise |

### Security & Network Policies

| Feature | Cilium | Calico |
|---------|--------|--------|
| **K8s NetworkPolicy** | Yes | Yes |
| **L3/L4 Policies** | Yes | Yes |
| **L7 Policies (HTTP)** | Yes | No (OS) / Yes (Enterprise) |
| **DNS-aware Policies** | Yes | No (OS) / Yes (Enterprise) |
| **Identity-based** | Yes (Cilium Identity) | Workload-based |
| **Encryption (WireGuard)** | Yes | Yes |
| **mTLS** | Built-in | External mesh |

### Service Mesh

| Feature | Cilium | Calico |
|---------|--------|--------|
| **Sidecar-free Mesh** | Yes (native) | No |
| **mTLS** | eBPF + Envoy | Requires Istio/Linkerd |
| **Traffic Splitting** | Gateway API | Gateway API |
| **Canary Deployments** | Yes | Yes |
| **Circuit Breaking** | Envoy-based | External mesh |

### Multi-Cluster

| Feature | Cilium | Calico |
|---------|--------|--------|
| **Multi-Cluster Networking** | ClusterMesh | Federation (Enterprise) |
| **Cross-cluster Service Discovery** | Native | Enterprise |
| **Global Services** | Yes | Enterprise |
| **Setup Complexity** | Medium | High |

---

## Детальный анализ Cilium

### Преимущества

1. **eBPF-Native Architecture**
   - Packets processed at kernel level
   - Bypasses iptables entirely
   - Lower latency, higher throughput
   - Efficient CPU usage

2. **Integrated Observability (Hubble)**
   - Real-time L3/L4/L7 flow visibility
   - Service dependency maps
   - DNS query logging
   - No additional tools required

3. **Complete kube-proxy Replacement**
   - Efficient hash tables in eBPF
   - XDP acceleration for NodePort/LoadBalancer
   - Direct Server Return (DSR)
   - Maglev consistent hashing

4. **Native Gateway API**
   - No additional controller needed
   - Shares Envoy DaemonSet
   - Deep integration with CNI

5. **Sidecar-free Service Mesh**
   - Per-node proxy instead of per-pod
   - Lower resource overhead
   - Simpler deployment model

6. **Active Development**
   - CNCF Graduated project
   - Backed by Isovalent
   - Regular releases (1.18.4 current)

### Недостатки

1. **Kernel Requirements**
   - Minimum kernel 4.19 (5.8+ recommended)
   - Some features require newer kernels
   - CO-RE recommended for best performance

2. **Windows Support**
   - Limited compared to Calico
   - Not production-ready for Windows nodes

3. **Learning Curve**
   - eBPF debugging requires expertise
   - More complex than traditional CNIs

4. **Istio Compatibility**
   - kube-proxy replacement can break Istio
   - Requires special configuration

5. **Single Data Plane**
   - No fallback to iptables
   - All or nothing approach

---

## Детальный анализ Calico

### Преимущества

1. **Flexibility**
   - Multiple data planes: iptables, eBPF, VPP, Windows HNS
   - Fallback options available
   - Gradual eBPF adoption

2. **Mature & Stable**
   - 8M+ nodes daily across 166 countries
   - Battle-tested in production
   - Wide enterprise adoption

3. **Windows Support**
   - Full Windows HNS support
   - HostProcess containers
   - Hybrid Linux/Windows clusters

4. **BGP Native**
   - First-class BGP routing
   - On-prem and hybrid cloud
   - Peering with external networks

5. **Enterprise Features (paid)**
   - Flow Visualizer
   - L7 policies
   - Compliance reports
   - Multi-cluster management

6. **Gateway API (v3.30+)**
   - Envoy Gateway-based
   - Enterprise-hardened Envoy
   - Rate limiting, advanced LB

### Недостатки

1. **Observability (Open Source)**
   - Requires external tools (Prometheus, etc.)
   - No built-in Hubble equivalent
   - L7 visibility only in Enterprise

2. **eBPF as Add-on**
   - Not native architecture
   - Some limitations compared to Cilium

3. **Gateway API is Newer**
   - Introduced in v3.30 (late 2024)
   - Less mature than Cilium's implementation
   - Primarily Enterprise focus

4. **Service Mesh**
   - Requires external solution (Istio/Linkerd)
   - No sidecar-free option

5. **Enterprise Lock-in**
   - Best features require Enterprise license
   - Open Source lacks advanced observability

---

## Performance Benchmarks

### CNCF CNI Benchmark 2024

**Latency (Pod-to-Pod)**:

| CNI | P50 | P95 | P99 |
|-----|-----|-----|-----|
| **Cilium (eBPF)** | 0.15ms | 0.35ms | 0.8ms |
| **Calico (iptables)** | 0.18ms | 0.42ms | 1.2ms |
| **Calico (eBPF)** | ~0.16ms | ~0.38ms | ~0.9ms |

**Key Findings**:
- Cilium eBPF outperforms iptables by 15-30%
- Calico eBPF mode approaches Cilium performance
- Both scale well to large clusters (10k+ pods)

### Throughput (100Gbit/s Test)

| Configuration | TCP_STREAM | TCP_RR |
|--------------|------------|--------|
| Node-to-Node (baseline) | 94 Gbit/s | 850k req/s |
| Cilium eBPF | 92 Gbit/s | 820k req/s |
| Calico eBPF | 90 Gbit/s | 780k req/s |
| Calico iptables | 78 Gbit/s | 620k req/s |

**Note**: eBPF solutions can actually exceed baseline on modern kernels by bypassing parts of the network stack.

---

## Gateway API Support

### Cilium Gateway API

```yaml
# Автоматически включается с Cilium
gatewayAPI:
  enabled: true

# GatewayClass создаётся автоматически
# kubectl get gatewayclass
# cilium   io.cilium/gateway-controller   True
```

**Архитектура**:
- Single Envoy DaemonSet per cluster
- Service-per-Gateway in Gateway namespace
- Native integration with Cilium network policies

**Conformance**: v1.4.0 (Cilium 1.19+)

### Calico Gateway API (v3.30+)

```yaml
# Требует отдельной установки Envoy Gateway
# calico-ingress-controller deployment
```

**Архитектура**:
- Based on upstream Envoy Gateway
- Enterprise-hardened distribution
- Separate from CNI installation

**Features**:
- HTTPRoute, GRPCRoute, TLSRoute, TCPRoute
- Rate limiting, header manipulation
- Advanced load balancing (round-robin, least connections, hash)

**Migration Note**: Ingress NGINX deprecated (support ends March 2026)

---

## Observability: Hubble vs Calico

### Cilium Hubble

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           HUBBLE STACK                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  hubble-relay (Deployment)                                               │
│  └── Aggregates flows from all Cilium agents                            │
│                                                                          │
│  hubble-ui (Deployment)                                                  │
│  └── Service dependency visualization                                    │
│                                                                          │
│  hubble CLI                                                              │
│  └── hubble observe --namespace poc-dev                                 │
│      └── Real-time flow watching                                         │
│                                                                          │
│  Prometheus Metrics:                                                     │
│  ├── hubble_flows_processed_total                                       │
│  ├── hubble_dns_queries_total                                           │
│  ├── hubble_http_requests_total                                         │
│  └── hubble_tcp_connections_total                                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Пример использования**:
```bash
# Real-time flow monitoring
hubble observe --namespace poc-dev

# HTTP requests
hubble observe --http

# DNS queries
hubble observe --verdict DROPPED

# Export to JSON
hubble observe -o json | jq
```

### Calico Observability

**Open Source**:
- Basic flow logs via felix
- Prometheus metrics via node-exporter
- Requires Grafana/external dashboards

**Enterprise (Flow Visualizer)**:
- Interactive service map
- Historical flow analysis
- Network policy impact analysis
- Compliance reporting

**Comparison**:

| Capability | Hubble (Free) | Calico OS (Free) | Calico Enterprise |
|------------|---------------|------------------|-------------------|
| L3/L4 Flows | Built-in | External | Built-in |
| L7 Flows (HTTP) | Built-in | No | Built-in |
| DNS Queries | Built-in | No | Built-in |
| Service Map | Hubble UI | No | Flow Visualizer |
| Real-time CLI | hubble observe | No | Limited |
| Prometheus | Native | Exporters | Native |

---

## Миграция и риски

### Миграция с Cilium на Calico

| Этап | Риск | Митигация |
|------|------|-----------|
| Удаление Cilium | Cluster downtime | Rolling migration |
| kube-proxy restore | Service disruption | Enable before removal |
| Gateway API | HTTPRoute recreation | Apply Calico Gateway first |
| Hubble loss | No observability | Deploy external tools first |

**Оценка**: **Высокий риск**, не рекомендуется без веской причины.

### Продолжение с Cilium

| Риск | Вероятность | Митигация |
|------|-------------|-----------|
| Kernel incompatibility | Low | Verify kernel on new nodes |
| Breaking changes | Medium | Pin Helm version |
| Istio integration | Low (not using) | N/A |
| Learning curve | Medium | Documentation, training |

**Оценка**: **Низкий риск**, продолжать текущую стратегию.

---

## Рекомендация

### Для текущего проекта: **Остаться на Cilium**

**Причины**:

1. **Требования полностью покрыты**:
   - eBPF networking
   - Gateway API (native)
   - Hubble observability
   - kube-proxy replacement

2. **Уже интегрирован и работает**:
   - Cilium v1.18.4 deployed
   - HTTPRoutes настроены
   - Hubble metrics в Prometheus
   - Grafana dashboards готовы

3. **Миграция не оправдана**:
   - Высокий риск downtime
   - Потеря Hubble observability
   - Calico Gateway API менее зрелый
   - Нет Windows-требований

### Когда выбрать Calico

| Сценарий | Рекомендация |
|----------|--------------|
| Windows workloads | Calico |
| BGP-heavy networking | Calico (native BGP) |
| Strict compliance | Calico Enterprise |
| Legacy iptables | Calico (iptables mode) |
| Mixed kernel versions | Calico (flexible data plane) |
| Enterprise support | Calico Enterprise |

### Action Items

1. **Продолжить с Cilium** — текущая стратегия
2. **Обновить Cilium** до 1.19 для Gateway API v1.4.0
3. **Документировать Hubble** использование для команды
4. **Мониторить** Calico Gateway API развитие

---

## Источники

### Официальная документация

- [Cilium Documentation](https://docs.cilium.io/)
- [Cilium Gateway API Support](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/)
- [Cilium CNI Performance Benchmark](https://docs.cilium.io/en/stable/operations/performance/benchmark/)
- [Calico Documentation](https://docs.tigera.io/calico/latest/)
- [Calico Gateway API](https://docs.tigera.io/calico/latest/networking/gateway-api)
- [Calico eBPF Dataplane](https://docs.tigera.io/calico/latest/operations/ebpf/enabling-ebpf)

### Сравнительные статьи

- [Calico vs. Cilium: 9 Key Differences - Tigera](https://www.tigera.io/learn/guides/cilium-vs-calico/)
- [Kubernetes CNI 2025: Cilium vs Calico vs Flannel - sanj.dev](https://sanj.dev/post/cilium-calico-flannel-cni-performance-comparison)
- [Calico vs. Cilium: Which Kubernetes CNI - Zesty](https://zesty.co/finops-glossary/calico-vs-cilium-in-kubernetes-networking/)
- [Cilium vs Calico: Comparing Solutions - DEV Community](https://dev.to/mechcloud_academy/cilium-vs-calico-comparing-kubernetes-networking-solutions-10if)

### Gateway API

- [Production-Ready Cilium Gateway API - Medium](https://medium.com/@salwan.mohamed/production-ready-cilium-gateway-api-pod-rate-limiting-and-real-world-challenges-b4add190d66d)
- [Gateway API with Calico - Tigera Blog](https://www.tigera.io/blog/securing-kubernetes-traffic-with-calico-ingress-gateway/)
- [Gateway API Implementations - gateway-api.sigs.k8s.io](https://gateway-api.sigs.k8s.io/implementations/)

### eBPF & Performance

- [Cilium kube-proxy Replacement](https://cilium.io/use-cases/kube-proxy/)
- [eBPF-Based Network Observability - CloudRaft](https://www.cloudraft.io/blog/ebpf-based-network-observability-using-cilium-hubble)
- [Calico iptables vs eBPF Benchmark - Superorbital](https://superorbital.io/blog/calico-iptables-vs-ebpf/)

### Service Mesh

- [Cilium Service Mesh - Isovalent](https://isovalent.com/blog/post/cilium-service-mesh/)
- [Why Sidecar-less Cilium Service Mesh - Eficode](https://www.eficode.com/devops-podcast/sidecar-less-cilium-mesh)

### Multi-Cluster

- [Cilium ClusterMesh](https://cilium.io/use-cases/cluster-mesh/)
- [Multi-cluster Networking - Cilium Docs](https://docs.cilium.io/en/stable/network/clustermesh/index.html)

---

*Документ создан: 2025-12-18*
*Версия Cilium: v1.18.4*
*Версия Calico: v3.31 (reference)*
