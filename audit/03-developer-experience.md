# Developer Experience & SDLC

## Обзор

Данный документ описывает опыт разработчика (Developer Experience, DX) при работе с платформой, включая SDLC (Software Development Life Cycle) и использование k8app Helm chart.

---

## Ключевые принципы DX

### 1. Минимум конфигурации

Разработчику не нужно знать Kubernetes, Helm или ArgoCD для деплоя:

```yaml
# Минимальная конфигурация для деплоя сервиса
# services/my-service/.cicd/default.yaml

appName: my-service

image:
  repository: registry.gitlab.com/group/my-service

service:
  enabled: true
  ports:
    http:
      externalPort: 8080
      internalPort: 8080
```

### 2. Convention over Configuration

Платформа использует разумные значения по умолчанию:

| Параметр | Default | Можно переопределить |
|----------|---------|---------------------|
| `replicas` | 1 | Да, в {env}.yaml |
| `resources.requests.cpu` | 100m | Да |
| `resources.requests.memory` | 128Mi | Да |
| `livenessProbe.initialDelaySeconds` | 15 | Да |
| `service.type` | ClusterIP | Да |

### 3. Self-Service

Команды могут самостоятельно:
- Добавлять сервисы
- Управлять секретами (Vault UI)
- Деплоить в dev
- Откатывать изменения

---

## k8app Helm Chart

### Что это

k8app — унифицированный Helm chart для деплоя микросервисов, абстрагирующий Kubernetes complexity.

**Репозиторий:** https://d7561985.github.io/k8app

**Версия:** 3.8.0 (указана в [`values.yaml:32`](../gitops-config/platform/core.yaml))

### Возможности k8app

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         k8app CAPABILITIES                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  DEPLOYMENT                         NETWORKING                           │
│  ──────────                         ──────────                           │
│  • Deployment                       • Service (ClusterIP/NodePort/LB)   │
│  • StatefulSet                      • HTTPRoute (Gateway API)           │
│  • DaemonSet                        • Ingress (legacy)                  │
│  • CronJob                          • NetworkPolicy                     │
│  • Job                                                                   │
│                                                                          │
│  CONFIGURATION                      SECURITY                             │
│  ─────────────                      ────────                             │
│  • ConfigMap (env vars)             • ServiceAccount                    │
│  • ConfigMap (files)                • RBAC                              │
│  • Secrets (K8s native)             • SecurityContext                   │
│  • VaultStaticSecret (VSO)          • PodSecurityPolicy                 │
│                                                                          │
│  OBSERVABILITY                      SCALING                              │
│  ─────────────                      ───────                              │
│  • ServiceMonitor (Prometheus)      • HPA (Horizontal Pod Autoscaler)   │
│  • PodMonitor                       • VPA (Vertical Pod Autoscaler)     │
│  • PrometheusRule (alerts)          • PDB (Pod Disruption Budget)       │
│                                                                          │
│  STORAGE                            DEPENDENCIES                         │
│  ───────                            ────────────                         │
│  • PVC                              • Redis (auto-deploy)               │
│  • EmptyDir                         • Init containers                   │
│  • ConfigMap mounts                 • Sidecar containers                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Философия k8app

k8app построен на 4 ключевых принципах:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     k8app DESIGN PRINCIPLES                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. AUTOMATION FIRST                                                     │
│  ───────────────────                                                     │
│  • Один chart генерирует ВСЕ K8s ресурсы                                │
│  • Зависимости (Redis, etc.) деплоятся автоматически                    │
│  • ServiceMonitor, VaultStaticSecret — автоматически                    │
│  • Разработчик НЕ пишет YAML-манифесты Kubernetes                       │
│                                                                          │
│  2. SIMPLICITY FOR DEVELOPERS                                            │
│  ────────────────────────────                                            │
│  • Минимальный конфиг: appName + image + ports                          │
│  • Convention over Configuration — разумные defaults                    │
│  • Не нужно знать Helm, kubectl, ArgoCD internals                       │
│  • Один паттерн для всех типов сервисов                                 │
│                                                                          │
│  3. ENVIRONMENT AGNOSTICISM                                              │
│  ──────────────────────────                                              │
│  • default.yaml — environment-agnostic base                             │
│  • {env}.yaml — только env-specific overrides                          │
│  • Один и тот же код → dev/staging/prod                                 │
│  • Promotion = копирование image.tag                                    │
│                                                                          │
│  4. REPRODUCIBILITY                                                      │
│  ─────────────────                                                       │
│  • Декларативная конфигурация = reproducible deploys                    │
│  • Версионирование через Git history                                    │
│  • Rollback = git revert + ArgoCD sync                                  │
│  • Один источник истины (Git)                                           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Практический эффект:**

