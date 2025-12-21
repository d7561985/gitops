# Capacity Planning Guide

Руководство по планированию ресурсов кластера и оценке накладных расходов платформы.

## Обзор

Платформа GitOps включает инфраструктурные компоненты, которые потребляют ресурсы независимо от количества приложений. Понимание этих накладных расходов важно для:
- Выбора размера нод
- Планирования бюджета
- Масштабирования кластера

## Типы накладных расходов

### 1. Фиксированные (Static)

Компоненты, которые запускаются **один раз** независимо от количества нод:

| Компонент | Pods | CPU (request) | RAM (request) | Назначение |
|-----------|------|---------------|---------------|------------|
| ArgoCD | 5 | 300m | 640Mi | GitOps, деплой |
| Vault + VSO | 3 | 265m | 384Mi | Секреты |
| Prometheus Stack | 7 | 500m | 784Mi | Мониторинг |
| cert-manager | 3 | 30m | 96Mi | TLS сертификаты |
| external-dns | 1 | 50m | 64Mi | DNS записи |
| cloudflared | 2 | 20m | 128Mi | Ingress tunnel |
| **Итого** | **21** | **~1.2 CPU** | **~2Gi** | |

### 2. Per-Node (DaemonSets)

Компоненты, которые запускаются **на каждой ноде**:

| DaemonSet | CPU/node | RAM/node | Обязательный |
|-----------|----------|----------|--------------|
| Cilium (CNI) | ~50m | ~300Mi | Да |
| Cilium Envoy (L7) | ~5m | ~50Mi | Да |
| kube-proxy | ~1m | ~30Mi | Да |
| node-exporter | ~1m | ~25Mi | Нет* |
| **Итого per node** | **~60m** | **~400Mi** | |

> *node-exporter можно отключить, но потеряете метрики нод

### 3. Per-Namespace

Компоненты, которые создаются для каждого environment:

| Компонент | CPU | RAM | Примечание |
|-----------|-----|-----|------------|
| VaultAuth | 0 | 0 | CRD, не pod |
| Gateway | 0 | 0 | CRD, Cilium обрабатывает |

## Формула расчёта

```
Total Overhead = Static + (Nodes × Per-Node)

Пример для 3 нод:
  Static:   1.2 CPU, 2Gi RAM
  Per-Node: 0.18 CPU, 1.2Gi RAM (3 × 60m, 3 × 400Mi)
  ─────────────────────────────
  Total:    1.38 CPU, 3.2Gi RAM
```

## Эффективность по масштабу

| Нод | Infra CPU | Infra RAM | % overhead (от 10 CPU/8Gi ноды) |
|-----|-----------|-----------|----------------------------------|
| 1 | 1.26 CPU | 2.4Gi | **12.6% CPU, 30% RAM** |
| 3 | 1.38 CPU | 3.2Gi | **4.6% CPU, 13% RAM** |
| 5 | 1.50 CPU | 4.0Gi | **3% CPU, 10% RAM** |
| 10 | 1.80 CPU | 6.0Gi | **1.8% CPU, 7.5% RAM** |

> При масштабировании фиксированный overhead "размазывается" по нодам

## Минимальные требования

### Development (1 нода)

```yaml
# Минимум для запуска платформы
Node:
  CPU: 4 cores
  RAM: 8Gi

# Breakdown:
#   Infrastructure: ~1.3 CPU, ~2.4Gi
#   Applications:   ~2.7 CPU, ~5.6Gi (доступно)
```

### Production (3+ ноды)

```yaml
# Рекомендуется для HA
Nodes: 3+
Per Node:
  CPU: 4-8 cores
  RAM: 16Gi

# При 3 нодах × 8 CPU, 16Gi:
#   Total:          24 CPU, 48Gi
#   Infrastructure: ~1.4 CPU, ~3.2Gi (~6%)
#   Applications:   ~22.6 CPU, ~44.8Gi (доступно)
```

## Оптимизация

### Уменьшение overhead

1. **Отключить ненужные компоненты:**
   ```yaml
   # values.yaml
   monitoring:
     enabled: false  # -500m CPU, -784Mi RAM
   ```

2. **Уменьшить реплики:**
   ```yaml
   cloudflare:
     replicas: 1  # вместо 2, -10m CPU, -64Mi RAM
   ```

3. **Использовать managed services:**
   - Managed Prometheus (GCP, AWS) вместо self-hosted
   - Managed Vault (HCP Vault) вместо self-hosted

### Что нельзя отключить

| Компонент | Причина |
|-----------|---------|
| Cilium | CNI, сеть не работает без него |
| ArgoCD | Core GitOps, без него нет деплоя |
| VSO | Секреты не синхронизируются |

## Мониторинг overhead

### Prometheus запросы

```promql
# CPU overhead инфраструктуры
sum(rate(container_cpu_usage_seconds_total{namespace=~"kube-system|argocd|vault|monitoring|cloudflare|external-dns|cert-manager"}[5m]))

# RAM overhead инфраструктуры
sum(container_memory_working_set_bytes{namespace=~"kube-system|argocd|vault|monitoring|cloudflare|external-dns|cert-manager"})

# % от общего потребления
sum(rate(container_cpu_usage_seconds_total{namespace=~"kube-system|argocd|vault|monitoring"}[5m]))
/
sum(rate(container_cpu_usage_seconds_total[5m])) * 100
```

### Grafana Dashboard

Рекомендуется создать dashboard с:
- Infrastructure vs Applications CPU/RAM
- Per-namespace breakdown
- DaemonSet resource usage

## Стоимость (примерная)

### GKE (n2-standard-4, us-central1)

| Конфигурация | Нод | $/month | Infra % | Effective $/app |
|--------------|-----|---------|---------|-----------------|
| Dev | 1 | ~$100 | 30% | $70 |
| Small Prod | 3 | ~$300 | 10% | $270 |
| Medium Prod | 5 | ~$500 | 6% | $470 |

### EKS (m5.xlarge, us-east-1)

| Конфигурация | Нод | $/month | Infra % | Effective $/app |
|--------------|-----|---------|---------|-----------------|
| Dev | 1 | ~$120 | 30% | $84 |
| Small Prod | 3 | ~$360 | 10% | $324 |
| Medium Prod | 5 | ~$600 | 6% | $564 |

> Цены приблизительные, не включают storage, traffic, managed services

## Checklist при планировании

- [ ] Определить количество environments (dev, staging, prod)
- [ ] Оценить количество сервисов и их ресурсы
- [ ] Добавить 30% buffer для пиков
- [ ] Учесть infrastructure overhead (~1.5 CPU, ~3Gi для базового сетапа)
- [ ] Добавить ~60m CPU, ~400Mi RAM per node для DaemonSets
- [ ] Запланировать мониторинг overhead в production

## См. также

- [new-service-guide.md](./new-service-guide.md) — добавление сервисов
- [PREFLIGHT-CHECKLIST.md](./PREFLIGHT-CHECKLIST.md) — первоначальная настройка
- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
