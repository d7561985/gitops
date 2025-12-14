# Pre-flight Checklist

Чеклист для полного развертывания системы с нуля.

## Этап 1: Внешние сервисы (ручная настройка)

### GitLab

- [ ] **Создать группу** в GitLab
  - URL: `https://gitlab.com/groups/new`
  - Имя: значение `GITLAB_GROUP` из `.env`

- [ ] **Создать репозитории** в группе:
  - [ ] `gitops-config` — инфраструктура и ArgoCD
  - [ ] `api-gateway` — Envoy proxy
  - [ ] `auth-adapter` — gRPC auth service
  - [ ] `web-grpc` — gRPC backend
  - [ ] `web-http` — HTTP backend
  - [ ] `health-demo` — Health check service

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

### CloudFlare (опционально)

- [ ] **Создать API Token** для cert-manager
  - URL: `https://dash.cloudflare.com/profile/api-tokens`
  - Template: "Edit zone DNS"
  - Permissions: Zone/DNS/Edit, Zone/Zone/Read
  - Сохранить в `.env` как `CLOUDFLARE_API_TOKEN`

- [ ] **Создать Tunnel** для локального доступа
  - URL: `https://one.dash.cloudflare.com/`
  - Networks → Tunnels → Create tunnel
  - Connector: Cloudflared
  - Скопировать token (начинается с `eyJ...`)
  - Сохранить в `.env` как `CLOUDFLARE_TUNNEL_TOKEN`

- [ ] **Настроить Public Hostnames** в Tunnel
  - `app.your-domain.com` → `http://cilium-gateway-gateway.poc-dev.svc:80`
  - `argocd.your-domain.com` → `http://argocd-server.argocd.svc:80`

---

## Этап 2: Локальная конфигурация

```bash
# Скопировать и заполнить конфигурацию
cp .env.example .env
vim .env

# Инициализировать проект (подставит значения в файлы)
./scripts/init-project.sh
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
./scripts/setup-infrastructure.sh
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
# 2. Файл: infrastructure/vault/.vault-keys (в .gitignore)

# При рестарте кластера выполнить:
./infrastructure/vault/unseal.sh
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
./scripts/setup-pull-based.sh
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

## Этап 5: Запуск сервисов

```bash
# Registry secrets для GitLab Container Registry
./scripts/setup-registry-secret.sh

# Запушить gitops-config в GitLab
cd gitops-config
git init
git remote add origin git@gitlab.com:${GITLAB_GROUP}/gitops-config.git
git add .
git commit -m "Initial commit"
git push -u origin main

# Применить bootstrap (ArgoCD создаст все Applications)
kubectl apply -f gitops-config/argocd/project.yaml
kubectl apply -f gitops-config/argocd/bootstrap-app.yaml
```

---

## Этап 6: Проверка

```bash
# Статус ArgoCD applications
kubectl get applications -n argocd

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
   ./infrastructure/vault/unseal.sh
   ```

2. **Проверить ArgoCD:**
   ```bash
   kubectl get applications -n argocd
   argocd app sync platform-bootstrap --grpc-web
   ```

### Потеряны Vault ключи

Если ключи утеряны и Vault sealed:
```bash
# Удалить PVC и переинициализировать
helm uninstall vault -n vault
kubectl delete pvc data-vault-0 -n vault
./infrastructure/vault/setup.sh

# Пересинхронизировать platform-bootstrap
argocd app sync platform-bootstrap --grpc-web
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