| Без k8app | С k8app |
|-----------|---------|
| 5-10 YAML файлов на сервис | 1-2 values файла |
| Знание K8s API обязательно | Только конфигурация приложения |
| Ручное создание ServiceMonitor | `metrics.enabled: true` |
| Ручная интеграция с Vault | `secrets.DB_PASSWORD: "config"` |
| Helm template debugging | ArgoCD diff в UI |

**Источник шаблона:** [`templates/service-repo/.cicd/default.yaml`](../templates/service-repo/.cicd/default.yaml)

---

## .cicd/ Directory Structure

```
services/my-service/
├── .cicd/
│   ├── default.yaml      # Базовая конфигурация (все окружения)
│   ├── dev.yaml          # Dev-specific overrides
│   ├── staging.yaml      # Staging-specific overrides
│   └── prod.yaml         # Production-specific overrides
│
├── .gitlab-ci.yml        # CI/CD pipeline
├── Dockerfile            # или dockerfiles/
└── src/                  # Application code
```

**Merge Order:** `default.yaml` → `{env}.yaml` (последний выигрывает)

**Источник:** [`docs/multi-tenancy-guide.md:86-100`](../docs/multi-tenancy-guide.md)

---

## Configuration Examples

### Minimal Service

```yaml
# .cicd/default.yaml
appName: hello-world

image:
  repository: registry.gitlab.com/group/hello-world

service:
  enabled: true
  ports:
    http:
      externalPort: 8080
      internalPort: 8080
```

```yaml
# .cicd/dev.yaml
image:
  tag: "abc123"  # Updated by CI
```

### Full-Featured Service

```yaml
# .cicd/default.yaml
appName: user-service

image:
  repository: registry.gitlab.com/gitops-poc-dzha/user-service
  pullPolicy: IfNotPresent

imagePullSecrets:
  - name: regsecret

service:
  enabled: true
  ports:
    http:
      externalPort: 8081
      internalPort: 8081
    grpc:
      externalPort: 50051
      internalPort: 50051

livenessProbe:
  enabled: true
  mode: httpGet
  httpGet:
    port: 8081
    path: "/health"
  initialDelaySeconds: 15
  periodSeconds: 10

readinessProbe:
  enabled: true
  mode: httpGet
  httpGet:
    port: 8081
    path: "/health"
  initialDelaySeconds: 10
  periodSeconds: 5

# Environment variables (non-sensitive)
configmap:
  GRPC_PORT: "50051"
  HTTP_PORT: "8081"
  LOG_FORMAT: "json"

# Vault integration for secrets
vault:
  enabled: true

secrets:
  JWT_SECRET: "config"        # → vault path: {ns}/{app}/{env}/config
  DB_PASSWORD: "database"     # → vault path: {ns}/{app}/{env}/database

secretsProvider:
  provider: vault
  vault:
    authRef: vault-auth
    mount: secret
    type: kv-v2

# HTTPRoute for Gateway API
httpRoute:
  enabled: true
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/user
      backendRefs:
        - name: user-service-sv
          port: 8081
```

