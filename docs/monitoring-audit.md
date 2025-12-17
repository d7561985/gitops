# Monitoring Audit Report

**Date**: 2025-12-14 (updated: 2025-12-17)
**Project**: GitOps POC
**Author**: Claude Code Audit

---

## 1. ТЕКУЩИЙ СТАТУС PROMETHEUS TARGETS

| Target | Health | Source |
|--------|--------|--------|
| `api-gateway` | UP | ServiceMonitor poc-dev |
| `health-demo` | UP | ServiceMonitor poc-dev |
| `user-service` | UP | ServiceMonitor poc-dev |
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

### 2.5 User Service (Go/gRPC)

**Конфигурация**: `services/user-service/.cicd/default.yaml`
**Библиотека**: `github.com/prometheus/client_golang`

| Метрика | Тип | Labels | Описание |
|---------|-----|--------|----------|
| + **Default metrics** | Various | - | go_*, process_* |

> **TODO**: Добавить `go-grpc-prometheus` interceptors для полноценного gRPC мониторинга.
> См. секцию 8.2 для инструкций.

### 2.6 API Gateway (Envoy)

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

**Конфигурация**: `infrastructure/cilium/helm-values.yaml:38-78`

```yaml
hubble:
  metrics:
    enabled:
      # labelsContext добавляет source_workload/destination_workload в метрики
      # Без него видно только "cilium-agent", а не реальные сервисы!
      - dns:query;ignoreAAAA;labelsContext=source_namespace,source_workload,destination_namespace,destination_workload
      - drop:labelsContext=source_namespace,source_workload,destination_namespace,destination_workload
      - tcp:labelsContext=source_namespace,source_workload,destination_namespace,destination_workload
      - flow:labelsContext=source_namespace,source_workload,destination_namespace,destination_workload
      - icmp
      - port-distribution:labelsContext=source_namespace,destination_namespace
      # httpV2 вместо http - лучшие labels включая status code
      - httpV2:labelsContext=source_namespace,source_workload,destination_namespace,destination_workload,traffic_direction
```

**Что даёт labelsContext:**
- Без него: `hubble_http_*{source="cilium-agent"}` (бесполезно)
- С ним: `hubble_http_*{source_workload="api-gateway", destination_workload="game-engine"}` (полезно)

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
| user-service | `go_*` (default only) | - | - |
| api-gateway | Envoy auto | Envoy auto | Envoy auto |

> **Примечание**: user-service требует добавления `go-grpc-prometheus` для полного RED compliance.

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
│  poc-dev (8)  │  │  kube-system (3)  │  │ monitoring(9)│
│               │  │                   │  │              │
│ • api-gateway │  │ • cilium-agent    │  │ • prometheus │
│ • game-engine │  │ • cilium-operator │  │ • grafana    │
│ • payment     │  │ • hubble          │  │ • alertmgr   │
│ • wager       │  │                   │  │ • node-exp   │
│ • health-demo │  └───────────────────┘  │ • kube-state │
│ • user-service│                         └──────────────┘
│ • *-cache (2) │
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

