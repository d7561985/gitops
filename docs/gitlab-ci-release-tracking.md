# GitLab CI + ArgoCD Release Tracking

Руководство по отслеживанию релизов в GitLab CI с ArgoCD. Разработчики видят статус деплоя прямо в pipeline.

## Содержание

- [Обзор](#обзор)
- [Архитектура](#архитектура)
- [Настройка](#настройка)
  - [1. Создание ArgoCD Service Account](#1-создание-argocd-service-account)
  - [2. Генерация API Token](#2-генерация-api-token)
  - [3. Настройка GitLab CI/CD Variables](#3-настройка-gitlab-cicd-variables)
  - [4. Настройка ArgoCD Network Access](#4-настройка-argocd-network-access)
- [Конфигурация CI/CD](#конфигурация-cicd)
  - [Release Template](#release-template)
  - [Release Jobs](#release-jobs)
- [Что видит разработчик](#что-видит-разработчик)
- [Troubleshooting](#troubleshooting)
- [Альтернативные подходы](#альтернативные-подходы)
- [Ссылки](#ссылки)

---

## Обзор

После push кода разработчик хочет знать:
1. Собрался ли Docker образ?
2. Задеплоился ли сервис в кластер?
3. Здоров ли сервис после деплоя?

**Решение:** добавить `release` stage в GitLab CI, который использует `argocd app wait` для ожидания успешного деплоя.

### Преимущества

| Аспект | Описание |
|--------|----------|
| **Visibility** | Статус деплоя виден прямо в GitLab pipeline |
| **Fail-fast** | Pipeline падает если деплой не удался |
| **Error details** | При ошибке показываются детали из ArgoCD |
| **Merge blocking** | Можно блокировать merge до успешного деплоя |

---

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         GitLab CI Pipeline                              │
│                                                                         │
│   Stage: build                         Stage: release                   │
│   ┌──────────────────┐                ┌──────────────────────────┐     │
│   │ 1. Build image   │                │ 4. Wait for ArgoCD sync  │     │
│   │ 2. Push to       │───────────────▶│    argocd app wait       │     │
│   │    registry      │                │    --health --sync       │     │
│   │ 3. Update        │                │    --timeout 300         │     │
│   │    dev.yaml      │                └────────────┬─────────────┘     │
│   └──────────────────┘                             │                   │
│                                                    │                   │
│                                           ┌───────┴───────┐            │
│                                           ▼               ▼            │
│                                    ✅ Success      ❌ Failed           │
│                                    (green job)     (red job +          │
│                                                     error logs)        │
└─────────────────────────────────────────────────────────────────────────┘
                                          │
                                          │ API calls
                                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            ArgoCD Server                                │
│                                                                         │
│   ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐  │
│   │ sentry-frontend │     │ sentry-game-    │     │ sentry-payment  │  │
│   │     -dev        │     │   engine-dev    │     │     -dev        │  │
│   │                 │     │                 │     │                 │  │
│   │ Health: Healthy │     │ Health: Healthy │     │ Health: Degraded│  │
│   │ Sync: Synced    │     │ Sync: Synced    │     │ Sync: OutOfSync │  │
│   └─────────────────┘     └─────────────────┘     └─────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Настройка

### 1. Создание ArgoCD Service Account

Создайте отдельный account для CI с минимальными правами:

```bash
# Подключиться к ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8081:443 &
argocd login localhost:8081 --insecure --username admin --password $(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)

# Создать CI account
argocd account create ci-readonly

# Или через ConfigMap (рекомендуется для GitOps)
kubectl patch configmap argocd-cm -n argocd --type merge -p '
data:
  accounts.ci-readonly: apiKey,login
  accounts.ci-readonly.enabled: "true"
'

# Назначить права только на чтение
kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '
data:
  policy.csv: |
    p, role:ci-readonly, applications, get, */*, allow
    p, role:ci-readonly, applications, sync, */*, allow
    p, role:ci-readonly, projects, get, *, allow
    g, ci-readonly, role:ci-readonly
'

# Важно: права на projects необходимы для работы команды argocd app wait
```

### 2. Генерация API Token

```bash
# Сгенерировать token для CI account
argocd account generate-token --account ci-readonly

# Вывод: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Или через UI:**
1. ArgoCD → Settings → Accounts
2. Выбрать `ci-readonly`
3. Generate New Token
4. Скопировать token

### 3. Настройка GitLab CI/CD Variables

Перейти в GitLab Group → Settings → CI/CD → Variables:

| Variable | Value | Protected | Masked |
|----------|-------|-----------|--------|
| `ARGOCD_SERVER` | `argocd.your-domain.com` | ✅ | ❌ |
| `ARGOCD_AUTH_TOKEN` | `eyJhbG...` (JWT token) | ✅ | ✅ |

> **Note:** Если ArgoCD доступен только внутри кластера, используйте GitLab Runner в том же кластере или настройте ingress.

### 4. Настройка ArgoCD Network Access

#### Вариант A: ArgoCD Ingress (рекомендуется для production)

```yaml
# argocd-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
    - host: argocd.your-domain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 443
  tls:
    - hosts:
        - argocd.your-domain.com
      secretName: argocd-tls
```

#### Вариант B: GitLab Runner в кластере

Если Runner запущен в том же кластере, можно использовать internal service:

```yaml
variables:
  ARGOCD_SERVER: "argocd-server.argocd.svc.cluster.local"
  ARGOCD_OPTS: "--grpc-web --plaintext"
```

#### Вариант C: CloudFlare Tunnel

Для локальной разработки с minikube:

```bash
# Добавить ArgoCD в tunnel public hostnames
# argocd.your-domain.com → http://argocd-server.argocd.svc:80
```

---

## Конфигурация CI/CD

### Release Template

Добавьте в начало `.gitlab-ci.yml`:

```yaml
stages:
  - build
  - release

variables:
  ARGOCD_OPTS: "--grpc-web"
  RELEASE_TIMEOUT: "300"  # 5 minutes

# =============================================================================
# Release Template - Waits for ArgoCD deployment
# =============================================================================
.release-template:
  stage: release
  image: alpine:3.19
  variables:
    ARGOCD_VERSION: "v2.13.2"  # Pin to specific version
  before_script:
    - apk add --no-cache curl
    - curl -sSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
    - chmod +x /usr/local/bin/argocd
  script:
    - echo "Waiting for ${ARGOCD_APP_NAME} to sync and become healthy..."
    - echo "ArgoCD Server: ${ARGOCD_SERVER}"
    - echo "Timeout: ${RELEASE_TIMEOUT}s"
    - |
      if argocd app wait ${ARGOCD_APP_NAME} \
        --timeout ${RELEASE_TIMEOUT} \
        --health \
        --sync \
        ${ARGOCD_OPTS}; then
        echo ""
        echo "============================================="
        echo "RELEASE SUCCESSFUL"
        echo "============================================="
        echo "Application: ${ARGOCD_APP_NAME}"
        echo "Image Tag:   ${CI_COMMIT_SHORT_SHA}"
        echo "============================================="
        argocd app get ${ARGOCD_APP_NAME} ${ARGOCD_OPTS} || true
      else
        EXIT_CODE=$?
        echo ""
        echo "============================================="
        echo "RELEASE FAILED"
        echo "============================================="
        echo "Application: ${ARGOCD_APP_NAME}"
        echo "============================================="
        echo ""
        echo "Application Status:"
        argocd app get ${ARGOCD_APP_NAME} ${ARGOCD_OPTS} || true
        echo ""
        echo "Recent Events:"
        argocd app resources ${ARGOCD_APP_NAME} ${ARGOCD_OPTS} || true
        exit $EXIT_CODE
      fi
  environment:
    name: dev
    action: start
  rules:
    - when: on_success
```

### Release Jobs

Для каждого сервиса создайте release job:

```yaml
release:frontend:
  extends: .release-template
  variables:
    ARGOCD_APP_NAME: sentry-frontend-dev
  needs:
    - job: build:frontend
      optional: true
  rules:
    - if: $CI_COMMIT_TAG
      when: never
    - changes:
        - frontend/**/*

release:game-engine:
  extends: .release-template
  variables:
    ARGOCD_APP_NAME: sentry-game-engine-dev
  needs:
    - job: build:game-engine
      optional: true
  rules:
    - changes:
        - game-engine/**/*

release:payment-service:
  extends: .release-template
  variables:
    ARGOCD_APP_NAME: sentry-payment-dev
  needs:
    - job: build:payment-service
      optional: true
  rules:
    - changes:
        - payment-service/**/*
```

---

## Что видит разработчик

### При успешном релизе

```
$ argocd app wait sentry-frontend-dev --timeout 300 --health --sync --grpc-web

Name:               argocd/sentry-frontend-dev
Project:            gitops-poc-dzha
Server:             https://kubernetes.default.svc
Namespace:          poc-dev
URL:                https://argocd.example.com/applications/sentry-frontend-dev
Repo:               https://gitlab.com/gitops-poc-dzha/sentry-demo.git
Target:             main
Path:               frontend/.cicd
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        Synced to main (abc1234)
Health Status:      Healthy

=============================================
RELEASE SUCCESSFUL
=============================================
Application: sentry-frontend-dev
Image Tag:   abc1234
=============================================
```

### При неудачном релизе

```
$ argocd app wait sentry-payment-dev --timeout 300 --health --sync --grpc-web

FATA[0045] timed out waiting for app sentry-payment-dev

=============================================
RELEASE FAILED
=============================================
Application: sentry-payment-dev
=============================================

Application Status:
Name:               argocd/sentry-payment-dev
Health Status:      Degraded
Sync Status:        OutOfSync

GROUP  KIND        NAMESPACE  NAME            STATUS  HEALTH   HOOK  MESSAGE
       Service     poc-dev    sentry-payment  Synced  Healthy
apps   Deployment  poc-dev    sentry-payment  Synced  Degraded

Recent Events:
NAMESPACE  NAME                               READY  STATUS              AGE
poc-dev    pod/sentry-payment-6d4f8b9-x2k4j  0/1    CrashLoopBackOff    2m

ERROR: Job failed
```

---

## Troubleshooting

### argocd CLI не может подключиться

```bash
# Проверить доступность сервера
curl -k https://${ARGOCD_SERVER}/api/version

# Проверить token
argocd account get-user-info --grpc-web

# Включить debug mode
ARGOCD_OPTS="--grpc-web --loglevel debug"
```

### Timeout при ожидании

```bash
# Увеличить timeout
RELEASE_TIMEOUT: "600"  # 10 minutes

# Проверить статус вручную
argocd app get ${APP_NAME} --grpc-web

# Принудительный sync
argocd app sync ${APP_NAME} --grpc-web --force
```

### Permission denied

```bash
# Проверить RBAC
argocd admin settings rbac can ci-readonly get applications '*/*' --grpc-web

# Проверить account
argocd account get --account ci-readonly --grpc-web
```

**Ошибка "permission denied: projects, get":**

Если видите ошибку `FATA[0000] permission denied: projects, get, your-project`, добавьте права на projects:

```bash
kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '
data:
  policy.csv: |
    p, role:ci-readonly, applications, get, */*, allow
    p, role:ci-readonly, applications, sync, */*, allow
    p, role:ci-readonly, projects, get, *, allow
    g, ci-readonly, role:ci-readonly
'
```

### SSL/TLS ошибки

```yaml
variables:
  # Для self-signed certificates
  ARGOCD_OPTS: "--grpc-web --insecure"

  # Или для plaintext (только в cluster)
  ARGOCD_OPTS: "--grpc-web --plaintext"
```

---

## Альтернативные подходы

### Подход 2: ArgoCD Notifications → GitLab Deployment API

Асинхронное отслеживание через webhooks:

```yaml
# argocd-notifications-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.webhook.gitlab: |
    url: https://gitlab.com/api/v4/projects/$PROJECT_ID/deployments
    headers:
      - name: PRIVATE-TOKEN
        value: $GITLAB_TOKEN
      - name: Content-Type
        value: application/json

  template.gitlab-deployment: |
    webhook:
      gitlab:
        method: POST
        body: |
          {
            "environment": "{{.app.spec.destination.namespace}}",
            "sha": "{{.app.status.sync.revision}}",
            "ref": "main",
            "status": "{{if eq .app.status.health.status \"Healthy\"}}success{{else}}failed{{end}}"
          }

  trigger.on-deployed: |
    - when: app.status.sync.status == 'Synced' and app.status.health.status == 'Healthy'
      send: [gitlab-deployment]
```

### Подход 3: Комбинированный

Использовать оба подхода:
1. `argocd app wait` для немедленной обратной связи в pipeline
2. ArgoCD Notifications для GitLab Environments UI

---

## Preview Environments

Для feature branches доступен автоматический preview через ArgoCD Pull Request Generator:

1. Создать ветку с JIRA тегом: `PROJ-123-description`
2. CI собирает image
3. ArgoCD создаёт preview environment
4. URL: `proj-123.preview.demo-poc-01.work`

> **Требование:** Ветка должна начинаться с JIRA тега (`PROJ-123-...`)

Подробнее: [preview-environments-guide.md](./preview-environments-guide.md)

---

## Ссылки

### Официальная документация

- [ArgoCD CI Automation](https://argo-cd.readthedocs.io/en/stable/user-guide/ci_automation/) — официальное руководство по интеграции с CI
- [argocd app wait Command](https://argo-cd.readthedocs.io/en/latest/user-guide/commands/argocd_app_wait/) — все опции команды wait
- [ArgoCD Notifications](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/) — настройка webhooks
- [GitLab External Deployment Tracking](https://docs.gitlab.com/ci/environments/external_deployment_tools/) — интеграция с GitLab Environments
- [ArgoCD Pull Request Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Pull-Request/) — автоматические preview environments

### Обсуждения и примеры

- [ArgoCD + GitLab Best Practices Discussion](https://github.com/argoproj/argo-cd/discussions/7475) — опыт сообщества
- [ArgoCD + GitLab Notifications Discussion](https://github.com/argoproj/argo-cd/discussions/21158) — настройка notifications

### Связанные документы

- [preview-environments-guide.md](./preview-environments-guide.md) — preview для feature branches
- [new-service-guide.md](./new-service-guide.md) — создание нового сервиса
- [PREFLIGHT-CHECKLIST.md](./PREFLIGHT-CHECKLIST.md) — полный чеклист развёртывания

### Дополнительно

- [ArgoCD RBAC Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/) — настройка прав доступа
- [ArgoCD User Management](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/) — управление пользователями
