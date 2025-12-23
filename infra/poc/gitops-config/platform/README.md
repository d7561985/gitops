# Platform Configuration

Modular platform configuration using centralized values with multi-source ArgoCD Applications.

> **Full documentation:** See [gitops/docs/](../../docs/) for detailed guides on preview environments, domain mirrors, and more.

## Architecture

```
platform/
├── base.yaml           # Shared: global, dns, ingress, vault, environments
├── core.yaml           # Services, namespaces, gateway, applicationset
├── service-groups.yaml # Infrastructure access (ArgoCD, Grafana, Vault)
├── preview.yaml        # Feature branch previews
└── ingress.yaml        # CloudFlare Tunnel aggregated routing
```

## Charts

| Chart | Description | Sync Wave |
|-------|-------------|-----------|
| platform-core | Namespaces, Gateway, ApplicationSet, Vault | -10 to 2 |
| service-groups | Infrastructure external access | -5 |
| preview-environments | Feature branch previews | -4 |
| ingress-cloudflare | CloudFlare Tunnel routing | -3 |

## Sync Waves (Deployment Order)

ArgoCD deploys resources in sync wave order (lower first):

| Wave | Component | Description |
|------|-----------|-------------|
| **-10** | Bootstrap Job | Vault: policies, roles, secret placeholders |
| **-5** | Service Groups | Infrastructure access (ArgoCD, Grafana, Vault) |
| **-4** | Preview Envs | Feature branch previews |
| **-3** | Ingress | CloudFlare Tunnel routing |
| **-2** | Namespaces | `poc-dev`, `infra-dev`, `poc-staging`, `infra-staging` |
| **-1** | Infrastructure | MongoDB, RabbitMQ → `infra-{env}` |
| **0** | Backend | `user-service`, `game-engine`, `payment`, `wager` |
| **1** | API Gateway | Depends on backend services |
| **2** | Frontend | Depends on API Gateway |

**Service sync wave recommendations:**
- `"0"` — backend services without dependencies on other services
- `"1"` — services depending on backend (API Gateway, aggregators)
- `"2"` — frontend applications

## Multi-Source Values

Each ArgoCD Application uses multi-source to combine:
1. `base.yaml` - shared settings
2. Chart-specific YAML - module configuration

Example:
```yaml
sources:
  - repoURL: https://gitlab.com/.../gitops-config.git
    ref: values
  - repoURL: https://gitlab.com/.../gitops-config.git
    path: charts/service-groups
    helm:
      valueFiles:
        - $values/platform/base.yaml
        - $values/platform/service-groups.yaml
```

## Usage

### Adding a New Service
Edit `core.yaml`:
```yaml
services:
  my-service:
    syncWave: "0"  # 0=backend, 1=gateway, 2=frontend
    repoURL: https://gitlab.com/group/my-service.git
    path: .cicd
```

### Adding Infrastructure Access
Edit `service-groups.yaml`:
```yaml
serviceGroups:
  infrastructure:
    services:
      my-tool:
        enabled: true
        subdomain: my-tool
        namespace: my-namespace
        serviceName: my-tool-svc
        servicePort: 80
```

### Enabling Preview Environments

Preview environments create temporary deployments for Merge Requests with JIRA-tagged branches.

**Domain format**: `{jira-tag}.demo-poc-01.work` (e.g., `jira-0001.demo-poc-01.work`)

Edit `preview.yaml`:
```yaml
previewEnvironments:
  enabled: true
  baseDomain: "demo-poc-01.work"
  services:
    my-service:
      enabled: true
      projectId: "12345678"
      branchMatch: "^[A-Z]+-[0-9]+-.*"
      namespace: "poc-dev"  # Shared namespace mode
      appNameBase: "my-service"
```

> **Detailed guide:** See [preview-environments-guide.md](../../docs/preview-environments-guide.md) for full configuration, CI setup, and troubleshooting.

## Deployment

Apply ArgoCD Applications:
```bash
kubectl apply -f argocd/platform-modules.yaml
```

This creates 4 separate Applications in ArgoCD UI for better visibility.
