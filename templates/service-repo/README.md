# {{SERVICE_NAME}}

Service repository template for GitOps POC.

## Structure

```
{{SERVICE_NAME}}/
├── .cicd/
│   ├── default.yaml    # Base Helm values (shared across all envs)
│   ├── dev.yaml        # Dev environment overrides
│   ├── staging.yaml    # Staging environment overrides
│   └── prod.yaml       # Production environment overrides
├── .gitlab-ci.yml      # CI/CD pipeline
├── Dockerfile          # Your service Dockerfile
└── src/                # Your service source code
```

## Setup

1. Replace all `{{SERVICE_NAME}}` with your actual service name
2. Add your service source code and Dockerfile
3. Update `.cicd/default.yaml` with your service configuration
4. Create the repository in GitLab under `gitops-poc` group
5. Register the service in ArgoCD ApplicationSet

## GitOps Mode

This template supports two GitOps modes controlled by `GITOPS_MODE` variable:

### Pull-based (ArgoCD) - Default

```yaml
GITOPS_MODE: "pull"
```

Flow:
1. Developer pushes code
2. CI builds and pushes Docker image
3. CI updates `.cicd/{env}.yaml` with new image tag
4. CI commits and pushes the change
5. ArgoCD detects the change and deploys

### Push-based (GitLab Agent)

```yaml
GITOPS_MODE: "push"
```

Flow:
1. Developer pushes code
2. CI builds and pushes Docker image
3. CI deploys directly to cluster via GitLab Agent

## Vault Secrets (k8app v3.4.0+)

Secrets are now managed declaratively in `.cicd/default.yaml`:

```yaml
# Define which env vars get which Vault paths
secrets:
  API_KEY: "/gitops-poc-dzha/{{SERVICE_NAME}}/dev/config"
  DB_PASSWORD: "/gitops-poc-dzha/{{SERVICE_NAME}}/dev/database"

# Provider configuration
secretsProvider:
  provider: "vault"
  vault:
    authRef: "vault-auth"  # VaultAuth in namespace
    mount: "secret"
    type: "kv-v2"
    refreshAfter: "1h"
```

Prerequisites:
1. Vault with KV v2 secrets engine at `secret/`
2. Kubernetes auth enabled in Vault
3. VaultAuth resource `vault-auth` in target namespace
4. Secrets created in Vault:

```bash
vault kv put secret/gitops-poc-dzha/{{SERVICE_NAME}}/dev/config \
  API_KEY="dev-secret" \
  DB_PASSWORD="dev-password"
```

k8app chart automatically creates VaultStaticSecret and injects env vars into pods.

## Private Go Modules

Если ваш сервис использует приватные Go модули из GitLab (например, gRPC код из `api/gen/`):

### Локальная разработка

```bash
# Установите переменные окружения
export GOPRIVATE=gitlab.com/gitops-poc-dzha/*
export GONOSUMDB=gitlab.com/gitops-poc-dzha/*
export GONOPROXY=gitlab.com/gitops-poc-dzha/*

# Создайте ~/.netrc с токеном (требуется scope read_api!)
echo "machine gitlab.com login YOUR_USERNAME password YOUR_GITLAB_TOKEN" > ~/.netrc
chmod 600 ~/.netrc

# Теперь go mod tidy/download будут работать
go mod tidy
```

### Dockerfile

Используйте `.netrc` для аутентификации:

```dockerfile
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git ca-certificates

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
# ...
```

### CI/CD

В `.gitlab-ci.yml` передавайте токен через `--build-arg`:

```yaml
build:
  script:
    - docker build --build-arg GITLAB_TOKEN=${CI_PUSH_TOKEN} -t ${IMAGE_NAME}:${TAG} .
```

> **Важно:** `CI_PUSH_TOKEN` настраивается на уровне группы `gitops-poc-dzha` и должен иметь scope `read_api`.