```yaml
# .cicd/dev.yaml
image:
  tag: "v1.2.3"

replicas: 1

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

configmap:
  MONGODB_URL: "mongodb://mongodb.infra-dev.svc:27017/users"
  REDIS_URL: "redis://redis.infra-dev.svc:6379"
  LOG_LEVEL: "debug"
  SENTRY_ENVIRONMENT: "dev"

vault:
  role: user-service-dev
  path: gitops-poc-dzha/user-service/dev/config

httpRoute:
  parentRefs:
    - name: gateway
      namespace: poc-dev
      sectionName: http-app
  hostnames:
    - app.demo-poc-01.work
```

```yaml
# .cicd/prod.yaml
image:
  tag: "v1.2.3"

replicas: 3

resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi

# Horizontal Pod Autoscaler
hpa:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

# Pod Disruption Budget
pdb:
  enabled: true
  minAvailable: 2

configmap:
  MONGODB_URL: "mongodb://mongodb.infra-prod.svc:27017/users"
  LOG_LEVEL: "info"
  SENTRY_ENVIRONMENT: "prod"
```

**Источник:** [`templates/service-repo/.cicd/`](../templates/service-repo/.cicd/)

---

## Vault Integration

### Automatic Secret Sync

k8app v3.8.0 автоматически создаёт `VaultStaticSecret` для синхронизации секретов:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     VAULT → K8s SECRET FLOW                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. Developer sets in .cicd/default.yaml:                               │
│     ──────────────────────────────────────                               │
│     secrets:                                                             │
│       JWT_SECRET: "config"    # Key name in Vault path                  │
│       DB_PASSWORD: "database"                                            │
│                                                                          │
│     secretsProvider:                                                     │
│       provider: vault                                                    │
│       vault:                                                             │
│         authRef: vault-auth                                              │
│                                                                          │
│  2. k8app generates VaultStaticSecret:                                  │
│     ─────────────────────────────────────                                │
│     apiVersion: secrets.hashicorp.com/v1beta1                           │
│     kind: VaultStaticSecret                                              │
│     spec:                                                                │
│       path: secret/data/{ns}/{app}/{env}/config                         │
│       destination:                                                       │
│         create: true                                                     │
│         name: {app}-secrets                                              │
│                                                                          │
│  3. VSO syncs secret:                                                    │
│     ─────────────────                                                    │
│     Vault KV → K8s Secret (auto-refresh)                                │
│                                                                          │
│  4. Pod consumes:                                                        │
│     ──────────────                                                       │
│     envFrom:                                                             │
│       - secretRef:                                                       │
│           name: {app}-secrets                                            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**VaultAuth** создаётся автоматически `platform-modules`:

**Источник:** [`gitops-config/charts/platform-core/templates/vault-auth.yaml`](../gitops-config/charts/platform-core/templates/vault-auth.yaml)

---

## CI/CD Pipeline

### GitLab CI Template

```yaml
# .gitlab-ci.yml (из templates/service-repo/)

include:
  - project: 'gitops-poc-dzha/ci-templates'
    file: '/templates/docker-build.yml'
  - project: 'gitops-poc-dzha/ci-templates'
    file: '/templates/gitops-update.yml'

stages:
  - build
  - test
  - deploy

variables:
  SERVICE_NAME: "my-service"
  DOCKER_IMAGE: "${CI_REGISTRY_IMAGE}"

build:
  stage: build
  extends: .docker-build
  script:
    - docker build -t ${DOCKER_IMAGE}:${CI_COMMIT_SHORT_SHA} .
    - docker push ${DOCKER_IMAGE}:${CI_COMMIT_SHORT_SHA}

deploy-dev:
  stage: deploy
  extends: .gitops-update
  variables:
    ENVIRONMENT: "dev"
    IMAGE_TAG: "${CI_COMMIT_SHORT_SHA}"
  only:
    - main
```

