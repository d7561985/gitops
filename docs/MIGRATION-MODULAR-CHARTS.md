# Migration Plan: Modular Charts Architecture

## Overview

Миграция монолитного `platform-bootstrap` chart на модульную архитектуру с отдельными charts и централизованными values.

**Дата:** 2025-12-21
**Статус:** В процессе

## Текущее состояние

```
platform-bootstrap/           # 1 монолитный chart, ~1500 строк templates
├── templates/
│   ├── namespaces.yaml
│   ├── vault-auth.yaml
│   ├── bootstrap-job.yaml
│   ├── applicationset.yaml
│   ├── gateway.yaml
│   ├── reference-grant.yaml
│   ├── cloudflared-config.yaml
│   ├── cloudflared-deployment.yaml
│   ├── domain-mirrors.yaml
│   ├── httproute-mirrors.yaml
│   ├── service-groups.yaml
│   ├── service-groups-network-policy.yaml
│   ├── preview-applicationset.yaml
│   └── preview-vault-secrets.yaml
└── values.yaml               # ~550 строк, все конфигурации
```

**Проблемы:**
- В ArgoCD видно 1 приложение — непонятно откуда ресурсы
- Любое изменение требует sync всего chart
- values.yaml слишком большой
- Сложно понять зависимости

## Целевая архитектура

```
gitops-config/
├── charts/                          # Chart definitions (templates only)
│   ├── platform-core/               # Namespaces, Vault, Services ApplicationSet
│   │   ├── Chart.yaml
│   │   ├── values.yaml              # Defaults
│   │   └── templates/
│   │       ├── namespaces.yaml
│   │       ├── vault-auth.yaml
│   │       ├── bootstrap-job.yaml
│   │       ├── applicationset.yaml
│   │       └── reference-grant.yaml
│   │
│   ├── ingress-cloudflare/          # Gateway + Cloudflared
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── gateway.yaml
│   │       ├── cloudflared-config.yaml
│   │       └── cloudflared-deployment.yaml
│   │
│   ├── domain-mirrors/              # Mirror management
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── domain-mirrors.yaml
│   │       └── httproute-mirrors.yaml
│   │
│   ├── service-groups/              # Infrastructure domains
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── service-groups.yaml
│   │       └── service-groups-network-policy.yaml
│   │
│   └── preview-environments/        # Feature branch previews
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── preview-applicationset.yaml
│           └── preview-vault-secrets.yaml
│
├── platform/                        # Values (configuration)
│   ├── base.yaml                    # Shared values
│   ├── core.yaml                    # platform-core specific
│   ├── ingress.yaml                 # ingress-cloudflare specific
│   ├── mirrors.yaml                 # domain-mirrors specific
│   ├── service-groups.yaml          # service-groups specific
│   └── preview.yaml                 # preview-environments specific
│
└── argocd/
    ├── project.yaml                 # Existing
    ├── bootstrap-app.yaml           # Existing (will be deprecated)
    └── platform-modules.yaml        # NEW: ApplicationSet for all modules
```

## Values Structure

### base.yaml (Shared)

```yaml
# Общие значения, используемые всеми charts
global:
  gitlabGroup: gitops-poc-dzha
  vaultPathPrefix: gitops-poc-dzha
  namespacePrefix: poc
  k8app:
    repoURL: https://d7561985.github.io/k8app
    chart: app
    version: "3.8.0"

# Environment definitions
environments:
  dev:
    enabled: true
    autoSync: true
    domain: "app.demo-poc-01.work"
    infraNamespace: "infra-dev"
    mirrors:
      - domain: "demo-poc-02.work"
        zoneId: "76d0dce2fd263121a17a36a188081b99"

# Vault connection
vault:
  address: "http://vault.vault.svc:8200"
  mount: "secret"
  tokenSecret:
    name: vault-admin-token
    key: token

# DNS settings
dns:
  enabled: true
  provider: cloudflare
  cloudflare:
    proxied: true
    secretName: cloudflare-api-credentials
    namespace: external-dns

# Ingress provider
ingress:
  provider: cloudflare-tunnel
  cloudflare:
    enabled: true
    tunnelId: "1172317a-8885-492f-9744-dfba842c4d88"
    credentialsSecret: cloudflared-credentials
    replicas: 2
    namespace: cloudflare
```

