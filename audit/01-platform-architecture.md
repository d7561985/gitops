# Platform Architecture

## Обзор

Данный документ описывает архитектуру платформенного слоя GitOps-системы: компоненты, их взаимодействие и конфигурацию.

---

## Архитектура высокого уровня

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PLATFORM ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  EXTERNAL LAYER                                                              │
│  ──────────────                                                              │
│  ┌─────────────────┐                                                         │
│  │ CloudFlare Edge │ ◄── TLS termination, DDoS protection, CDN             │
│  └────────┬────────┘                                                         │
│           │ QUIC/HTTP2                                                       │
│           ▼                                                                  │
│  ┌─────────────────┐                                                         │
│  │ CloudFlare      │ ◄── Outbound-only tunnel (no public IP needed)         │
│  │ Tunnel          │                                                         │
│  └────────┬────────┘                                                         │
│           │                                                                  │
│  ═════════╪══════════════════════════════════════════════════════════════   │
│           │                                                                  │
│  KUBERNETES CLUSTER                                                          │
│  ──────────────────                                                          │
│           ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     GATEWAY LAYER (Cilium)                           │    │
│  │  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐            │    │
│  │  │ Gateway     │     │ HTTPRoute   │     │ HTTPRoute   │            │    │
│  │  │ (poc-dev)   │ ◄───│ api-gateway │     │ frontend    │            │    │
│  │  │             │     │ /api/*      │     │ /*          │            │    │
│  │  └─────────────┘     └─────────────┘     └─────────────┘            │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     APPLICATION LAYER                                │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │    │
│  │  │ api-gateway │  │ user-service│  │ game-engine │  │ payment     │ │    │
│  │  │ (Envoy)     │  │ (Go/Connect)│  │ (Python)    │  │ (Node.js)   │ │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     PLATFORM SERVICES                                │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │    │
│  │  │   ArgoCD    │  │    Vault    │  │  Prometheus │  │  Hubble UI  │ │    │
│  │  │             │  │    + VSO    │  │  + Grafana  │  │  (Cilium)   │ │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     INFRASTRUCTURE LAYER                             │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │    │
│  │  │   MongoDB   │  │  RabbitMQ   │  │    Redis    │                  │    │
│  │  │ (infra-dev) │  │ (infra-dev) │  │ (infra-dev) │                  │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Компоненты платформы

### 1. Cilium CNI

**Назначение:** Container Network Interface с eBPF

**Особенности:**
- eBPF-native networking (kernel-level packet processing)
- Замена kube-proxy (kubeProxyReplacement: true)
- Gateway API controller встроен
- Hubble observability встроен

**Конфигурация:** [`infrastructure/cilium/helm-values.yaml`](../infrastructure/cilium/helm-values.yaml)

```yaml
# Ключевые настройки из helm-values.yaml
kubeProxyReplacement: true      # Замена kube-proxy на eBPF
gatewayAPI:
  enabled: true                  # Gateway API controller
hubble:
  enabled: true
  metrics:
    enabled: "{dns,tcp,flow,httpV2}"
    serviceMonitor:
      enabled: true              # Prometheus интеграция
l7Proxy: true                    # L7 visibility
```

**Версия:** Cilium v1.18.4

**Источник анализа:** [`docs/embodiment/cni-comparison-cilium-vs-calico.md`](../docs/embodiment/cni-comparison-cilium-vs-calico.md)

---

### 2. Gateway API

**Назначение:** Стандартный Kubernetes ingress (замена deprecated Ingress API)

**Архитектура:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        GATEWAY API STRUCTURE                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  GatewayClass                    Gateway                    HTTPRoute   │
│  ────────────                    ───────                    ─────────   │
│  ┌────────────┐                 ┌───────────────┐         ┌───────────┐│
│  │ cilium     │ ◄─────────────  │ gateway       │ ◄────── │ api-gw    ││
│  │            │   gatewayClass  │ poc-dev       │ parentRef│ /api/*   ││
│  │ Controller:│   Reference     │               │         │           ││
│  │ io.cilium/ │                 │ Listener:     │         │ backendRef││
│  │ gateway-   │                 │  http-app:80  │         │ api-gw-sv ││
│  │ controller │                 │  hostname:    │         └───────────┘│
│  └────────────┘                 │  app.demo-    │                      │
│                                 │  poc-01.work  │         ┌───────────┐│
│                                 └───────────────┘ ◄────── │ frontend  ││
│                                                   parentRef│ /*       ││
│                                                           │           ││
│                                                           └───────────┘│
└─────────────────────────────────────────────────────────────────────────┘
```

**Конфигурация Gateway:** [`gitops-config/charts/platform-bootstrap/templates/gateway.yaml`](../gitops-config/charts/platform-bootstrap/templates/gateway.yaml)

**Конфигурация HTTPRoute (пример):**

```yaml
# Из services/api-gateway/.cicd/default.yaml
httpRoute:
  enabled: true
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api-gateway-sv
          port: 8080
```

**Документация:** [`docs/gateway-api-plan.md`](../docs/gateway-api-plan.md)

---

### 3. HashiCorp Vault + VSO

**Назначение:** Централизованное управление секретами

**Архитектура:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     VAULT + VSO ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                        VAULT SERVER                                 │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐ │ │
│  │  │ KV v2 Engine    │  │ Kubernetes Auth │  │ Policies            │ │ │
│  │  │                 │  │                 │  │                     │ │ │
│  │  │ secret/data/    │  │ Validates JWT   │  │ {ns}-{env}-read     │ │ │
│  │  │ {group}/        │  │ from Service    │  │ allows read on      │ │ │
│  │  │ {service}/      │  │ Account tokens  │  │ service paths       │ │ │
│  │  │ {env}/config    │  │                 │  │                     │ │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                    ▲                                     │
│                                    │ API calls                          │
│                                    │                                     │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                  VAULT SECRETS OPERATOR (VSO)                       │ │
│  │                                                                     │ │
│  │  Watches VaultStaticSecret → Reads from Vault → Creates K8s Secret │ │
│  │                                                                     │ │
│  │  ┌─────────────────┐          ┌─────────────────┐                  │ │
│  │  │ VaultStaticSecret│   ──►   │ Kubernetes      │                  │ │
│  │  │ (CRD)           │          │ Secret          │                  │ │
│  │  │                 │          │ (auto-created)  │                  │ │
│  │  │ path: secret/   │          │                 │                  │ │
│  │  │ data/{svc}/{env}│          │ Synced every    │                  │ │
│  │  │ /config         │          │ refreshAfter    │                  │ │
│  │  └─────────────────┘          └─────────────────┘                  │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Конфигурация Vault:** [`infrastructure/vault/helm-values.yaml`](../infrastructure/vault/helm-values.yaml)

**Конфигурация VSO:** [`infrastructure/vault/vso-values.yaml`](../infrastructure/vault/vso-values.yaml)

**Bootstrap Job:** [`gitops-config/charts/platform-bootstrap/templates/bootstrap-job.yaml`](../gitops-config/charts/platform-bootstrap/templates/bootstrap-job.yaml)

Автоматически создаёт:
- Vault policies для каждого namespace/env
- Kubernetes auth roles
- Placeholder secrets

**Структура путей в Vault:**

```
secret/data/{VAULT_PATH_PREFIX}/{service}/{env}/config

Пример: secret/data/gitops-poc-dzha/api-gateway/dev/config
```

---

### 4. ArgoCD

**Назначение:** GitOps Continuous Delivery

**Паттерн "App of Apps":**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     ARGOCD APP OF APPS PATTERN                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Root Application                                                        │
│  ────────────────                                                        │
│  ┌───────────────────┐                                                   │
│  │ bootstrap-app     │ ◄── Один Application управляет всем               │
│  │ (App of Apps)     │                                                   │
│  └─────────┬─────────┘                                                   │
│            │                                                             │
│            │ Creates                                                     │
│            ▼                                                             │
│  ┌───────────────────┐                                                   │
│  │ platform-bootstrap│ ◄── Helm chart, Single Source of Truth           │
│  │ Application       │                                                   │
│  └─────────┬─────────┘                                                   │
│            │                                                             │
│            │ Generates via ApplicationSet                                │
│            ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                    Generated Applications                            ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ ││
│  │  │ api-gateway │  │ web-grpc    │  │ user-service│  │ sentry-     │ ││
│  │  │ -dev        │  │ -dev        │  │ -dev        │  │ frontend-dev│ ││
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Конфигурация ArgoCD:** [`infrastructure/argocd/helm-values.yaml`](../infrastructure/argocd/helm-values.yaml)

**Bootstrap Application:** [`gitops-config/argocd/bootstrap-app.yaml`](../gitops-config/argocd/bootstrap-app.yaml)

**ApplicationSet:** [`gitops-config/charts/platform-bootstrap/templates/applicationset.yaml`](../gitops-config/charts/platform-bootstrap/templates/applicationset.yaml)

---

### 5. cert-manager

**Назначение:** Автоматическое управление TLS сертификатами

**Конфигурация:** [`infrastructure/cert-manager/helm-values.yaml`](../infrastructure/cert-manager/helm-values.yaml)

**ClusterIssuers:** [`infrastructure/cert-manager/cluster-issuers.yaml`](../infrastructure/cert-manager/cluster-issuers.yaml)

**Поддерживаемые методы:**
- Let's Encrypt (ACME)
- CloudFlare DNS01 challenge

---

### 6. Monitoring Stack

**Назначение:** Метрики, алерты, визуализация

**Компоненты:**
- Prometheus — сбор метрик
- Grafana — дашборды
- AlertManager — алерты
- Hubble — сетевые метрики (Cilium)

**Конфигурация:** [`infrastructure/monitoring/helm-values.yaml`](../infrastructure/monitoring/helm-values.yaml)

**Версия:** kube-prometheus-stack 80.4.1

---

## Namespace Strategy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        NAMESPACE STRUCTURE                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  APPLICATION NAMESPACES (per environment)                                │
│  ────────────────────────────────────────                                │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │
│  │    poc-dev      │  │  poc-staging    │  │    poc-prod     │          │
│  │                 │  │                 │  │                 │          │
│  │  All services   │  │  All services   │  │  All services   │          │
│  │  for dev env    │  │  for staging    │  │  for production │          │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘          │
│                                                                          │
│  INFRASTRUCTURE NAMESPACES (per environment)                             │
│  ───────────────────────────────────────────                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │
│  │   infra-dev     │  │ infra-staging   │  │   infra-prod    │          │
│  │                 │  │                 │  │                 │          │
│  │  MongoDB        │  │  MongoDB        │  │  MongoDB        │          │
│  │  RabbitMQ       │  │  RabbitMQ       │  │  RabbitMQ       │          │
│  │  Redis          │  │  Redis          │  │  Redis          │          │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘          │
│                                                                          │
│  PLATFORM NAMESPACES (shared)                                            │
│  ────────────────────────────                                            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │
│  │     argocd      │  │      vault      │  │   monitoring    │          │
│  │                 │  │                 │  │                 │          │
│  │  ArgoCD Server  │  │  Vault + VSO    │  │  Prometheus     │          │
│  │  ApplicationSet │  │                 │  │  Grafana        │          │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Naming Conventions:**

| Resource | Pattern | Example |
|----------|---------|---------|
| Application Namespace | `{prefix}-{env}` | `poc-dev`, `poc-staging` |
| Infrastructure Namespace | `infra-{env}` | `infra-dev` |
| Service Name (K8s) | `{service}-sv` | `api-gateway-sv` |
| ArgoCD Application | `{service}-{env}` | `api-gateway-dev` |
| Vault Role | `{service}-{env}` | `api-gateway-dev` |

**Источник:** [`docs/multi-tenancy-guide.md`](../docs/multi-tenancy-guide.md)

**Детальный разбор:** [Multi-Tenancy Architecture](./07-multi-tenancy.md)

---

## Platform Bootstrap

### Single Source of Truth

Весь платформенный слой описан в одном Helm chart: [`gitops-config/charts/platform-bootstrap/`](../gitops-config/charts/platform-bootstrap/)

**Что генерирует chart:**

| Template | Ресурс | Назначение |
|----------|--------|------------|
| `namespaces.yaml` | Namespaces | poc-dev, poc-staging, poc-prod |
| `vault-auth.yaml` | VaultAuth | VSO authentication per namespace |
| `bootstrap-job.yaml` | Job | Vault policies, roles, placeholders |
| `applicationset.yaml` | ApplicationSet | ArgoCD Apps для всех сервисов |
| `gateway.yaml` | Gateway | Per-environment Gateway + mirror listeners |
| `httproute-mirrors.yaml` | HTTPRoute | Routes для зеркальных доменов |
| `cloudflared-config.yaml` | ConfigMap | Tunnel ingress rules для mirrors |
| `reference-grant.yaml` | ReferenceGrant | Cross-namespace routing |

**Конфигурация:** [`gitops-config/charts/platform-bootstrap/values.yaml`](../gitops-config/charts/platform-bootstrap/values.yaml)

```yaml
# Ключевые секции values.yaml

global:
  gitlabGroup: gitops-poc-dzha
  vaultPathPrefix: gitops-poc-dzha
  namespacePrefix: poc
  k8app:
    repoURL: https://d7561985.github.io/k8app
    chart: app
    version: "3.8.0"

environments:
  dev:
    enabled: true
    autoSync: true
    domain: "app.demo-poc-01.work"
    infraNamespace: "infra-dev"
  # staging: ...
  # prod: ...

services:
  api-gateway:
    syncWave: "0"
  user-service:
    syncWave: "0"
    repoURL: https://gitlab.com/gitops-poc-dzha/user-service.git
  # ... more services
```

---

## Ingress Architecture

### Модульная архитектура

Ingress провайдер полностью независим от DNS management. Это позволяет переключать провайдеры без изменения DNS конфигурации.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     MODULAR INGRESS ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌───────────────────────────────────┐   ┌───────────────────────────┐ │
│  │         Ingress Providers          │   │      DNS Management       │ │
│  │            (выбор 1)               │   │        (независим)        │ │
│  │  ┌─────────────────────────────┐  │   │  ┌─────────────────────┐  │ │
│  │  │ ○ cloudflare-tunnel         │  │   │  │ external-dns        │  │ │
│  │  │   (текущий)                 │  │   │  │                     │  │ │
│  │  ├─────────────────────────────┤  │   │  │ Watches Gateway     │  │ │
│  │  │ ○ haproxy                   │  │   │  │ annotations and     │  │ │
│  │  │   loadBalancerIP: x.x.x.x   │  │   │  │ creates DNS records │  │ │
│  │  ├─────────────────────────────┤  │   │  │                     │  │ │
│  │  │ ○ nginx                     │  │   │  │ Provider: cloudflare│  │ │
│  │  │   loadBalancerIP: x.x.x.x   │  │   │  └─────────────────────┘  │ │
│  │  ├─────────────────────────────┤  │   │                           │ │
│  │  │ ○ external                  │  │   │  Target выбирается        │ │
│  │  │   (только DNS)              │  │   │  автоматически:           │ │
│  │  └─────────────────────────────┘  │   │  • tunnel → CNAME         │ │
│  │                                    │   │  • haproxy → A record     │ │
│  └───────────────────────────────────┘   └───────────────────────────┘ │
│                                                                          │
│  Переключение: ingress.provider: "haproxy" → меняется только target    │
│                DNS конфигурация остаётся без изменений                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Конфигурация провайдеров:**

```yaml
# gitops-config/charts/platform-bootstrap/values.yaml

ingress:
  provider: cloudflare-tunnel   # или: haproxy, nginx, external

  cloudflare:
    enabled: true
    tunnelId: "1172317a-8885-492f-9744-dfba842c4d88"
    credentialsSecret: cloudflared-credentials
    replicas: 2
    namespace: cloudflare

  # Альтернативные провайдеры:
  # haproxy:
  #   loadBalancerIP: "203.0.113.10"  # Статический IP
  # nginx:
  #   loadBalancerIP: "203.0.113.20"
```

**Источник:** [`gitops-config/charts/platform-bootstrap/values.yaml:224-257`](../gitops-config/charts/platform-bootstrap/values.yaml)

---

### CloudFlare Tunnel

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     CLOUDFLARE TUNNEL FLOW                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Internet                CloudFlare           Kubernetes                 │
│  ────────                ──────────           ──────────                 │
│                                                                          │
│  Browser ──HTTPS──► CloudFlare Edge                                      │
│                     (TLS termination)                                    │
│                            │                                             │
│                            │ QUIC                                        │
│                            ▼                                             │
│                     cloudflared Pod ──HTTP──► cilium-gateway-gateway    │
│                     (outbound-only)           (Gateway Service)          │
│                                                      │                   │
│                                                      ▼                   │
│                                               HTTPRoute matching         │
│                                                      │                   │
│                                                      ▼                   │
│                                               Backend Service            │
│                                                                          │
│  Key Points:                                                             │
│  • No public IP needed on cluster                                        │
│  • Outbound-only connection (secure)                                     │
│  • CloudFlare provides DDoS protection                                   │
│  • TLS terminated at CloudFlare Edge                                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Конфигурация:** [`infrastructure/cloudflare-tunnel/deployment.yaml`](../infrastructure/cloudflare-tunnel/deployment.yaml)

---

## DNS Management

### external-dns

Автоматическое создание DNS записей на основе Gateway annotations.

**Конфигурация:** [`infrastructure/external-dns/helm-values.yaml`](../infrastructure/external-dns/helm-values.yaml)

**Setup скрипт:** [`infrastructure/external-dns/setup.sh`](../infrastructure/external-dns/setup.sh)

### Архитектура

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     EXTERNAL-DNS FLOW                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  platform-bootstrap                                                      │
│  ──────────────────                                                      │
│  gateway.yaml template adds annotations:                                │
│                                                                          │
│  apiVersion: gateway.networking.k8s.io/v1                               │
│  kind: Gateway                                                           │
│  metadata:                                                               │
│    annotations:                                                          │
│      external-dns.alpha.kubernetes.io/hostname: "app.demo...,mirror..."│
│      external-dns.alpha.kubernetes.io/target: "{tunnelId}.cfargotunnel"│
│                                                                          │
│       │                                                                  │
│       ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │              external-dns (watches Gateway resources)           │   │
│  │                                                                  │   │
│  │  sources:                                                        │   │
│  │    - gateway-httproute                                          │   │
│  │    - gateway-grpcroute                                          │   │
│  │                                                                  │   │
│  │  Reads annotations → Creates DNS records in CloudFlare          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│       │                                                                  │
│       ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    CloudFlare DNS                                │   │
│  │                                                                  │   │
│  │  CNAME: app.demo-poc-01.work → {tunnelId}.cfargotunnel.com     │   │
│  │  CNAME: mirror.example.com   → {tunnelId}.cfargotunnel.com     │   │
│  │                                                                  │   │
│  │  (proxied: orange cloud для DDoS protection)                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Конфигурация в values.yaml

```yaml
# platform-bootstrap values.yaml
dns:
  enabled: true
  provider: cloudflare
  cloudflare:
    proxied: true              # Orange cloud in CloudFlare
    secretName: cloudflare-api-credentials
```

### Gateway Annotations (автоматически генерируются)

```yaml
# Генерируется gateway.yaml template
annotations:
  # Все hostnames через запятую (основной + mirrors)
  external-dns.alpha.kubernetes.io/hostname: "app.demo-poc-01.work,mirror.example.com"

  # Target зависит от ingress provider:
  # CloudFlare Tunnel:
  external-dns.alpha.kubernetes.io/target: "{tunnelId}.cfargotunnel.com"
  # HAProxy/Nginx:
  external-dns.alpha.kubernetes.io/target: "203.0.113.10"
```

**Источник:** [`gitops-config/charts/platform-bootstrap/templates/gateway.yaml:46-66`](../gitops-config/charts/platform-bootstrap/templates/gateway.yaml)

### helm-values.yaml

```yaml
# infrastructure/external-dns/helm-values.yaml

# Источники для DNS записей
sources:
  - gateway-httproute
  - gateway-grpcroute

provider:
  name: cloudflare

# RBAC для Gateway API
rbac:
  additionalPermissions:
    - apiGroups: ["gateway.networking.k8s.io"]
      resources: ["gateways", "httproutes", "grpcroutes"]
      verbs: ["get", "list", "watch"]

# Metrics для Prometheus
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
```

---

## Domain Mirrors

### Обзор

Domain Mirrors — функциональность для автоматического создания зеркальных доменов, которые маршрутизируют трафик на те же сервисы, что и основной домен.

**Документация:** [`docs/domain-mirrors-guide.md`](../docs/domain-mirrors-guide.md)

### Архитектура

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     DOMAIN MIRRORS ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  values.yaml                                                             │
│  ───────────                                                             │
│  environments:                                                           │
│    dev:                                                                  │
│      domain: "app.demo-poc-01.work"     ← Primary domain                │
│      mirrors:                                                            │
│        - domain: "mirror.example.com"   ← Mirror domain                 │
│          zoneId: "abc123..."            ← CloudFlare Zone ID            │
│                                                                          │
│                           │                                              │
│                           ▼                                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                 Helm Templates Generate                          │   │
│  │                                                                  │   │
│  │  gateway.yaml           httproute-mirrors.yaml                  │   │
│  │  ─────────────          ─────────────────────                   │   │
│  │  Gateway:               HTTPRoute:                               │   │
│  │  listeners:             - name: mirror-0-api                    │   │
│  │   - http-app            - name: mirror-0-frontend               │   │
│  │   - http-mirror-0  ◄────  parentRef: http-mirror-0             │   │
│  │                                                                  │   │
│  │  cloudflared-config.yaml                                         │   │
│  │  ───────────────────────                                         │   │
│  │  ingress:                                                        │   │
│  │    - hostname: mirror.example.com                               │   │
│  │      service: http://cilium-gateway...                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│                           │                                              │
│                           ▼                                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                  Created Resources                               │   │
│  │                                                                  │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │   │
│  │  │ Gateway     │  │ HTTPRoutes  │  │ DNS Record  │             │   │
│  │  │ listener    │  │ for mirror  │  │ (CloudFlare)│             │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘             │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Что создаётся автоматически

При добавлении зеркала в `values.yaml`:

| Ресурс | Название | Описание |
|--------|----------|----------|
| Gateway Listener | `http-mirror-{idx}` | Принимает трафик для mirror домена |
| HTTPRoute | `mirror-{idx}-{route}` | Маршрутизирует на backend сервисы |
| DNS CNAME | `mirror.example.com` | Создаётся external-dns в CloudFlare |
| Tunnel Rule | `hostname: mirror...` | Добавляется в cloudflared ConfigMap |

### Конфигурация

```yaml
# gitops-config/charts/platform-bootstrap/values.yaml

environments:
  dev:
    enabled: true
    domain: "app.demo-poc-01.work"
    mirrors:
      # Простой вариант — использует defaultRoutes
      - domain: "mirror1.example.com"
        zoneId: "cloudflare-zone-id"

      # Расширенный — кастомные маршруты
      - domain: "mirror2.other.net"
        zoneId: "other-zone-id"
        routes:
          - name: api-only
            path: /api
            pathType: PathPrefix
            serviceName: api-gateway-sv
            servicePort: 8080

# Default routes для всех зеркал
domainMirrors:
  enabled: true
  addToGateway: true      # Добавить listeners в Gateway
  createDNS: true         # Создать DNS записи
  addToTunnel: true       # Добавить в CloudFlare Tunnel

  defaultRoutes:
    - name: api
      path: /api
      serviceName: api-gateway-sv
      servicePort: 8080
    - name: frontend
      path: /
      serviceName: sentry-frontend-sv
      servicePort: 4200
```

**Источник:** [`gitops-config/charts/platform-bootstrap/values.yaml:47-80, 279-318`](../gitops-config/charts/platform-bootstrap/values.yaml)

### Ключевые особенности

1. **Не требует изменений в k8app** — зеркала создают параллельные HTTPRoutes
2. **Модульность** — можно включать/выключать отдельные функции
3. **Ingress-agnostic** — работает с CloudFlare Tunnel, HAProxy, Nginx
4. **Автоматический DNS** — external-dns создаёт записи в CloudFlare

### Templates

| Template | Функция |
|----------|---------|
| [`gateway.yaml`](../gitops-config/charts/platform-bootstrap/templates/gateway.yaml) | Добавляет listeners для mirrors |
| [`httproute-mirrors.yaml`](../gitops-config/charts/platform-bootstrap/templates/httproute-mirrors.yaml) | Создаёт HTTPRoutes |
| [`cloudflared-config.yaml`](../gitops-config/charts/platform-bootstrap/templates/cloudflared-config.yaml) | Генерирует tunnel ingress rules |

---

## Service Groups — Universal External Access

### Обзор

Service Groups — универсальный механизм публикации инфраструктурных сервисов (ArgoCD, Grafana, Vault) через домены. Один template обрабатывает все группы — добавление сервиса занимает 5 строк в values.yaml.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     SERVICE GROUPS ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  DOMAIN FORMAT: {subdomain}.{clusterName}.{baseDomain}                   │
│  ────────────────────────────────────────────────────                    │
│  argocd.poc.infra-01.work                                                │
│  grafana.poc.infra-01.work                                               │
│  vault.poc.infra-01.work                                                 │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                     CloudFlare DNS + Tunnel                         │ │
│  │  DNS: *.poc.infra-01.work → {tunnelId}.cfargotunnel.com           │ │
│  │  ⚠️  Требуется Advanced Certificate для multi-level subdomains     │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                    │                                     │
│                                    ▼                                     │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  Namespace: platform                                                │ │
│  │  ─────────────────────                                              │ │
│  │  Gateway: gateway-infrastructure                                    │ │
│  │    ├─ listener: http-argocd  (argocd.poc.infra-01.work)           │ │
│  │    ├─ listener: http-grafana (grafana.poc.infra-01.work)          │ │
│  │    └─ listener: http-vault   (vault.poc.infra-01.work)            │ │
│  │                                                                     │ │
│  │  HTTPRoutes + ReferenceGrants                                       │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│         │                    │                    │                      │
│         ▼                    ▼                    ▼                      │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                │
│  │ ns: argocd  │     │ns: monitoring│     │ ns: vault   │                │
│  │argocd-server│     │   grafana   │     │   vault     │                │
│  └─────────────┘     └─────────────┘     └─────────────┘                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Конфигурация

```yaml
# gitops-config/charts/platform-bootstrap/values.yaml

serviceGroups:
  infrastructure:
    enabled: true
    baseDomain: "infra-01.work"
    clusterName: "poc"                    # Уникальный ID кластера
    gatewayNamespace: "platform"
    zoneId: "cloudflare-zone-id"

    # Опциональная безопасность: только VPN/Office
    security:
      ipWhitelist:
        enabled: false
        cidrs:
          - "10.8.0.0/24"      # VPN range
          - "192.168.1.0/24"   # Office network

    services:
      argocd:
        enabled: true
        subdomain: argocd      # → argocd.poc.infra-01.work
        namespace: argocd
        serviceName: argocd-server
        servicePort: 80

      grafana:
        enabled: true
        subdomain: grafana     # → grafana.poc.infra-01.work
        namespace: monitoring
        serviceName: kube-prometheus-stack-grafana
        servicePort: 80

      vault:
        enabled: true
        subdomain: vault       # → vault.poc.infra-01.work
        namespace: vault
        serviceName: vault
        servicePort: 8200
```

**Источник:** [`gitops-config/charts/platform-bootstrap/values.yaml:319-422`](../gitops-config/charts/platform-bootstrap/values.yaml)

### Что создаётся автоматически

| Ресурс | Описание |
|--------|----------|
| **Namespace** | Namespace для Gateway группы |
| **Gateway** | Listeners для каждого сервиса |
| **HTTPRoute** | Маршрут с cross-namespace routing |
| **ReferenceGrant** | Разрешение routing в другой namespace |
| **DNS** | CNAME через external-dns |
| **Tunnel Rule** | Ingress rule в cloudflared ConfigMap |
| **CiliumNetworkPolicy** | IP whitelist (если enabled) |

### Принцип: Унифицированные домены

**Проблема:** Без стандарта домены хаотичны и сложно запомнить:
- `grafana-dev.company.com`
- `argocd.internal.company.io`
- `vault-prod-eu.ops.net`

**Решение:** Единый формат `{service}.{cluster}.{baseDomain}`:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     UNIFIED DOMAIN NAMING                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  FORMAT: {service}.{clusterName}.{baseDomain}                           │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  POC Cluster (clusterName: poc)                                  │   │
│  │  ─────────────────────────────────                               │   │
│  │  argocd.poc.infra-01.work                                       │   │
│  │  grafana.poc.infra-01.work                                      │   │
│  │  vault.poc.infra-01.work                                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Staging EU (clusterName: staging-eu)                            │   │
│  │  ────────────────────────────────────                            │   │
│  │  argocd.staging-eu.infra-01.work                                │   │
│  │  grafana.staging-eu.infra-01.work                               │   │
│  │  vault.staging-eu.infra-01.work                                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Prod US (clusterName: prod-us)                                  │   │
│  │  ──────────────────────────────                                  │   │
│  │  argocd.prod-us.infra-01.work                                   │   │
│  │  grafana.prod-us.infra-01.work                                  │   │
│  │  vault.prod-us.infra-01.work                                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ПРЕИМУЩЕСТВА:                                                           │
│  • Сразу понятно какой сервис и какой кластер                          │
│  • Легко запомнить паттерн                                              │
│  • Нет путаницы между environments/brands                               │
│  • Один wildcard cert на clusterName: *.poc.infra-01.work              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Multi-Cluster Ready

| Кластер | clusterName | ArgoCD домен |
|---------|-------------|--------------|
| Dev local | poc | argocd.poc.infra-01.work |
| Staging EU | staging-eu | argocd.staging-eu.infra-01.work |
| Prod US | prod-us | argocd.prod-us.infra-01.work |

### Добавление нового сервиса

**5 строк в values.yaml:**

```yaml
serviceGroups:
  infrastructure:
    services:
      prometheus:               # ← Новый сервис
        enabled: true
        subdomain: prometheus   # → prometheus.poc.infra-01.work
        namespace: monitoring
        serviceName: prometheus-server
        servicePort: 9090
```

После `git push` → ArgoCD создаёт всё автоматически.

**Полная документация:** [`docs/service-groups-guide.md`](../docs/service-groups-guide.md)

---

## Security Architecture

### Network Policies

Cilium Network Policies для изоляции:
- Namespace-level isolation
- Service-to-service policies
- Egress control

### RBAC

Kubernetes RBAC для доступа к API:
- ClusterRoles per persona (developer, tech-lead, sre)
- RoleBindings per namespace/environment

**Источник:** [`docs/embodiment/access-management.md`](../docs/embodiment/access-management.md)

### Secrets

Vault для всех секретов:
- No secrets in Git
- Automatic rotation capability
- Audit logging

---

## Resilience

### High Availability

| Компонент | HA Strategy |
|-----------|-------------|
| ArgoCD | Multi-replica, Redis for cache |
| Vault | HA mode, auto-unseal |
| Cilium | DaemonSet on all nodes |
| cloudflared | Multiple replicas |

### Disaster Recovery

- **RTO:** Minutes (ArgoCD re-sync from Git)
- **RPO:** Zero (Git is the source of truth)

ArgoCD может восстановить весь кластер из Git:
```bash
argocd app sync --all
```

---

## Версии компонентов

| Компонент | Версия | Источник |
|-----------|--------|----------|
| Kubernetes | 1.28+ | Minikube/Managed |
| Cilium | 1.18.4 | `infrastructure/cilium/` |
| ArgoCD | 2.9+ | `infrastructure/argocd/` |
| Vault | 1.15 | `infrastructure/vault/` |
| VSO | Latest | `infrastructure/vault/vso-values.yaml` |
| cert-manager | 1.13+ | `infrastructure/cert-manager/` |
| kube-prometheus | 80.4.1 | `infrastructure/monitoring/` |
| k8app | 3.8.0 | `values.yaml` |

---

## Связанные документы

- [Executive Summary](./00-executive-summary.md)
- [GitOps Principles](./02-gitops-principles.md)
- [Observability](./06-observability.md)
- [Multi-Tenancy](./07-multi-tenancy.md) — environments, brands, Vault isolation

---

*Документ создан на основе аудита кодовой базы GitOps POC*
*Дата: 2025-12-21*
