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
├── vault-secret.yaml   # Vault secrets configuration
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

## Vault Secrets

Apply `vault-secret.yaml` after:
1. Vault is configured with KV v2 secrets engine
2. Kubernetes auth is enabled
3. Policy and role are created for this service
4. Service namespace exists

```bash
# Create secrets in Vault
vault kv put secret/gitops-poc/{{SERVICE_NAME}}/dev/config \
  API_KEY="dev-secret" \
  DB_PASSWORD="dev-password"

# Apply VaultStaticSecret
kubectl apply -f vault-secret.yaml
```