| Dashboard | ID/Source | Folder | Описание |
|-----------|-----------|--------|----------|
| **Redis Exporter Quickstart** | 14091 | Infrastructure | Метрики Redis: память, клиенты, команды |
| **RabbitMQ-Overview** | [Official](https://github.com/rabbitmq/rabbitmq-server/tree/main/deps/rabbitmq_prometheus) | Infrastructure | Официальный от RabbitMQ Team - сообщения, соединения, очереди |
| **MongoDB (Percona Compat)** | 12079 | Infrastructure | Для percona/mongodb_exporter - connections, memory, ops |
| **Envoy Global** | 11022 | Infrastructure | Общий обзор Envoy proxy |
| **Envoy Clusters** | 11021 | Infrastructure | Детальные метрики по upstream clusters |

### 7.3 Совместимость дашбордов с экспортерами

#### MongoDB Dashboard
- **Exporter**: `percona/mongodb_exporter:0.40` с флагом `--compatible-mode`
- **Метрики**: `mongodb_*`, `mongodb_mongod_*`, `mongodb_ss_*` (1973 метрик)
- **Dashboard 12079**: Совместим с percona exporter, показывает connections, memory, ops
- **Примечание**: Dashboard 16490 (Opstree) не подходит - требует replica set метрики

#### RabbitMQ Dashboard
- **Source**: Официальный от [RabbitMQ Team](https://github.com/rabbitmq/rabbitmq-server/tree/main/deps/rabbitmq_prometheus/docker/grafana/dashboards)
- **Plugin**: Встроенный `rabbitmq_prometheus` (RabbitMQ 3.8+)
- **Метрики**: `rabbitmq_*` (1884 метрик)
- **Endpoint**: `/metrics` на порту 15692

#### Redis Dashboard (ID: 14091)
- **Exporter**: Встроен в k8app cache (redis-exporter sidecar)
- **Метрики**: `redis_*`
- **Статус**: Работает

#### Envoy Dashboards
- **Exporter**: Встроен в Envoy
- **Метрики**: `envoy_*`
- **Endpoint**: `/stats/prometheus` на порту 8000
- **Dashboard 11022**: Global overview
- **Dashboard 11021**: Clusters detail

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
├── service-golden-signals.json      # Custom: HTTP + gRPC Golden Signals
├── redis-exporter.json              # ID: 14091
├── rabbitmq-overview-official.json  # Official RabbitMQ Team
├── mongodb-percona-compat.json      # ID: 12079
├── envoy-global.json                # ID: 11022
└── envoy-clusters.json              # ID: 11021

# Проверка
kubectl get configmaps -n monitoring -l grafana_dashboard=1
```

---

## 8. GRPC МОНИТОРИНГ

### 8.1 Важное ограничение Hubble/Cilium

**Hubble eBPF метрики НЕ поддерживают gRPC на уровне L7!**

Hubble предоставляет только `httpV2` метрики:
- `hubble_http_requests_total` - HTTP запросы
- `hubble_http_request_duration_seconds` - HTTP latency

gRPC использует HTTP/2, но Hubble не декодирует gRPC фреймы. Для gRPC мониторинга необходимы **application-level метрики**.

### 8.2 Два подхода к gRPC метрикам

#### Подход 1: go-grpc-prometheus (рекомендуется)

Стандартная библиотека для gRPC мониторинга. Создаёт метрики автоматически.

```go
import (
    grpcprometheus "github.com/grpc-ecosystem/go-grpc-prometheus"
)

// Server
server := grpc.NewServer(
    grpc.UnaryInterceptor(grpcprometheus.UnaryServerInterceptor),
    grpc.StreamInterceptor(grpcprometheus.StreamServerInterceptor),
)
grpcprometheus.Register(server)

// Client
conn, _ := grpc.Dial(address,
    grpc.WithUnaryInterceptor(grpcprometheus.UnaryClientInterceptor),
    grpc.WithStreamInterceptor(grpcprometheus.StreamClientInterceptor),
)
```

**Метрики:**
| Метрика | Тип | Labels | Описание |
|---------|-----|--------|----------|
| `grpc_server_started_total` | Counter | method, service, type | Начатые RPC |
| `grpc_server_handled_total` | Counter | method, service, code | Завершённые RPC |
| `grpc_server_handling_seconds` | Histogram | method, service, type | Latency |
| `grpc_server_msg_received_total` | Counter | method, service, type | Полученные сообщения |
| `grpc_server_msg_sent_total` | Counter | method, service, type | Отправленные сообщения |

#### Подход 2: Custom метрики (текущий health-demo)

Ручное создание метрик в коде. Даёт полный контроль над labels.

```go
var (
    grpcRequests = promauto.NewCounterVec(
        prometheus.CounterOpts{
            Name: "health_demo_grpc_requests_total",
            Help: "Total gRPC requests",
        },
        []string{"method", "status"},
    )
    grpcDuration = promauto.NewHistogramVec(
        prometheus.HistogramOpts{
            Name: "health_demo_grpc_request_duration_seconds",
            Help: "gRPC request duration",
        },
        []string{"method"},
    )
)
```

**Метрики:**
| Метрика | Тип | Labels | Описание |
|---------|-----|--------|----------|
| `{service}_grpc_requests_total` | Counter | method, status | gRPC запросы |
| `{service}_grpc_request_duration_seconds` | Histogram | method | Latency |

### 8.3 Рекомендации по выбору

| Критерий | go-grpc-prometheus | Custom |
|----------|-------------------|--------|
| Время интеграции | 5 минут | 30+ минут |
| Стандартизация | Да (gRPC стандарт) | Нет |
| Совместимость с дашбордами | Grafana ID 14061 и др. | Требуется кастомизация |
| Контроль labels | Ограниченный | Полный |
| Overhead | Минимальный | Зависит от реализации |

**Рекомендация**: Используйте `go-grpc-prometheus` для новых сервисов.

### 8.4 Dashboard для gRPC

Обновлённый дашборд `service-golden-signals.json` поддерживает оба подхода:

```
infrastructure/monitoring/dashboards/json/service-golden-signals.json
```

Дашборд автоматически агрегирует:
- HTTP метрики из Hubble (`hubble_http_*`)
- gRPC метрики из go-grpc-prometheus (`grpc_server_*`)
- Custom gRPC метрики (`{service}_grpc_*`)

### 8.5 Добавление gRPC мониторинга в сервис

1. Добавить зависимость:
```bash
go get github.com/grpc-ecosystem/go-grpc-prometheus
```

2. Подключить interceptors (см. код выше)

3. Убедиться что ServiceMonitor настроен в `.cicd/default.yaml`:
```yaml
serviceMonitor:
  enabled: true
  port: "metrics"
  path: "/metrics"
  interval: 30s
```

4. Метрики появятся в Prometheus после деплоя

---

## 9. SOURCES

- [The RED Method - Grafana Labs](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/)
- [prom-client npm](https://www.npmjs.com/package/prom-client)
- [prometheus_client PyPI](https://pypi.org/project/prometheus-client/)
- [prometheus/client_golang](https://github.com/prometheus/client_golang)
- [go-grpc-prometheus](https://github.com/grpc-ecosystem/go-grpc-prometheus)
- [Cilium Hubble Metrics](https://docs.cilium.io/en/stable/observability/metrics/)
