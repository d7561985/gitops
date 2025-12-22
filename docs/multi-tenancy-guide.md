# Multi-Tenancy Architecture & Configuration Guidelines

## Overview

This document describes the multi-tenancy architecture for deploying multiple environments (dev, staging, prod) and potentially multiple brands/products within a single Kubernetes cluster.

**Goals:**
- Environment-agnostic service configurations
- Minimal manual work between DEV → STAGING → PROD promotions
- Support for multiple brands in one cluster without conflicts
- Clear separation of concerns

---

## Architecture

### Namespace Strategy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           KUBERNETES CLUSTER                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │    poc-dev      │  │  poc-staging    │  │    poc-prod     │         │
│  │                 │  │                 │  │                 │         │
│  │  All services:  │  │  All services:  │  │  All services:  │         │
│  │  - api-gateway  │  │  - api-gateway  │  │  - api-gateway  │         │
│  │  - frontend     │  │  - frontend     │  │  - frontend     │         │
│  │  - game-engine  │  │  - game-engine  │  │  - game-engine  │         │
│  │  - payment      │  │  - payment      │  │  - payment      │         │
│  │  - wager        │  │  - wager        │  │  - wager        │         │
│  │  - user-service │  │  - user-service │  │  - user-service │         │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘         │
│           │                    │                    │                   │
│           ▼                    ▼                    ▼                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │   infra-dev     │  │  infra-staging  │  │   infra-prod    │         │
│  │                 │  │                 │  │                 │         │
│  │  - MongoDB      │  │  - MongoDB      │  │  - MongoDB      │         │
│  │  - RabbitMQ     │  │  - RabbitMQ     │  │  - RabbitMQ     │         │
│  │  - Redis        │  │  - Redis        │  │  - Redis        │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    SHARED INFRASTRUCTURE                         │   │
│  │  - argocd (ArgoCD)                                              │   │
│  │  - vault (HashiCorp Vault)                                      │   │
│  │  - monitoring (Prometheus, Grafana)                             │   │
│  │  - cert-manager                                                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Naming Conventions

| Resource | Pattern | Example |
|----------|---------|---------|
| Application Namespace | `{prefix}-{env}` | `poc-dev`, `poc-staging`, `poc-prod` |
| Infrastructure Namespace | `infra-{env}` | `infra-dev`, `infra-staging` |
| Service Name | `{service}-sv` | `api-gateway-sv`, `sentry-frontend-sv` |
| ArgoCD Application | `{service}-{env}` | `api-gateway-dev`, `sentry-frontend-prod` |
| Vault Role | `{service}-{env}` | `api-gateway-dev`, `sentry-payment-staging` |
| Vault Path | `{prefix}/{service}/{env}/config` | `gitops-poc-dzha/api-gateway/dev/config` |

### Multi-Brand Support (Future)

For multiple brands in one cluster:

```
┌─────────────────────────────────────────────────────────────────┐
│  Brand A: sentry                    Brand B: casino             │
│  ┌─────────────┐ ┌─────────────┐   ┌─────────────┐             │
│  │ sentry-dev  │ │sentry-staging│   │ casino-dev  │             │
│  └─────────────┘ └─────────────┘   └─────────────┘             │
│         │               │                 │                     │
│         ▼               ▼                 ▼                     │
│  ┌─────────────┐ ┌─────────────┐   ┌─────────────┐             │
│  │ infra-dev   │ │infra-staging│   │ infra-dev   │ (shared)    │
│  └─────────────┘ └─────────────┘   └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Configuration Structure

### Values Files Hierarchy

```
services/{service}/.cicd/
├── default.yaml      # Base configuration (environment-agnostic)
├── dev.yaml          # Dev environment overrides
├── staging.yaml      # Staging environment overrides
└── prod.yaml         # Production environment overrides
```

**Merge order (last wins):**
```
default.yaml → {env}.yaml
```

### What Goes Where

#### `default.yaml` — Environment-Agnostic Base

```yaml
# ✅ DO include:
appName: my-service
version: "1.0.0"

serviceAccountName: default

image:
  repository: registry.gitlab.com/group/my-service
  # tag: managed by CI in env overlay
  pullPolicy: IfNotPresent

imagePullSecrets:
  - name: regsecret

service:
  enabled: true
  type: ClusterIP
  ports:
    http:
      externalPort: 8080
      internalPort: 8080

