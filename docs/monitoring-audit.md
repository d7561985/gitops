# Monitoring Audit Report

**Date**: 2025-12-14
**Project**: GitOps POC
**Author**: Claude Code Audit

---

## 1. ТЕКУЩИЙ СТАТУС PROMETHEUS TARGETS

| Target | Health | Source |
|--------|--------|--------|
| `api-gateway` | UP | ServiceMonitor poc-dev |
| `health-demo` | UP | ServiceMonitor poc-dev |
| `sentry-game-engine` | DOWN | Образ без /metrics (ожидает CI/CD) |
| `sentry-game-engine-cache` | UP | Redis exporter |
| `sentry-payment` | UP | ServiceMonitor poc-dev |
| `sentry-payment-cache` | UP | Redis exporter |
| `sentry-wager` | DOWN | Образ без /metrics (ожидает CI/CD) |
| `cilium-agent` | UP | ServiceMonitor kube-system |
| `cilium-operator` | UP | ServiceMonitor kube-system |
| `hubble` | UP | ServiceMonitor kube-system |

---

## 2. PROMETHEUS МЕТРИКИ ПО СЕРВИСАМ

### 2.1 Game Engine (Python/Tornado)

**Файл**: `services/sentry-demo/game-engine/main.py:49-78`
**Библиотека**: `prometheus-client==0.21.0` ([PyPI](https://pypi.org/project/prometheus-client/))

| Метрика | Тип | Labels | Описание |
|---------|-----|--------|----------|
| `game_engine_requests_total` | Counter | method, endpoint, status | HTTP requests |
| `game_engine_request_duration_seconds` | Histogram | method, endpoint | Request latency |
| `game_engine_calculations_total` | Counter | result (win/lose) | Game calculations |
| `game_engine_bet_amount` | Histogram | - | Bet distribution |
| `game_engine_payout_amount` | Histogram | - | Payout distribution |
| `game_engine_active_users` | Gauge | - | Active users |

### 2.2 Payment Service (Node.js/Express)

**Файл**: `services/sentry-demo/payment-service/index.js:19-49`
**Библиотека**: `prom-client@15.1.0` ([npm](https://www.npmjs.com/package/prom-client))

| Метрика | Тип | Labels | Описание |
|---------|-----|--------|----------|
| `payment_service_requests_total` | Counter | method, route, status | HTTP requests |
| `payment_service_request_duration_seconds` | Histogram | method, route | Request latency |
| `payment_service_payments_total` | Counter | status, type | Payments processed |
| `payment_service_amount` | Histogram | - | Payment amounts |
| + **Default metrics** | Various | - | nodejs_*, process_* |

### 2.3 Wager Service (PHP/Symfony)

**Файл**: `services/sentry-demo/wager-service/src/Controller/MetricsController.php:13-65`
**Библиотека**: Нативная реализация (без внешних библиотек)

| Метрика | Тип | Labels | Описание |
|---------|-----|--------|----------|
| `wager_service_info` | Gauge | version, php_version | Service info |
| `wager_service_memory_bytes` | Gauge | type (usage/peak) | Memory usage |
| `wager_service_process_id` | Gauge | - | PID |
| `wager_service_uptime_seconds` | Gauge | - | Uptime |
| `wager_service_opcache_memory_bytes` | Gauge | type | OPcache usage |

### 2.4 Health Demo (Go/gRPC)

**Файл**: `services/health-demo/main.go:17-38`
**Библиотека**: `github.com/prometheus/client_golang@v1.19.0` ([Go](https://github.com/prometheus/client_golang))

| Метрика | Тип | Labels | Описание |
|---------|-----|--------|----------|
| `health_demo_grpc_requests_total` | Counter | method, status | gRPC requests |
| `health_demo_grpc_request_duration_seconds` | Histogram | method | gRPC latency |
| + **Default metrics** | Various | - | go_*, process_* |

### 2.5 API Gateway (Envoy)

**Endpoint**: `/stats/prometheus` на порту `8000`
**Конфигурация**: `services/api-gateway/.cicd/default.yaml:72-76`

Envoy автоматически предоставляет ~200+ метрик без дополнительного кода.

---

## 3. ИНФРАСТРУКТУРНЫЙ МОНИТОРИНГ

### 3.1 Компоненты kube-prometheus-stack

**Конфигурация**: `infrastructure/monitoring/helm-values.yaml`

| Компонент | Статус | Назначение |
|-----------|--------|------------|
| Prometheus | Running | Сбор метрик, retention 7d, storage 10Gi |
| Grafana | Running | Визуализация, persistence 1Gi |
| Alertmanager | Running | Алертинг |
| node-exporter | Running | Метрики хоста |
| kube-state-metrics | Running | Метрики K8s объектов |

### 3.2 Cilium/Hubble Observability

**Конфигурация**: `infrastructure/cilium/helm-values.yaml:38-68`

```yaml
hubble:
  metrics:
    enabled:
      - dns:query;ignoreAAAA
      - drop
      - tcp
      - flow
      - icmp
      - http  # L7 HTTP метрики
      - port-distribution
```

---

## 4. GRAFANA ДАШБОРДЫ

### 4.1 Установленные дашборды (28 штук)

**Kubernetes/Infrastructure:**
- kube-prometheus-stack-k8s-resources-cluster
- kube-prometheus-stack-k8s-resources-namespace
- kube-prometheus-stack-k8s-resources-pod
- kube-prometheus-stack-k8s-resources-workload
- kube-prometheus-stack-nodes
- kube-prometheus-stack-kubelet
- kube-prometheus-stack-alertmanager-overview
- kube-prometheus-stack-prometheus

**Cilium/Hubble:**
- hubble-dashboard
- hubble-dns-namespace
- hubble-l7-http-metrics-by-workload
- hubble-network-overview-namespace

### 4.2 Рекомендуемые дашборды

| Язык | Dashboard ID | Название | URL |
|------|-------------|----------|-----|
| Node.js | 11159 | NodeJS Application Dashboard | https://grafana.com/grafana/dashboards/11159 |
| Node.js | 14058 | Node.js Exporter Quickstart | https://grafana.com/grafana/dashboards/14058 |
| Go | 14061 | Go Runtime Exporter | https://grafana.com/grafana/dashboards/14061 |
| Go | 6671 | Go Processes | https://grafana.com/grafana/dashboards/6671 |

---

## 5. RED METHOD COMPLIANCE

| Сервис | Rate | Errors | Duration |
|--------|------|--------|----------|
| game-engine | `_requests_total` | labels: status | `_duration_seconds` |
| payment-service | `_requests_total` | labels: status | `_duration_seconds` |
| health-demo | `_grpc_requests_total` | labels: status | `_duration_seconds` |
| api-gateway | Envoy auto | Envoy auto | Envoy auto |

---

## 6. АРХИТЕКТУРА

```
┌─────────────────────────────────────────────────────────────┐
│                        GRAFANA                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ K8s Dashb.  │  │ Hubble L7   │  │ App Dashboards      │  │
│  │ (28 built-in)│  │ (4 dashb.) │  │ (needs import)      │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────┴───────────────────────────────┐
│                       PROMETHEUS                             │
│  serviceMonitorSelectorNilUsesHelmValues: false              │
│  (discovers ALL ServiceMonitors in ALL namespaces)           │
└─────────────────────────────────────────────────────────────┘
        ▲                    ▲                    ▲
        │                    │                    │
┌───────┴───────┐  ┌─────────┴─────────┐  ┌──────┴───────┐
│  poc-dev (7)  │  │  kube-system (3)  │  │ monitoring(9)│
│               │  │                   │  │              │
│ • api-gateway │  │ • cilium-agent    │  │ • prometheus │
│ • game-engine │  │ • cilium-operator │  │ • grafana    │
│ • payment     │  │ • hubble          │  │ • alertmgr   │
│ • wager       │  │                   │  │ • node-exp   │
│ • health-demo │  └───────────────────┘  │ • kube-state │
│ • *-cache (2) │                         └──────────────┘
└───────────────┘
```

---

## 7. УСТАНОВЛЕННЫЕ ИНФРАСТРУКТУРНЫЕ ДАШБОРДЫ

### 7.1 Версии компонентов в кластере

| Компонент | Версия | Namespace |
|-----------|--------|-----------|
| MongoDB | 5.0.31 | infra-dev |
| RabbitMQ | 3-management | infra-dev |
| Redis | 7-alpine | poc-dev (cache) |
| Envoy | latest (api-gateway) | poc-dev |

### 7.2 Установленные дашборды

| Dashboard | Grafana ID | Folder | Source |
|-----------|-----------|--------|--------|
| Redis Exporter Quickstart | 14091 | Infrastructure | [grafana.com](https://grafana.com/grafana/dashboards/14091) |
| RabbitMQ Monitoring | 4279 | Infrastructure | [grafana.com](https://grafana.com/grafana/dashboards/4279) |
| MongoDB Prometheus Exporter | 2583 | Infrastructure | [grafana.com](https://grafana.com/grafana/dashboards/2583) |
| Envoy Global | 11022 | Infrastructure | [grafana.com](https://grafana.com/grafana/dashboards/11022) |

### 7.3 Требования для работы дашбордов

#### MongoDB Dashboard (ID: 2583)
- **Exporter**: [percona/mongodb_exporter](https://github.com/percona/mongodb_exporter) v0.40.0+
- **Метрики**: `mongodb_*`
- **Порт**: 9216
- **ВАЖНО**: Нужен отдельный deployment с mongodb-exporter

#### Redis Dashboard (ID: 14091)
- **Exporter**: Встроен в k8app cache (redis-exporter sidecar)
- **Метрики**: `redis_*`
- **ServiceMonitor**: `sentry-game-engine-cache`, `sentry-payment-cache`
- **Статус**: Работает

#### RabbitMQ Dashboard (ID: 4279)
- **Exporter**: Встроен в RabbitMQ 3.8+ (`rabbitmq_prometheus` plugin)
- **Метрики**: `rabbitmq_*`
- **Endpoint**: `/metrics` на порту 15692
- **ВАЖНО**: Нужен ServiceMonitor для RabbitMQ

#### Envoy Dashboard (ID: 11022)
- **Exporter**: Встроен в Envoy
- **Метрики**: `envoy_*`
- **Endpoint**: `/stats/prometheus` на порту 8000
- **ServiceMonitor**: `api-gateway`
- **Статус**: Работает

### 7.4 Статус Prometheus Targets для инфраструктуры

| Компонент | Target | Статус |
|-----------|--------|--------|
| MongoDB | serviceMonitor/infra-dev/mongodb/0 | UP |
| RabbitMQ | serviceMonitor/infra-dev/rabbitmq/0 | UP |
| Redis (game-engine-cache) | serviceMonitor/poc-dev/sentry-game-engine-cache/0 | UP |
| Redis (payment-cache) | serviceMonitor/poc-dev/sentry-payment-cache/0 | UP |
| Envoy (api-gateway) | serviceMonitor/poc-dev/api-gateway/0 | UP |

**Конфигурация:**
- MongoDB: `percona/mongodb_exporter:0.40` sidecar в deployment
- RabbitMQ: Built-in `rabbitmq_prometheus` plugin на порту 15692
- Redis: `redis-exporter` sidecar через k8app cache feature
- Envoy: `/stats/prometheus` на порту 8000

### 7.5 Установка дашбордов

```bash
# Скрипт установки
./infrastructure/monitoring/dashboards/install-dashboards.sh

# JSON файлы дашбордов
infrastructure/monitoring/dashboards/json/
├── redis-exporter.json      # ID: 14091
├── rabbitmq-monitoring.json # ID: 4279
├── mongodb.json             # ID: 2583
└── envoy-global.json        # ID: 11022

# Проверка
kubectl get configmaps -n monitoring -l grafana_dashboard=1
```

---

## 8. SOURCES

- [The RED Method - Grafana Labs](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/)
- [prom-client npm](https://www.npmjs.com/package/prom-client)
- [prometheus_client PyPI](https://pypi.org/project/prometheus-client/)
- [prometheus/client_golang](https://github.com/prometheus/client_golang)
