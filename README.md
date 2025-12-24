# GitOps POC: Multi-Repository Architecture

GitOps платформа с мультирепозиторной архитектурой на базе ArgoCD.

> **Первый раз?** См. [Pre-flight Checklist](docs/PREFLIGHT-CHECKLIST.md) — полный чеклист настройки GitLab, CloudFlare и инфраструктуры.

## Quick Start (Конфигурация)

```bash
# 1. Скопировать и настроить конфигурацию
cp .env.example .env
vim .env  # Изменить GITLAB_GROUP на свой

# 2. Инициализировать проект (обновит все файлы)
./shared/scripts/init-project.sh

# 3. Запустить инфраструктуру
./shared/scripts/setup-infrastructure.sh

# 4. Полезные команды (Makefile)
make help              # Показать все команды
make proxy-all         # Запустить все прокси (Vault, ArgoCD, API Gateway)
make proxy-argocd      # Только ArgoCD UI
make proxy-vault       # Только Vault UI
make stop-proxy        # Остановить все прокси
```

**Конфигурируемые параметры (.env):**
- `GITLAB_GROUP` — группа в GitLab (например: `gitops-poc-dzha`)
- `GITLAB_HOST` — хост GitLab (`gitlab.com` или self-managed)
- `SERVICES` — список сервисов
- `NAMESPACE_PREFIX` — префикс namespace (все сервисы в `{prefix}-{env}`)
- `VAULT_PATH_PREFIX` — префикс путей в Vault

---

## Архитектура

```
GitLab (gitlab.com/${GITLAB_GROUP}/):
│
├── api-gateway/           ← Репо сервиса с кодом + .cicd/
├── auth-adapter/          ← Репо сервиса
├── web-grpc/              ← Репо сервиса
├── web-http/              ← Репо сервиса
├── health-demo/           ← Репо сервиса
│
└── gitops-config/         ← Этот репозиторий (инфраструктура + ArgoCD)
```

### Структура репозитория сервиса

```
service-repo/
├── src/                   # Код сервиса (Go)
├── Dockerfile             # Multi-stage сборка образа
├── .cicd/
│   ├── default.yaml       # Базовые Helm values (k8app/app v3.4.0 format)
│   ├── dev.yaml           # Dev overrides + GitLab Registry image
│   ├── staging.yaml       # Staging overrides
│   └── prod.yaml          # Prod overrides
└── .gitlab-ci.yml         # CI/CD pipeline
```

> **Note:** С k8app v3.4.0 отдельный `vault-secret.yaml` не нужен — chart автоматически создаёт `VaultStaticSecret` на основе секции `secrets:` в values.

### Сервисы

