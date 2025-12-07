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
```

**Конфигурируемые параметры (.env):**
- `GITLAB_GROUP` — группа в GitLab (например: `gitops-poc-dzha`)
- `GITLAB_HOST` — хост GitLab (`gitlab.com` или self-managed)
- `SERVICES` — список сервисов
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
├── src/                   # Код сервиса
├── Dockerfile             # Сборка образа
├── .cicd/
│   ├── default.yaml       # Базовые Helm values
│   ├── dev.yaml           # Dev overrides (image.tag обновляется CI)
│   ├── staging.yaml       # Staging overrides
│   └── prod.yaml          # Prod overrides
├── vault-secret.yaml      # Vault secrets config
└── .gitlab-ci.yml         # CI/CD pipeline
```

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

### 2. GitLab Container Registry

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
# Добавить credentials
export GITLAB_DEPLOY_TOKEN_USER='gitlab+deploy-token-xxxxx'
export GITLAB_DEPLOY_TOKEN='gldt-xxxxxxxxxxxx'

# Создать секреты во всех namespace
./scripts/setup-registry-secret.sh
```

Секрет `regsecret` будет создан в каждом namespace сервиса (`api-gateway-dev`, `api-gateway-staging`, ...).

> **Note:** k8app чарт использует hardcoded имя секрета `regsecret`. См. [docs/k8app-recommendations.md](docs/k8app-recommendations.md) для предложения по улучшению.

#### Использование в values

Включить `deploySecretHarbor` в `.cicd/default.yaml` сервисов:
```yaml
image:
  repository: registry.gitlab.com/${GITLAB_GROUP}/api-gateway
  tag: latest
  pullPolicy: IfNotPresent

# k8app uses hardcoded secret name "regsecret"
deploySecretHarbor: true
```

### 3. Создать GitLab группу и репозитории

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

### 4. Pull-based (ArgoCD)

ApplicationSet находится в репозитории `gitops-config` и создаёт Application для каждого сервиса.

```bash
# 1. Добавить репозитории в ArgoCD (если приватные)
argocd repo add https://gitlab.com/${GITLAB_GROUP}/api-gateway.git \
  --username git --password <gitlab-token>
# Повторить для каждого сервиса...

# Или добавить credentials для всей группы:
argocd repocreds add https://gitlab.com/${GITLAB_GROUP} \
  --username git --password <gitlab-token>

# 2. Применить ArgoCD Project и ApplicationSet
kubectl apply -f gitops-config/argocd/project.yaml
kubectl apply -f gitops-config/argocd/applicationset.yaml

# 3. Проверить созданные приложения
kubectl get applications -n argocd

# 4. Открыть ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080
```

**Как это работает:**
- ApplicationSet генерирует 15 Applications (5 сервисов × 3 окружения)
- Каждый Application следит за своим репо сервиса (`api-gateway`, `auth-adapter`, ...)
- При изменении `.cicd/*.yaml` в репо сервиса → ArgoCD деплоит

### 5. Push-based (GitLab Agent)

```bash
# 1. Получить токен агента из GitLab:
#    Project (gitops-config) → Infrastructure → Kubernetes clusters → Connect a cluster
#    Имя агента: minikube-agent

# 2. Установить агента
export GITLAB_AGENT_TOKEN='glagent-xxx...'
./scripts/setup-push-based.sh

# 3. Добавить конфиг агента в репо gitops-config:
mkdir -p .gitlab/agents/minikube-agent
cp infrastructure/gitlab-agent/config.yaml .gitlab/agents/minikube-agent/
git add . && git commit -m "Add agent config" && git push
```

---

## Структура проекта

```
gitops-config/                     # Этот репозиторий
├── README.md
├── .env.example                   # Шаблон конфигурации
├── .env                           # Конфигурация проекта (не в git)
├── .gitignore
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
│   │   │   ├── default.yaml
│   │   │   ├── dev.yaml
│   │   │   ├── staging.yaml
│   │   │   └── prod.yaml
│   │   ├── vault-secret.yaml
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

## Vault Secrets

### Структура путей

```
secret/data/${VAULT_PATH_PREFIX}/{service}/{env}/config
                    │                │       │
                    │                │       └── dev | staging | prod
                    │                └── api-gateway | auth-adapter | ...
                    └── Из .env (по умолчанию = GITLAB_GROUP)
```

### Создание секретов

```bash
# Port-forward к Vault
kubectl port-forward svc/vault -n vault 8200:8200 &

export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# Создать секреты (путь из .env)
vault kv put secret/${VAULT_PATH_PREFIX}/api-gateway/dev/config \
  API_KEY="dev-secret" \
  DB_PASSWORD="dev-password"
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
# Проверить наличие секрета в namespace (k8app использует "regsecret")
kubectl get secret regsecret -n api-gateway-dev

# Проверить конфигурацию секрета
kubectl get secret regsecret -n api-gateway-dev -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq

# Если секрета нет - создать
./scripts/setup-registry-secret.sh

# Проверить что imagePullSecrets указан в deployment
kubectl get deployment api-gateway -n api-gateway-dev -o yaml | grep -A5 imagePullSecrets

# Проверить события pod
kubectl describe pod -n api-gateway-dev -l app=api-gateway
```

**Частые причины:**
- Deploy Token истёк или отозван → создать новый
- Неверный scope токена → должен быть `read_registry`
- `deploySecretHarbor: false` в values → установить `true` в `.cicd/default.yaml`

---

## Ссылки

- [GitLab Agent CI/CD Workflow](https://docs.gitlab.com/user/clusters/agent/ci_cd_workflow/)
- [GitLab Container Registry](https://docs.gitlab.com/user/packages/container_registry/)
- [GitLab Deploy Tokens](https://docs.gitlab.com/user/project/deploy_tokens/)
- [ArgoCD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [ArgoCD Multi-Source Applications](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)
- [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso)
- [k8app Helm Chart](https://github.com/d7561985/k8app)
