# Push-Based GitOps with GitLab Agent

## Overview

Push-based GitOps использует GitLab CI/CD pipeline для деплоя в кластер через GitLab Agent.

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   GitLab    │      │   GitLab    │      │  Kubernetes │
│ Repository  │ ───► │   Runner    │ ───► │   Cluster   │
│             │      │  (CI/CD)    │      │  (Agent)    │
└─────────────┘      └─────────────┘      └─────────────┘
     Push               Execute             Apply
```

## Advantages

- **Immediate deployment** — деплой происходит сразу при push
- **Pipeline visibility** — полная видимость в GitLab CI/CD
- **Conditional deployments** — гибкие правила деплоя
- **Easy debugging** — логи pipeline доступны в GitLab

## Disadvantages

- **No drift detection** — не обнаруживает изменения в кластере
- **Pipeline dependency** — если pipeline сломан, деплой невозможен
- **Security** — требует хранения credentials в GitLab

## Setup

### 1. Register GitLab Agent

```bash
# В GitLab UI:
# Project → Infrastructure → Kubernetes clusters → Connect a cluster
# Выбрать имя агента (например: minikube-agent)
# Скопировать токен
```

### 2. Install Agent in Cluster

```bash
export GITLAB_AGENT_TOKEN="<token-from-step-1>"
./infrastructure/gitlab-agent/setup.sh
```

### 3. Configure Agent Access

Create `.gitlab/agents/minikube-agent/config.yaml` in your repository:

```yaml
ci_access:
  projects:
    - id: your-group/your-project
```

### 4. Use Pipeline Template

Copy `.gitlab-ci.yml` to your service repository and customize:

```yaml
variables:
  SERVICE_NAME: "your-service"
  KUBE_CONTEXT: "your-group/gitops-poc:minikube-agent"
```

## Deployment Flow

```
1. Developer pushes code
2. GitLab CI triggers pipeline
3. Pipeline validates Helm templates
4. Dev deployment (automatic)
5. Staging deployment (manual trigger)
6. Production deployment (manual approval)
```

## Rollback

```bash
# Via Helm
helm rollback <service-name> <revision> -n <namespace>

# Via Git revert
git revert <commit-sha>
git push
# Pipeline will redeploy previous version
```

## Troubleshooting

### Agent not connecting

```bash
kubectl logs -n gitlab-agent -l app=gitlab-agent
```

### Pipeline can't access cluster

1. Check agent config in `.gitlab/agents/<agent-name>/config.yaml`
2. Verify `ci_access.projects` includes your project
3. Wait 1-2 minutes for config propagation
