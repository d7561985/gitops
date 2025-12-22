# Preview Environments Guide

Руководство по настройке preview environments для feature branches.

## Обзор

Preview environments позволяют автоматически деплоить frontend из feature branch для тестирования перед merge. Каждый Merge Request из ветки с JIRA тегом получает уникальный поддомен.

**Ключевые принципы:**
- **GitOps** — ArgoCD Pull Request Generator следит за MR в GitLab
- **Автоматизация** — создание/удаление при открытии/закрытии MR
- **Shared Namespace** — preview деплоится в существующий namespace (poc-dev)
- **Shared Backend** — frontend использует backend из dev environment

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            GitLab MR                                         │
│  Разработчик создаёт ветку PROJ-123-description, открывает MR               │
│  CI собирает image: frontend:{branch-name}                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                   ArgoCD Pull Request Generator                              │
│  ApplicationSet: preview-frontend                                            │
│  Проверяет GitLab API каждые 60 сек                                         │
│  Фильтр: branchMatch + state "opened"                                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ArgoCD Application                                    │
│  Name: preview-frontend-{jira-tag}                                           │
│  Namespace: poc-dev (shared namespace)                                       │
│  Sources:                                                                    │
│    - k8app chart (v3.8.0)                                                   │
│    - sentry-demo repo (branch: {branch})                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     poc-dev namespace (shared)                               │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ Deployment: sentry-frontend-proj-123 (unique name with JIRA suffix)     │ │
│  │   image: registry.../frontend:proj-123-description                      │ │
│  │   env:                                                                  │ │
│  │     API_URL: http://api-gateway-sv:8080                                 │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ HTTPRoute                                                               │ │
│  │   hostname: proj-123.demo-poc-01.work                                   │ │
│  │   parentRef: gateway/http-preview (poc-dev)                             │ │
│  │   backendRef: sentry-frontend-proj-123-sv:4200                          │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ Existing services: api-gateway-sv, game-engine-sv, etc.                 │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Формат домена

```
{jira-tag}.{baseDomain}
```

Из branch name извлекается только JIRA тег для короткого URL:

| Branch | JIRA Tag | URL |
|--------|----------|-----|
| `PROJ-123-new-login-feature` | `proj-123` | `proj-123.demo-poc-01.work` |
| `JIRA-456-fix-button-color` | `jira-456` | `jira-456.demo-poc-01.work` |
| `ABC-1-test` | `abc-1` | `abc-1.demo-poc-01.work` |

> **Note:** JIRA тег извлекается regex `^[A-Za-z]+-[0-9]+` и приводится к lowercase.
>
> **SSL:** CloudFlare Universal SSL покрывает `*.demo-poc-01.work` — Advanced Certificate не требуется!

### Требования к именам веток

Ветка должна начинаться с JIRA тега:
```
{PROJECT}-{NUMBER}-{description}
```

Примеры **валидных** веток:
- `PROJ-123-new-feature`
- `JIRA-456-fix-bug`
- `ABC-1-test`

Примеры **невалидных** веток (preview НЕ создастся):
- `feature/login` — нет JIRA тега
- `fix-typo` — нет JIRA тега
- `main` — нет JIRA тега

## Настройка

### Шаг 1: Получить GitLab Project ID

```bash
# GitLab → sentry-demo → Settings → General → Project ID
# Например: 12345678
```

### Шаг 2: Создать GitLab Access Token и сохранить в Vault

1. Перейти в GitLab → Settings → Access Tokens
2. Создать token:
   - Name: `argocd-preview`
   - Scopes: `read_api`
   - Expiration: выбрать срок

3. Сохранить токен в Vault:

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
> По умолчанию: `gitops-poc-dzha/argocd/gitlab-preview/dev`
>
> VSO автоматически синхронизирует токен в K8s secret (имя из `tokenRef.secretName`).
> Это происходит при sync platform-core.

