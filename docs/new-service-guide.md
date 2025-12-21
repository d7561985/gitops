# New Service Creation Guide

Руководство по созданию нового микросервиса в GitOps платформе.

## Обзор

Платформа следует GitOps подходу с использованием:
- **ArgoCD** для деплоя
- **k8app Helm chart** (v3.8.0+) для стандартизации
- **Vault** для секретов
- **platform-bootstrap** для автоматической конфигурации
- **Distroless images** для безопасности (Go, Node.js)

## Шаг 1: Регистрация сервиса

Добавьте сервис в `gitops-config/charts/platform-bootstrap/values.yaml`:

```yaml
services:
  my-service:
    syncWave: "0"  # Порядок деплоя (0 = первый)
```

Это автоматически создаст:
- Vault policy: `gitops-poc-dzha-my-service-dev`
- Vault role: `my-service-dev`
- ArgoCD Application: `my-service-dev`
- Secret path placeholder: `secret/gitops-poc-dzha/my-service/dev/config`

## Шаг 2: Выбор Dockerfile

Выберите подходящий Dockerfile из `templates/service-repo/dockerfiles/`:

| Язык | Файл | Base Image | Размер |
|------|------|------------|--------|
| **Go** | `Dockerfile.go` | `gcr.io/distroless/static-debian12:nonroot` | ~2MB |
| **Go** (простой) | `Dockerfile.go-simple` | То же, без приватных зависимостей | ~2MB |
| **Python** | `Dockerfile.python` | `python:3.12-slim` | ~150MB |
| **Node.js** | `Dockerfile.nodejs` | `gcr.io/distroless/nodejs22-debian12:nonroot` | ~180MB |
| **Node.js** (native) | `Dockerfile.nodejs-native` | `node:22-alpine` | ~180MB |
| **PHP** | `Dockerfile.php` | `php:8.2-fpm-alpine` + nginx | ~150MB |
| **Angular/React** | `Dockerfile.angular` | `nginx:alpine` | ~40MB |

### Distroless Images

