# GitOps POC: Multi-Repository Architecture

Демонстрация GitOps подходов (Push и Pull) с мультирепозиторной архитектурой на базе GitLab Agent и ArgoCD.

## Quick Start (Конфигурация)

```bash
# 1. Скопировать и настроить конфигурацию
cp .env.example .env
vim .env  # Изменить GITLAB_GROUP на свой

# 2. Инициализировать проект (обновит все файлы)
./scripts/init-project.sh

# 3. Запустить инфраструктуру
./scripts/setup-infrastructure.sh

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

# Установить инфраструктуру (Vault, ArgoCD)
./scripts/setup-infrastructure.sh

# Настроить Vault секреты
./scripts/setup-vault-secrets.sh
```

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

#### Настройка секретов

```bash
# Вариант 1: Добавить в .env (рекомендуется)
echo 'GITLAB_DEPLOY_TOKEN_USER="gitlab+deploy-token-xxxxx"' >> .env
echo 'GITLAB_DEPLOY_TOKEN="gldt-xxxxxxxxxxxx"' >> .env
./scripts/setup-registry-secret.sh

# Вариант 2: Интерактивный режим (скрипт запросит credentials)
./scripts/setup-registry-secret.sh
```

Скрипт создаёт:
1. Namespace для каждого окружения: `poc-dev`, `poc-staging`, `poc-prod`
2. Секрет `regsecret` в каждом namespace
3. Патчит `default` ServiceAccount — все pods автоматически получают доступ к registry

> **Note:** Благодаря патчу ServiceAccount, `imagePullSecrets` в values **не обязателен** — pods автоматически наследуют imagePullSecrets. В k8app v3.4.0 используется универсальный формат `imagePullSecrets: [{name: regsecret}]`.

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

#### Структура gitops-config/argocd/

```
gitops-config/argocd/
├── project.yaml           # ArgoCD Project с permissions
├── applicationset.yaml    # Генерирует 15 Apps (5 сервисов × 3 env)
├── bootstrap-app.yaml     # "App of Apps" — следит за этой папкой
└── repo-credentials.yaml  # Шаблон для GitLab credentials
```

#### Быстрый старт

```bash
# 1. Добавить GITLAB_TOKEN в .env (нужен scope: read_repository)
echo 'GITLAB_TOKEN="glpat-xxxxxxxxxxxx"' >> .env

# 2. Запустить скрипт настройки
./scripts/setup-pull-based.sh
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

#### Как это работает (App of Apps)

```
┌─────────────────┐     ┌───────────────────┐     ┌─────────────────┐
│ gitops-config/  │────▶│  bootstrap-app    │────▶│  ApplicationSet │
│ argocd/         │     │  (watches folder) │     │  (15 apps)      │
└─────────────────┘     └───────────────────┘     └─────────────────┘
                                                          │
                               ┌──────────────────────────┼──────────────────────────┐
                               ▼                          ▼                          ▼
                        ┌─────────────┐           ┌─────────────┐           ┌─────────────┐
                        │api-gateway  │           │auth-adapter │           │ ... (x15)   │
                        │  -dev       │           │  -dev       │           │             │
                        └─────────────┘           └─────────────┘           └─────────────┘
