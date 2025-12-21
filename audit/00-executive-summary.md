# Executive Summary: GitOps Platform Architecture

## Для руководителей и архитекторов

Данный документ описывает высокоуровневую архитектуру GitOps-платформы, разработанной для обеспечения **декларативного**, **автоматизированного** и **агностичного к окружениям** подхода к разработке и эксплуатации программного обеспечения.

---

## Ключевые принципы

### 1. Декларативность
**Вся инфраструктура и конфигурация описаны как код**

Платформа использует декларативный подход, где желаемое состояние системы описывается в Git-репозитории. Это обеспечивает:
- Полную воспроизводимость окружений
- Аудируемость всех изменений через Git history
- Возможность review изменений до применения

**Источник:** [`gitops-config/charts/platform-bootstrap/values.yaml`](../gitops-config/charts/platform-bootstrap/values.yaml) — единый источник истины для всей платформы

### 2. Агностичность к окружениям
**Один код — множество окружений**

Конфигурация разделена на:
- **`default.yaml`** — базовые параметры, не зависящие от окружения
- **`{env}.yaml`** — переопределения для конкретного окружения (dev/staging/prod)

```
services/{service}/.cicd/
├── default.yaml      # Порты, health checks, зависимости
├── dev.yaml          # image.tag, replicas: 1, resources
├── staging.yaml      # replicas: 2, staging-specific URLs
└── prod.yaml         # replicas: 3, HPA, PDB
```

**Источник:** [`docs/multi-tenancy-guide.md`](../docs/multi-tenancy-guide.md)

### 3. Автоматизация и простота
**Минимум ручных действий для деплоя**

