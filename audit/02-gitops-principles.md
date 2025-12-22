# GitOps Principles

## Обзор

Данный документ описывает принципы GitOps, реализованные в платформе, и их практическое применение.

---

## Что такое GitOps

GitOps — операционная модель для cloud-native приложений, где:

1. **Git** является единственным источником истины для декларативной инфраструктуры и приложений
2. **Автоматизированные процессы** (операторы) непрерывно сверяют и синхронизируют фактическое состояние с желаемым
3. **Все изменения** проходят через Git (Pull Request, review, audit trail)

---

## Четыре принципа GitOps (CNCF)

### 1. Декларативность

> Вся система описана декларативно

**Реализация в платформе:**

```yaml
# Вместо императивных команд:
# kubectl create namespace poc-dev
# kubectl apply -f deployment.yaml
# helm install my-app ...

# Используется декларативное описание:
# gitops-config/platform/core.yaml

environments:
  dev:
    enabled: true           # ← Желаемое состояние
    autoSync: true
    domain: "app.demo-poc-01.work"

services:
  api-gateway:              # ← Желаемое состояние
    syncWave: "0"
  user-service:
    syncWave: "0"
```

**Преимущества:**
- Воспроизводимость: любой может пересоздать систему из Git
- Версионность: вся история изменений сохранена
- Review: изменения можно проверить до применения

**Источник:** [`gitops-config/platform/core.yaml`](../gitops-config/platform/core.yaml)

---

### 2. Версионирование и неизменяемость

> Желаемое состояние хранится с возможностью отката

**Реализация:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        GIT AS SOURCE OF TRUTH                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Git History (Immutable)                                                 │
│  ───────────────────────                                                 │
│                                                                          │
│  commit abc123: "feat: add user-service"                                │
│  commit def456: "fix: increase replicas to 3"                           │
│  commit ghi789: "chore: update api-gateway to v2.1.0"    ◄── HEAD       │
│                                                                          │
│  Rollback:                                                               │
│  ─────────                                                               │
│  git revert ghi789  → Creates new commit                                │
│  ArgoCD syncs       → Deploys previous state                            │
│                                                                          │
│  Benefits:                                                               │
│  • Complete audit trail                                                  │
│  • Easy rollback to any point                                            │
│  • Blame/bisect for debugging                                            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Структура репозиториев:**

| Repository | Содержимое | Изменяется |
|------------|------------|------------|
| `gitops-config` | Platform config, ArgoCD apps | Platform Team |
| `services/{name}` | Service code + `.cicd/` | Product Teams |
| `api/proto` | Proto definitions | API owners |
| `api/gen` | Generated code | CI automation |

**Источник:** [`README.md:156-200`](../README.md)

---

### 3. Автоматическое применение (Pull)

> Approved changes automatically applied to the system

**Pull-Based Model:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PULL-BASED DEPLOYMENT                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ТРАДИЦИОННЫЙ CI/CD (Push)              GitOps (Pull)                   │
│  ─────────────────────────              ─────────────                   │
│                                                                          │
│  CI Server ──push──► Cluster            Git ◄──poll── ArgoCD           │
│  (has credentials)                       │              │                │
│                                          │              ▼                │
│  Problems:                               │        ┌──────────┐           │
│  • CI needs cluster access               │        │ Compare  │           │
│  • Credentials spread                    │        │ Desired  │           │
│  • No drift detection                    │        │   vs     │           │
│                                          │        │ Actual   │           │
│                                          │        └────┬─────┘           │
│                                          │             │                 │
│                                          │             ▼                 │
│                                          │      ┌────────────┐          │
│                                          │      │   Apply    │          │
│                                          └──────│  Changes   │          │
│                                                 └────────────┘          │
│                                                                          │
│  Benefits of Pull:                                                       │
│  • Cluster pulls from Git (no external access needed)                   │
│  • Continuous drift detection                                            │
│  • CI only needs git write access                                        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**ArgoCD Polling Configuration:**

```yaml
# Default: 3 minutes polling interval
# Can be changed to webhook for instant sync
```

**Источник:** [`gitops-config/argocd/README.md`](../gitops-config/argocd/README.md)

---

### 4. Непрерывная реконсиляция

> Software agents continuously compare desired vs actual state