```

- **bootstrap-app** следит за `gitops-config/argocd/` в GitLab
- При изменении автоматически применяет `project.yaml` и `applicationset.yaml`
- **ApplicationSet** генерирует 15 Applications (5 сервисов × 3 окружения)
- Каждый Application следит за `.cicd/*.yaml` в репо сервиса

### 6. Push-based (GitLab Agent)

Push-based подход использует GitLab Agent для прямого деплоя из CI/CD pipeline в кластер.

#### Шаг 1: Создать репозиторий gitops-config в GitLab

```bash
# Создать пустой репо в GitLab: https://gitlab.com/groups/${GITLAB_GROUP}/-/new
# Name: gitops-config

# Запушить содержимое
cd gitops-config/
git init
git remote add origin git@gitlab.com:${GITLAB_GROUP}/gitops-config.git
git add .
git commit -m "Initial commit: ArgoCD + GitLab Agent config"
git push -u origin main
```

#### Шаг 2: Зарегистрировать агента в GitLab и получить токен

1. Перейти в проект `gitops-config` в GitLab:
   ```
   https://gitlab.com/${GITLAB_GROUP}/gitops-config
   ```

2. **Operate** → **Kubernetes clusters** → **Connect a cluster (agent)**

3. Ввести имя агента: `minikube-agent`

4. Нажать **Create and register**

5. **ВАЖНО: Скопировать токен!** Он показывается только один раз.
   ```
   Формат: glagent-xxxxxx-xxxxxxxxxxxxxxxxx
   ```

6. GitLab также покажет готовую команду Helm — можно использовать её или наш скрипт.

#### Шаг 3: Установить агента в Kubernetes кластер

```bash
# Убедиться что кластер запущен
kubectl cluster-info

# Добавить токен в .env файл (полученный на шаге 2)
echo 'GITLAB_AGENT_TOKEN="glagent-xxxxxx-xxxxxxxxxxxxxxxxx"' >> .env

# Запустить установку через наш скрипт
./scripts/setup-push-based.sh
```

Или вручную через Helm:
```bash
export GITLAB_AGENT_TOKEN='glagent-xxxxxx-xxxxxxxxxxxxxxxxx'
helm repo add gitlab https://charts.gitlab.io
helm repo update
helm upgrade --install gitlab-agent gitlab/gitlab-agent \
  --namespace gitlab-agent \
  --create-namespace \
  --set config.token=${GITLAB_AGENT_TOKEN} \
  --set config.kasAddress=wss://kas.gitlab.com
```

#### Шаг 4: Проверить подключение агента

```bash
# Проверить что pod запущен
kubectl get pods -n gitlab-agent
# Ожидаемый статус: Running

# Проверить логи — должно быть "Feature: agent_configuration started"
kubectl logs -n gitlab-agent -l app.kubernetes.io/name=gitlab-agent

# В GitLab UI: Operate → Kubernetes clusters
# Агент должен показывать "Connected"
```

#### Шаг 5: Настроить CI/CD доступ (ci_access)

Конфиг `.gitlab/agents/minikube-agent/config.yaml` уже есть в репо — он разрешает всем проектам группы использовать агента:

```yaml
ci_access:
  groups:
    - id: gitops-poc-dzha
```

#### Шаг 6: Переключить CI/CD на Push-based режим

**Вариант A:** Изменить в `.gitlab-ci.yml` каждого сервиса:
```yaml
variables:
  GITOPS_MODE: "push"  # Было: "pull"
```

**Вариант B:** Добавить переменную на уровне группы:
```
GitLab Group → Settings → CI/CD → Variables
Key: GITOPS_MODE
Value: push
```

#### Как это работает (Push-based)

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Developer  │────▶│  GitLab CI  │────▶│GitLab Agent │────▶│  Kubernetes │
│   commit    │     │ build+helm  │     │  (в кластере)│     │   deploy    │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

CI использует контекст агента: `${GITLAB_GROUP}/gitops-config:minikube-agent`

#### Troubleshooting Agent

```bash
# Статус pod
kubectl get pods -n gitlab-agent

# Логи (ищи ошибки подключения)
kubectl logs -n gitlab-agent -l app.kubernetes.io/name=gitlab-agent -f

# События namespace
kubectl get events -n gitlab-agent --sort-by='.lastTimestamp'

# Переустановить агента
helm uninstall gitlab-agent -n gitlab-agent
export GITLAB_AGENT_TOKEN='новый-токен'
./scripts/setup-push-based.sh
```

| Проблема | Решение |
|----------|---------|
| Pod в CrashLoopBackOff | Неверный токен — перерегистрируй агента |
| "connection refused" | Проверь kasAddress (должен быть `wss://kas.gitlab.com`) |
| CI не видит контекст | Проверь ci_access в config.yaml и что агент Connected |

---

## Структура проекта

```
gitops-poc/                        # Этот репозиторий (GitHub)
├── README.md
├── Makefile                       # Полезные команды (make proxy-all, etc.)
├── .env.example                   # Шаблон конфигурации
├── .env                           # Конфигурация проекта (не в git)
├── .gitignore
├── gitops-config/                 # → Отдельный репо в GitLab
│   ├── .gitlab/
│   │   └── agents/
│   │       └── minikube-agent/
│   │           └── config.yaml    # Конфиг GitLab Agent (Push-based)
│   └── argocd/
│       ├── project.yaml           # ArgoCD Project
│       ├── applicationset.yaml    # Генерирует 15 Apps (5 сервисов × 3 env)
│       ├── bootstrap-app.yaml     # "App of Apps" - следит за этой папкой
│       └── repo-credentials.yaml  # Шаблон для GitLab credentials
├── infrastructure/
│   ├── vault/                     # Vault + VSO
│   │   ├── helm-values.yaml
│   │   ├── vso-values.yaml
│   │   └── setup.sh
│   ├── argocd/                    # ArgoCD
│   │   ├── helm-values.yaml
│   │   └── setup.sh
│   └── gitlab-agent/              # GitLab Agent
│       ├── helm-values.yaml
│       ├── config.yaml
│       └── setup.sh
├── scripts/
│   ├── init-project.sh            # Инициализация проекта
│   ├── setup-infrastructure.sh
│   ├── setup-vault-secrets.sh
│   ├── setup-registry-secret.sh   # imagePullSecrets (regsecret)
│   ├── setup-push-based.sh
│   ├── setup-pull-based.sh
│   └── build-local-images.sh
├── gitops-config/
│   └── argocd/
│       ├── applicationset.yaml    # ArgoCD ApplicationSet
│       ├── project.yaml           # ArgoCD Project
│       └── README.md
├── services/                      # Примеры репозиториев сервисов
│   ├── api-gateway/
│   │   ├── .cicd/
│   │   │   ├── default.yaml       # Включает secrets: и secretsProvider:
│   │   │   ├── dev.yaml
│   │   │   ├── staging.yaml
│   │   │   └── prod.yaml
│   │   └── .gitlab-ci.yml
│   ├── auth-adapter/
│   ├── web-grpc/
│   ├── web-http/
│   └── health-demo/
├── templates/                     # Шаблон для новых сервисов
│   └── service-repo/
├── docs/
│   └── k8app-recommendations.md   # Рекомендации для k8app
└── tests/
    └── smoke-test.sh
```

---

## GitOps подходы

### Pull-based (ArgoCD) — рекомендуется для Production

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

### Push-based (GitLab Agent) — для быстрой итерации

| Характеристика | Описание |
|----------------|----------|
| Триггер деплоя | Pipeline completion |
| Источник истины | Git + текущее состояние кластера |
| Версия образа | `--set image.tag=${CI_COMMIT_SHORT_SHA}` |
| Rollback | Re-run pipeline или `git revert` |

**CI Pipeline деплоит напрямую:**
```yaml
deploy:dev:
  script:
    - helm upgrade --install ... --set image.tag=${CI_COMMIT_SHORT_SHA}
```

---

## Vault Secrets (k8app v3.4.0)

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

`gitops-config/infrastructure/poc-dev/vault-auth.yaml`:
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

4. **Добавить сервис в `.env`:**
   ```bash
   SERVICES="api-gateway auth-adapter web-grpc web-http health-demo my-new-service"
   ```

5. **Перезапустить init-project.sh:**
   ```bash
   ./scripts/init-project.sh
   ```
   Это обновит ApplicationSet и другие файлы.

6. **Создать Vault секреты:**
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

# Проверить что default SA патчирован
kubectl get sa default -n poc-dev -o yaml | grep -A5 imagePullSecrets

# Проверить конфигурацию секрета
kubectl get secret regsecret -n poc-dev -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq

# Если секрета нет или SA не патчирован - перезапустить
./scripts/setup-registry-secret.sh

# Проверить события pod
kubectl describe pod -n poc-dev -l app=api-gateway
```

**Частые причины:**
- Deploy Token истёк или отозван → создать новый
- Неверный scope токена → должен быть `read_registry`
- ServiceAccount не патчирован → перезапустить `setup-registry-secret.sh`

---

## Ссылки

- [GitLab Agent CI/CD Workflow](https://docs.gitlab.com/user/clusters/agent/ci_cd_workflow/)
- [GitLab Container Registry](https://docs.gitlab.com/user/packages/container_registry/)
- [GitLab Deploy Tokens](https://docs.gitlab.com/user/project/deploy_tokens/)
- [ArgoCD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [ArgoCD Multi-Source Applications](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)
- [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso)
- [k8app Helm Chart](https://github.com/d7561985/k8app)