livenessProbe:
  enabled: true
  mode: httpGet
  httpGet:
    port: 8080
    path: "/health"
  initialDelaySeconds: 15
  periodSeconds: 10

readinessProbe:
  enabled: true
  mode: httpGet
  httpGet:
    port: 8080
    path: "/health"
  initialDelaySeconds: 10
  periodSeconds: 5

# Service-to-service communication (SAME namespace = short DNS)
configmap:
  USER_SERVICE_URL: "http://user-service-sv:8081"
  PAYMENT_SERVICE_URL: "http://sentry-payment-sv:8083"
  # ❌ DO NOT include infrastructure URLs here

# Vault configuration (pattern, not full path)
vault:
  enabled: true
  # role and path are typically env-specific

# HTTPRoute base (without namespace and hostname)
httpRoute:
  enabled: true
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: my-service-sv
          port: 8080
```

#### `{env}.yaml` — Environment-Specific Overrides

```yaml
# dev.yaml example

# Image tag (updated by CI)
image:
  tag: "abc123"

# Replicas
replicas: 1

# Resources (environment-appropriate)
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

# Infrastructure URLs (CROSS-namespace = FQDN required)
configmap:
  MONGODB_URL: "mongodb://root:password@mongodb.infra-dev.svc:27017/mydb?authSource=admin"
  RABBITMQ_URL: "amqp://guest:guest@rabbitmq.infra-dev.svc:5672"
  REDIS_URL: "redis://redis.infra-dev.svc:6379"
  # Sentry/monitoring
  SENTRY_ENVIRONMENT: "dev"
  LOG_LEVEL: "debug"

# Vault (environment-specific)
vault:
  role: my-service-dev
  path: gitops-poc-dzha/my-service/dev/config

# HTTPRoute (environment-specific gateway and domain)
httpRoute:
  parentRefs:
    - name: gateway
      namespace: poc-dev
      sectionName: http-app
  hostnames:
    - app.demo-poc-01.work
```

---

## Service Discovery Rules

### Same Namespace (Service-to-Service)

All application services within the same environment share a namespace. Use **short DNS names**:

```yaml
# ✅ Correct - works in any namespace
USER_SERVICE_URL: "http://user-service-sv:8081"
PAYMENT_SERVICE_URL: "http://sentry-payment-sv:8083"

# ❌ Wrong - hardcoded namespace
USER_SERVICE_URL: "http://user-service-sv.poc-dev.svc.cluster.local:8081"
```

### Cross-Namespace (Service-to-Infrastructure)

Infrastructure services (MongoDB, RabbitMQ, Redis) are in separate `infra-{env}` namespaces. Use **FQDN in env overlays**:

```yaml
# In dev.yaml
configmap:
  MONGODB_URL: "mongodb://mongodb.infra-dev.svc:27017/db"

# In staging.yaml
configmap:
  MONGODB_URL: "mongodb://mongodb.infra-staging.svc:27017/db"

# In prod.yaml
configmap:
  MONGODB_URL: "mongodb://mongodb.infra-prod.svc:27017/db"
```

### DNS Formats Reference

| Scope | Format | Example |
|-------|--------|---------|
| Same namespace | `{service}` | `user-service-sv` |
| Same namespace (explicit) | `{service}.{namespace}` | `user-service-sv.poc-dev` |
| Cross namespace | `{service}.{namespace}.svc` | `mongodb.infra-dev.svc` |
| Full FQDN | `{service}.{namespace}.svc.cluster.local` | `mongodb.infra-dev.svc.cluster.local` |

---

## Gateway & Routing

### Gateway per Environment

Each environment has its own Gateway resource in the application namespace:

```yaml
# Created by platform-core
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway
  namespace: poc-dev  # or poc-staging, poc-prod
spec:
  gatewayClassName: cilium
  listeners:
    - name: http-app
      hostname: "app.demo-poc-01.work"
      protocol: HTTP
      port: 80
```

### HTTPRoute Configuration

Services define their routing in env-specific overlays:

```yaml
# default.yaml - routing rules only
httpRoute:
  enabled: true
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api-gateway-sv
          port: 8080

# dev.yaml - gateway reference and domain
httpRoute:
  parentRefs:
    - name: gateway
      namespace: poc-dev
      sectionName: http-app
  hostnames:
    - app.demo-poc-01.work
