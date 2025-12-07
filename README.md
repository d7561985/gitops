# GitOps POC: Push & Pull Based Approaches

Демонстрация двух подходов GitOps на базе GitLab Agent (Push) и ArgoCD (Pull) с интеграцией HashiCorp Vault для управления секретами.

## Содержание

- [Архитектура](#архитектура)
- [Требования](#требования)
- [Quick Start](#quick-start)
- [Политики и Стандарты](#политики-и-стандарты)
- [Структура проекта](#структура-проекта)
- [Детальная настройка](#детальная-настройка)

---

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              GitLab.com / Self-Managed                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ api-gateway │  │auth-adapter │  │  web-grpc   │  │  web-http   │  ...    │
│  │    repo     │  │    repo     │  │    repo     │  │    repo     │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
└─────────┼────────────────┼────────────────┼────────────────┼────────────────┘
          │                │                │                │
          ▼                ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Minikube Cluster                                   │
│                                                                              │
│  ┌──────────────────────┐        ┌──────────────────────┐                   │
│  │   PUSH-BASED (CI/CD) │        │   PULL-BASED (GitOps)│                   │
│  │   ┌────────────────┐ │        │   ┌────────────────┐ │                   │
│  │   │  GitLab Agent  │ │        │   │    ArgoCD      │ │                   │
│  │   │  (agentk)      │ │        │   │                │ │                   │
│  │   └───────┬────────┘ │        │   └───────┬────────┘ │                   │
│  │           │          │        │           │          │                   │
│  │   Pipeline triggers  │        │   Polls repository   │                   │
│  │   helm upgrade       │        │   auto-sync          │                   │
│  └───────────┼──────────┘        └───────────┼──────────┘                   │
│              │                               │                               │
│              ▼                               ▼                               │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │                    Application Namespaces                      │          │
│  │   ┌─────────┐  ┌─────────┐  ┌─────────┐                       │          │
│  │   │   dev   │  │ staging │  │  prod   │                       │          │
│  │   └─────────┘  └─────────┘  └─────────┘                       │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                              │                                               │
│                              ▼                                               │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │                    HashiCorp Vault                             │          │
│  │   ┌─────────────────────────────────────────────────────────┐ │          │
│  │   │  Vault Secrets Operator (VSO)                           │ │          │
│  │   │  secret/data/gitops-poc/{service}/{env}/config          │ │          │
│  │   └─────────────────────────────────────────────────────────┘ │          │
│  └───────────────────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Сервисы POC (на базе api-gateway проекта)

| Сервис | Описание | Image | Порты |
|--------|----------|-------|-------|
| api-gateway | Envoy API Gateway | local build | 8080, 8000 |
| auth-adapter | Сервис авторизации | local build | 9000 |
| web-grpc | gRPC backend | nicholasjackson/fake-service:v0.19.1 | 9091 |
| web-http | HTTP backend | nicholasjackson/fake-service:v0.19.1 | 9092 |
| health-demo | Health check service | local build | 8081 |

---

## Требования

| Компонент | Версия | Проверка | Установка |
|-----------|--------|----------|-----------|
| Minikube | 1.34+ | `minikube version` | [docs](https://minikube.sigs.k8s.io/docs/start/) |
| kubectl | 1.28+ | `kubectl version --client` | [docs](https://kubernetes.io/docs/tasks/tools/) |
| Helm | 3.12+ | `helm version` | `brew install helm` |
| Docker | 24+ | `docker --version` | [docs](https://docs.docker.com/get-docker/) |
| Vault CLI | 1.15+ | `vault version` | `brew tap hashicorp/tap && brew install hashicorp/tap/vault` |
| ArgoCD CLI | 2.9+ | `argocd version --client` | `brew install argocd` |

---

## Quick Start

```bash
# 1. Клонировать репозиторий
git clone <repository-url>
cd gitops

# 2. Запустить Minikube и установить инфраструктуру
./scripts/setup-infrastructure.sh

# 3. Настроить Vault секреты
./scripts/setup-vault-secrets.sh

# 4. Выбрать подход GitOps:

# Push-based (GitLab Agent):
./scripts/setup-push-based.sh

# Pull-based (ArgoCD):
./scripts/setup-pull-based.sh
```

---

## Политики и Стандарты

### 1. Структура репозитория сервиса (k8app based)

Каждый сервис должен иметь следующую структуру values файлов:

```
service-repo/
├── helm/
│   ├── default.yaml      # Общие настройки для всех окружений
│   ├── dev.yaml          # Override для dev (наследует default)
│   ├── staging.yaml      # Override для staging (наследует default)
│   └── prod.yaml         # Override для prod (наследует default)
└── .gitlab-ci.yml        # CI/CD pipeline (для push-based)
```

**Принцип наследования values:**
```bash
# Итоговые values = default.yaml + {env}.yaml
helm upgrade app k8app/app \
  -f helm/default.yaml \
  -f helm/dev.yaml      # env-specific overrides
```

### 2. Именование ресурсов

| Ресурс | Паттерн | Пример |
|--------|---------|--------|
| Namespace | `{service}-{env}` | `api-gateway-dev` |
| Deployment | `{service}` | `api-gateway` |
| Service | `{service}` | `api-gateway` |
| Secret | `{service}-secrets` | `api-gateway-secrets` |

### 3. Vault Secrets — Структура путей

```
secret/data/gitops-poc/{service}/{env}/config
                 │         │       │      │
                 │         │       │      └── Всегда "config" для консистентности
                 │         │       └── dev | staging | prod
                 │         └── api-gateway | auth-adapter | web-grpc | ...
                 └── Название проекта (единое для всех сервисов)
```

**Примеры путей:**
```
secret/data/gitops-poc/api-gateway/dev/config
secret/data/gitops-poc/api-gateway/staging/config
secret/data/gitops-poc/api-gateway/prod/config
secret/data/gitops-poc/auth-adapter/dev/config
secret/data/gitops-poc/auth-adapter/prod/config
```

**Vault Policy для сервиса (шаблон):**
```hcl
# Policy: gitops-poc-{service}-{env}
path "secret/data/gitops-poc/{service}/{env}/*" {
  capabilities = ["read"]
}
```

### 4. Kubernetes Auth Roles для Vault

Каждый сервис в каждом окружении имеет свою роль:

```bash
# Паттерн: {service}-{env}
vault write auth/kubernetes/role/api-gateway-dev \
  bound_service_account_names=api-gateway \
  bound_service_account_namespaces=api-gateway-dev \
  policies=gitops-poc-api-gateway-dev \
  ttl=1h
```

### 5. Labels и Annotations (обязательные)

```yaml
metadata:
  labels:
    app.kubernetes.io/name: "{service}"
    app.kubernetes.io/instance: "{service}-{env}"
    app.kubernetes.io/version: "{version}"
    app.kubernetes.io/component: "backend|frontend|gateway"
    app.kubernetes.io/part-of: "gitops-poc"
    app.kubernetes.io/managed-by: "helm"
    environment: "{env}"
  annotations:
    # Для ArgoCD sync waves
    argocd.argoproj.io/sync-wave: "0"
```

### 6. GitOps подходы — когда использовать

| Критерий | Push-based (GitLab Agent) | Pull-based (ArgoCD) |
|----------|---------------------------|---------------------|
| Скорость деплоя | Мгновенно при push | По интервалу (3 мин default) |
| Контроль | Pipeline должен успешно завершиться | Автоматическая синхронизация |
| Rollback | `git revert` + pipeline | UI/CLI ArgoCD или `git revert` |
| Visibility | GitLab CI/CD UI | ArgoCD Dashboard |
| Multi-cluster | Сложнее настроить | Нативная поддержка |
| Secrets | Во время pipeline | Vault Secrets Operator |

**Рекомендация:**
- **Dev/Staging**: Push-based — быстрая итерация
- **Production**: Pull-based — аудит, approval gates, drift detection

### 7. Secrets Management — Правила

1. **Никогда** не коммитить секреты в Git
2. **Всегда** использовать Vault для хранения секретов
3. **Один путь** = одно окружение одного сервиса
4. **Rotation**: Настроить `refreshAfter: 1h` в VaultStaticSecret
5. **Least Privilege**: Каждый сервис видит только свои секреты

### 8. Environment Promotion Flow

```
┌─────┐     Manual      ┌─────────┐     Manual      ┌──────┐
│ Dev │ ──────────────► │ Staging │ ──────────────► │ Prod │
└─────┘   PR + Review   └─────────┘   PR + Approval └──────┘

# Git branches:
main ──► dev     (auto-deploy)
main ──► staging (manual trigger / PR)
main ──► prod    (manual approval required)
```

---

## Структура проекта

```
gitops/
├── README.md                          # Этот файл
├── docs/
│   └── k8app-recommendations.md       # Задача для команды k8app
├── infrastructure/
│   ├── vault/                         # Vault + VSO установка
│   │   ├── helm-values.yaml
│   │   ├── vso-values.yaml
│   │   └── setup.sh
│   ├── argocd/                        # ArgoCD установка
│   │   ├── helm-values.yaml
│   │   └── setup.sh
│   └── gitlab-agent/                  # GitLab Agent установка
│       ├── helm-values.yaml
│       ├── config.yaml
│       └── setup.sh
├── services/                          # Сервисы на базе k8app
│   ├── api-gateway/
│   │   ├── default.yaml
│   │   ├── dev.yaml
│   │   ├── staging.yaml
│   │   ├── prod.yaml
│   │   └── vault-secret.yaml          # VaultStaticSecret CRD
│   ├── auth-adapter/
│   ├── web-grpc/
│   ├── web-http/
│   └── health-demo/
├── gitops/
│   ├── push-based/
│   │   ├── .gitlab-ci.yml             # Template CI/CD pipeline
│   │   └── README.md                  # Push-based documentation
│   └── pull-based/
│       ├── applicationset.yaml        # ArgoCD ApplicationSet
│       ├── project.yaml               # ArgoCD Project
│       └── README.md                  # Pull-based documentation
├── scripts/
│   ├── setup-infrastructure.sh
│   ├── setup-vault-secrets.sh
│   ├── setup-push-based.sh
│   ├── setup-pull-based.sh
│   └── build-local-images.sh
└── tests/
    └── smoke-test.sh
```

---

## Детальная настройка

### Minikube с поддержкой локального Docker

```bash
# Запуск Minikube
minikube start --cpus 4 --memory 8192 --disk-size 40g

# Использовать Docker daemon Minikube для локальных образов
eval $(minikube docker-env)

# Проверка
docker images  # Должны видеть k8s.gcr.io images
```

### Сборка локальных образов

```bash
# Клонировать api-gateway репозиторий
git clone https://github.com/d7561985/api-gateway.git /tmp/api-gateway

# Переключиться на Docker daemon Minikube
eval $(minikube docker-env)

# Собрать образы
cd /tmp/api-gateway/envoy
docker build -t api-gateway:local -f api-gateway/Dockerfile .
docker build -t auth-adapter:local -f auth-adapter/Dockerfile .
docker build -t health-demo:local -f ../tools/health-demo/Dockerfile ../tools/health-demo
```

### Установка Vault

```bash
# Добавить репозиторий HashiCorp
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Установить Vault в dev режиме
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  -f infrastructure/vault/helm-values.yaml

# Установить Vault Secrets Operator
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace vault-secrets-operator-system \
  --create-namespace \
  -f infrastructure/vault/vso-values.yaml
```

### Установка ArgoCD

```bash
# Установить ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f infrastructure/argocd/helm-values.yaml

# Получить пароль admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Доступ к UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Открыть https://localhost:8080
```

### Установка GitLab Agent

```bash
# Получить токен агента из GitLab UI:
# Project → Infrastructure → Kubernetes clusters → Connect a cluster

helm repo add gitlab https://charts.gitlab.io
helm install gitlab-agent gitlab/gitlab-agent \
  --namespace gitlab-agent \
  --create-namespace \
  --set config.token=<YOUR_AGENT_TOKEN> \
  --set config.kasAddress=wss://kas.gitlab.com \
  -f infrastructure/gitlab-agent/helm-values.yaml
```

---

## Vault Configuration Details

### Инициализация секретов

```bash
# Port-forward к Vault
kubectl port-forward svc/vault -n vault 8200:8200 &

# Экспорт адреса и токена (dev mode)
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# Включить KV v2 secrets engine
vault secrets enable -path=secret kv-v2

# Создать секреты для api-gateway
vault kv put secret/gitops-poc/api-gateway/dev/config \
  AUTH_ADAPTER_HOST=auth-adapter \
  LOG_LEVEL=debug \
  API_KEY=dev-api-key-12345

vault kv put secret/gitops-poc/api-gateway/staging/config \
  AUTH_ADAPTER_HOST=auth-adapter \
  LOG_LEVEL=info \
  API_KEY=staging-api-key-67890

vault kv put secret/gitops-poc/api-gateway/prod/config \
  AUTH_ADAPTER_HOST=auth-adapter \
  LOG_LEVEL=warn \
  API_KEY=prod-api-key-secure

# Аналогично для других сервисов...
```

### Настройка Kubernetes Auth

```bash
# Включить Kubernetes auth
vault auth enable kubernetes

# Настроить auth method (внутри кластера)
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc"

# Создать policy для api-gateway-dev
vault policy write gitops-poc-api-gateway-dev - <<EOF
path "secret/data/gitops-poc/api-gateway/dev/*" {
  capabilities = ["read"]
}
EOF

# Создать role для api-gateway-dev
vault write auth/kubernetes/role/api-gateway-dev \
  bound_service_account_names=api-gateway \
  bound_service_account_namespaces=api-gateway-dev \
  policies=gitops-poc-api-gateway-dev \
  ttl=1h
```

---

## Troubleshooting

### Vault Secrets не синхронизируются

```bash
# Проверить статус VaultStaticSecret
kubectl get vaultstaticsecret -A
kubectl describe vaultstaticsecret api-gateway-secrets -n api-gateway-dev

# Логи VSO
kubectl logs -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator
```

### ArgoCD Application не синхронизируется

```bash
# Статус приложения
argocd app get api-gateway-dev

# Принудительная синхронизация
argocd app sync api-gateway-dev --force

# Логи ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### GitLab Agent не подключается

```bash
# Статус агента
kubectl get pods -n gitlab-agent

# Логи агента
kubectl logs -n gitlab-agent -l app=gitlab-agent

# Проверить токен
kubectl get secret -n gitlab-agent gitlab-agent-token -o yaml
```

---

## Ссылки

- [GitLab Agent CI/CD Workflow](https://docs.gitlab.com/user/clusters/agent/ci_cd_workflow/)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso)
- [k8app Helm Chart](https://github.com/d7561985/k8app)
- [API Gateway Project](https://github.com/d7561985/api-gateway)