| Этап | Ручные действия | Автоматизированные действия |
|------|-----------------|----------------------------|
| Добавить сервис | 1 строка в `values.yaml` | Namespace, Vault policies, ArgoCD App |
| Деплой в dev | `git push` | Build → Registry → .cicd update → ArgoCD sync |
| Деплой в prod | Merge PR | ArgoCD sync |
| Секреты | Vault UI | VSO sync → K8s Secret |
| Добавить домен-зеркало | `mirrors:` в `values.yaml` | Gateway listener, HTTPRoutes, DNS, Tunnel |
| Сменить ingress provider | `ingress.provider:` | DNS target обновляется автоматически |
| Добавить новый API | Cluster в `api-gateway/config.yaml` | /api/{service}/* routing через единый endpoint |
| Опубликовать infra-сервис | 5 строк в `serviceGroups:` | Gateway, HTTPRoute, DNS, Tunnel, ReferenceGrant |
| Preview для MR | Ветка с JIRA тегом | Namespace, Deployment, HTTPRoute, DNS, auto-cleanup |

**Источник:** [`docs/new-service-guide.md`](../docs/new-service-guide.md)

### 4. Multi-Tenancy
**Один кластер — множество tenant'ов**

Платформа поддерживает изоляцию на уровне:
- **Environments** — dev/staging/prod в одном кластере
- **Brands/Products** — разные продукты с разными `namespacePrefix`
- **Secrets** — Vault policies изолируют секреты по `{prefix}/{service}/{env}/`

```
Cluster
├── poc-dev, poc-staging, poc-prod        ← Tenant A
├── casino-dev, casino-prod               ← Tenant B
├── infra-dev, infra-staging, infra-prod  ← Shared infrastructure
└── argocd, vault, monitoring             ← Platform layer
```

**Источник:** [`07-multi-tenancy.md`](./07-multi-tenancy.md), [`docs/multi-tenancy-guide.md`](../docs/multi-tenancy-guide.md)

---

## GitOps Pull-Based подход

### Модель реконсиляции

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      GitOps RECONCILIATION LOOP                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Git Repository                     Kubernetes Cluster                 │
│   ──────────────                     ──────────────────                 │
│   ┌────────────┐                     ┌────────────────┐                 │
│   │ Desired    │ ◄───── Polling ────►│  ArgoCD        │                 │
│   │ State      │        (3 min)      │  Controller    │                 │
│   │            │                     │                │                 │
│   │ values.yaml│                     │  Compares      │                 │
│   │ templates/ │                     │  Desired vs    │                 │
│   │            │                     │  Actual State  │                 │
│   └────────────┘                     └───────┬────────┘                 │
│                                              │                          │
│                                              ▼                          │
│                                      ┌────────────────┐                 │
│                                      │  Actual State  │                 │
│                                      │  (K8s objects) │                 │
│                                      └────────────────┘                 │
│                                                                          │
│   Гарантия: То что в Git = То что в кластере                            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Pull-based преимущества:**
- CI/CD не имеет прямого доступа к кластеру (безопасность)
- ArgoCD периодически сверяет и корректирует drift
- Полный аудит через Git history

**Источник:** [`gitops-config/argocd/README.md`](../gitops-config/argocd/README.md), [`README.md:463-513`](../README.md)

---

## Два уровня управления

### Слой платформы (Platform Layer)

**Ответственные:** Platform/SRE команда

| Компонент | Назначение | Источник |
|-----------|------------|----------|
| **Cilium CNI** | Networking, eBPF, Gateway API | [`infrastructure/cilium/`](../infrastructure/cilium/) |
| **HashiCorp Vault** | Secrets management | [`infrastructure/vault/`](../infrastructure/vault/) |
| **ArgoCD** | GitOps CD controller | [`infrastructure/argocd/`](../infrastructure/argocd/) |
| **cert-manager** | TLS сертификаты | [`infrastructure/cert-manager/`](../infrastructure/cert-manager/) |
| **kube-prometheus-stack** | Monitoring | [`infrastructure/monitoring/`](../infrastructure/monitoring/) |

**Автоматизация:** `platform-bootstrap` Helm chart создаёт всё необходимое для сервисов:
- Namespaces
- Vault policies и roles
- VaultAuth ресурсы
- Gateway listeners
- ArgoCD Applications

**Источник:** [`gitops-config/charts/platform-bootstrap/`](../gitops-config/charts/platform-bootstrap/)

### Слой приложений (Application Layer)

**Ответственные:** Продуктовые команды

| Компонент | Назначение | Источник |
|-----------|------------|----------|
| **k8app Helm Chart** | Унифицированный деплой | [k8app v3.8.0](https://d7561985.github.io/k8app) |
| **CI/CD Pipeline** | Build, test, update gitops | [`templates/service-repo/.gitlab-ci.yml`](../templates/service-repo/.gitlab-ci.yml) |
| **Proto Generation** | API контракты | [`api/proto/`](../api/proto/) |
| **Service Configs** | `.cicd/` директория | [`templates/service-repo/.cicd/`](../templates/service-repo/.cicd/) |

---

## Стандартизация API (Buf + ConnectRPC)

### Централизованный API Registry

```
api/
├── proto/                          # Proto определения
│   ├── user-service/              # Контракт user-service
│   ├── game-engine/               # Контракт game-engine
│   ├── payment-service/           # Контракт payment-service
│   └── wager-service/             # Контракт wager-service
│
└── gen/                           # Сгенерированный код
    ├── go/                        # Go пакеты
    ├── nodejs/                    # NPM пакеты
    ├── php/                       # Composer пакеты
    ├── python/                    # PyPI пакеты
    └── angular/                   # Angular services
```

**Преимущества API Registry:**
- Единый источник истины для всех API
- Автоматическая генерация кода для 5 языков
- Breaking change detection в CI
- Переиспользуемые пакеты для всех сервисов

**Источник:** [`docs/proto-grpc-infrastructure.md`](../docs/proto-grpc-infrastructure.md)

### Connect Protocol

**Вместо gRPC-Web** используется Connect Protocol (CNCF, 2024), который:
- Не требует прокси (работает через любой HTTP)
- Поддерживает JSON debugging
- Совместим с существующими gRPC серверами

**Источник:** [`docs/connect-migration-architecture.md`](../docs/connect-migration-architecture.md)

---

## eBPF Observability (Cilium Hubble)

### Сетевая видимость без агентов

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        HUBBLE OBSERVABILITY                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Cilium Agent (eBPF)                    Hubble Stack                   │
│   ───────────────────                    ───────────────                │
│   Kernel-level packet                    ┌─────────────┐                │
│   inspection via eBPF    ───────────────►│ hubble-relay│                │
│                          flow events     └──────┬──────┘                │
│   • L3/L4 flows                                 │                       │
│   • L7 HTTP/gRPC                                ▼                       │
│   • DNS queries                          ┌─────────────┐                │
│   • Network policies                     │  hubble-ui  │                │
│                                          │  (Service   │                │
│                                          │   Map)      │                │
│                                          └─────────────┘                │
│                                                                          │
│   Prometheus Metrics:                                                    │
│   • hubble_flows_processed_total                                        │
│   • hubble_dns_queries_total                                            │
│   • hubble_http_requests_total                                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источник:** [`docs/embodiment/cni-comparison-cilium-vs-calico.md`](../docs/embodiment/cni-comparison-cilium-vs-calico.md)

---

## Модель команд

### До: Разделение Dev и Ops

```
┌──────────────┐          ┌──────────────┐
│  Dev Team    │  ─────►  │  Ops Team    │
│              │  "deploy │              │
│ • Code       │   this"  │ • kubectl    │
│ • Features   │          │ • Helm       │
│ • Bugs       │          │ • Secrets    │
└──────────────┘          └──────────────┘
```

### После: Кросс-функциональные команды + Platform Team

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     CROSS-FUNCTIONAL TEAMS                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────┐   ┌────────────────────┐   ┌──────────────────┐ │
│  │  Product Team A    │   │  Product Team B    │   │  Product Team C  │ │
│  │                    │   │                    │   │                  │ │
│  │  Full ownership:   │   │  Full ownership:   │   │  Full ownership: │ │
│  │  • Code            │   │  • Code            │   │  • Code          │ │
│  │  • .cicd/ configs  │   │  • .cicd/ configs  │   │  • .cicd/ configs│ │
│  │  • Secrets (Vault) │   │  • Secrets (Vault) │   │  • Secrets       │ │
│  │  • Monitoring      │   │  • Monitoring      │   │  • Monitoring    │ │
│  │  • Deploys (dev)   │   │  • Deploys (dev)   │   │  • Deploys (dev) │ │
│  └────────────────────┘   └────────────────────┘   └──────────────────┘ │
│                                                                          │
│                                 ▲                                        │
│                                 │ Self-service                          │
│                                 │                                        │
│  ┌──────────────────────────────┴───────────────────────────────────┐   │
│  │                      PLATFORM TEAM                                 │   │
│  │                                                                    │   │
│  │  Provides:                        Maintains:                       │   │
│  │  • k8app Helm chart               • Kubernetes cluster            │   │
│  │  • CI/CD templates                • Cilium/Gateway API            │   │
│  │  • platform-bootstrap             • Vault/ArgoCD                  │   │
│  │  • Proto generation               • Monitoring stack              │   │
│  │  • Documentation                  • Security policies             │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источник:** [`docs/embodiment/access-management.md`](../docs/embodiment/access-management.md)

---

## Автоматизация инфраструктуры (k8app)

### Пример: Автоматический Redis

k8app Helm chart поддерживает автоматическое развёртывание зависимостей:

```yaml
# services/my-service/.cicd/default.yaml
dependencies:
  redis:
    enabled: true
    # Автоматически создаёт Redis StatefulSet
    # Автоматически добавляет REDIS_URL в configmap
```

**Результат:** Команда получает Redis без участия Platform Team.

**Источник:** [k8app documentation](https://d7561985.github.io/k8app)

---

## Метрики успеха платформы

| Метрика | До | После |
|---------|-----|--------|
| **Lead Time** (commit → prod) | Дни | Часы |
| **Deployment Frequency** | Еженедельно | Несколько раз в день |
| **MTTR** (time to recovery) | Часы | Минуты (ArgoCD rollback) |
| **Change Failure Rate** | Высокий | Низкий (preview, review) |

---

## Связанные документы

| Документ | Описание |
|----------|----------|
| [`01-platform-architecture.md`](./01-platform-architecture.md) | Детальная архитектура платформы |
| [`02-gitops-principles.md`](./02-gitops-principles.md) | Принципы GitOps |
| [`03-developer-experience.md`](./03-developer-experience.md) | Developer Experience и SDLC |
| [`04-api-standards.md`](./04-api-standards.md) | Стандарты API (Buf, ConnectRPC) |
| [`05-team-model.md`](./05-team-model.md) | Модель команд и RACI |
| [`06-observability.md`](./06-observability.md) | Observability и eBPF |
| [`07-multi-tenancy.md`](./07-multi-tenancy.md) | Environments, brands, Vault isolation |

---

## Заключение

Представленная архитектура обеспечивает:

1. **Скорость** — от commit до production за минуты
2. **Надёжность** — декларативное состояние, автоматическая реконсиляция
3. **Безопасность** — GitOps audit trail, Vault secrets, RBAC
4. **Масштабируемость** — добавление сервисов без увеличения нагрузки на Platform Team
5. **Автономность команд** — self-service для продуктовых команд
6. **Multi-tenancy** — один кластер для всех environments и brands с полной изоляцией

**Все утверждения в данном документе подкреплены ссылками на реальные файлы кодовой базы.**

---

*Документ создан на основе аудита кодовой базы GitOps POC*
*Дата: 2025-12-21*