Go и Node.js сервисы используют [Google Distroless](https://github.com/GoogleContainerTools/distroless):
- **Нет shell** — нельзя exec в контейнер (безопаснее)
- **Нет package manager** — меньше attack surface
- **Runs as nonroot** — UID 65532 по умолчанию
- **Включает ca-certificates** — TLS работает из коробки

## Шаг 3: Структура репозитория

```
my-service/
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   └── ...
├── .cicd/
│   ├── default.yaml     # Базовые настройки k8app
│   └── dev.yaml         # Переопределения для dev
├── .gitlab-ci.yml
├── Dockerfile
├── go.mod
└── go.sum
```

## Шаг 4: Конфигурация k8app

### .cicd/default.yaml

```yaml
appName: my-service
version: "1.0.0"
serviceAccountName: default

image:
  repository: my-service
  tag: local
  pullPolicy: Never

imagePullSecrets:
  - name: regsecret

service:
  enabled: true
  type: ClusterIP
  ports:
    grpc:
      externalPort: 8081
      internalPort: 8081
      protocol: TCP
    metrics:
      externalPort: 9090
      internalPort: 9090
      protocol: TCP

# Для gRPC используйте tcpSocket
livenessProbe:
  enabled: true
  mode: tcpSocket
  tcpSocket:
    port: 8081
  initialDelaySeconds: 10
  periodSeconds: 10

readinessProbe:
  enabled: true
  mode: tcpSocket
  tcpSocket:
    port: 8081
  initialDelaySeconds: 5
  periodSeconds: 5

args:
  - "-port=8081"
  - "-metrics-port=9090"

serviceMonitor:
  enabled: true
  port: "metrics"
  path: "/metrics"
  interval: 30s

# Секреты из Vault
secrets:
  DATABASE_URL: "/gitops-poc-dzha/my-service/dev/config"
  API_KEY: "/gitops-poc-dzha/my-service/dev/config"

secretsProvider:
  provider: "vault"
  vault:
    authRef: "vault-auth"
    mount: "secret"
    type: "kv-v2"
    refreshAfter: "1h"
```

### .cicd/dev.yaml

```yaml
environment: dev
branch: main

image:
  repository: registry.gitlab.com/gitops-poc-dzha/my-service
  tag: "latest"
  pullPolicy: IfNotPresent

replicas: 1

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi

labels:
  app.kubernetes.io/instance: my-service-dev
  environment: dev

annotations:
  argocd.argoproj.io/sync-wave: "0"
```

## Шаг 5: Dockerfile (Go с Distroless)

### Без приватных зависимостей

```dockerfile
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /server ./cmd/server

# Distroless (~2MB, secure by default)
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /server /server
ENTRYPOINT ["/server"]
```

### С приватными GitLab зависимостями

```dockerfile
FROM golang:1.23-alpine AS builder
WORKDIR /app

RUN apk add --no-cache git ca-certificates

# Аутентификация для приватных репозиториев
# Токен должен иметь scope read_api!
ARG GITLAB_TOKEN
RUN if [ -n "$GITLAB_TOKEN" ]; then \
    echo "machine gitlab.com login gitlab-ci-token password ${GITLAB_TOKEN}" > ~/.netrc && \
    chmod 600 ~/.netrc; \
    fi

ENV GOPRIVATE=gitlab.com/gitops-poc-dzha/*
ENV GONOSUMDB=gitlab.com/gitops-poc-dzha/*
ENV GONOPROXY=gitlab.com/gitops-poc-dzha/*

SHELL ["/bin/ash", "-c"]

COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /server ./cmd/server

# Distroless (~2MB, secure by default)
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /server /server
ENTRYPOINT ["/server"]
```

## Шаг 6: GitLab CI/CD

### .gitlab-ci.yml

```yaml
variables:
  SERVICE_NAME: "my-service"
  REGISTRY: ${CI_REGISTRY}
  IMAGE_NAME: ${CI_REGISTRY_IMAGE}
  GITOPS_MODE: "pull"
  ARGOCD_OPTS: "--grpc-web"
  RELEASE_TIMEOUT: "300"

stages:
  - build
  - update-manifests
  - release

build:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  variables:
    DOCKER_TLS_CERTDIR: "/certs"
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    # Для приватных Go зависимостей добавьте --build-arg GITLAB_TOKEN=${CI_PUSH_TOKEN}
    - docker build --build-arg GITLAB_TOKEN=${CI_PUSH_TOKEN} -t ${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA} .
    - docker push ${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}
    - |
      if [ "$CI_COMMIT_BRANCH" == "$CI_DEFAULT_BRANCH" ]; then
        docker tag ${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA} ${IMAGE_NAME}:latest
        docker push ${IMAGE_NAME}:latest
      fi
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

update:dev:
  stage: update-manifests
  image: alpine:3.19
  before_script:
    - apk add --no-cache git yq
    - git config --global user.email "ci@gitlab.com"
    - git config --global user.name "GitLab CI"
    - git remote set-url origin "https://oauth2:${CI_PUSH_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git"
    - git fetch origin ${CI_COMMIT_BRANCH}
    - git checkout ${CI_COMMIT_BRANCH}
  script:
    - |
      yq -i '.image.tag = "'${CI_COMMIT_SHORT_SHA}'"' .cicd/dev.yaml
      yq -i '.image.repository = "'${IMAGE_NAME}'"' .cicd/dev.yaml
      git add .cicd/dev.yaml
      git commit -m "ci(dev): update image to ${CI_COMMIT_SHORT_SHA} [skip ci]"
      git push origin ${CI_COMMIT_BRANCH}
  rules:
    - if: $GITOPS_MODE == "pull" && $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

release:dev:
  stage: release
  image: alpine:3.19
  variables:
    ARGOCD_APP_NAME: ${SERVICE_NAME}-dev
    ARGOCD_VERSION: "v2.13.2"
  before_script:
    - apk add --no-cache curl
    - curl -sSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
    - chmod +x /usr/local/bin/argocd
  script:
    - argocd app get ${ARGOCD_APP_NAME} --refresh ${ARGOCD_OPTS} > /dev/null
    - argocd app wait ${ARGOCD_APP_NAME} --timeout ${RELEASE_TIMEOUT} --health --sync ${ARGOCD_OPTS}
  needs:
    - job: update:dev
  rules:
    - if: $GITOPS_MODE == "pull" && $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

## Шаг 7: Создание секретов в Vault

```bash
# Подключение к Vault
kubectl exec -it vault-0 -n vault -- sh

# Создание секретов
vault kv put secret/gitops-poc-dzha/my-service/dev/config \
  DATABASE_URL="mongodb://mongodb.infra-dev.svc:27017/mydb" \
  API_KEY="your-api-key"
```

## Dockerfile шаблоны для других языков

### Python (FastAPI/Flask)

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends gcc python3-dev && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
ENV PATH=/root/.local/bin:$PATH
COPY . .
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser
EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

### Node.js (Distroless)

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm prune --production

FROM gcr.io/distroless/nodejs22-debian12:nonroot
WORKDIR /app
COPY --from=builder /app .
EXPOSE 8080
CMD ["index.js"]
```

### Angular/React (nginx)

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist/my-app /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### Angular/React с Connect-ES (gRPC-Web)

Используем [Connect-ES](https://connectrpc.com/) от Buf — современную замену устаревшему `grpc-web`.

#### Почему Connect-ES вместо grpc-web?

| Проблема grpc-web | Решение Connect-ES |
|-------------------|-------------------|
| Бандл огромный | **На 80% меньше** размер бандла |
| Java-style API (setters/getters) | Идиоматический TypeScript |
| `@types/google-protobuf` не обновлялся 2+ года | Встроенные типы |
| Нечитаемый бинарный формат в DevTools | JSON в network inspector |
| Минимальная поддержка от Google | Активная разработка Buf |

#### package.json

```json
{
  "dependencies": {
    "@bufbuild/protobuf": "^2.2.0",
    "@connectrpc/connect": "^2.0.0",
    "@connectrpc/connect-web": "^2.0.0",
    "@gitops-poc-dzha/my-service-web": "git+https://gitlab.com/gitops-poc-dzha/api/gen/my-service/web.git#main"
  }
}
```

> **Важно:** Репозиторий теперь `web` вместо `angular` (генерация изменена на Connect-ES).

#### Использование в Angular

```typescript
import { Injectable } from '@angular/core';
import { createClient } from '@connectrpc/connect';
import { createGrpcWebTransport } from '@connectrpc/connect-web';
import { UserService } from '@gitops-poc-dzha/user-service-web/user/v1/user_connect';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private client = createClient(
    UserService,
    createGrpcWebTransport({ baseUrl: '/api' })
  );

  async login(email: string, password: string) {
    // Идиоматический TypeScript — без setters!
    const response = await this.client.login({ email, password });
    return response.accessToken;
  }
}
```

#### Dockerfile

```dockerfile
FROM node:22-alpine AS builder

ARG API_URL
ARG APP_VERSION

RUN apk add --no-cache git ca-certificates

WORKDIR /app
COPY package*.json ./

# Install dependencies with GitLab authentication via .netrc
# .netrc is a standard mechanism that works with git, npm, pip, composer
RUN --mount=type=secret,id=gitlab_token \
    GITLAB_TOKEN=$(cat /run/secrets/gitlab_token 2>/dev/null | tr -d '\n' || echo "") && \
    if [ -n "$GITLAB_TOKEN" ]; then \
        echo "machine gitlab.com login gitlab-ci-token password ${GITLAB_TOKEN}" > ~/.netrc && \
        chmod 600 ~/.netrc; \
    fi && \
    npm ci --prefer-offline --no-audit && \
    rm -f ~/.netrc

COPY . .
ENV API_URL=${API_URL} APP_VERSION=${APP_VERSION}
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist/my-app /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

#### CI команда сборки

```yaml
script:
  # IMPORTANT: Use CI_PUSH_TOKEN, not CI_JOB_TOKEN (no cross-project access)
  - echo "$CI_PUSH_TOKEN" > /tmp/gitlab_token
  - docker build --secret id=gitlab_token,src=/tmp/gitlab_token --build-arg APP_VERSION=$CI_COMMIT_SHORT_SHA -t $IMAGE .
  - rm -f /tmp/gitlab_token
```

#### Локальная разработка

Настройте доступ к приватным репозиториям GitLab:

```bash
# Вариант 1: ~/.netrc (рекомендуется)
echo "machine gitlab.com login YOUR_USERNAME password YOUR_GITLAB_TOKEN" >> ~/.netrc
chmod 600 ~/.netrc

# Вариант 2: git URL replacement
git config --global url."https://oauth2:YOUR_GITLAB_TOKEN@gitlab.com/".insteadOf "https://gitlab.com/"
```

Установка и запуск:

```bash
npm install
npm start
```

> **Важно:** Токен должен иметь scope `read_api`.

## gRPC сервисы

### 1. Создать Proto репозиторий

В группе `api/proto/`:

```
api/proto/my-service/
├── buf.yaml
├── buf.gen.yaml
├── .gitlab-ci.yml
└── proto/
    └── myservice/
        └── v1/
            └── service.proto
```

### 2. buf.yaml

```yaml
version: v2
modules:
  - path: proto
    name: buf.build/gitops-poc-dzha/my-service
lint:
  use:
    - DEFAULT
breaking:
  use:
    - FILE
```

### 3. buf.gen.yaml

```yaml
version: v2
managed:
  enabled: true
  override:
    - file_option: go_package_prefix
      value: gitlab.com/gitops-poc-dzha/api/gen/my-service/go
plugins:
  - remote: buf.build/protocolbuffers/go
    out: gen/go
    opt: paths=source_relative
  - remote: buf.build/grpc/go
    out: gen/go
    opt: paths=source_relative
```

### 4. .gitlab-ci.yml

```yaml
include:
  - project: 'gitops-poc-dzha/api/ci'
    ref: main
    file: '/templates/proto-gen/template.yml'

variables:
  PROTO_GEN_LANGUAGES: "go"  # go,nodejs,php,python,angular
```

### 5. Использование сгенерированного кода

```go
import (
    pb "gitlab.com/gitops-poc-dzha/api/gen/my-service/go/myservice/v1"
)
```

## Чеклист

- [ ] Добавлен в platform-bootstrap/values.yaml
- [ ] Создан репозиторий с кодом
- [ ] Выбран подходящий Dockerfile (distroless для Go/Node.js)
- [ ] Создан .cicd/default.yaml
- [ ] Создан .cicd/dev.yaml
- [ ] Создан .gitlab-ci.yml
- [ ] Созданы секреты в Vault
- [ ] (gRPC) Создан proto репозиторий
- [ ] (gRPC) Дождались генерации кода
- [ ] Проверен деплой в dev окружении

## Полезные команды

```bash
# Статус ArgoCD приложения
argocd app get my-service-dev --grpc-web

# Логи пода
kubectl logs -f deployment/my-service -n poc-dev

# Секреты
kubectl get secret my-service-secrets -n poc-dev -o yaml

# Принудительный sync
argocd app sync my-service-dev --grpc-web
```

## Инфраструктурные сервисы

| Сервис | Адрес | Namespace |
|--------|-------|-----------|
| MongoDB | mongodb.infra-dev.svc:27017 | infra-dev |
| RabbitMQ | rabbitmq.infra-dev.svc:5672 | infra-dev |
| Vault | vault.vault.svc:8200 | vault |

## Preview Environments (Feature Branches)

Для frontend сервисов доступны preview environments — автоматический деплой из feature branch для тестирования.

### Как использовать

1. Создать ветку с JIRA тегом: `PROJ-123-description`
2. Push изменения, создать MR
3. CI соберёт image, ArgoCD создаст preview
4. URL: `proj-123.preview.demo-poc-01.work` (только JIRA тег!)
5. При закрытии MR — preview автоматически удаляется

### Пример

```bash
# Branch: PROJ-123-new-login-page
# URL: proj-123.preview.demo-poc-01.work
```

### Требования

- Ветка должна начинаться с JIRA тега: `PROJ-123-...`
- Frontend-only (backend из dev environment)

Подробнее: [preview-environments-guide.md](./preview-environments-guide.md)

## См. также

- [capacity-planning.md](./capacity-planning.md) — планирование ресурсов кластера
- [preview-environments-guide.md](./preview-environments-guide.md) — preview для feature branches
- [gitlab-ci-release-tracking.md](./gitlab-ci-release-tracking.md) — отслеживание релизов
- [domain-mirrors-guide.md](./domain-mirrors-guide.md) — зеркала доменов
- [service-groups-guide.md](./service-groups-guide.md) — инфраструктурные домены