```

---

## CI/CD Pipeline

### GitLab CI (Build Only)

GitLab CI handles:
- Building Docker images
- Running tests
- Pushing to registry
- **Updating image.tag in `{env}.yaml`**

```yaml
# .gitlab-ci.yml example
update-gitops:
  stage: deploy
  script:
    - |
      yq -i '.image.tag = "'${CI_COMMIT_SHORT_SHA}'"' \
        services/${SERVICE_NAME}/.cicd/${ENVIRONMENT}.yaml
    - git commit -am "chore: update ${SERVICE_NAME} to ${CI_COMMIT_SHORT_SHA}"
    - git push
```

### ArgoCD (Deploy Only)

ArgoCD handles all deployments via GitOps:
- Watches git repository for changes
- Syncs Kubernetes state to match git
- Manages rollbacks

**No kubectl/helm commands in CI for deployment.**

---

## Promotion Workflow

### Dev → Staging → Prod

```
1. Developer pushes code
   └── GitLab CI builds image, updates dev.yaml with new tag
       └── ArgoCD syncs dev automatically

2. QA approves
   └── Copy image.tag from dev.yaml to staging.yaml
       └── ArgoCD syncs staging automatically

3. Release approved
   └── Copy image.tag from staging.yaml to prod.yaml
       └── ArgoCD syncs prod (manual sync if configured)
```

### Automated Promotion (Optional)

```yaml
# In platform-core ApplicationSet
environments:
  dev:
    enabled: true
    autoSync: true      # Automatic
  staging:
    enabled: true
    autoSync: true      # Automatic after approval
  prod:
    enabled: true
    autoSync: false     # Manual sync required
```

---

## Adding a New Environment

When you need to add a new environment (e.g., `staging` or `prod`):

### Step 1: Enable Environment in Platform Bootstrap

Edit `gitops-config/platform/core.yaml`:

```yaml
environments:
  dev:
    enabled: true
    autoSync: true
    domain: "app.demo-poc-01.work"
    infraNamespace: "infra-dev"
  staging:                                  # ← Add new environment
    enabled: true
    autoSync: true
    domain: "app.staging.example.com"       # ← Each env needs unique domain
    infraNamespace: "infra-staging"
  prod:                                     # ← Add new environment
    enabled: true
    autoSync: false                         # Manual sync for production
    domain: "app.prod.example.com"          # ← Each env needs unique domain
    infraNamespace: "infra-prod"
```

**Important**: Each environment MUST have a unique `domain`. The Gateway template creates a separate Gateway per environment with the specified hostname.

### Step 2: Configure CloudFlare Tunnel

Add a Public Hostname in CloudFlare Dashboard for the new environment:

1. Go to https://one.dash.cloudflare.com/
2. Navigate to: Networks → Tunnels → Your tunnel → Public Hostname
3. Add hostname:
   - **Public hostname**: `app.staging.example.com`
   - **Service Type**: HTTP
   - **URL**: `cilium-gateway-gateway.poc-staging.svc.cluster.local:80`

| Environment | Public Hostname           | Service URL                                              |
|-------------|---------------------------|----------------------------------------------------------|
| dev         | app.demo-poc-01.work      | `cilium-gateway-gateway.poc-dev.svc.cluster.local:80`    |
| staging     | app.staging.example.com   | `cilium-gateway-gateway.poc-staging.svc.cluster.local:80`|
| prod        | app.prod.example.com      | `cilium-gateway-gateway.poc-prod.svc.cluster.local:80`   |

**Note**: Cilium creates a LoadBalancer service named `cilium-gateway-{gateway-name}`. Since our Gateway is named `gateway`, the service is `cilium-gateway-gateway`.

### Step 3: Deploy Infrastructure

Create infrastructure namespace and deploy services:

```bash
# Create namespace
kubectl create namespace infra-staging

# Deploy MongoDB, RabbitMQ, Redis (example with Helm)
helm install mongodb bitnami/mongodb -n infra-staging
helm install rabbitmq bitnami/rabbitmq -n infra-staging
```

### Step 4: Create Registry Secret

```bash
# Add new namespace to the list
NAMESPACES="poc-dev poc-staging poc-prod" ./scripts/setup-registry-secret.sh
```

### Step 5: Create Service Overlays

For each service, create `{env}.yaml`:

```bash
# Copy from dev as template
cp services/my-service/.cicd/dev.yaml services/my-service/.cicd/staging.yaml
```

Edit `staging.yaml`:

```yaml
image:
  tag: "latest"  # CI will update

replicas: 2