### core.yaml (platform-core)

```yaml
# Specific to platform-core chart
namespaces:
  enabled: true
  labels:
    app.kubernetes.io/managed-by: platform-bootstrap

vaultAuth:
  enabled: true
  audiences:
    - vault

job:
  enabled: true
  image: hashicorp/vault:1.15
  backoffLimit: 3
  ttlSecondsAfterFinished: 300
  hook: PreSync
  hookDeletePolicy: HookSucceeded
  syncWave: "-10"

applicationSet:
  enabled: true
  name: gitops-services
  project: gitops-poc-dzha

services:
  api-gateway:
    syncWave: "0"
  web-grpc:
    syncWave: "0"
  # ... etc
```

### ingress.yaml (ingress-cloudflare)

```yaml
# Specific to ingress-cloudflare chart
gateway:
  enabled: true
  gatewayClassName: cilium
  listener:
    name: http-app
    protocol: HTTP
    port: 80
  certManager:
    enabled: false
```

### mirrors.yaml (domain-mirrors)

```yaml
# Specific to domain-mirrors chart
domainMirrors:
  enabled: true
  addToGateway: true
  createDNS: true
  addToTunnel: true
  defaultRoutes:
    - name: api
      path: /api
      pathType: PathPrefix
      serviceName: api-gateway-sv
      servicePort: 8080
    - name: frontend
      path: /
      pathType: PathPrefix
      serviceName: sentry-frontend-sv
      servicePort: 4200
```

### service-groups.yaml

```yaml
# Specific to service-groups chart
serviceGroups:
  infrastructure:
    enabled: true
    baseDomain: "infra-01.work"
    clusterName: "poc"
    gatewayNamespace: "platform"
    zoneId: "cca72b9991480eb87d5e07717ddb8a4a"
    gateway:
      gatewayClassName: cilium
      protocol: HTTP
      port: 80
    security:
      ipWhitelist:
        enabled: false
        cidrs: []
    services:
      argocd:
        enabled: true
        subdomain: argocd
        namespace: argocd
        serviceName: argocd-server
        servicePort: 80
        path: /
        pathType: PathPrefix
      # ... etc
```

### preview.yaml (preview-environments)

```yaml
# Specific to preview-environments chart
previewEnvironments:
  enabled: true
  vault:
    enabled: true
    path: "gitops-poc-dzha/argocd/gitlab-preview/dev"
  baseDomain: "preview.demo-poc-01.work"
  zoneId: "4326314d3e3737ed7a7cde0081ab31af"
  gitlab:
    api: "https://gitlab.com/"
    tokenRef:
      secretName: gitlab-preview-token
      key: token
    requeueAfterSeconds: 60
  services:
    frontend:
      enabled: true
      projectId: "76998085"
      branchMatch: "^[A-Z]+-[0-9]+-.*"
      cicdPath: "frontend/.cicd"
      repoURL: "https://gitlab.com/gitops-poc-dzha/sentry-demo.git"
      namespacePrefix: "preview-frontend"
      backendNamespace: "poc-dev"
  gateway:
    namespace: "poc-dev"
    gatewayClassName: cilium
    protocol: HTTP
    port: 80
```

## ArgoCD ApplicationSet

### platform-modules.yaml

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform-modules
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - name: platform-core
            chart: platform-core
            values: core.yaml
            syncWave: "0"
          - name: ingress-cloudflare
            chart: ingress-cloudflare
            values: ingress.yaml
            syncWave: "1"
          - name: domain-mirrors
            chart: domain-mirrors
            values: mirrors.yaml
            syncWave: "2"
          - name: service-groups
            chart: service-groups
            values: service-groups.yaml
            syncWave: "2"
          - name: preview-environments
            chart: preview-environments
            values: preview.yaml
            syncWave: "3"
  template:
    metadata:
      name: '{{ .name }}'
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: '{{ .syncWave }}'
    spec:
      project: gitops-poc-dzha
      sources:
        # Chart source
        - repoURL: https://gitlab.com/gitops-poc-dzha/gitops-config.git
          targetRevision: main
          path: 'charts/{{ .chart }}'
          helm:
            valueFiles:
              - $values/platform/base.yaml
              - '$values/platform/{{ .values }}'
        # Values source
        - repoURL: https://gitlab.com/gitops-poc-dzha/gitops-config.git
          targetRevision: main
          path: platform
          ref: values
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