### Шаг 3: Получить CloudFlare Zone ID

```bash
# CloudFlare Dashboard → demo-poc-01.work → Overview → Zone ID
# Или через API:
curl -s "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq '.result[] | {name, id}'
```

### Шаг 4: Обновить values.yaml

> **Note:** CloudFlare Universal SSL автоматически покрывает `*.demo-poc-01.work` — дополнительный сертификат не требуется!

```yaml
# gitops-config/platform/preview.yaml

previewEnvironments:
  enabled: true

  # Vault интеграция (токен синхронизируется автоматически)
  vault:
    enabled: true
    path: "gitops-poc-dzha/argocd/gitlab-preview/dev"  # Путь в Vault

  # Формат домена: {jira-tag}.baseDomain
  baseDomain: "demo-poc-01.work"
  zoneId: "your-cloudflare-zone-id"

  gitlab:
    api: "https://gitlab.com/"
    tokenRef:
      secretName: gitlab-preview-token  # Создаётся VSO из Vault
      key: token
    requeueAfterSeconds: 60

  # Shared namespace mode - все preview в одном namespace
  sharedNamespace: true

  services:
    frontend:
      enabled: true
      projectId: "12345678"  # GitLab Project ID
      branchMatch: "^[A-Z]+-[0-9]+-.*"  # JIRA tag pattern
      cicdPath: "frontend/.cicd"
      repoURL: "https://gitlab.com/gitops-poc-dzha/sentry-demo.git"
      namespace: "poc-dev"  # Deploy to existing namespace
      appNameBase: "sentry-frontend"  # Resources: sentry-frontend-{jira-tag}

  gateway:
    namespace: "poc-dev"
    gatewayClassName: cilium
    protocol: HTTP
    port: 80
```

### Шаг 5: Применить изменения

```bash
git add .
git commit -m "feat: enable preview environments for frontend"
git push

argocd app sync platform-core --grpc-web
```

## Использование

### Для разработчика

1. **Создать ветку** с JIRA тегом:
   ```bash
   git checkout -b PROJ-123-new-feature
   ```

2. **Сделать изменения** в `frontend/`

3. **Push и создать MR**:
   ```bash
   git push -u origin PROJ-123-new-feature
   ```

4. **Дождаться CI build**:
   - CI соберёт image с `commit-sha`
   - ArgoCD обнаружит MR (до 60 сек)

5. **Получить URL**:
   - URL: `proj-123.demo-poc-01.work` (только JIRA тег!)
   - Или посмотреть в ArgoCD UI

6. **Тестировать**:
   - Frontend доступен по preview URL
   - API запросы идут на dev backend

7. **Закрыть MR**:
   - При merge/close → Application удаляется
   - Namespace очищается автоматически

### Команды для отладки

```bash
# Список preview applications
kubectl get applications -n argocd | grep preview

# Статус конкретного preview
argocd app get preview-frontend-proj-123 --grpc-web

# Логи preview frontend
kubectl logs -f deployment/sentry-frontend -n preview-frontend-proj-123

# Принудительный sync
argocd app sync preview-frontend-proj-123 --grpc-web

# Удалить preview вручную
argocd app delete preview-frontend-proj-123 --grpc-web
```

## Монорепо: фильтрация по branch name

Для монорепозитория (sentry-demo содержит frontend, game-engine, payment, wager):

**Проблема:** Pull Request Generator работает на уровне репозитория, не path.

**Решение:** Фильтрация по имени ветки через `branchMatch`.

```yaml
# ApplicationSet фильтрует MR по regex
generators:
  - pullRequest:
      gitlab:
        branchMatch: "^[A-Z]+-[0-9]+-.*"  # Только ветки с JIRA тегом
```

**Результат:**
- Ветка `PROJ-123-new-feature` → preview создаётся
- Ветка `feature/login` → preview НЕ создаётся
- Ветка `fix-typo` → preview НЕ создаётся