configmap:
  # Update infrastructure URLs
  MONGODB_URL: "mongodb://mongodb.infra-staging.svc:27017/db"
  RABBITMQ_URL: "amqp://rabbitmq.infra-staging.svc:5672"
  SENTRY_ENVIRONMENT: "staging"

vault:
  role: my-service-staging
  path: gitops-poc-dzha/my-service/staging/config

httpRoute:
  parentRefs:
    - name: gateway
      namespace: poc-staging
      sectionName: http-app          # ← Same listener name across all environments
  hostnames:
    - app.staging.example.com        # ← Must match environments.staging.domain
```

### Step 6: Create Vault Secrets

```bash
vault kv put secret/gitops-poc-dzha/my-service/staging/config \
  API_KEY="xxx" \
  DB_PASSWORD="yyy"
```

### Step 7: Sync Platform Bootstrap

```bash
# ArgoCD will auto-create:
# - Namespace: poc-staging
# - VaultAuth resource
# - Gateway resource
# - ArgoCD Applications for all services

argocd app sync platform-core
```

### What Gets Auto-Created

When you enable a new environment, `platform-core` automatically creates:

| Resource | Name | Namespace |
|----------|------|-----------|
| Namespace | `poc-staging` | - |
| Gateway | `gateway` | `poc-staging` |
| VaultAuth | `vault-auth` | `poc-staging` |
| Vault Policy | `poc-staging-read` | Vault |
| Vault Role | `poc-staging-default` | Vault |
| ArgoCD Apps | `{service}-staging` | `argocd` |

---

## Adding a New Brand/Product

When you need to deploy a completely separate brand/product in the same cluster:

### Option A: Separate GitOps Repository (Recommended)

For full isolation, create a new GitOps repository:

```
gitops-brand-b/
├── gitops-config/
│   ├── charts/
│   │   ├── platform-core/
│   │   ├── service-groups/
│   │   ├── preview-environments/
│   │   └── ingress-cloudflare/
│   └── platform/
│       ├── base.yaml            # brand-b specific
│       ├── core.yaml
│       ├── service-groups.yaml
│       └── ingress.yaml
├── services/
│   └── ...                      # brand-b services
└── infrastructure/
    └── ...
```

Update `platform/base.yaml` for brand-b:

```yaml
global:
  gitlabGroup: brand-b-group
  vaultPathPrefix: brand-b
  namespacePrefix: brand-b       # ← Different prefix

environments:
  dev:
    enabled: true
  prod:
    enabled: true

services:
  frontend:
    syncWave: "1"
  api:
    syncWave: "0"
```

This creates namespaces: `brand-b-dev`, `brand-b-prod`

### Option B: Same Repository, Different Prefix

For lighter isolation, add brand as a new "tenant" in the same repo:

#### Step 1: Create Brand-Specific Bootstrap

```bash
cp -r gitops-config/charts gitops-config-brand-b/charts
cp -r gitops-config/platform gitops-config-brand-b/platform
```

Edit `brand-b-bootstrap/values.yaml`:

```yaml
global:
  gitlabGroup: gitops-poc-dzha
  vaultPathPrefix: brand-b
  namespacePrefix: brand-b       # ← Different prefix

services:
  brand-b-frontend:
    syncWave: "1"
    repoURL: https://gitlab.com/gitops-poc-dzha/brand-b.git
    path: frontend/.cicd
  brand-b-api:
    syncWave: "0"
    repoURL: https://gitlab.com/gitops-poc-dzha/brand-b.git
    path: api/.cicd
```

#### Step 2: Create ArgoCD Application for Brand

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: brand-b-bootstrap
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.com/gitops-poc-dzha/gitops.git
    path: gitops-config/charts/brand-b-bootstrap
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

#### Step 3: Create Service Configurations

```
services/brand-b/
├── frontend/
│   └── .cicd/
│       ├── default.yaml
│       └── dev.yaml
└── api/
    └── .cicd/
        ├── default.yaml
        └── dev.yaml
```

### Infrastructure Sharing Options

| Approach | Isolation | Cost | Complexity |
|----------|-----------|------|------------|
| **Shared infra namespace** | Low | Low | Low |
| **Per-brand infra namespace** | Medium | Medium | Medium |
| **External managed services** | High | High | Low |

#### Shared Infrastructure

Both brands use same `infra-dev`:

```yaml
# brand-a dev.yaml
MONGODB_URL: "mongodb://mongodb.infra-dev.svc:27017/brand_a_db"