| Сервис | Описание | Исходный код | Docker образ |
|--------|----------|--------------|--------------|
| api-gateway | Envoy Proxy с Go config generator | [github.com/d7561985/api-gateway](https://github.com/d7561985/api-gateway) | GitLab Registry |
| auth-adapter | gRPC ext_authz сервис | [github.com/d7561985/api-gateway/envoy/auth-adapter](https://github.com/d7561985/api-gateway) | GitLab Registry |
| health-demo | Простой health check сервис | Локальный | GitLab Registry |
| web-grpc | gRPC backend (fake-service) | [nicholasjackson/fake-service](https://github.com/nicholasjackson/fake-service) | Docker Hub |
| web-http | HTTP backend (fake-service) | [nicholasjackson/fake-service](https://github.com/nicholasjackson/fake-service) | Docker Hub |

### Принципы конфигурации

**Environment-agnostic конфиги:**
- Все сервисы одной системы деплоятся в один namespace (`poc-dev`, `poc-staging`, `poc-prod`)
- Конфиги не содержат hardcoded namespace — один конфиг работает в любом окружении
- Inter-service communication через короткие DNS имена (`auth-adapter` вместо `auth-adapter.poc-dev.svc.cluster.local`)
- Kubernetes автоматически резолвит короткие имена в текущем namespace

**Разделение конфигов:**

| Файл | Содержит | Пример |
|------|----------|--------|
| `default.yaml` | Общие настройки для всех окружений | `appName`, `service.ports`, `configmap`, `configfiles` |
| `{env}.yaml` | Env-specific переопределения + image | `image.repository/tag`, `replicas`, `resources`, `configmap` overrides |

**Формат k8app/app chart v3.4.0:**
```yaml
# default.yaml
configmap:              # Env vars через ConfigMap
  LOG_LEVEL: "info"
  AUTH_HOST: "auth-adapter-sv"

configfiles:            # Конфиг файлы через ConfigMap
  mountPath: "/config"
  data:
    config.yaml: |
      key: value

# Секреты из Vault (k8app v3.4.0 автоматически создаёт VaultStaticSecret)
secrets:
  API_KEY: "/gitops-poc-dzha/my-service/dev/config"  # Абсолютный путь
  DB_PASSWORD: "database"                             # Относительный: {ns}/{app}/{env}/database

secretsProvider:
  provider: "vault"      # vault | aws | none
  vault:
    authRef: "vault-auth"
    mount: "secret"
    type: "kv-v2"
    refreshAfter: "1h"

imagePullSecrets:       # Универсальный формат (v3.4.0+)
  - name: regsecret

# dev.yaml
image:
  repository: registry.gitlab.com/gitops-poc-dzha/my-service
  tag: latest
configmap:
  LOG_LEVEL: "debug"    # Переопределение
```

**Что НЕ должно быть в env-specific файлах:**
- Ссылки на другие сервисы (используй короткие DNS имена в `default.yaml`)
- Namespace-зависимые значения
- Дублирование значений из `default.yaml` (кроме configmap overrides)

**Что должно быть в env-specific файлах:**
- `image.repository/tag` — URL образа в GitLab Registry
- `environment: dev/staging/prod`
- `replicas` — количество реплик
- `resources` — CPU/memory limits
- `configmap` переопределения (`LOG_LEVEL`, `OTEL_ENABLE`)
- `labels`/`annotations` с env-specific значениями
- `hpa`/`pdb` настройки (только для staging/prod)

### Flow деплоя (Pull-based)

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Developer  │────▶│  GitLab CI  │────▶│   Git Repo  │────▶│   ArgoCD    │
│   commit    │     │ build+push  │     │ .cicd/dev   │     │   deploy    │
└─────────────┘     │ update yaml │     │   updated   │     └─────────────┘
                    └─────────────┘     └─────────────┘
```

1. Developer пушит код
2. CI собирает Docker образ и пушит в registry
3. CI обновляет `.cicd/dev.yaml` с новым `image.tag`
4. CI коммитит и пушит изменение `[skip ci]`
5. ArgoCD видит изменение → деплоит автоматически

---

## Требования

| Компонент | Версия | Установка |
|-----------|--------|-----------|
| Minikube | 1.34+ | [docs](https://minikube.sigs.k8s.io/docs/start/) |
| kubectl | 1.28+ | [docs](https://kubernetes.io/docs/tasks/tools/) |
| Helm | 3.12+ | `brew install helm` |
| Docker | 24+ | [docs](https://docs.docker.com/get-docker/) |
| Vault CLI | 1.15+ | `brew tap hashicorp/tap && brew install hashicorp/tap/vault` |
| ArgoCD CLI | 2.9+ | `brew install argocd` |

---

## Quick Start

### 1. Инфраструктура

```bash
# Запустить Minikube
minikube start --cpus 4 --memory 8192 --disk-size 40g

# Установить инфраструктуру (Vault, ArgoCD, vault-admin-token)
./shared/scripts/setup-infrastructure.sh
```

> **Note:** `setup-vault-secrets.sh` больше не нужен! Platform-bootstrap chart автоматически создаёт Vault policies, roles и secret placeholders.

### 2. GitLab Personal Access Token (CI Push)

> **Важно!** Для Pull-based GitOps CI должен пушить изменения `.cicd/*.yaml` обратно в репозиторий. `CI_JOB_TOKEN` не имеет прав на push, поэтому необходим Personal Access Token.
>
> **Note:** Group Access Tokens требуют Premium/Ultimate подписку на GitLab.com. Personal Access Token работает на бесплатном тарифе.

#### Создание Personal Access Token

1. Перейти в User Settings:
   ```
   https://gitlab.com/-/user_settings/personal_access_tokens
   ```

2. Нажать **Add new token** и заполнить:
   - **Token name:** `ci-push-gitops`
   - **Expiration date:** выбрать дату (макс. 1 год)
   - **Scopes:** ✅ `read_repository`, ✅ `write_repository`

3. Нажать **Create personal access token**

4. **Сохранить токен** — он показывается только один раз!

> ⚠️ **Безопасность:** Personal Access Token имеет доступ ко всем твоим репозиториям. Используй отдельный аккаунт для CI или ограничь scope только нужными правами.

#### Добавление токена в CI/CD Variables (на уровне группы)

1. Перейти в CI/CD Variables группы:
   ```
   https://gitlab.com/groups/${GITLAB_GROUP}/-/settings/ci_cd
   ```

2. Развернуть секцию **Variables** → **Add variable**:
   - **Key:** `CI_PUSH_TOKEN`
   - **Value:** `<скопированный токен>`
   - **Protected:** `No` (чтобы работало на всех ветках)
   - **Masked:** `Yes` (скрыть в логах)
   - **Expand variable reference:** `No`

> **Note:** Переменная на уровне группы автоматически доступна всем проектам в группе.

### 3. GitLab Container Registry

Kubernetes требует `imagePullSecrets` для доступа к приватному GitLab Container Registry.

#### Создание Deploy Token

1. Перейти в Settings группы GitLab:
   ```
   https://gitlab.com/${GITLAB_GROUP}/-/settings/repository
   ```
2. Развернуть секцию **Deploy tokens**
3. Создать токен:
   - **Name:** `kubernetes-pull`
   - **Scopes:** `read_registry`
4. Сохранить username и token

#### Настройка через Vault (рекомендуется)

Registry credentials хранятся в Vault и автоматически синхронизируются через VSO:

```bash
# 1. Добавить credentials в .env
echo 'GITLAB_DEPLOY_TOKEN_USER="gitlab+deploy-token-xxxxx"' >> .env
echo 'GITLAB_DEPLOY_TOKEN="gldt-xxxxxxxxxxxx"' >> .env

# 2. setup-infrastructure.sh автоматически сохранит их в Vault
./shared/scripts/setup-infrastructure.sh
```

**Как это работает:**
- Credentials хранятся в Vault: `secret/gitops-poc-dzha/platform/registry`
- `platform-core` создаёт VaultStaticSecret для каждого namespace
- VSO синхронизирует `regsecret` автоматически во все namespace
- При удалении/пересоздании namespace — secret восстанавливается

**Ручная настройка (если нужно обновить credentials):**

```bash
# Подключиться к Vault
kubectl port-forward svc/vault -n vault 8200:8200 &
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.root-token}' | base64 -d)

# Сохранить credentials
REGISTRY="registry.gitlab.com"
USERNAME="gitlab+deploy-token-xxxxx"
PASSWORD="gldt-xxxxxxxxxxxx"
AUTH=$(echo -n "${USERNAME}:${PASSWORD}" | base64)

vault kv put secret/gitops-poc-dzha/platform/registry \
  .dockerconfigjson="{\"auths\":{\"${REGISTRY}\":{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\",\"auth\":\"${AUTH}\"}}}"
```

> **Important:** Каждый сервис должен объявить `imagePullSecrets` в своих values (автоматически через k8app-defaults.yaml):
> ```yaml
> # .cicd/default.yaml или k8app-defaults.yaml
> imagePullSecrets:
>   - name: regsecret
> ```

#### Namespace схема

Все сервисы деплоятся в один namespace на окружение:
```
poc-dev/          ← api-gateway, auth-adapter, web-grpc, web-http, health-demo
poc-staging/      ← api-gateway, auth-adapter, web-grpc, web-http, health-demo
poc-prod/         ← api-gateway, auth-adapter, web-grpc, web-http, health-demo
```

Настраивается через `NAMESPACE_PREFIX` в `.env`.

### 4. Создать GitLab группу и репозитории

```bash
# Структура в GitLab:
# gitlab.com/${GITLAB_GROUP}/
# ├── gitops-config/     ← этот репозиторий (ApplicationSet живёт здесь)
# ├── api-gateway/       ← репо сервиса (.cicd/, .gitlab-ci.yml)
# ├── auth-adapter/
# ├── web-grpc/
# ├── web-http/
# └── health-demo/
```

**Шаги:**

1. Создать группу `${GITLAB_GROUP}` в GitLab
2. Создать репозиторий `gitops-config` и запушить этот проект
3. Создать репозитории для сервисов и скопировать туда файлы:
   ```bash
   # Пример для api-gateway
   git clone git@gitlab.com:${GITLAB_GROUP}/api-gateway.git
   cp -r services/api-gateway/* api-gateway/
   cd api-gateway && git add . && git commit -m "Initial" && git push
   ```

### 5. Pull-based (ArgoCD)

Pull-based подход использует **App of Apps** паттерн — ArgoCD следит за репозиторием `gitops-config` и автоматически создаёт все Application'ы.

#### Структура gitops-config/

```
gitops-config/
├── argocd/
│   ├── project.yaml               # ArgoCD Project с permissions
│   ├── bootstrap-app.yaml         # "App of Apps" — следит за этой папкой
│   └── platform-modules.yaml # ArgoCD Application для platform-core chart
└── charts/
    └── platform-core/, service-groups/, preview-environments/, ingress-cloudflare/        # Helm chart - single source of truth
        ├── Chart.yaml
        ├── values.yaml            # Конфигурация сервисов и окружений
        └── templates/
            ├── bootstrap-job.yaml     # Создаёт Vault policies/roles/secrets
            ├── applicationset.yaml    # Генерирует 15 Apps (5 сервисов × 3 env)
            ├── vault-auth.yaml        # VaultAuth для каждого namespace
            └── namespaces.yaml        # Создаёт poc-dev/staging/prod
```

#### Быстрый старт

```bash
# 1. Добавить GITLAB_TOKEN в .env (нужен scope: read_repository)
echo 'GITLAB_TOKEN="glpat-xxxxxxxxxxxx"' >> .env

# 2. Запустить скрипт настройки
./shared/scripts/setup-pull-based.sh
```

Скрипт автоматически:
- Добавит GitLab credentials в ArgoCD
- Применит Project и Bootstrap Application
- Bootstrap App создаст все 15 Application'ов из ApplicationSet

#### Ручная настройка (альтернатива)

```bash
# 1. Добавить credentials для всей группы
kubectl create secret generic gitlab-repo-creds -n argocd \
  --from-literal=type=git \
  --from-literal=url=https://gitlab.com/${GITLAB_GROUP} \
  --from-literal=username=oauth2 \
  --from-literal=password=${GITLAB_TOKEN}
kubectl label secret gitlab-repo-creds -n argocd \
  argocd.argoproj.io/secret-type=repo-creds

# 2. Применить ArgoCD конфигурацию
kubectl apply -f gitops-config/argocd/project.yaml
kubectl apply -f gitops-config/argocd/bootstrap-app.yaml

# 3. Проверить созданные приложения
kubectl get applications -n argocd

# 4. Открыть ArgoCD UI
make proxy-argocd
# http://localhost:8081
```

#### Как это работает (App of Apps + Modular Platform Charts)

```
┌─────────────────┐     ┌───────────────────┐     ┌─────────────────────┐
│ gitops-config/  │────▶│  bootstrap-app    │────▶│  platform-modules  │
│ argocd/         │     │  (watches folder) │     │    (4 Apps)        │
└─────────────────┘     └───────────────────┘     └──────────┬──────────┘
                                                             │ генерирует
                        ┌────────────────────────────────────┴────────────────────────────┐
                        ▼                          ▼                          ▼           ▼
                 ┌─────────────┐           ┌─────────────┐           ┌───────────┐ ┌──────────┐
                 │ Namespaces  │           │  VaultAuth  │           │ApplicationSet│ │Vault Job│
                 │poc-dev/...  │           │ per env     │           │ (15 apps) │ │policies  │
                 └─────────────┘           └─────────────┘           └─────┬─────┘ └──────────┘
                                                                           │
                               ┌──────────────────────────┼──────────────────────────┐
                               ▼                          ▼                          ▼
                        ┌─────────────┐           ┌─────────────┐           ┌─────────────┐
                        │api-gateway  │           │auth-adapter │           │ ... (x15)   │
                        │  -dev       │           │  -dev       │           │             │
                        └─────────────┘           └─────────────┘           └─────────────┘
```

- **bootstrap-app** следит за `gitops-config/argocd/` в GitLab
- При изменении применяет `project.yaml` и `platform-modules.yaml`
- **platform-core** and modular charts создаёт:
  - Namespaces для каждого окружения
  - Vault policies и Kubernetes auth roles (через PreSync Job)
  - VaultAuth ресурсы для VSO
  - ApplicationSet для генерации 15 Applications
- Каждый Application следит за `.cicd/*.yaml` в репо сервиса

---

## Структура проекта

```
gitops/                            # Монорепо
├── README.md
├── Makefile                       # Полезные команды (make proxy-all, etc.)
├── .env.example                   # Шаблон конфигурации
├── .env                           # Конфигурация проекта (не в git)
│
├── infra/                         # Per-brand infrastructure configs
│   └── poc/
│       └── gitops-config/         # → GitLab: infra/poc/gitops-config
│           ├── argocd/
│           │   ├── project.yaml           # ArgoCD Project
│           │   ├── bootstrap-app.yaml     # "App of Apps"
│           │   └── platform-modules.yaml  # 4 ArgoCD Applications
│           ├── charts/
│           │   ├── platform-core/         # Namespaces, ApplicationSet, Vault
│           │   ├── service-groups/        # Infrastructure access (ArgoCD, Grafana)
│           │   ├── preview-environments/  # Feature branch previews
│           │   └── ingress-cloudflare/    # CloudFlare Tunnel routing
│           └── platform/
│               ├── base.yaml              # Shared settings
│               ├── core.yaml              # Services config
│               └── preview.yaml           # Preview environments config
│
├── shared/                        # Shared tooling (all brands)
│   ├── infrastructure/            # → GitLab: shared/infrastructure
│   │   ├── vault/                 # Vault + VSO setup
│   │   ├── argocd/                # ArgoCD setup
│   │   ├── cilium/                # CNI + Hubble
│   │   ├── monitoring/            # Prometheus + Grafana
│   │   ├── cert-manager/          # TLS certificates
│   │   ├── external-dns/          # DNS automation
│   │   └── cloudflare-tunnel/     # Tunnel setup
│   ├── scripts/                   # → GitLab: shared/scripts
│   │   ├── setup-infrastructure.sh    # Install all infrastructure + Vault registry
│   │   ├── setup-pull-based.sh        # Configure ArgoCD
│   │   ├── init-project.sh            # Initialize new project
│   │   ├── setup-vault-secrets.sh     # Create Vault policies
│   │   └── setup-registry-secret.sh   # DEPRECATED (use Vault instead)
│   └── templates/                 # → GitLab: shared/templates
│       ├── service-repo/          # Template for new services
│       └── proto-service/         # Template for proto repos
│
├── services/                      # → GitLab: services/*
│   ├── sentry-demo/               # Submodule
│   ├── api-gateway/               # Submodule
│   └── ...
│
└── docs/                          # Documentation
```

---

## GitOps подходы

### Pull-based (ArgoCD)

| Характеристика | Описание |
|----------------|----------|
| Триггер деплоя | ArgoCD polling (3 мин) или webhook |
| Источник истины | Git репозиторий сервиса |
| Версия образа | В `.cicd/{env}.yaml` |
| Rollback | UI/CLI ArgoCD или `git revert` |
| Audit trail | Git history |

**CI Pipeline обновляет `.cicd/{env}.yaml`:**
```yaml
update:dev:
  script:
    - yq -i '.image.tag = "'${CI_COMMIT_SHORT_SHA}'"' .cicd/dev.yaml
    - git commit -m "ci(dev): update image [skip ci]"
    - git push
```

ArgoCD автоматически синхронизирует изменения и деплоит новую версию.

---

## Vault Secrets (k8app v3.4.0)

### Vault Mode: Standalone с Persistence

Vault работает в **standalone mode** с persistent storage (PVC). Это означает:

- Данные сохраняются между рестартами pod
- **Требуется unseal после каждого рестарта**
- Ключи хранятся в K8s secret `vault-keys` и файле `.vault-keys`

**Unseal после рестарта:**
```bash
./shared/infrastructure/vault/unseal.sh

# Или вручную:
UNSEAL_KEY=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.unseal-key}' | base64 -d)
kubectl exec vault-0 -n vault -- vault operator unseal "$UNSEAL_KEY"
```

**Полная переустановка Vault:**
```bash
helm uninstall vault -n vault
kubectl delete pvc data-vault-0 -n vault
./shared/infrastructure/vault/setup.sh
```

> **Важно:** После переустановки нужно пересинхронизировать `platform-core` для создания policies и roles.

### Архитектура

```
┌──────────────┐      ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│    Vault     │─────▶│     VSO      │─────▶│  K8s Secret  │─────▶│     Pod      │
│  KV secrets  │      │VaultStatic   │      │ (appName)    │      │   env vars   │
└──────────────┘      │   Secret     │      └──────────────┘      └──────────────┘
                      └──────────────┘
                            ▲
                            │ создаёт автоматически
                      ┌──────────────┐
                      │   k8app      │
                      │   chart      │
                      │   v3.4.0     │
                      └──────────────┘
```

### Структура путей в Vault

```
secret/data/${GITLAB_GROUP}/{service}/{env}/config
             │               │         │
             │               │         └── dev | staging | prod
             │               └── api-gateway | auth-adapter | ...
             └── gitops-poc-dzha (группа GitLab)

Примеры:
  secret/data/gitops-poc-dzha/api-gateway/dev/config
  secret/data/gitops-poc-dzha/health-demo/dev/config
```

### Формат путей в k8app secrets

```yaml
secrets:
  # Абсолютный путь (начинается с /) - используется как есть
  API_KEY: "/gitops-poc-dzha/api-gateway/dev/config"

  # Относительный путь - становится {namespace}/{appName}/{path}
  DB_URL: "database"  # → poc-dev/api-gateway/database
```

> **Note:** В `secrets:` путь указывается БЕЗ `secret/data/` префикса — k8app добавляет его автоматически через `secretsProvider.vault.mount`.

### Vault Policy и Role

Для каждого namespace создаётся policy и role:

**Policy `poc-dev-read`:**
```hcl
# Glob доступ ко всем сервисам в dev окружении
# ВАЖНО: используем + (single segment glob), а не * (wildcard)
path "secret/data/gitops-poc-dzha/+/dev/+" {
  capabilities = ["read"]
}
path "secret/metadata/gitops-poc-dzha/+/dev/+" {
  capabilities = ["read", "list"]
}
```

> **Note:** В Vault HCL `*` матчит любое количество символов в пределах одного сегмента, но `+` явно указывает на single segment glob match, что более предсказуемо.

**Role `poc-dev-default`:**
```bash
vault write auth/kubernetes/role/poc-dev-default \
  bound_service_account_names=default \
  bound_service_account_namespaces=poc-dev \
  policies=poc-dev-read \
  audience=vault \
  ttl=1h
```

> **Важно:** `audience=vault` обязателен — VaultAuth использует `audiences: [vault]`.

### Как настроить секреты

**1. Создать секреты в Vault:**
```bash
# Port-forward к Vault
kubectl port-forward svc/vault -n vault 8200:8200 &
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# Создать секреты для сервиса
vault kv put secret/gitops-poc-dzha/api-gateway/dev/config \
  API_KEY="dev-secret-key" \
  DB_PASSWORD="dev-password"
```

**2. Добавить секцию secrets в .cicd/default.yaml:**
```yaml
# Формат: ENV_VAR_NAME: "vault-path"
secrets:
  API_KEY: "/gitops-poc-dzha/api-gateway/dev/config"
  DB_PASSWORD: "/gitops-poc-dzha/api-gateway/dev/config"

secretsProvider:
  provider: "vault"
  vault:
    authRef: "vault-auth"   # VaultAuth ресурс в namespace
    mount: "secret"         # KV secrets engine mount
    type: "kv-v2"           # KV version 2
    refreshAfter: "1h"      # Интервал синхронизации
```

**3. VaultAuth (создаётся infrastructure-app):**

`infra/poc/gitops-config/charts/platform-core/templates/vault-auth.yaml`:
```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth
  namespace: poc-dev
spec:
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: poc-dev-default    # Vault role
    serviceAccount: default  # K8s SA
    audiences:
      - vault                # Должен совпадать с audience в role
```

### Что создаёт k8app chart

При деплое с `secrets:` и `secretsProvider:` chart автоматически создаёт:

1. **VaultStaticSecret** — запрашивает секреты из Vault
2. **K8s Secret** — VSO синхронизирует данные из Vault
3. **Pod env vars** — через `secretKeyRef` из созданного Secret

### Требования

| Компонент | Описание |
|-----------|----------|
| VSO | Vault Secrets Operator установлен в кластере |
| VaultAuth | Ресурс `vault-auth` в namespace (создаётся `infrastructure-app`) |
| Vault policy | `poc-{env}-read` с доступом к `secret/data/gitops-poc-dzha/*/{env}/*` |
| Vault role | `poc-{env}-default` с audience=vault, привязан к SA default |

### Troubleshooting Secrets

```bash
# Проверить VaultStaticSecret статус
kubectl get vaultstaticsecret -n poc-dev
kubectl describe vaultstaticsecret <name> -n poc-dev

# Проверить созданный K8s Secret
kubectl get secret -n poc-dev | grep -v regsecret

# Проверить env vars в поде
kubectl exec -n poc-dev deploy/api-gateway -- env | grep API_KEY

# Логи VSO
kubectl logs -n vault-secrets-operator-system -l control-plane=controller-manager
```

---

## Monitoring (Prometheus + Grafana + Hubble)

Система мониторинга построена на двух уровнях:

### 1. Application Metrics (Prometheus)

**kube-prometheus-stack** собирает метрики приложений:
- Request latency, error rates, throughput
- Business metrics (orders, users, etc.)
- Resource usage (CPU, memory)
- Custom application metrics

### 2. Network Observability (Cilium Hubble)

**Hubble** с eBPF даёт сетевую видимость:
- L3/L4 network flows (кто с кем общается)
- L7 visibility (HTTP, gRPC, DNS запросы)
- Network policy enforcement
- Service dependency maps

> **Важно:** Hubble и Prometheus **дополняют** друг друга, не заменяют!

### Быстрый доступ

```bash
# Grafana (метрики + дашборды)
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# URL: http://localhost:3000 (admin / admin)

# Prometheus (raw метрики)
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090

# Hubble UI (сетевые потоки)
cilium hubble ui
```

### Grafana Dashboards

**Включены по умолчанию:**
- Kubernetes cluster overview
- Node exporter metrics
- Pod/Deployment/StatefulSet metrics
- CoreDNS metrics

**Cilium/Hubble (импортировать вручную):**
| Dashboard | Grafana ID |
|-----------|------------|
| Cilium Agent | 13286 |
| Hubble | 13502 |
| Hubble DNS | 13537 |
| Hubble HTTP | 13538 |

### Service Discovery

Prometheus автоматически обнаруживает все сервисы через:

1. **ServiceMonitor** — для сервисов с K8s Service (предпочтительно)
2. **Pod annotations** — fallback для legacy приложений:
   ```yaml
   annotations:
     prometheus.io/scrape: "true"
     prometheus.io/port: "8080"
     prometheus.io/path: "/metrics"
   ```

> **Note:** k8app пока не поддерживает ServiceMonitor нативно. См. [feature request](docs/k8app-servicemonitor-feature-request.md).

### Redis Cache Metrics

Для сервисов с `cache.enabled: true`:
```yaml
cache:
  enabled: true
  exporter:
    enabled: true  # Redis exporter на порту 9121
```

Redis exporter автоматически скрейпится через ServiceMonitor.

---

## Добавление нового сервиса

1. **Скопировать шаблон:**
   ```bash
   cp -r templates/service-repo/ /path/to/my-new-service
   ```

2. **Заменить placeholder:**
   ```bash
   sed -i 's/{{SERVICE_NAME}}/my-new-service/g' /path/to/my-new-service/**/*
   ```

3. **Создать репозиторий в GitLab:**
   - `${GITLAB_GROUP}/my-new-service`

4. **Добавить сервис в `gitops-config/platform/core.yaml`:**
   ```yaml
   services:
     # ... существующие сервисы
     my-new-service:
       syncWave: "0"
   ```

5. **Закоммитить и запушить изменения:**
   ```bash
   cd gitops-config
   git add platform/core.yaml
   git commit -m "feat: add my-new-service to platform"
   git push
   ```

   ArgoCD автоматически:
   - Создаст Vault policy и role для сервиса
   - Создаст placeholder для секретов в Vault
   - Сгенерирует ArgoCD Applications для всех окружений

6. **Обновить секреты в Vault (опционально):**
   ```bash
   vault kv put secret/${VAULT_PATH_PREFIX}/my-new-service/dev/config KEY=value
   ```

---

## Troubleshooting

### ArgoCD не синхронизируется

```bash
# Статус приложений
argocd app list
argocd app get api-gateway-dev

# Принудительная синхронизация
argocd app sync api-gateway-dev --force

# Логи
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### CI не обновляет .cicd/*.yaml

```bash
# Проверить права GitLab CI token
# Settings → CI/CD → Variables
# CI_JOB_TOKEN должен иметь права на push

# Проверить protected branches
# Settings → Repository → Protected branches
```

### Vault секреты не синхронизируются

```bash
# Статус VaultStaticSecret
kubectl get vaultstaticsecret -A
kubectl describe vaultstaticsecret api-gateway-secrets -n api-gateway-dev

# Логи VSO
kubectl logs -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator
```

### ImagePullBackOff / ErrImagePull

Проблема с доступом к GitLab Container Registry:

```bash
# Проверить наличие секрета в namespace
kubectl get secret regsecret -n poc-dev

# Проверить конфигурацию секрета
kubectl get secret regsecret -n poc-dev -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq

# Проверить VaultStaticSecret статус
kubectl get vaultstaticsecret -n poc-dev

# Проверить что сервис объявляет imagePullSecrets
kubectl get deployment api-gateway -n poc-dev -o yaml | grep -A3 imagePullSecrets

# Проверить события pod
kubectl describe pod -n poc-dev -l app=api-gateway
```

**Частые причины:**
- Deploy Token истёк или отозван → обновить в Vault
- Credentials не сохранены в Vault → см. секцию "GitLab Container Registry"
- VaultStaticSecret в ошибке → проверить `kubectl describe vaultstaticsecret regsecret -n poc-dev`
- Сервис не объявляет `imagePullSecrets` → наследуется из k8app-defaults.yaml

**Обновить credentials в Vault:**
```bash
vault kv put secret/gitops-poc-dzha/platform/registry \
  .dockerconfigjson='{"auths":{"registry.gitlab.com":{"username":"...","password":"..."}}}'
```

---

## CloudFlare Integration

### TLS Certificates (cert-manager + DNS01)

Автоматические TLS сертификаты через Let's Encrypt с DNS01 challenge.

#### Создание CloudFlare API Token

1. Перейти в [CloudFlare API Tokens](https://dash.cloudflare.com/profile/api-tokens)

2. Нажать **Create Token**

3. Использовать шаблон **"Edit zone DNS"** или создать custom token:
   - **Zone / DNS / Edit** — редактирование DNS записей
   - **Zone / Zone / Read** — чтение информации о зоне
   - **Zone Resources:** Include All Zones (или конкретная зона)

4. Добавить токен в `.env`:
   ```bash
   CLOUDFLARE_API_TOKEN="your-actual-token"
   ```

5. Запустить setup:
   ```bash
   ./shared/infrastructure/cert-manager/setup.sh
   ```

### CloudFlare Tunnel (expose local services)

Позволяет выставить minikube сервисы в интернет без публичного IP и открытых портов.

#### Как это работает

```
Internet → CloudFlare Edge → Tunnel → cloudflared pod → Gateway → Services
                                      (outbound only)
```

- **Outbound-only connection** — не нужен публичный IP или открытые порты
- **Automatic TLS** — CloudFlare терминирует TLS на edge
- **Zero Trust** — интегрируется с CloudFlare Access для авторизации

#### Создание Tunnel

1. Перейти в [CloudFlare Zero Trust](https://one.dash.cloudflare.com/)

2. **Networks** → **Tunnels** → **Create a tunnel**

3. Выбрать **Cloudflared** connector

4. Назвать tunnel (например: `minikube-dev`)

5. Выбрать **Docker** environment → скопировать **token** (начинается с `eyJ...`)

6. Добавить в `.env`:
   ```bash
   CLOUDFLARE_TUNNEL_TOKEN="eyJhIjoiNWFi..."
   ```

7. Запустить setup:
   ```bash
   ./shared/infrastructure/cloudflare-tunnel/setup.sh
   ```

8. Настроить **Public Hostname** в dashboard:
   | Public Hostname | Service |
   |-----------------|---------|
   | `app.example.com` | `http://gateway-dev-cilium-gateway.gateway-dev.svc:80` |
   | `api.example.com` | `http://gateway-dev-cilium-gateway.gateway-dev.svc:80` |

#### Когда использовать

| Сценарий | Решение |
|----------|---------|
| Local dev с реальным доменом | CloudFlare Tunnel |
| Показать demo клиенту | CloudFlare Tunnel |
| Webhook тестирование (Stripe, GitHub) | CloudFlare Tunnel |
| Production с публичным IP | cert-manager + DNS01 |

#### Quick Tunnel (без регистрации)

Для быстрого тестирования без настройки:
```bash
# Запустить временный tunnel
cloudflared tunnel --url http://localhost:8080

# Получите URL типа: https://random-name.trycloudflare.com
```

---

## GitLab CI Release Tracking

Отслеживание статуса релиза прямо в GitLab Pipeline. Разработчик видит успех или ошибку деплоя.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Developer  │────▶│  GitLab CI  │────▶│   ArgoCD    │────▶│  Kubernetes │
│   commit    │     │ build+push  │     │   sync      │     │   deploy    │
└─────────────┘     └──────┬──────┘     └─────────────┘     └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   release   │ ◀── argocd app wait
                    │   stage     │     --health --sync
                    │             │
                    │ ✅ Success  │
                    │ ❌ Failed   │
                    └─────────────┘
```

**Быстрый старт:**

1. Создать ArgoCD API token:
   ```bash
   argocd account generate-token --account ci-readonly
   ```

2. Добавить GitLab CI/CD Variables:
   - `ARGOCD_SERVER` — URL ArgoCD сервера
   - `ARGOCD_AUTH_TOKEN` — JWT token

3. Добавить release stage в `.gitlab-ci.yml` (см. [документацию](docs/gitlab-ci-release-tracking.md))

**Подробное руководство:** [docs/gitlab-ci-release-tracking.md](docs/gitlab-ci-release-tracking.md)

---

## Документация

| Документ | Описание |
|----------|----------|
| [Pre-flight Checklist](docs/PREFLIGHT-CHECKLIST.md) | Полный чеклист первоначальной настройки |
| [GitLab CI Release Tracking](docs/gitlab-ci-release-tracking.md) | Отслеживание деплоя в GitLab Pipeline |
| [Gateway API Plan](docs/gateway-api-plan.md) | Настройка Gateway API с Cilium |
| [k8app Recommendations](docs/k8app-recommendations.md) | Рекомендации по использованию k8app chart |
| [k8app ServiceMonitor Feature](docs/k8app-servicemonitor-feature-request.md) | Feature request для ServiceMonitor в k8app |

---

## Tech Stack

### Infrastructure Layer

| Component | Version | Description |
|-----------|---------|-------------|
| **Kubernetes** | 1.28+ | Container orchestration (Minikube for local dev) |
| **Cilium** | 1.15+ | CNI plugin with eBPF, Gateway API support |
| **Gateway API** | v1.0 | Kubernetes-native ingress (HTTPRoute, Gateway) |

### GitOps & Deployment

| Component | Version | Description |
|-----------|---------|-------------|
| **ArgoCD** | 2.9+ | GitOps continuous delivery, App of Apps pattern |
| **GitLab CI/CD** | - | Build pipelines, container registry |
| **Helm** | 3.12+ | Package manager, k8app chart v3.6.0 |

### Security & Secrets

| Component | Version | Description |
|-----------|---------|-------------|
| **HashiCorp Vault** | 1.15+ | Secrets management, KV v2 engine |
| **Vault Secrets Operator (VSO)** | - | K8s-native Vault integration |
| **cert-manager** | 1.13+ | TLS certificates automation (Let's Encrypt) |

### Networking & Exposure

| Component | Version | Description |
|-----------|---------|-------------|
| **CloudFlare Tunnel** | - | Zero-trust access, outbound-only connection |
| **CloudFlare DNS** | - | DNS01 challenge for cert-manager |
| **Envoy Proxy** | - | API Gateway (api-gateway service) |

### Observability

| Component | Version | Description |
|-----------|---------|-------------|
| **Prometheus** | kube-prometheus-stack 80.4.1 | Metrics collection, alerting |
| **Grafana** | (included in stack) | Visualization, dashboards |
| **Hubble** | (Cilium) | eBPF-based network observability |
| **Sentry** | - | Error tracking, performance monitoring, distributed tracing |

### Application Services

| Service | Language/Framework | Description |
|---------|-------------------|-------------|
| **api-gateway** | Go + Envoy | API Gateway with ext_authz |
| **auth-adapter** | Go | gRPC ext_authz service for Envoy |
| **sentry-demo/frontend** | Angular 17 | SPA slot machine demo |
| **sentry-demo/game-engine** | Python/Tornado | Game logic, MongoDB balance tracking |
| **sentry-demo/wager-service** | PHP 8.2/Symfony | Bonus & wagering management |
| **sentry-demo/payment-service** | Node.js | Payment processing |

### Data Stores

| Component | Usage |
|-----------|-------|
| **MongoDB** | Game state, user balances, wager history |
| **RabbitMQ** | Message queue (game events) |
| **Redis** | Caching |

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              CloudFlare Edge                                     │
│  ┌─────────────────┐    ┌─────────────────┐                                     │
│  │   DNS (*.work)  │    │   TLS Termination│                                    │
│  └────────┬────────┘    └────────┬────────┘                                     │
└───────────┼──────────────────────┼──────────────────────────────────────────────┘
            │                      │
            ▼                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         CloudFlare Tunnel (cloudflared)                          │
│                              outbound-only connection                            │
└────────────────────────────────────┬────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            Kubernetes (Minikube)                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                         Gateway API (Cilium)                              │   │
│  │   ┌─────────────┐    ┌─────────────────────────────────────────────┐     │   │
│  │   │   Gateway   │───▶│              HTTPRoute Rules                 │     │   │
│  │   │   (port 80) │    │  /api/game/* → game-engine                  │     │   │
│  │   └─────────────┘    │  /api/bonus/* → wager-service               │     │   │
│  │                      │  /api/wager/* → wager-service               │     │   │
│  │                      │  /* → frontend                              │     │   │
│  │                      └─────────────────────────────────────────────┘     │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                           poc-dev namespace                              │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │    │
│  │  │   frontend   │  │ game-engine  │  │wager-service │  │api-gateway  │  │    │
│  │  │  (Angular)   │  │  (Python)    │  │   (PHP)      │  │  (Envoy)    │  │    │
│  │  └──────────────┘  └──────┬───────┘  └──────┬───────┘  └─────────────┘  │    │
│  │                           │                 │                            │    │
│  │                           ▼                 ▼                            │    │
│  │                    ┌──────────────────────────────┐                      │    │
│  │                    │     infra-dev namespace      │                      │    │
│  │                    │  ┌────────┐  ┌────────────┐  │                      │    │
│  │                    │  │MongoDB │  │  RabbitMQ  │  │                      │    │
│  │                    │  └────────┘  └────────────┘  │                      │    │
│  │                    └──────────────────────────────┘                      │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                  │
│  │  vault (ns)     │  │   argocd (ns)   │  │ cert-manager(ns)│                  │
│  │  ┌───────────┐  │  │  ┌───────────┐  │  │ ┌─────────────┐ │                  │
│  │  │   Vault   │  │  │  │  ArgoCD   │  │  │ │cert-manager │ │                  │
│  │  │    VSO    │  │  │  │ App of Apps│  │  │ │ ClusterIssuer│ │                │
│  │  └───────────┘  │  │  └───────────┘  │  │ └─────────────┘ │                  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Ссылки

- [GitLab Container Registry](https://docs.gitlab.com/user/packages/container_registry/)
- [GitLab Deploy Tokens](https://docs.gitlab.com/user/project/deploy_tokens/)
- [ArgoCD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [ArgoCD Multi-Source Applications](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)
- [ArgoCD CI Automation](https://argo-cd.readthedocs.io/en/stable/user-guide/ci_automation/)
- [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso)
- [k8app Helm Chart](https://github.com/d7561985/k8app)
- [CloudFlare Tunnel Kubernetes Guide](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/deployment-guides/kubernetes/)
- [cert-manager CloudFlare DNS01](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