**Reconciliation Loop:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     CONTINUOUS RECONCILIATION                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│          ┌─────────────────────────────────────────────────────┐        │
│          │                 ArgoCD Controller                    │        │
│          │                                                      │        │
│          │  while true:                                        │        │
│          │    desired = fetch_from_git()                       │        │
│          │    actual = fetch_from_cluster()                    │        │
│          │                                                      │        │
│          │    if desired != actual:                            │        │
│          │      if autoSync:                                   │        │
│          │        apply(desired)   # Self-healing              │        │
│          │      else:                                          │        │
│          │        alert("OutOfSync")                           │        │
│          │                                                      │        │
│          │    sleep(3 minutes)                                 │        │
│          │                                                      │        │
│          └─────────────────────────────────────────────────────┘        │
│                                                                          │
│  Self-Healing Scenarios:                                                 │
│  ─────────────────────────                                               │
│  • Someone runs: kubectl delete pod X                                   │
│    → ArgoCD recreates pod                                               │
│                                                                          │
│  • Someone runs: kubectl scale deployment --replicas=10                 │
│    → ArgoCD reverts to Git-defined replicas                             │
│                                                                          │
│  • Manual ConfigMap edit                                                 │
│    → ArgoCD reverts to Git version                                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**AutoSync Configuration:**

```yaml
# gitops-config/platform/core.yaml
environments:
  dev:
    autoSync: true      # ← Automatic reconciliation
  staging:
    autoSync: true
  prod:
    autoSync: false     # ← Manual approval required
```

**Источник:** [`gitops-config/platform/core.yaml:47-78`](../gitops-config/platform/core.yaml)

---

## Deployment Flow

### Pull-Based (ArgoCD) — Рекомендуемый

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PULL-BASED DEPLOYMENT FLOW                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. Developer pushes code                                                │
│     └─► GitLab CI triggered                                              │
│                                                                          │
│  2. CI Pipeline                                                          │
│     ├─► Build Docker image                                               │
│     ├─► Push to GitLab Registry                                          │
│     └─► Update .cicd/dev.yaml with new image.tag                        │
│         └─► git push (CI_PUSH_TOKEN)                                    │
│                                                                          │
│  3. ArgoCD detects change                                                │
│     └─► Polls git repo (every 3 min) OR webhook                         │
│                                                                          │
│  4. ArgoCD syncs                                                         │
│     ├─► Renders Helm templates (k8app chart)                            │
│     └─► Applies to Kubernetes                                            │
│                                                                          │
│  5. VSO syncs secrets                                                    │
│     └─► VaultStaticSecret → K8s Secret                                  │
│                                                                          │
│  6. Deployment complete                                                  │
│     └─► New pods running with updated image                             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**CI/CD Template:** [`templates/service-repo/.gitlab-ci.yml`](../templates/service-repo/.gitlab-ci.yml)

### Push-Based (GitLab Agent) — Альтернатива

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PUSH-BASED DEPLOYMENT FLOW                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. Developer pushes code                                                │
│     └─► GitLab CI triggered                                              │
│                                                                          │
│  2. CI Pipeline                                                          │
│     ├─► Build Docker image                                               │
│     ├─► Push to GitLab Registry                                          │
│     └─► helm upgrade --install (via GitLab Agent)                       │
│                                                                          │
│  Differences from Pull:                                                  │
│  • Faster (no polling delay)                                             │
│  • Less auditable (CI does direct deploy)                               │
│  • No continuous reconciliation                                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**GitLab Agent Config:** [`gitops-config/.gitlab/agents/minikube-agent/config.yaml`](../gitops-config/.gitlab/agents/minikube-agent/config.yaml)

---

## Environment Promotion

### Dev → Staging → Prod

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     ENVIRONMENT PROMOTION                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Stage 1: Development                                                    │
│  ────────────────────                                                    │
│  git push → CI builds → .cicd/dev.yaml updated → ArgoCD syncs          │
│                                                                          │
│                    ▼ (QA approved)                                      │
│                                                                          │
│  Stage 2: Staging Promotion                                              │
│  ─────────────────────────                                               │
│  Copy image.tag from dev.yaml to staging.yaml                           │
│  OR: Create MR with staging changes                                      │
│  ArgoCD syncs staging (autoSync: true)                                  │
│                                                                          │
│                    ▼ (Release approved)                                 │
│                                                                          │
│  Stage 3: Production Promotion                                           │
│  ────────────────────────────                                            │
│  Copy image.tag from staging.yaml to prod.yaml                          │
│  Create MR → Approve → Merge                                             │
│  ArgoCD shows "OutOfSync" (autoSync: false)                             │
│  Manual sync in ArgoCD UI or CLI                                         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источник:** [`docs/multi-tenancy-guide.md:349-380`](../docs/multi-tenancy-guide.md)