# brand-b dev.yaml
MONGODB_URL: "mongodb://mongodb.infra-dev.svc:27017/brand_b_db"
```

#### Per-Brand Infrastructure

Each brand has own infra namespace:

```yaml
# brand-a dev.yaml
MONGODB_URL: "mongodb://mongodb.infra-brand-a-dev.svc:27017/db"

# brand-b dev.yaml
MONGODB_URL: "mongodb://mongodb.infra-brand-b-dev.svc:27017/db"
```

### Brand Isolation Checklist

- [ ] Separate namespace prefix (`brand-a-*`, `brand-b-*`)
- [ ] Separate Vault paths (`brand-a/`, `brand-b/`)
- [ ] Separate domains (`app.brand-a.com`, `app.brand-b.com`)
- [ ] Separate ArgoCD Project (optional, for RBAC)
- [ ] Separate monitoring dashboards (optional)
- [ ] Resource quotas per namespace (recommended)

### Resource Quotas (Recommended)

To prevent one brand from consuming all cluster resources:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: brand-quota
  namespace: brand-b-dev
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
```

Add to platform-core or apply manually.

---

## Checklist for New Services

### 1. Create Service Configuration

```bash
mkdir -p services/my-new-service/.cicd
```

### 2. Create `default.yaml`

- [ ] Set `appName`
- [ ] Configure `image.repository` (without tag)
- [ ] Add `imagePullSecrets: [{name: regsecret}]`
- [ ] Define service ports
- [ ] Configure health probes
- [ ] Add service-to-service URLs (short DNS)
- [ ] Configure HTTPRoute rules (without namespace/hostname)

### 3. Create Environment Overlays

For each environment (`dev.yaml`, `staging.yaml`, `prod.yaml`):

- [ ] Set `image.tag`
- [ ] Set `replicas`
- [ ] Configure `resources`
- [ ] Add infrastructure URLs (FQDN)
- [ ] Set environment-specific config (LOG_LEVEL, SENTRY_ENVIRONMENT)
- [ ] Configure `vault.role` and `vault.path`
- [ ] Add `httpRoute.parentRefs` with namespace
- [ ] Add `httpRoute.hostnames`

### 4. Register in Platform Bootstrap

Add to `gitops-config/platform/core.yaml`:

```yaml
services:
  my-new-service:
    syncWave: "0"
    # repoURL: custom if not default pattern
    # path: custom if not .cicd
```

### 5. Create Vault Secrets

Secrets are auto-provisioned by platform-core job, but add actual values:

```bash
vault kv put secret/gitops-poc-dzha/my-new-service/dev/config \
  API_KEY="xxx" \
  DB_PASSWORD="yyy"
```

---

## Anti-Patterns to Avoid

### ❌ Hardcoded Namespaces in URLs

```yaml
# WRONG
MONGODB_URL: "mongodb://mongodb.infra-dev.svc:27017/db"  # in default.yaml
```

### ❌ Environment-Specific Values in default.yaml

```yaml
# WRONG - these belong in env overlay
replicas: 3
image:
  tag: "v1.2.3"
configmap:
  SENTRY_ENVIRONMENT: "dev"
```

### ❌ Cross-Namespace Short DNS

```yaml
# WRONG - won't resolve across namespaces
MONGODB_URL: "mongodb://mongodb:27017/db"  # mongodb is in infra-dev
```

### ❌ kubectl in CI for Deployments

```yaml
# WRONG - use ArgoCD
deploy:
  script:
    - kubectl apply -f manifests/
```

---

## Troubleshooting

### Service Can't Reach Infrastructure

1. Check namespace: `kubectl get pods -n infra-dev`
2. Verify DNS resolution: `kubectl run -it --rm debug --image=busybox -- nslookup mongodb.infra-dev.svc`
3. Check URL format in configmap: must be FQDN for cross-namespace

### HTTPRoute Not Working

1. Verify Gateway exists: `kubectl get gateway -n poc-dev`
2. Check parentRefs namespace matches Gateway namespace
3. Verify hostname matches Gateway listener

### ArgoCD Not Syncing

1. Check ApplicationSet: `kubectl get applicationset -n argocd`
2. Verify service is registered in platform/core.yaml
3. Check ArgoCD UI for sync errors

---

## References

- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Multi-tenancy in Argo CD](https://blog.argoproj.io/best-practices-for-multi-tenancy-in-argo-cd-273e25a047b0)
- [Kubernetes Service Discovery](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
