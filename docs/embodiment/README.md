# Platform Embodiment Vision

Высокоуровневый план внедрения технологического стека GitOps платформы.

## Содержание

- [Текущее состояние POC](#текущее-состояние-poc)
- [Архитектура Embodiment](#архитектура-embodiment)
- [План по фазам](#план-embodiment-по-фазам)
- [Порядок внедрения](#порядок-embodiment-dependency-graph)
- [Риски и митигации](#риски-и-митигации)
- [Что копировать из POC](#что-копировать-из-poc)

**Связанные документы:**
- [Access Management & RACI Matrix](./access-management.md) — управление доступами, роли, политики
- [CNI Comparison: Cilium vs Calico](./cni-comparison-cilium-vs-calico.md) — сравнительный анализ CNI решений
- [Frontend + gRPC Protocols 2025](./frontend-grpc-protocols-2025.md) — gRPC-Web, Connect-RPC, tRPC сравнение

---

## Текущее состояние POC

| Компонент | Статус | Готовность |
|-----------|--------|------------|
| **GitOps (ArgoCD + Push)** | Полностью готов | POC → Production |
| **k8app Helm Chart** | v3.8.0 с VSO | Готов к использованию |
| **Vault + VSO** | Автоматизация через bootstrap | Production-ready |
| **CI/CD Templates** | Pull/Push режимы | Копировать в сервисы |
| **Proto/gRPC Generation** | 5 языков | Готов к использованию |
| **Monitoring (Prometheus/Grafana)** | Dashboards готовы | Production-ready |
| **Gateway API (Cilium)** | HTTPRoute | Production-ready |
| **Multi-environment** | dev enabled | Нужно включить staging/prod |

---

## Архитектура Embodiment

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          PLATFORM EMBODIMENT                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐   │
│  │   FOUNDATION   │ →  │   AUTOMATION    │ →  │   SERVICE ONBOARDING    │   │
│  │                │    │                 │    │                         │   │
│  │ • Kubernetes   │    │ • GitLab CI/CD  │    │ • service-repo template │   │
│  │ • Cilium CNI   │    │ • ArgoCD        │    │ • proto-service template│   │
│  │ • Vault        │    │ • platform-boot │    │ • .cicd/ values         │   │
│  │ • Monitoring   │    │ • k8app chart   │    │ • .gitlab-ci.yml        │   │
│  └────────────────┘    └─────────────────┘    └─────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                         DEVELOPER WORKFLOW                               ││
│  │                                                                          ││
│  │  1. git clone template  →  2. код + Dockerfile  →  3. git push         ││
│  │                                        ↓                                 ││
│  │  6. ArgoCD deploys ← 5. .cicd/*.yaml updated ← 4. CI builds image      ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## План Embodiment по фазам

### Фаза 0: Pre-requisites (Foundation)

**Цель:** Подготовка инфраструктуры кластера

| Шаг | Действие | Зависимости |
|-----|----------|-------------|
| 0.1 | Kubernetes кластер (managed или self-hosted) | — |
| 0.2 | Cilium CNI с Gateway API | K8s |
| 0.3 | cert-manager + CloudFlare DNS01 | K8s |
| 0.4 | HashiCorp Vault + VSO | K8s |
| 0.5 | ArgoCD + GitLab Agent | K8s, GitLab |
| 0.6 | kube-prometheus-stack + Grafana | K8s |

**Скрипты из POC:** `shared/infrastructure/*/setup.sh`

---

### Фаза 1: Platform Bootstrap

**Цель:** Единый source of truth для всей платформы

```yaml
# Что делает platform-core chart:
1. Создает namespaces (poc-dev, poc-staging, poc-prod)
2. Настраивает Vault policies/roles автоматически
3. Создает VaultAuth ресурсы
4. Генерирует ArgoCD Applications через ApplicationSet
5. Создает Gateway ресурсы (если enabled)
```

**Действия:**

| Шаг | Действие |
|-----|----------|
| 1.1 | Скопировать `infra/poc/gitops-config/` в свой GitLab |
| 1.2 | Настроить `values.yaml` под свою организацию |
| 1.3 | Добавить сервисы в `services:` секцию |
| 1.4 | Включить environments (dev/staging/prod) |
| 1.5 | ArgoCD sync → всё создается автоматически |

---

### Фаза 2: CI/CD Pipeline Migration

**Цель:** Унификация всех сервисов под единый CI/CD паттерн

```
BEFORE (ad-hoc):                    AFTER (unified):
┌──────────────────┐                ┌──────────────────┐
│ service-A        │                │ service-A        │
│ └─ custom CI     │                │ ├─ .cicd/        │
├──────────────────┤       →        │ │ ├─ default.yaml│
│ service-B        │                │ │ ├─ dev.yaml    │
│ └─ different CI  │                │ │ └─ prod.yaml   │
├──────────────────┤                │ └─ .gitlab-ci.yml│ (template)
│ service-C        │                └──────────────────┘
│ └─ no CI         │
└──────────────────┘
```

**Действия для каждого сервиса:**

| Шаг | Действие | Источник |
|-----|----------|----------|
| 2.1 | Скопировать `.cicd/` директорию | `shared/templates/service-repo/.cicd/` |
| 2.2 | Скопировать `.gitlab-ci.yml` | `shared/templates/service-repo/.gitlab-ci.yml` |
| 2.3 | Настроить `default.yaml` (ports, env vars, secrets) | — |
| 2.4 | Настроить `dev.yaml` (image repository) | — |
| 2.5 | Добавить сервис в `platform/core.yaml` | — |

**CI/CD Variables (на уровне группы):**

```
CI_PUSH_TOKEN      - Personal Access Token (write_repository)
ARGOCD_SERVER      - argocd.your-domain.com
ARGOCD_AUTH_TOKEN  - ArgoCD API token
GITOPS_MODE        - pull (default) или push
```

---

### Фаза 3: k8app Deployment Integration

**Цель:** Стандартизация Helm values для всех сервисов

**Структура `.cicd/`:**

```yaml
.cicd/
├── default.yaml      # Общее для всех окружений
│   ├── appName
│   ├── service.ports
│   ├── configmap (env vars)
│   ├── configfiles (mounted files)
│   ├── secrets + secretsProvider (Vault)
│   └── healthchecks
│
├── dev.yaml          # Dev-specific
│   ├── image.repository/tag
│   ├── replicas: 1
│   ├── resources (minimal)
│   └── configmap overrides (LOG_LEVEL: debug)
│
├── staging.yaml      # Staging-specific
│   └── replicas, resources
│
└── prod.yaml         # Prod-specific
    ├── replicas: 3
    ├── resources (full)
    ├── hpa (autoscaling)
    └── pdb (disruption budget)
```

**Vault Integration (автоматическая):**

```yaml
# k8app v3.8.0 автоматически создает VaultStaticSecret
secrets:
  DB_PASSWORD: "database"    # → {ns}/{app}/{env}/database
  API_KEY: "config"          # → {ns}/{app}/{env}/config

secretsProvider:
  provider: vault
  vault:
    authRef: vault-auth       # Создается platform-core
    mount: secret
    type: kv-v2
```

---

### Фаза 4: Proto/gRPC Infrastructure

**Цель:** Автоматическая генерация кода из .proto файлов

```
┌─────────────────────────────────────────────────────────────────────┐
│                     PROTO GENERATION FLOW                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  api/proto/{service}/          api/gen/{service}/                   │
│  ├── buf.yaml                  ├── go/       → go get ...           │
│  ├── buf.gen.yaml              ├── nodejs/   → npm install ...      │
│  └── proto/                    ├── php/      → composer require ... │
│      └── v1/                   ├── python/   → pip install ...      │
│          └── service.proto     └── angular/  → npm install ...      │
│                                                                     │
│  git push → CI lint → breaking check → buf generate → publish       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Действия:**

| Шаг | Действие |
|-----|----------|
| 4.1 | Создать GitLab sub-groups: `api/proto/`, `api/gen/` |
| 4.2 | Настроить CI_PUSH_TOKEN + GEN_GROUP_ID |
| 4.3 | Скопировать `.gitlab-ci.yml` из `shared/templates/proto-service/` (Zero-Config!) |
| 4.4 | Написать `.proto` файлы в `proto/` директорию |
| 4.5 | Push → автогенерация для 5 языков (buf.yaml генерируется автоматически) |

**Versioning:**

- `dev` branch → `v0.0.0-{sha}` (snapshots)
- `main` + tag → `v1.2.3` (releases)

---

### Фаза 5: Observability Enablement

**Цель:** Мониторинг всех сервисов из коробки

**Компоненты:**

```
┌────────────────────────────────────────────────────────────────────┐
│                     OBSERVABILITY STACK                             │
├─────────────────┬─────────────────┬────────────────────────────────┤
│   Prometheus    │     Grafana     │         Hubble (Cilium)        │
│                 │                 │                                │
│ • Scrape pods   │ • Golden Signals│ • L3/L4/L7 network flows       │
│ • ServiceMonitor│ • Per-service   │ • Service dependency map       │
│ • AlertManager  │ • Infrastructure│ • Network policy audit         │
└─────────────────┴─────────────────┴────────────────────────────────┘
```

**k8app автоматически включает:**

```yaml
# При наличии метрик порта - создается ServiceMonitor
metrics:
  enabled: true
  port: 9090
  path: /metrics
```

**Dashboards из POC:**

- `service-golden-signals.json` - RED метрики через Hubble
- `envoy-*.json` - API Gateway метрики
- `mongodb/rabbitmq/redis` - Infra dashboards

---

## Порядок Embodiment (Dependency Graph)

```
                    ┌─────────────────┐
                    │  0. Foundation  │
                    │   (Kubernetes)  │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ↓              ↓              ↓
     ┌────────────────┐ ┌────────────┐ ┌──────────────┐
     │ Cilium + GW API│ │ Vault + VSO│ │ Monitoring   │
     └────────┬───────┘ └─────┬──────┘ └──────┬───────┘
              │               │               │
              └───────────────┼───────────────┘
                              ↓
                    ┌─────────────────┐
                    │ 1. Platform     │
                    │    Bootstrap    │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ↓              ↓              ↓
     ┌────────────────┐ ┌────────────┐ ┌──────────────┐
     │ 2. CI/CD       │ │ 3. k8app   │ │ 4. ProtoGen  │
     │    Migration   │ │ Integration│ │              │
     └────────────────┘ └────────────┘ └──────────────┘
                              │
                              ↓
                    ┌─────────────────┐
                    │ 5. Observability│
                    │    Enablement   │
                    └─────────────────┘
```

---

## Риски и митигации

| Риск | Митигация |
|------|-----------|
| **k8app breaking changes** | Зафиксировать версию (v3.8.0), тестировать апгрейды |
| **Vault unavailable** | Graceful degradation, fallback к K8s Secrets |
| **ArgoCD sync delays** | Webhook вместо polling (3 min → instant) |
| **Proto breaking changes** | CI проверяет `buf breaking`, блокирует merge |
| **Multi-cluster** | Отдельный `infra/{brand}/gitops-config` per cluster |

---

## Что копировать из POC

```
gitops/
├── infra/poc/gitops-config/    # → В GitLab: infra/{brand}/gitops-config
│   ├── charts/platform-core/   # Single source of truth
│   └── argocd/                 # App of Apps
│
├── shared/
│   ├── templates/
│   │   ├── service-repo/       # → Шаблон для каждого сервиса
│   │   │   ├── .cicd/
│   │   │   └── .gitlab-ci.yml
│   │   │
│   │   └── proto-service/      # → Шаблон для proto сервисов
│   │       ├── buf.yaml
│   │       ├── buf.gen.yaml
│   │       └── proto/
│   │
│   └── infrastructure/         # → Setup scripts (adapt to your env)
│       ├── */setup.sh
│       └── monitoring/dashboards/
│
├── docs/                       # → Документация
│   ├── PREFLIGHT-CHECKLIST.md
│   ├── proto-grpc-infrastructure.md
│   └── k8app-recommendations.md
│
└── scripts/                    # → Automation scripts
    ├── init-project.sh
    └── setup-*.sh
```

---

## Summary: Что получаем

| До | После |
|----|-------|
| Ручной kubectl/helm | ArgoCD автосинк из Git |
| Хардкод секретов | Vault + автоматическая ротация |
| Adhoc CI/CD | Unified pipeline template |
| Копипаста конфигов | k8app Helm chart |
| Ручная proto-генерация | Автоматическая 5-языковая |
| Отсутствие visibility | Prometheus + Grafana + Hubble |

---

## Следующие шаги

Детальные инструкции по каждой фазе:

- [Фаза 0: Foundation Setup](./phase-0-foundation.md) *(planned)*
- [Фаза 1: Platform Modules](./phase-1-platform-modules.md) *(planned)*
- [Фаза 2: CI/CD Migration](./phase-2-cicd-migration.md) *(planned)*
- [Фаза 3: k8app Integration](./phase-3-k8app-integration.md) *(planned)*
- [Фаза 4: Proto/gRPC Setup](./phase-4-protogen.md) *(planned)*
- [Фаза 5: Observability](./phase-5-observability.md) *(planned)*