---

## Configuration Separation

### default.yaml vs {env}.yaml

```yaml
# services/my-service/.cicd/default.yaml
# ─────────────────────────────────────
# Environment-agnostic configuration

appName: my-service

image:
  repository: registry.gitlab.com/group/my-service
  # tag: defined in env overlay

service:
  enabled: true
  ports:
    http:
      externalPort: 8080
      internalPort: 8080

livenessProbe:
  enabled: true
  httpGet:
    port: 8080
    path: "/health"

# Service-to-service (same namespace = short DNS)
configmap:
  USER_SERVICE_URL: "http://user-service-sv:8081"
```

```yaml
# services/my-service/.cicd/dev.yaml
# ─────────────────────────────────
# Dev-specific overrides

image:
  tag: "abc123"           # Updated by CI

replicas: 1

resources:
  requests:
    cpu: 100m
    memory: 128Mi

# Cross-namespace = FQDN required
configmap:
  MONGODB_URL: "mongodb://mongodb.infra-dev.svc:27017/db"
  LOG_LEVEL: "debug"

vault:
  role: my-service-dev
  path: gitops-poc-dzha/my-service/dev/config

httpRoute:
  parentRefs:
    - name: gateway
      namespace: poc-dev
  hostnames:
    - app.demo-poc-01.work
```

**Источник:** [`docs/multi-tenancy-guide.md:86-216`](../docs/multi-tenancy-guide.md)

---

## Anti-Patterns

### Чего следует избегать

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     GitOps ANTI-PATTERNS                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ❌ kubectl apply в CI                                                   │
│     Причина: Обходит GitOps, нет audit trail                            │
│     Решение: Обновлять .cicd/*.yaml, ArgoCD синхронизирует              │
│                                                                          │
│  ❌ helm install/upgrade в CI                                            │
│     Причина: Push-based, нет drift detection                            │
│     Решение: Pull-based через ArgoCD                                    │
│                                                                          │
│  ❌ Секреты в Git                                                        │
│     Причина: Security risk                                               │
│     Решение: Vault + VSO, только references в Git                       │
│                                                                          │
│  ❌ Hardcoded image tags                                                 │
│     Причина: Нет версионности, нельзя откатить                          │
│     Решение: CI обновляет image.tag в .cicd/                            │
│                                                                          │
│  ❌ Manual kubectl edits                                                 │
│     Причина: Drift от Git state                                          │
│     Решение: ArgoCD revert (self-healing)                               │
│                                                                          │
│  ❌ Environment-specific values в default.yaml                          │
│     Причина: Breaks environment agnosticism                             │
│     Решение: Разделять default.yaml и {env}.yaml                        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источник:** [`docs/multi-tenancy-guide.md:750-785`](../docs/multi-tenancy-guide.md)

---

## Rollback Strategies

### Git Revert

```bash
# Откат на предыдущую версию
git revert HEAD
git push

# ArgoCD автоматически синхронизирует
```

### ArgoCD Rollback

```bash
# Откат на предыдущий revision в ArgoCD
argocd app rollback my-app-dev --revision=-1
```

### Image Tag Rollback

```yaml
# Обновить image.tag на предыдущий
# services/my-service/.cicd/dev.yaml
image:
  tag: "previous-sha"   # Changed from "current-sha"
```

---

## Audit Trail

### Git History

```bash
# Кто, когда и что изменил
git log --oneline --graph services/api-gateway/.cicd/

# Конкретное изменение
git show abc123

# Blame
git blame services/api-gateway/.cicd/dev.yaml
```

### ArgoCD History

```bash
# История синхронизаций
argocd app history api-gateway-dev

# Diff между revisions
argocd app diff api-gateway-dev --revision=3
```

---

## Compliance Benefits

| Требование | Как GitOps помогает |
|------------|---------------------|
| **Audit Trail** | Полная история в Git |
| **Change Control** | Все через PR/MR |
| **Rollback** | git revert или ArgoCD rollback |
| **Approval** | GitLab MR approvals |
| **Separation of Duties** | CODEOWNERS, protected branches |
| **Reproducibility** | Идентичное состояние из Git |

---

## Связанные документы

- [Executive Summary](./00-executive-summary.md)
- [Platform Architecture](./01-platform-architecture.md)
- [Developer Experience](./03-developer-experience.md)

---

*Документ создан на основе аудита кодовой базы GitOps POC*
*Дата: 2025-12-21*
