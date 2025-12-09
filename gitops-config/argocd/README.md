# Pull-Based GitOps with ArgoCD

## Overview

Pull-based GitOps использует ArgoCD для мониторинга Git репозитория и автоматической синхронизации состояния кластера.

```
┌─────────────┐                    ┌─────────────┐
│   GitLab    │ ◄──── Poll ─────── │   ArgoCD    │
│ Repository  │                    │ Controller  │
│             │                    │             │
└─────────────┘                    └──────┬──────┘
                                          │
                                          │ Apply
                                          ▼
                                   ┌─────────────┐
                                   │  Kubernetes │
                                   │   Cluster   │
                                   └─────────────┘
```

## Advantages

- **Drift detection** — обнаруживает и исправляет изменения в кластере
- **Self-healing** — автоматически восстанавливает желаемое состояние
- **Audit trail** — полная история изменений в Git
- **Multi-cluster** — легко управлять несколькими кластерами
- **UI Dashboard** — визуализация состояния приложений

## Disadvantages

- **Polling delay** — изменения применяются не мгновенно (default: 3 min)
- **Learning curve** — требует изучения ArgoCD концепций
- **Resource overhead** — ArgoCD потребляет ресурсы кластера

## Setup

### 1. Install ArgoCD

```bash
./infrastructure/argocd/setup.sh
```

### 2. Access ArgoCD UI

```bash
# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Open https://localhost:8080
# Login: admin / <password>
```

### 3. Add GitLab Repository

```bash
# Via CLI
argocd repo add https://gitlab.com/your-group/gitops-poc.git \
  --username oauth2 \
  --password <gitlab-token>

# Or via UI: Settings → Repositories → Connect Repo
```

### 4. Apply Bootstrap (запускает всё автоматически)

```bash
kubectl apply -f gitops-config/argocd/project.yaml
kubectl apply -f gitops-config/argocd/bootstrap-app.yaml
```

Bootstrap Application автоматически создаёт:
- **platform-bootstrap** — Helm chart, который генерирует:
  - Namespaces (poc-dev, poc-staging, poc-prod)
  - Vault policies и Kubernetes auth roles
  - Vault secret placeholders
  - ApplicationSet для всех сервисов
  - VaultAuth ресурсы для каждого окружения

## Sync Waves

Сервисы деплоятся в определённом порядке:

| Wave | Services | Description |
|------|----------|-------------|
| 0 | web-grpc, web-http, health-demo | Backend services (no dependencies) |
| 1 | auth-adapter | Auth service |
| 2 | api-gateway | Gateway (depends on auth-adapter) |

```yaml
annotations:
  argocd.argoproj.io/sync-wave: "0"  # Deploy first
```

## Auto-Sync Configuration

| Environment | Auto-Sync | Self-Heal | Description |
|-------------|-----------|-----------|-------------|
| dev | Yes | Yes | Fully automated |
| staging | Yes | Yes | Fully automated |
| prod | No | No | Manual sync required |

## Manual Sync (Production)

```bash
# Via CLI
argocd app sync api-gateway-prod

# Via UI
# Applications → api-gateway-prod → SYNC
```

## Rollback

```bash
# List history
argocd app history api-gateway-prod

# Rollback to specific revision
argocd app rollback api-gateway-prod <revision>

# Or via Git
git revert <commit>
git push
# ArgoCD will auto-sync (or manual sync for prod)
```

## Monitoring

### Application Status

```bash
argocd app list
argocd app get api-gateway-dev
```

### Health Status

- **Healthy** — все ресурсы работают
- **Progressing** — деплой в процессе
- **Degraded** — часть ресурсов не работает
- **Suspended** — приложение приостановлено

### Sync Status

- **Synced** — кластер соответствует Git
- **OutOfSync** — есть расхождения
- **Unknown** — статус неизвестен

## Troubleshooting

### Application stuck in Progressing

```bash
# Check events
argocd app get <app-name> --show-operation

# Check pod logs
kubectl logs -n <namespace> -l app=<service-name>
```

### Sync failed

```bash
# Check diff
argocd app diff <app-name>

# Force sync
argocd app sync <app-name> --force
```

### ArgoCD can't access repository

```bash
# Check repo connection
argocd repo list

# Test repository
argocd repo get https://gitlab.com/your-group/gitops-poc.git
```
