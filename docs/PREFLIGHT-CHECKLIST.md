# Pre-flight Checklist

Чеклист для полного развертывания системы с нуля.

> **Планирование ресурсов:** Перед началом ознакомьтесь с [capacity-planning.md](./capacity-planning.md) для оценки требований к кластеру.

## Этап 1: Внешние сервисы (ручная настройка)

### GitLab

- [ ] **Создать группу** в GitLab
  - URL: `https://gitlab.com/groups/new`
  - Имя: значение `GITLAB_GROUP` из `.env`

- [ ] **Создать subgroups и репозитории:**
  - [ ] `services/` — subgroup для сервисов
    - [ ] `api-gateway` — Envoy proxy
    - [ ] `auth-adapter` — gRPC auth service
    - [ ] `web-grpc` — gRPC backend
    - [ ] `web-http` — HTTP backend
    - [ ] `health-demo` — Health check service
  - [ ] `shared/` — subgroup для shared tooling
    - [ ] `infrastructure` — setup scripts
    - [ ] `templates` — CI templates
  - [ ] `infra/poc/` — subgroup для brand config
    - [ ] `gitops-config` — ArgoCD config

- [ ] **Создать Personal Access Token** (для CI push)
  - URL: `https://gitlab.com/-/user_settings/personal_access_tokens`
  - Name: `ci-push-gitops`
  - Scopes: `read_repository`, `write_repository`
  - Сохранить в `.env` как `GITLAB_TOKEN`

- [ ] **Создать Deploy Token** (для registry pull)
  - URL: `https://gitlab.com/${GITLAB_GROUP}/-/settings/repository`
  - Name: `kubernetes-pull`
  - Scopes: `read_registry`
  - Сохранить в `.env`:
    - `GITLAB_DEPLOY_TOKEN_USER`
    - `GITLAB_DEPLOY_TOKEN`

- [ ] **Добавить CI/CD Variables** (на уровне группы)
  - URL: `https://gitlab.com/groups/${GITLAB_GROUP}/-/settings/ci_cd`
  - Variables:
    - `CI_PUSH_TOKEN` = Personal Access Token
    - `ARGOCD_SERVER` = `argocd.your-domain.com` (позже)
    - `ARGOCD_AUTH_TOKEN` = (позже, после создания)

### CloudFlare

- [ ] **Создать API Token** для external-dns и cert-manager
  - URL: `https://dash.cloudflare.com/profile/api-tokens`
  - Template: "Custom token"
  - Permissions:
    - `Zone:Zone:Read` (все зоны или конкретные)
    - `Zone:DNS:Edit` (все зоны или конкретные)
    - `Account:Cloudflare Tunnel:Edit` (если используете tunnel)
  - Сохранить в `.env` как `CLOUDFLARE_API_TOKEN`

- [ ] **Создать Tunnel** (для locally-managed mode)
  - Вариант A: Через CLI (рекомендуется)
    ```bash
    cloudflared tunnel login
    cloudflared tunnel create gitops-poc
    # Сохранить credentials: ~/.cloudflared/<tunnel-id>.json
    ```
  - Вариант B: Через Dashboard
    - URL: `https://one.dash.cloudflare.com/`
    - Networks → Tunnels → Create tunnel
  - Сохранить Tunnel ID в `.env` как `CLOUDFLARE_TUNNEL_ID`

- [ ] **Получить Zone ID** для каждого домена с зеркалами
  - URL: `https://dash.cloudflare.com/` → выбрать домен → Overview (справа)
  - Или: `cloudflare zone list` (если установлен cloudflare-cli)

### External-DNS (автоматическое управление DNS)

- [ ] **Установить external-dns**
  ```bash
  # Токен загружается автоматически из .env
  ./shared/infrastructure/external-dns/setup.sh
  ```

- [ ] **Проверить работу**
  ```bash
  kubectl logs -f deployment/external-dns -n external-dns
  ```

### CloudFlare Tunnel (locally-managed)

**Вариант A: Новая установка (с нуля)**
```bash
# Создаёт tunnel, credentials secret, деплоит cloudflared
./shared/infrastructure/cloudflare-tunnel/setup.sh

# Скрипт выведет tunnelId — добавьте в values.yaml
```

**Вариант B: Миграция с remotely-managed**
```bash
# Если уже есть tunnel с настройками в Dashboard
./shared/infrastructure/cloudflare-tunnel/migrate-to-locally-managed.sh
```

- [ ] **Добавить Tunnel ID в values.yaml**
  ```yaml
  ingress:
    cloudflare:
      tunnelId: "your-tunnel-uuid"  # скрипт покажет это значение
  ```

---

## Этап 2: Локальная конфигурация