> **Note:** Для backend изменений (game-engine, payment) preview тоже создастся если ветка имеет JIRA тег. Но это frontend-only preview — backend остаётся из dev.

## Что создаётся автоматически

При открытии MR с веткой `PROJ-123-description`:

| Ресурс | Name | Namespace |
|--------|------|-----------|
| ArgoCD Application | `preview-frontend-proj-123` | argocd |
| Deployment | `sentry-frontend-proj-123` | poc-dev |
| Service | `sentry-frontend-proj-123-sv` | poc-dev |
| HTTPRoute | автогенерируемый | poc-dev |

**Shared Namespace преимущества:**
- Секреты уже существуют (нет ручного управления)
- Нет sprawl namespaces
- Ресурсы различаются суффиксом JIRA-тега

**HTTPRoute маршрутизация:**

Preview HTTPRoute включает два правила:
```yaml
rules:
  # /api → shared backend (существующий api-gateway)
  - matches:
      - path: {type: PathPrefix, value: /api}
    backendRefs:
      - name: api-gateway-sv
        port: 8080
  # / → preview frontend (уникальный для JIRA тега)
  - matches:
      - path: {type: PathPrefix, value: /}
    backendRefs:
      - name: sentry-frontend-{jira-tag}-sv
        port: 4200
```

Это позволяет preview frontend использовать shared backend для API запросов.

При закрытии MR:
- ArgoCD Application удаляется
- Все ресурсы preview (Deployment, Service, HTTPRoute) удаляются
- Существующие сервисы не затрагиваются

## CI: Image Tagging по имени ветки

**Важно:** CI должен тегировать images именем ветки, а не commit SHA!

### Почему не SHA?

CI часто создаёт `[skip ci]` commits после сборки (например, version bump):

```
1. CI собирает image с SHA abc123
2. CI создаёт commit "[skip ci] bump version"
3. HEAD теперь def456
4. ArgoCD берёт def456 как image tag
5. ImagePullBackOff — image def456 не существует!
```

Branch name остаётся стабильным во время всего MR lifecycle.

### Настройка .gitlab-ci.yml

```yaml
build:
  stage: build
  script:
    # Build с SHA (для production deployments)
    - docker build -t $REGISTRY/$SERVICE:$CI_COMMIT_SHORT_SHA .
    - docker push $REGISTRY/$SERVICE:$CI_COMMIT_SHORT_SHA

    # Также тегировать именем ветки (для preview)
    - BRANCH_TAG=$(echo "$CI_COMMIT_REF_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
    - docker tag $REGISTRY/$SERVICE:$CI_COMMIT_SHORT_SHA $REGISTRY/$SERVICE:$BRANCH_TAG
    - docker push $REGISTRY/$SERVICE:$BRANCH_TAG
```

### ApplicationSet использует branch tag

```yaml
# В ApplicationSet template
image:
  tag: "{{.branch | replace "/" "-" | lower}}"
```

## Ограничения

| Ограничение | Причина | Workaround |
|-------------|---------|------------|
| Только frontend | Backend требует изоляции данных | Используйте staging для full-stack |
| Shared backend | Preview использует dev backend | Ожидаемое поведение для UI preview |
| DNS propagation | До 5 минут | Подождать или использовать curl с --resolve |
| Max 50 chars branch | DNS ограничение | Короткие имена веток |

## Troubleshooting

### Preview не создаётся

```bash
# Проверить что ApplicationSet существует
kubectl get applicationset preview-frontend -n argocd -o yaml

# Проверить логи ArgoCD applicationset-controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller

# Проверить GitLab API доступ (секрет должен быть синхронизирован из Vault)
kubectl get secret gitlab-preview-token -n argocd
```

### GitLab токен не синхронизируется из Vault