### What CI Does

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     CI/CD PIPELINE STAGES                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  BUILD STAGE                                                             │
│  ───────────                                                             │
│  1. Checkout code                                                        │
│  2. Build Docker image                                                   │
│  3. Push to GitLab Registry                                              │
│     → registry.gitlab.com/group/service:abc123                          │
│                                                                          │
│  TEST STAGE                                                              │
│  ──────────                                                              │
│  1. Unit tests                                                           │
│  2. Integration tests                                                    │
│  3. Security scan (optional)                                             │
│                                                                          │
│  DEPLOY STAGE (GitOps Update)                                            │
│  ─────────────────────────────                                           │
│  1. Clone gitops-config repo                                             │
│  2. Update .cicd/dev.yaml:                                              │
│     image:                                                               │
│       tag: "abc123"   # ← new commit SHA                                │
│  3. Commit and push                                                      │
│  4. ArgoCD picks up change (polling or webhook)                         │
│                                                                          │
│  CI does NOT:                                                            │
│  • kubectl apply                                                         │
│  • helm install/upgrade                                                  │
│  • Direct cluster access                                                 │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источник:** [`templates/service-repo/.gitlab-ci.yml`](../templates/service-repo/.gitlab-ci.yml)

---

## Adding a New Service

### Step-by-Step Guide

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     ADDING A NEW SERVICE                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  STEP 1: Create Repository                                               │
│  ─────────────────────────                                               │
│  • Create new GitLab repo                                                │
│  • Copy templates/service-repo/ structure                               │
│  • Add your application code                                             │
│                                                                          │
│  STEP 2: Configure .cicd/                                                │
│  ─────────────────────────                                               │
│  • Edit default.yaml: appName, ports, env vars                          │
│  • Edit dev.yaml: image.repository, vault paths                         │
│                                                                          │
│  STEP 3: Register in Platform Bootstrap                                  │
│  ───────────────────────────────────────                                 │
│  # gitops-config/platform/core.yaml                  │
│  services:                                                               │
│    my-new-service:         # ← Add this                                 │
│      syncWave: "0"                                                       │
│      # repoURL: optional if different from default                      │
│                                                                          │
│  STEP 4: Create Vault Secrets                                            │
│  ────────────────────────────                                            │
│  vault kv put secret/gitops-poc-dzha/my-service/dev/config \            │
│    API_KEY="xxx" \                                                       │
│    DB_PASSWORD="yyy"                                                     │
│                                                                          │
│  STEP 5: Push and Wait                                                   │
│  ─────────────────────                                                   │
│  • git push (triggers CI)                                                │
│  • ArgoCD syncs platform-modules                                       │
│  • ArgoCD creates Application for my-new-service-dev                    │
│  • Service deployed!                                                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Подробная инструкция:** [`docs/new-service-guide.md`](../docs/new-service-guide.md)

---

## Service Discovery

### Same Namespace (Short DNS)

Все application сервисы в одном namespace могут использовать короткие DNS:

```yaml
# В .cicd/default.yaml
configmap:
  USER_SERVICE_URL: "http://user-service-sv:8081"
  PAYMENT_SERVICE_URL: "http://sentry-payment-sv:8083"
```

### Cross-Namespace (FQDN)

Для доступа к инфраструктуре (MongoDB, Redis) используется FQDN в env-specific overlay:

```yaml
# В .cicd/dev.yaml
configmap:
  MONGODB_URL: "mongodb://mongodb.infra-dev.svc:27017/db"
  REDIS_URL: "redis://redis.infra-dev.svc:6379"
```

**Источник:** [`docs/multi-tenancy-guide.md:219-260`](../docs/multi-tenancy-guide.md)

---

## Automatic Dependencies

### Redis Auto-Provisioning

k8app поддерживает автоматический деплой зависимостей:

```yaml
# .cicd/default.yaml
dependencies:
  redis:
    enabled: true
    # Автоматически:
    # 1. Создаёт Redis StatefulSet
    # 2. Добавляет REDIS_URL в configmap
```

**Результат:** Команда получает Redis без Platform Team.

---

## HTTPRoute Configuration

### Gateway API Integration

```yaml
# .cicd/default.yaml - базовые правила
httpRoute:
  enabled: true
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/users
      backendRefs:
        - name: user-service-sv
          port: 8081

# .cicd/dev.yaml - привязка к Gateway
httpRoute:
  parentRefs:
    - name: gateway
      namespace: poc-dev
      sectionName: http-app
  hostnames:
    - app.demo-poc-01.work
```