```bash
# Скопировать и заполнить конфигурацию
cp .env.example .env
vim .env

# Инициализировать проект (подставит значения в файлы)
./shared/scripts/init-project.sh
```

### Обязательные переменные в `.env`

| Переменная | Описание | Пример |
|------------|----------|--------|
| `GITLAB_GROUP` | Группа GitLab | `gitops-poc-dzha` |
| `GITLAB_HOST` | Хост GitLab | `gitlab.com` |
| `GITLAB_TOKEN` | PAT для ArgoCD | `glpat-xxx` |
| `GITLAB_DEPLOY_TOKEN_USER` | Deploy token username | `gitlab+deploy-token-123` |
| `GITLAB_DEPLOY_TOKEN` | Deploy token | `gldt-xxx` |

---

## Этап 3: Инфраструктура

```bash
# Запустить всю инфраструктуру
./shared/scripts/setup-infrastructure.sh
```

Скрипт установит:
- Minikube с Cilium CNI
- Gateway API CRDs
- cert-manager
- Vault + VSO (standalone mode с persistence)
- ArgoCD

### После установки Vault

**ВАЖНО:** Сохранить Vault credentials!

```bash
# Ключи сохраняются автоматически в:
# 1. K8s secret: kubectl get secret vault-keys -n vault
# 2. Файл: shared/infrastructure/vault/.vault-keys (в .gitignore)

# При рестарте кластера выполнить:
./shared/infrastructure/vault/unseal.sh
```

### Получить ArgoCD пароль

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

---

## Этап 4: GitOps настройка

### Pull-based (ArgoCD)

```bash
./shared/scripts/setup-pull-based.sh
```

### Настроить Release Tracking (CI → ArgoCD)

1. Создать ArgoCD account:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
argocd login localhost:8080 --insecure

# Создать account
kubectl patch configmap argocd-cm -n argocd --type merge -p '
{"data":{"accounts.ci-readonly":"apiKey"}}'

kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '
{"data":{"policy.csv":"g, ci-readonly, role:readonly"}}'

# Сгенерировать токен
argocd account generate-token --account ci-readonly
```

2. Добавить в GitLab CI/CD Variables:
   - `ARGOCD_SERVER` = `argocd.your-domain.com`
   - `ARGOCD_AUTH_TOKEN` = токен из предыдущего шага

---

## Этап 5: Registry Credentials в Vault

> **Важно:** Registry credentials теперь управляются через Vault + VSO.
> Secret `regsecret` автоматически синхронизируется во все namespace через VaultStaticSecret.

```bash
# Подключиться к Vault
kubectl port-forward svc/vault -n vault 8200:8200 &
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.root-token}' | base64 -d)

# Сохранить registry credentials в Vault
# Формат: dockerconfigjson для kubernetes.io/dockerconfigjson secret
REGISTRY="registry.gitlab.com"
USERNAME="gitlab+deploy-token-xxxxx"  # Из GitLab Deploy Token
PASSWORD="gldt-xxxxxxxxxxxx"          # Из GitLab Deploy Token

# Создать .dockerconfigjson и сохранить в Vault
vault kv put secret/gitops-poc-dzha/platform/registry \
  .dockerconfigjson="{\"auths\":{\"${REGISTRY}\":{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\",\"auth\":\"$(echo -n ${USERNAME}:${PASSWORD} | base64)\"}}}"
```

После сохранения в Vault, platform-core создаст VaultStaticSecret который автоматически:
- Синхронизирует `regsecret` в каждый namespace (`poc-dev`, `poc-staging`, etc.)
- Переживает удаление namespace (пересоздаётся при ресинхронизации)
- Обновляет credentials при изменении в Vault

---

## Этап 6: Запуск GitOps

```bash
# Запушить gitops-config в GitLab
cd infra/poc/gitops-config
git init
git remote add origin git@gitlab.com:${GITLAB_GROUP}/infra/poc/gitops-config.git
git add .
git commit -m "Initial commit"
git push -u origin main

# Применить bootstrap (ArgoCD создаст все Applications)
kubectl apply -f infra/poc/gitops-config/argocd/project.yaml
kubectl apply -f infra/poc/gitops-config/argocd/bootstrap-app.yaml
```

---

## Этап 7: Проверка

```bash
# Статус ArgoCD applications
kubectl get applications -n argocd

# Проверить что regsecret создался во всех namespace
kubectl get secret regsecret -n poc-dev
kubectl get secret regsecret -n poc-staging

# Статус pods
kubectl get pods -n poc-dev

