# {{SERVICE_NAME}}

Service repository template for GitOps POC.

## Quick Start

1. Copy this template to your new service repository
2. Replace all `{{SERVICE_NAME}}` with your actual service name
3. Choose appropriate Dockerfile from `dockerfiles/` directory
4. Update `.cicd/default.yaml` with your service configuration
5. Register the service in `gitops-config/charts/platform-bootstrap/values.yaml`

## Structure

```
{{SERVICE_NAME}}/
├── .cicd/
│   ├── default.yaml    # Base Helm values (k8app chart)
│   ├── dev.yaml        # Dev environment overrides
│   ├── staging.yaml    # Staging environment overrides
│   └── prod.yaml       # Production environment overrides
├── .gitlab-ci.yml      # CI/CD pipeline
├── Dockerfile          # Your service Dockerfile
└── src/                # Your service source code
```

## Dockerfile Templates

Choose the appropriate Dockerfile from `dockerfiles/`:

| Language | File | Base Image | Size |
|----------|------|------------|------|
| **Go** | `Dockerfile.go` | `gcr.io/distroless/static-debian12:nonroot` | ~2MB |
| **Go** (simple) | `Dockerfile.go-simple` | Same, no private deps | ~2MB |
| **Python** | `Dockerfile.python` | `python:3.12-slim` | ~150MB |
| **Node.js** | `Dockerfile.nodejs` | `gcr.io/distroless/nodejs22-debian12:nonroot` | ~180MB |
| **Node.js** (native) | `Dockerfile.nodejs-native` | `node:22-alpine` | ~180MB |
| **PHP** | `Dockerfile.php` | `php:8.2-fpm-alpine` + nginx | ~150MB |
| **Angular/React** | `Dockerfile.angular` | `nginx:alpine` | ~40MB |

### Distroless Images

Go and Node.js services use [Google Distroless](https://github.com/GoogleContainerTools/distroless) images:
- **No shell** - Cannot exec into container (more secure)
- **No package manager** - Smaller attack surface
- **Runs as nonroot** - UID 65532 by default
- **Includes ca-certificates** - TLS works out of the box

## GitOps Mode

Controlled by `GITOPS_MODE` variable in `.gitlab-ci.yml`:

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

Secrets are managed declaratively in `.cicd/default.yaml`:

```yaml
secrets:
  DATABASE_PASSWORD: "/gitops-poc-dzha/{{SERVICE_NAME}}/dev/config"
  API_KEY: "/gitops-poc-dzha/{{SERVICE_NAME}}/dev/config"

secretsProvider:
  provider: "vault"
  vault:
    authRef: "vault-auth"
    mount: "secret"
    type: "kv-v2"
    refreshAfter: "1h"
```

Create secrets in Vault:

```bash
vault kv put secret/gitops-poc-dzha/{{SERVICE_NAME}}/dev/config \
  DATABASE_PASSWORD="secret" \
  API_KEY="your-api-key"
```

## Private Go Modules

If your Go service uses private GitLab modules (e.g., generated gRPC code):

### Local Development

```bash
export GOPRIVATE=gitlab.com/gitops-poc-dzha/*
export GONOSUMDB=gitlab.com/gitops-poc-dzha/*
export GONOPROXY=gitlab.com/gitops-poc-dzha/*

# Create ~/.netrc with token (requires read_api scope!)
echo "machine gitlab.com login YOUR_USERNAME password YOUR_GITLAB_TOKEN" > ~/.netrc
chmod 600 ~/.netrc

go mod tidy
```

### Dockerfile

Use `Dockerfile.go` which includes `.netrc` authentication:

```dockerfile
ARG GITLAB_TOKEN
RUN if [ -n "$GITLAB_TOKEN" ]; then \
    echo "machine gitlab.com login gitlab-ci-token password ${GITLAB_TOKEN}" > ~/.netrc && \
    chmod 600 ~/.netrc; \
    fi

ENV GOPRIVATE=gitlab.com/gitops-poc-dzha/*
```

### CI/CD

In `.gitlab-ci.yml`, pass token via `--build-arg`:

```yaml
build:
  script:
    - docker build --build-arg GITLAB_TOKEN=${CI_PUSH_TOKEN} -t ${IMAGE_NAME}:${TAG} .
```

> **Important:** `CI_PUSH_TOKEN` must have `read_api` scope (not just `read_repository`).

## Service Registration

Add your service to `gitops-config/charts/platform-bootstrap/values.yaml`:

```yaml
services:
  {{SERVICE_NAME}}:
    syncWave: "0"
```

This automatically creates:
- Vault policy: `gitops-poc-dzha-{{SERVICE_NAME}}-dev`
- Vault role: `{{SERVICE_NAME}}-dev`
- ArgoCD Application: `{{SERVICE_NAME}}-dev`
- Secret path placeholder in Vault

## k8app Chart Reference

Key configuration options for `.cicd/default.yaml`:

| Feature | Version | Description |
|---------|---------|-------------|
| `secrets` + `secretsProvider` | v3.4.0+ | Vault integration |
| `sharedVolumes` | v3.5.0+ | Shared volumes between containers |
| `extensions` | v3.5.0+ | Sidecar containers |
| `httpRoute` | v3.6.0+ | Gateway API HTTPRoute |
| `serviceMonitor` | v3.8.0+ | Prometheus metrics |

Full documentation: https://github.com/d7561985/k8app