**Источник:** [`docs/gateway-api-plan.md`](../docs/gateway-api-plan.md)

---

## Metrics and Monitoring

### ServiceMonitor Auto-Creation

```yaml
# .cicd/default.yaml
metrics:
  enabled: true
  port: 9090
  path: /metrics

# k8app автоматически создаёт:
# - ServiceMonitor для Prometheus
# - Grafana dashboard reference
```

**Источник:** [`docs/monitoring-audit.md`](../docs/monitoring-audit.md)

---

## Developer Commands

### Local Development

```bash
# Просмотр логов
kubectl logs -n poc-dev -l app=my-service -f

# Port-forward для отладки
kubectl port-forward -n poc-dev svc/my-service-sv 8080:8080

# Exec в pod
kubectl exec -it -n poc-dev deploy/my-service -- /bin/sh
```

### ArgoCD Commands

```bash
# Статус приложения
argocd app get my-service-dev

# Ручная синхронизация
argocd app sync my-service-dev

# Откат
argocd app rollback my-service-dev --revision=-1

# Diff (что изменится при sync)
argocd app diff my-service-dev
```

### Makefile Helpers

```bash
# Proxies (из Makefile)
make proxy-argocd      # ArgoCD UI на :8081
make proxy-grafana     # Grafana на :3000
make proxy-vault       # Vault UI на :8200
make hubble-ui         # Hubble (сетевые потоки)
```

**Источник:** [`Makefile`](../Makefile)

---

## SDLC Flow Summary

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     COMPLETE SDLC FLOW                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. DEVELOP                                                              │
│     └─► Code locally with docker-compose or minikube                    │
│                                                                          │
│  2. COMMIT                                                               │
│     └─► git commit -m "feat: add new endpoint"                          │
│         └─► git push origin feature/my-feature                          │
│                                                                          │
│  3. CI BUILD                                                             │
│     └─► GitLab CI triggers                                              │
│         ├─► Build Docker image                                           │
│         ├─► Run tests                                                    │
│         └─► Push to registry                                             │
│                                                                          │
│  4. MERGE REQUEST                                                        │
│     └─► Create MR to main                                               │
│         └─► Code review                                                  │
│             └─► Approve and merge                                        │
│                                                                          │
│  5. GITOPS UPDATE                                                        │
│     └─► CI updates .cicd/dev.yaml                                       │
│         └─► image.tag: "new-sha"                                        │
│             └─► git push (automated)                                    │
│                                                                          │
│  6. ARGOCD SYNC                                                          │
│     └─► Detects change (3 min polling or webhook)                       │
│         └─► Syncs to Kubernetes                                          │
│             └─► New pods deployed                                        │
│                                                                          │
│  7. VERIFY                                                               │
│     └─► Check ArgoCD UI                                                  │
│         └─► Check Grafana dashboards                                     │
│             └─► Test functionality                                       │
│                                                                          │
│  8. PROMOTE                                                              │
│     └─► Copy tag to staging.yaml                                        │
│         └─► Copy tag to prod.yaml                                        │
│             └─► Manual sync for prod                                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Preview Environments

### Обзор

Preview environments автоматически создаются для каждого Merge Request из ветки с JIRA тегом. Каждый MR получает уникальный поддомен для тестирования перед merge.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PREVIEW ENVIRONMENTS FLOW                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  DEVELOPER WORKFLOW                                                      │
│  ──────────────────                                                      │
│  1. git checkout -b PROJ-123-new-feature                                │
│  2. ... make changes ...                                                 │
│  3. git push → CI builds image                                          │
│  4. Open Merge Request                                                   │
│                                                                          │
│                          │                                               │
│                          ▼                                               │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  ArgoCD Pull Request Generator (каждые 60 сек)                     │ │
│  │  • Обнаруживает MR с JIRA тегом                                    │ │
│  │  • branchMatch: "^[A-Z]+-[0-9]+-.*"                                │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                          │                                               │
│                          ▼                                               │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  Автоматически создаётся:                                          │ │
│  │  • Namespace: preview-frontend-proj-123                            │ │
│  │  • Deployment с image из feature branch                           │ │
│  │  • HTTPRoute → proj-123.preview.demo-poc-01.work                  │ │
│  │  • DNS запись через external-dns                                   │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                          │                                               │
│                          ▼                                               │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  READY TO TEST                                                      │ │
│  │  URL: https://proj-123.preview.demo-poc-01.work                    │ │
│  │  Frontend: из feature branch                                        │ │
│  │  Backend: shared из dev environment                                 │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                          │                                               │
│                          ▼                                               │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  MR merged/closed → всё автоматически удаляется                    │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Формат домена