# Доступ к UI
make proxy-all  # или make proxy-argocd
```

---

## Disaster Recovery

### Кластер перезапустился

1. **Unseal Vault:**
   ```bash
   ./shared/infrastructure/vault/unseal.sh
   ```

2. **Проверить ArgoCD:**
   ```bash
   kubectl get applications -n argocd
   argocd app sync platform-core --grpc-web
   ```

### Потеряны Vault ключи

Если ключи утеряны и Vault sealed:
```bash
# Удалить PVC и переинициализировать
helm uninstall vault -n vault
kubectl delete pvc data-vault-0 -n vault
./shared/infrastructure/vault/setup.sh

# Пересинхронизировать platform-core
argocd app sync platform-core --grpc-web
```

### Secrets в Vault

Все секреты создаются как placeholders при первом sync. Реальные значения нужно добавить:
```bash
kubectl port-forward svc/vault -n vault 8200:8200 &
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.root-token}' | base64 -d)

vault kv put secret/${GITLAB_GROUP}/api-gateway/dev/config \
  API_KEY="real-value" \
  DB_PASSWORD="real-password"
```

---

## Добавление Domain Mirrors

### Быстрый старт

1. **Получить Zone ID** для домена зеркала:
   ```bash
   curl -X GET "https://api.cloudflare.com/client/v4/zones" \
     -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq '.result[] | {name, id}'
   ```

2. **Добавить зеркало** в `values.yaml`:
   ```yaml
   environments:
     dev:
       mirrors:
         - domain: "mirror.example.com"
           zoneId: "your-zone-id"
   ```

3. **Commit и sync**:
   ```bash
   git add . && git commit -m "feat: add mirror domain"
   git push
   argocd app sync platform-core --grpc-web
   ```

4. **Проверить**:
   ```bash
   kubectl get httproutes -n poc-dev | grep mirror
   kubectl logs deployment/external-dns -n external-dns | grep mirror
   curl -I https://mirror.example.com
   ```

### Критерии успеха

- [ ] Gateway listener `http-mirror-N` создан
- [ ] HTTPRoute `mirror-N-api` и `mirror-N-frontend` созданы
- [ ] DNS запись появилась в CloudFlare
- [ ] `curl https://mirror.domain.com` возвращает 200

Подробнее: [domain-mirrors-guide.md](./domain-mirrors-guide.md)

---

## Preview Environments (Feature Branches)

Автоматический деплой frontend из feature branch для тестирования.

### Шаг 1: GitLab Access Token → Vault

- [ ] **Создать Access Token** в GitLab
  - URL: `https://gitlab.com/-/user_settings/personal_access_tokens`
  - Scopes: `read_api`

- [ ] **Сохранить токен в Vault**
  ```bash
  # Подключиться к Vault
  kubectl port-forward svc/vault -n vault 8200:8200 &
  export VAULT_ADDR='http://127.0.0.1:8200'
  export VAULT_TOKEN=$(kubectl get secret vault-keys -n vault \
    -o jsonpath='{.data.root-token}' | base64 -d)

  # Сохранить токен (путь должен совпадать с previewEnvironments.vault.path)
  vault kv put secret/gitops-poc-dzha/argocd/gitlab-preview/dev \
    token="glpat-xxxxxxxxxxxxx"
  ```

  > **Vault path:** настраивается в `previewEnvironments.vault.path`
  >
  > VSO автоматически синхронизирует в K8s secret `gitlab-preview-token` в namespace `argocd`

### Шаг 2: CloudFlare Advanced Certificate

- [ ] **Заказать Advanced Certificate**
  - URL: CloudFlare Dashboard → SSL/TLS → Edge Certificates
  - Hostnames:
    - `*.preview.demo-poc-01.work`
  - Стоимость: $10/month

- [ ] **Дождаться активации** (5-15 минут)

### Шаг 3: Получить GitLab Project ID

- [ ] **Найти Project ID**
  - GitLab → sentry-demo → Settings → General → Project ID
  - Записать: `_____________`

### Шаг 4: Обновить values.yaml

```yaml
previewEnvironments:
  enabled: true
  baseDomain: "preview.demo-poc-01.work"
  zoneId: "your-zone-id"

  services:
    frontend:
      enabled: true
      projectId: "your-project-id"
```

### Шаг 5: Применить и проверить

```bash
git add . && git commit -m "feat: enable preview environments"
git push
argocd app sync platform-core --grpc-web

# Проверить ApplicationSet
kubectl get applicationset preview-frontend -n argocd
```

### Критерии успеха

- [ ] ApplicationSet `preview-frontend` создан
- [ ] Gateway listener `http-preview` добавлен
- [ ] При создании MR с веткой `PROJ-123-...` → Application появляется
- [ ] URL `proj-123.preview.demo-poc-01.work` доступен

> **Важно:** Ветка должна начинаться с JIRA тега: `PROJ-123-description`

Подробнее: [preview-environments-guide.md](./preview-environments-guide.md)
