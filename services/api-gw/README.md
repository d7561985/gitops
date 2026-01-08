# API Gateway Configuration

Configuration repository for API Gateway deployment. Contains routes, clusters, and deployment configuration.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      api-gateway-image                          │
│  (Golden Image - Envoy + Config Generator)                      │
│  Versioned: v1.0.0, v1.1.0, etc.                               │
│  Changes rarely                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ FROM api-gateway-image:v1.0.0
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         api-gw (this repo)                      │
│  ├── config.yaml      ← Developers edit this!                   │
│  ├── Dockerfile       ← Adds config.yaml to golden image        │
│  └── .cicd/           ← Deployment configuration                │
│                                                                 │
│  Micro-image built in ~5 seconds                               │
│  Changes frequently                                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ ArgoCD watches .cicd/
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Kubernetes                               │
│  api-gw-dev, api-gw-staging, api-gw-prod                       │
└─────────────────────────────────────────────────────────────────┘
```

## Files

| File | Description |
|------|-------------|
| `config.yaml` | Routes, clusters, auth policies for Envoy |
| `Dockerfile` | Micro-image (extends golden image + adds config) |
| `.cicd/default.yaml` | Base deployment values for k8app chart |
| `.cicd/dev.yaml` | Dev environment overrides |
| `.cicd/staging.yaml` | Staging environment overrides |
| `.cicd/prod.yaml` | Production environment overrides |

## Workflow

### Changing Routes/Clusters

1. Edit `config.yaml`
2. Commit and push to `main`
3. CI builds micro-image (~5 seconds)
4. CI updates `.cicd/dev.yaml` with new image tag
5. ArgoCD syncs deployment

### Updating Golden Image Version

When `api-gateway-image` releases a new version:

1. Edit `.gitlab-ci.yml`
2. Update `BASE_VERSION: "v1.0.0"` to new version
3. Commit and push
4. CI rebuilds micro-image with new base

## Local Development

```bash
# Build micro-image locally
docker build \
  --build-arg BASE_IMAGE=api-gateway-image \
  --build-arg BASE_VERSION=local \
  -t api-gw:local .

# Test with docker-compose or minikube
```

## config.yaml Structure

```yaml
api_route: /api/

clusters:
  - name: my-service
    addr: "my-service-sv:8080"
    type: "http"  # or "grpc"
    tls:
      enabled: true
      sni: "api.example.com"

apis:
  - name: "MyAPI"
    cluster: "my-service"
    auth:
      policy: "required"  # required | optional | no-need
    methods:
      - name: "GetData"
        auth:
          policy: "required"
          rate_limit:
            period: "1m"
            count: 100
```

See `config.yaml` for full example with all routes.
