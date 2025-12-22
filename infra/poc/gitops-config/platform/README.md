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
| platform-core | Namespaces, Gateway, ApplicationSet, Vault | -10 |
| service-groups | Infrastructure external access | -5 |
| preview-environments | Feature branch previews | -4 |
| ingress-cloudflare | CloudFlare Tunnel routing | -3 |

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
    syncWave: "0"
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
