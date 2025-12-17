# New Service Creation Guide

Руководство по созданию нового микросервиса в GitOps платформе.

## Обзор

Платформа следует GitOps подходу с использованием:
- **ArgoCD** для деплоя
- **k8app Helm chart** для стандартизации
- **Vault** для секретов
- **platform-bootstrap** для автоматической конфигурации

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

## Шаг 2: Создание репозитория

### Структура репозитория

```
my-service/
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   └── ...
├── .cicd/
│   ├── default.yaml     # Базовые настройки k8app
│   └── dev.yaml         # Переопределения для dev окружения
├── .gitlab-ci.yml
├── Dockerfile
├── go.mod
└── go.sum
```

### .cicd/default.yaml

Базовая конфигурация для k8app chart:

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

livenessProbe:
  enabled: true
  mode: tcpSocket
  tcpSocket:
    port: 8081
  initialDelaySeconds: 5
  periodSeconds: 10

readinessProbe:
  enabled: true
  mode: tcpSocket
  tcpSocket:
    port: 8081
  initialDelaySeconds: 3
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
  MY_SECRET: "/gitops-poc-dzha/my-service/dev/config"

secretsProvider:
  provider: "vault"
  vault:
    authRef: "vault-auth"
    mount: "secret"
    type: "kv-v2"
    refreshAfter: "1h"
```

### .cicd/dev.yaml

Переопределения для dev окружения:

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

## Шаг 3: GitLab CI/CD

### .gitlab-ci.yml

```yaml
variables:
  SERVICE_NAME: "my-service"
  REGISTRY: ${CI_REGISTRY}
  IMAGE_NAME: ${CI_REGISTRY_IMAGE}
  HELM_CHART: "k8app/app"
  HELM_REPO: "https://d7561985.github.io/k8app"
  GITOPS_MODE: "pull"
  ARGOCD_OPTS: "--grpc-web"
  RELEASE_TIMEOUT: "300"

stages:
  - build
  - update-manifests
  - release

# Build Docker image
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
    - docker build -t ${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA} .
    - docker push ${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}
    - |
      if [ "$CI_COMMIT_BRANCH" == "$CI_DEFAULT_BRANCH" ]; then
        docker tag ${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA} ${IMAGE_NAME}:latest
        docker push ${IMAGE_NAME}:latest
      fi
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

# Update .cicd/dev.yaml with new image tag
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

# Wait for ArgoCD sync
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

## Шаг 4: Dockerfile

### Без приватных зависимостей

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /server ./cmd/server

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /server /server
ENTRYPOINT ["/server"]
```

### С приватными GitLab зависимостями

Если сервис использует приватные Go модули из GitLab (например, сгенерированный gRPC код):

```dockerfile
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Install git for private dependencies
RUN apk add --no-cache git ca-certificates

# Configure authentication for private GitLab repos
# Token must have read_api scope (not just read_repository)
# See: https://docs.gitlab.com/ee/user/project/use_project_as_go_package.html
ARG GITLAB_TOKEN
RUN if [ -n "$GITLAB_TOKEN" ]; then \
    echo "machine gitlab.com login gitlab-ci-token password ${GITLAB_TOKEN}" > ~/.netrc && \
    chmod 600 ~/.netrc; \
    fi

# Set GOPRIVATE to skip proxy and checksum for private repos
ENV GOPRIVATE=gitlab.com/gitops-poc-dzha/*
ENV GONOSUMDB=gitlab.com/gitops-poc-dzha/*
ENV GONOPROXY=gitlab.com/gitops-poc-dzha/*

# Use ash shell for proper .netrc support
SHELL ["/bin/ash", "-c"]

# Copy go mod files and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-w -s" -o /server ./cmd/server

# Final image
FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /server /server
ENTRYPOINT ["/server"]
```

**Важно для CI/CD:**
- В `.gitlab-ci.yml` передавайте токен через `--build-arg`:
  ```yaml
  script:
    - docker build --build-arg GITLAB_TOKEN=${CI_PUSH_TOKEN} -t ${IMAGE_NAME}:${TAG} .
  ```
- `CI_PUSH_TOKEN` должен быть Personal Access Token с scope `read_api`
- Переменная настраивается на уровне группы `gitops-poc-dzha`

## Шаг 5: Создание секретов в Vault

```bash
# Подключение к Vault
kubectl exec -it vault-0 -n vault -- sh

# Создание секретов
vault kv put secret/gitops-poc-dzha/my-service/dev/config \
  DATABASE_URL="mongodb://mongodb.infra-dev.svc:27017/mydb" \
  API_KEY="your-api-key"
```

## Шаг 6: Добавление маршрутов (опционально)

Если сервис должен быть доступен извне, добавьте HTTPRoute в api-gateway:

```yaml
# В конфигурации api-gateway
routes:
  my-service:
    matches:
      - path:
          type: PathPrefix
          value: /api/my-service
    backendRefs:
      - name: my-service
        port: 8081
```

## gRPC сервисы

Для gRPC сервисов дополнительно нужно:

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

CI автоматически сгенерирует код и опубликует в `api/gen/my-service/go`.

### 5. Использование сгенерированного кода

```go
import (
    pb "gitlab.com/gitops-poc-dzha/api/gen/my-service/go/myservice/v1"
)
```

## Чеклист

- [ ] Добавлен в platform-bootstrap/values.yaml
- [ ] Создан репозиторий с кодом
- [ ] Создан .cicd/default.yaml
- [ ] Создан .cicd/dev.yaml
- [ ] Создан .gitlab-ci.yml
- [ ] Создан Dockerfile
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