```
{jira-tag}.preview.{baseDomain}
```

| Branch | JIRA Tag | Preview URL |
|--------|----------|-------------|
| `PROJ-123-new-login-feature` | `proj-123` | `proj-123.preview.demo-poc-01.work` |
| `JIRA-456-fix-button-color` | `jira-456` | `jira-456.preview.demo-poc-01.work` |

### Требования к веткам

Ветка должна начинаться с JIRA тега:
```
{PROJECT}-{NUMBER}-{description}
```

| Ветка | Preview создастся? |
|-------|-------------------|
| `PROJ-123-new-feature` | ✅ Да |
| `JIRA-456-fix-bug` | ✅ Да |
| `feature/login` | ❌ Нет (нет JIRA тега) |
| `fix-typo` | ❌ Нет (нет JIRA тега) |

### Что создаётся автоматически

| Ресурс | Name | Lifecycle |
|--------|------|-----------|
| ArgoCD Application | `preview-frontend-proj-123` | MR open → delete on close |
| Namespace | `preview-frontend-proj-123` | Cascade delete |
| Deployment | `sentry-frontend` | В preview namespace |
| HTTPRoute | Auto-generated | С hostname preview URL |

### Ключевые особенности

1. **GitOps** — ArgoCD Pull Request Generator следит за MR
2. **Автоматизация** — создание/удаление при открытии/закрытии MR
3. **Изоляция** — каждый preview в отдельном namespace
4. **Shared Backend** — frontend использует backend из dev (экономия ресурсов)

**Полная документация:** [`docs/preview-environments-guide.md`](../docs/preview-environments-guide.md)

---

## Guidelines для разработчиков

