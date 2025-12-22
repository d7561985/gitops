# Multi-Brand Repository Migration

## Новая структура

```
GitLab (gitops-poc-dzha/):
├── services/                    # Shared codebase (all brands)
│   ├── sentry-demo/
│   ├── user-service/
│   ├── api-gateway/
│   ├── auth-adapter/
│   ├── health-demo/
│   ├── web-grpc/
│   └── web-http/
├── api/                         # Shared contracts (если нужно)
│   └── proto/
├── shared/                      # Shared tooling (all brands)
│   ├── infrastructure/          # Cluster setup scripts, Helm values
│   └── templates/               # Chart templates, boilerplates
└── infra/                       # Per-brand infrastructure
    └── poc/
        └── gitops-config/       # Brand "poc" ArgoCD config

Local (gitops/):
├── services/                    # Mirrors GitLab services/
├── api/                         # Mirrors GitLab api/
├── shared/
│   ├── infrastructure/          # Mirrors GitLab shared/infrastructure
│   └── templates/               # Mirrors GitLab shared/templates
├── infra/
│   └── poc/
│       └── gitops-config/       # Mirrors GitLab infra/poc/gitops-config
└── docs/
```

## Шаги миграции в GitLab

### 1. Создать subgroups

```bash
# GitLab → gitops-poc-dzha → Settings → General → Subgroups

# Создать:
# - gitops-poc-dzha/services
# - gitops-poc-dzha/shared
# - gitops-poc-dzha/infra
# - gitops-poc-dzha/infra/poc
```

### 2. Переместить репозитории

**Все сервисы → `gitops-poc-dzha/services/`:**

| Repo | Действие |
|------|----------|
| `sentry-demo` | Transfer to `gitops-poc-dzha/services` |
| `user-service` | Transfer to `gitops-poc-dzha/services` |
| `api-gateway` | Transfer to `gitops-poc-dzha/services` |
| `auth-adapter` | Transfer to `gitops-poc-dzha/services` |
| `health-demo` | Transfer to `gitops-poc-dzha/services` |
| `web-grpc` | Transfer to `gitops-poc-dzha/services` |
| `web-http` | Transfer to `gitops-poc-dzha/services` |

**Shared tooling → `gitops-poc-dzha/shared/`:**

| Repo | Действие |
|------|----------|
| `infrastructure` | Transfer to `gitops-poc-dzha/shared` |
| `templates` | Transfer to `gitops-poc-dzha/shared` |

**Infrastructure → `gitops-poc-dzha/infra/poc/`:**

| Repo | Действие |
|------|----------|
| `gitops-config` | Transfer to `gitops-poc-dzha/infra/poc` |

**Через GitLab UI:**
Project → Settings → General → Advanced → Transfer project

**Или через API:**
```bash
# Transfer project to subgroup
curl -X PUT "https://gitlab.com/api/v4/projects/PROJECT_ID/transfer" \
  -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  -d "namespace=gitops-poc-dzha/services"
```

### 3. Обновить git remotes локально

```bash
# gitops-config
cd infra/poc/gitops-config
git remote set-url origin git@gitlab.com:gitops-poc-dzha/infra/poc/gitops-config.git

# Сервисы
for svc in sentry-demo user-service api-gateway auth-adapter health-demo web-grpc web-http; do
  cd services/$svc 2>/dev/null && \
  git remote set-url origin git@gitlab.com:gitops-poc-dzha/services/$svc.git && \
  echo "Updated $svc" && cd ../..
done

# Shared
cd shared/infrastructure && \
  git remote set-url origin git@gitlab.com:gitops-poc-dzha/shared/infrastructure.git && \
  echo "Updated infrastructure" && cd ../..

cd shared/templates && \
  git remote set-url origin git@gitlab.com:gitops-poc-dzha/shared/templates.git && \
  echo "Updated templates" && cd ../..
```

### 4. Push изменений

```bash
cd infra/poc/gitops-config
git add -A
git commit -m "refactor: update repoURLs for multi-brand structure"
git push origin main
```

### 5. Применить bootstrap

После переноса репозиториев в GitLab:

```bash
kubectl apply -f infra/poc/gitops-config/argocd/bootstrap-app.yaml
```

## Изменённые файлы

| Файл | Изменение |
|------|-----------|
| `platform/base.yaml` | `gitlabGroup: gitops-poc-dzha/services` |
| `platform/core.yaml` | repoURLs с `/services/` prefix |
| `platform/preview.yaml` | repoURL с `/services/` prefix |
| `argocd/bootstrap-app.yaml` | repoURL: `/infra/poc/gitops-config` |
| `argocd/platform-modules.yaml` | repoURL: `/infra/poc/gitops-config` |
| `argocd/infra-app.yaml` | repoURL: `/infra/poc/gitops-config` |

## Добавление нового бренда

1. **Скопировать gitops-config:**
   ```bash
   cp -r infra/poc/gitops-config infra/brand-b/gitops-config
   ```

2. **Обновить values для brand-b:**
   ```yaml
   # platform/base.yaml
   global:
     brand: brand-b
     namespacePrefix: brand-b

   environments:
     dev:
       domain: "app.brand-b.com"
   ```

3. **Создать GitLab repo:**
   - `gitops-poc-dzha/infra/brand-b/gitops-config`

4. **Применить в кластере brand-b:**
   ```bash
   kubectl apply -f infra/brand-b/gitops-config/argocd/bootstrap-app.yaml
   ```

## Rollback

Если что-то пошло не так:

1. В GitLab: Transfer repos обратно в root group
2. Локально: `git remote set-url origin` на старые URL
3. Revert changes в gitops-config