## Migration Steps

### Phase 1: Preparation (No Breaking Changes)

1. [ ] Create `charts/` directory structure
2. [ ] Create `platform/` values directory
3. [ ] Create `base.yaml` with shared values
4. [ ] Create chart-specific values files

### Phase 2: Extract Charts (Parallel Operation)

5. [ ] Extract `preview-environments` chart
   - Copy templates
   - Test with `helm template`
   - Deploy as separate ArgoCD App (parallel to existing)

6. [ ] Extract `service-groups` chart
7. [ ] Extract `domain-mirrors` chart
8. [ ] Extract `ingress-cloudflare` chart
9. [ ] Create `platform-core` chart (remaining templates)

### Phase 3: Switch Over

10. [ ] Create `platform-modules.yaml` ApplicationSet
11. [ ] Apply ApplicationSet (creates new Apps)
12. [ ] Verify all modules synced
13. [x] Delete old `platform-bootstrap` Application
14. [x] Archive old `platform-bootstrap` chart

### Phase 4: Cleanup

15. [ ] Remove deprecated templates
16. [ ] Update documentation
17. [ ] Update CI/CD references

## Rollback Plan

If migration fails:
1. Delete new ApplicationSet: `kubectl delete appset platform-modules -n argocd`
2. Re-sync old platform-bootstrap: `argocd app sync platform-bootstrap`
3. Old chart remains unchanged during migration

## Dependencies Between Charts

```
platform-core (sync-wave: 0)
├── Creates: Namespaces, Vault roles, Service ApplicationSet
└── Required by: All other charts

ingress-cloudflare (sync-wave: 1)
├── Creates: Gateway, Cloudflared
├── Requires: Namespaces from platform-core
└── Required by: domain-mirrors, service-groups, preview-environments

domain-mirrors (sync-wave: 2)
├── Creates: HTTPRoutes for mirrors
├── Requires: Gateway from ingress-cloudflare
└── Updates: Cloudflared config (via ingress-cloudflare values)

service-groups (sync-wave: 2)
├── Creates: Gateway, HTTPRoutes for infra services
├── Self-contained (creates own Gateway)
└── Updates: Cloudflared config

preview-environments (sync-wave: 3)
├── Creates: ApplicationSet for previews, VaultAuth
├── Requires: Gateway listener from ingress-cloudflare
└── Requires: Vault role from platform-core bootstrap job
```

## Testing Strategy

### Local Testing

```bash
# Test individual chart
cd charts/preview-environments
helm template . -f ../../platform/base.yaml -f ../../platform/preview.yaml

# Validate all charts
for chart in charts/*/; do
  echo "Testing $chart..."
  helm lint "$chart" -f platform/base.yaml
done
```

### ArgoCD Testing

```bash
# Deploy single module first
argocd app create preview-environments-test \
  --repo https://gitlab.com/.../gitops-config.git \
  --path charts/preview-environments \
  --helm-value-file ../platform/base.yaml \
  --helm-value-file ../platform/preview.yaml \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace argocd

# Verify
argocd app get preview-environments-test
```

## Success Criteria

- [ ] All 5 modules visible as separate Apps in ArgoCD
- [ ] Each module can sync independently
- [ ] No duplicate resources
- [ ] All existing functionality preserved
- [ ] Preview environments still work
- [ ] Service groups still accessible
- [ ] Domain mirrors still route correctly

## Notes

- Keep `platform-bootstrap` chart during migration as fallback
- Use sync-waves to ensure correct deployment order
- Multi-source requires ArgoCD 2.6+
- Test in dev environment first