### DO (Делайте)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     DEVELOPER DO's                                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  CONFIGURATION                                                           │
│  ─────────────                                                           │
│  ✅ Используйте default.yaml для environment-agnostic конфига          │
│  ✅ Храните image.tag только в {env}.yaml                              │
│  ✅ Используйте короткие DNS для сервисов в том же namespace           │
│     USER_SERVICE_URL: "http://user-service-sv:8081"                     │
│  ✅ Используйте FQDN для infra в {env}.yaml                            │
│     MONGODB_URL: "mongodb://mongodb.infra-dev.svc:27017/db"             │
│                                                                          │
│  SECRETS                                                                 │
│  ───────                                                                 │
│  ✅ Храните секреты ТОЛЬКО в Vault                                      │
│  ✅ Используйте secrets: в k8app для ссылок на Vault paths             │
│  ✅ Разделяйте секреты по env: /service/dev/config, /service/prod/...  │
│                                                                          │
│  DEPLOYMENT                                                              │
│  ──────────                                                              │
│  ✅ Деплойте через git push → ArgoCD                                   │
│  ✅ Тестируйте в dev перед promotion в staging                         │
│  ✅ Используйте ArgoCD UI для мониторинга sync статуса                 │
│  ✅ Используйте argocd app diff перед sync                              │
│                                                                          │
│  OBSERVABILITY                                                           │
│  ─────────────                                                           │
│  ✅ Экспортируйте метрики на /metrics порт 9090                        │
│  ✅ Включайте serviceMonitor.enabled: true                              │
│  ✅ Добавляйте health endpoints: /health, /ready                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### DON'T (Не делайте)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     DEVELOPER DON'Ts                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  CONFIGURATION                                                           │
│  ─────────────                                                           │
│  ❌ НЕ хардкодьте namespace в URLs в default.yaml                       │
│     WRONG: MONGODB_URL: "mongodb://mongodb.infra-dev.svc:27017"         │
│                                                                          │
│  ❌ НЕ добавляйте env-specific значения в default.yaml                  │
│     WRONG: replicas: 3, SENTRY_ENV: "dev" в default.yaml               │
│                                                                          │
│  ❌ НЕ используйте короткие DNS для cross-namespace                     │
│     WRONG: MONGODB_URL: "mongodb://mongodb:27017"                        │
│                                                                          │
│  SECRETS                                                                 │
│  ───────                                                                 │
│  ❌ НЕ коммитьте секреты в Git (даже зашифрованные)                    │
│  ❌ НЕ храните пароли в configmap                                       │
│  ❌ НЕ используйте одинаковые секреты для dev/prod                      │
│                                                                          │
│  DEPLOYMENT                                                              │
│  ──────────                                                              │
│  ❌ НЕ используйте kubectl apply напрямую                               │
│  ❌ НЕ используйте helm install/upgrade в CI                            │
│  ❌ НЕ редактируйте ресурсы в кластере вручную (drift!)                │
│  ❌ НЕ деплойте в prod без тестирования в staging                       │
│                                                                          │
│  VERSIONING                                                              │
│  ──────────                                                              │
│  ❌ НЕ используйте :latest tag                                          │
│  ❌ НЕ хардкодьте версии — пусть CI обновляет tag                       │
│                                                                          │
│  API ROUTING                                                             │
│  ───────────                                                             │
│  ❌ НЕ создавайте отдельные домены для API сервисов                     │
│  ❌ НЕ создавайте HTTPRoutes для backend — только через api-gateway    │
│  ❌ НЕ обходите api-gateway для внешних вызовов                         │
│     → ВСЕ API через /api/* (см. 04-api-standards.md)                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Checklist нового сервиса

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     NEW SERVICE CHECKLIST                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  BEFORE STARTING                                                         │
│  ───────────────                                                         │
│  [ ] Скопирован templates/service-repo/                                  │
│  [ ] Заменены все {{SERVICE_NAME}} плейсхолдеры                         │
│                                                                          │
│  default.yaml                                                            │
│  ────────────                                                            │
│  [ ] appName установлен                                                  │
│  [ ] image.repository указан (без tag!)                                 │
│  [ ] imagePullSecrets: [{name: regsecret}]                              │
│  [ ] service.ports настроены                                             │
│  [ ] livenessProbe и readinessProbe настроены                           │
│  [ ] serviceMonitor.enabled: true для метрик                            │
│                                                                          │
│  {env}.yaml                                                              │
│  ──────────                                                              │
│  [ ] image.tag установлен (CI будет обновлять)                          │
│  [ ] replicas соответствует env                                         │
│  [ ] resources.requests/limits установлены                              │
│  [ ] configmap с infra URLs (FQDN!)                                     │
│  [ ] vault.role и vault.path                                             │
│  [ ] httpRoute.parentRefs с правильным namespace                        │
│  [ ] httpRoute.hostnames                                                 │
│                                                                          │
│  VAULT                                                                   │
│  ─────                                                                   │
│  [ ] Секреты созданы в Vault                                            │
│  [ ] Путь соответствует secrets: в yaml                                 │
│                                                                          │
│  PLATFORM-BOOTSTRAP                                                      │
│  ──────────────────                                                      │
│  [ ] Сервис добавлен в values.yaml services:                            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источники:**
- [`docs/multi-tenancy-guide.md:750-785`](../docs/multi-tenancy-guide.md) — Anti-patterns
- [`templates/service-repo/`](../templates/service-repo/) — Template
- [`docs/new-service-guide.md`](../docs/new-service-guide.md) — Полный guide

---

## Связанные документы

- [Executive Summary](./00-executive-summary.md)
- [GitOps Principles](./02-gitops-principles.md)
- [API Standards](./04-api-standards.md)

---

*Документ создан на основе аудита кодовой базы GitOps POC*
*Дата: 2025-12-21*