```bash
# Проверить VaultStaticSecret
kubectl get vaultstaticsecret gitlab-preview-token -n argocd -o yaml

# Проверить VaultAuth
kubectl get vaultauth vault-auth -n argocd -o yaml

# Проверить что токен есть в Vault
kubectl port-forward svc/vault -n vault 8200:8200 &
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN=$(kubectl get secret vault-keys -n vault \
  -o jsonpath='{.data.root-token}' | base64 -d)
vault kv get secret/gitops-poc-dzha/argocd/gitlab-preview

# Проверить логи VSO
kubectl logs -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator
```

### SSL ошибка (ERR_SSL_VERSION_OR_CIPHER_MISMATCH)

CloudFlare Universal SSL покрывает только первый уровень wildcard:

| Паттерн | Покрывается Universal SSL |
|---------|---------------------------|
| `*.demo-poc-01.work` | ✅ Да |
| `*.preview.demo-poc-01.work` | ❌ Нет |

**Решение:** Используйте формат `{jira-tag}.demo-poc-01.work` (без `.preview.`).

> **Note:** Advanced Certificate ($10/month) НЕ требуется при правильном формате домена!

### 404 на preview URL

```bash
# Проверить HTTPRoute
kubectl get httproute -n poc-dev | grep proj-123

# Проверить что Gateway listener существует
kubectl get gateway gateway -n poc-dev -o yaml | grep http-preview

# Проверить что hostname в listener правильный (wildcard)
kubectl get gateway gateway -n poc-dev -o jsonpath='{.spec.listeners[?(@.name=="http-preview")].hostname}'
# Должно быть: *.demo-poc-01.work

# Проверить cloudflared config
kubectl get cm cloudflared-config -n cloudflare -o yaml | grep preview
```

### Gateway validation error (prefix-*.domain)

Gateway API не поддерживает prefix-wildcard паттерны:

```
# ❌ Невалидно
hostname: "preview-*.demo-poc-01.work"

# ✅ Валидно
hostname: "*.demo-poc-01.work"
```

**Решение:** Gateway использует стандартный wildcard `*.baseDomain`, HTTPRoute указывает точный hostname.

### ImagePullBackOff

```bash
# Какой tag ожидается?
kubectl get deployment -n poc-dev sentry-frontend-proj-123 \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Проверить что image с branch tag существует в registry
# (команда зависит от вашего registry)
```

**Частая причина:** CI тегирует по SHA, но после сборки создаётся `[skip ci]` commit.

**Решение:** Тегировать images именем ветки (см. раздел "CI: Image Tagging").

### Preview не удаляется после merge

```bash
# Проверить что MR закрыт в GitLab
# ArgoCD проверяет каждые requeueAfterSeconds (60 сек)

# Принудительно удалить
argocd app delete preview-frontend-{jira-tag} --grpc-web --cascade
```

## Конфигурация webhook (опционально)

Для мгновенного реагирования на MR events вместо polling:

1. GitLab → Settings → Webhooks
2. URL: `https://argocd.your-domain.com/api/webhook`
3. Secret Token: (опционально)
4. Trigger: Merge request events
5. SSL verification: Enable

```bash
# Проверить что ArgoCD принимает webhooks
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server | grep webhook
```

## Стоимость

| Компонент | Стоимость |
|-----------|-----------|
| CloudFlare Universal SSL | $0 (включён) |
| GitLab (Free tier) | $0 |
| Kubernetes resources | Minimal (1 pod per preview) |

> **Note:** Advanced Certificate НЕ требуется при использовании формата `{jira-tag}.baseDomain`!

## См. также

- [new-service-guide.md](./new-service-guide.md) — создание нового сервиса
- [gitlab-ci-release-tracking.md](./gitlab-ci-release-tracking.md) — отслеживание релизов
- [domain-mirrors-guide.md](./domain-mirrors-guide.md) — зеркала доменов
- [service-groups-guide.md](./service-groups-guide.md) — инфраструктурные домены
- [ArgoCD Pull Request Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Pull-Request/) — официальная документация
