# Access Management & RACI Matrix

Управление доступами для GitOps платформы с учетом принципа least privilege.

## Содержание

- [Роли в организации](#роли-в-организации)
- [Компоненты доступа](#компоненты-доступа)
- [RACI Matrix](#raci-matrix)
- [GitLab Access Model](#gitlab-access-model)
- [Kubernetes RBAC](#kubernetes-rbac)
- [Vault Policies](#vault-policies)
- [ArgoCD RBAC](#argocd-rbac)
- [Monitoring Access](#monitoring-access)
- [Audit & Compliance](#audit--compliance)

---

## Роли в организации

| Роль | Описание | Типичные задачи |
|------|----------|-----------------|
| **Developer** | Разработчик в команде | Код, unit-тесты, MR, debug в dev |
| **Tech Lead** | Технический лидер команды | Code review, merge, архитектура, on-call |
| **Maintainer** | Владелец сервиса/компонента | Release decisions, breaking changes |
| **SRE/Platform** | Site Reliability / Platform Engineer | Инфраструктура, prod access, incidents |
| **Security** | Security Engineer | Audit, policies, vulnerability management |
| **Manager/PO** | Product Owner / Engineering Manager | Visibility, metrics, не техн. доступ |

---

## Компоненты доступа

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ACCESS CONTROL LAYERS                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │   GitLab     │  │  Kubernetes  │  │    Vault     │  │   ArgoCD     │ │
│  │              │  │              │  │              │  │              │ │
│  │ • Repos      │  │ • Namespaces │  │ • Policies   │  │ • Projects   │ │
│  │ • Groups     │  │ • RBAC       │  │ • Auth       │  │ • Apps       │ │
│  │ • CI/CD vars │  │ • Secrets    │  │ • Audit      │  │ • Sync       │ │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘ │
│                                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                   │
│  │  Monitoring  │  │   Logging    │  │   Registry   │                   │
│  │              │  │              │  │              │                   │
│  │ • Grafana    │  │ • Loki/ELK   │  │ • Pull/Push  │                   │
│  │ • Alerts     │  │ • Audit logs │  │ • Scan       │                   │
│  └──────────────┘  └──────────────┘  └──────────────┘                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## RACI Matrix

### Legend

- **R** = Responsible (выполняет работу)
- **A** = Accountable (отвечает за результат, только один на задачу)
- **C** = Consulted (консультируют до выполнения)
- **I** = Informed (информируют после выполнения)

### Development Operations

| Операция | Developer | Tech Lead | Maintainer | SRE/Platform | Security |
|----------|:---------:|:---------:|:----------:|:------------:|:--------:|
| **Code commit** | R | I | I | - | - |
| **Create MR** | R | I | I | - | - |
| **Code review** | C | R | A | C | C |
| **Merge to main** | - | R | A | I | I |
| **Hotfix (urgent)** | R | A | I | C | I |

### CI/CD Operations

| Операция | Developer | Tech Lead | Maintainer | SRE/Platform | Security |
|----------|:---------:|:---------:|:----------:|:------------:|:--------:|
| **Docker image build** | R | I | I | I | - |
| **Update .cicd/dev.yaml** | R | I | I | I | - |
| **Update .cicd/staging.yaml** | C | R | A | I | I |
| **Update .cicd/prod.yaml** | - | C | A | R | C |
| **CI pipeline config** | C | R | A | C | C |

### Deployment Operations

| Операция | Developer | Tech Lead | Maintainer | SRE/Platform | Security |
|----------|:---------:|:---------:|:----------:|:------------:|:--------:|
| **Deploy to dev** | R | I | I | I | - |
| **Deploy to staging** | I | R | A | I | I |
| **Deploy to prod** | - | C | A | R | I |
| **Rollback dev** | R | I | I | I | - |
| **Rollback staging** | C | R | A | I | I |
| **Rollback prod** | - | C | A | R | I |
| **Emergency rollback prod** | - | I | I | R/A | I |

### Secret Management

| Операция | Developer | Tech Lead | Maintainer | SRE/Platform | Security |
|----------|:---------:|:---------:|:----------:|:------------:|:--------:|
| **Request new secret** | R | A | I | I | C |
| **Create dev secret** | - | R | A | I | I |
| **Create staging secret** | - | C | A | R | C |
| **Create prod secret** | - | - | C | R | A |
| **Rotate secrets** | - | I | I | R | A |
| **Audit secret access** | - | I | I | C | R/A |

### Infrastructure Operations

| Операция | Developer | Tech Lead | Maintainer | SRE/Platform | Security |
|----------|:---------:|:---------:|:----------:|:------------:|:--------:|
| **gitops-config changes** | - | C | C | R | A |
| **platform-bootstrap update** | - | C | C | R | A |
| **New service onboarding** | C | R | A | C | C |
| **Namespace creation** | - | C | C | R | A |
| **Network policy changes** | - | C | C | R | A |
| **Vault policy changes** | - | C | C | R | A |

### Incident Response

| Операция | Developer | Tech Lead | Maintainer | SRE/Platform | Security |
|----------|:---------:|:---------:|:----------:|:------------:|:--------:|
| **Incident detection** | I | I | I | R | I |
| **Initial triage** | C | C | C | R/A | C |
| **Root cause analysis** | R | R | A | R | C |
| **Incident resolution** | R | R | A | R | C |
| **Post-mortem** | C | R | A | R | C |
| **Security incident** | I | C | C | R | A |

---

## GitLab Access Model

### Group Structure

```
gitlab.com/your-org/
├── platform/                    # Platform team only
│   ├── gitops-config/          # Maintainer: Platform, Guest: All
│   └── infrastructure/         # Maintainer: Platform only
│
├── services/                    # Service teams
│   ├── service-a/              # Team A access
│   ├── service-b/              # Team B access
│   └── shared-libs/            # Maintainer: Leads, Developer: All
│
└── api/                         # Proto definitions
    ├── proto/                   # Developer: All (propose changes)
    └── gen/                     # Read-only (auto-generated)
```

### Role Mapping

| GitLab Role | Capabilities | Assigned To |
|-------------|--------------|-------------|
| **Guest** | View code, create issues | Managers, PO |
| **Reporter** | + Clone, download | External stakeholders |
| **Developer** | + Push to branches, create MR | Developers |
| **Maintainer** | + Merge to protected, manage CI/CD | Tech Leads, Maintainers |
| **Owner** | + Delete repo, manage members | Platform team |

### Protected Branches

```yaml
# Каждый service repo
main:
  allowed_to_push: Maintainers
  allowed_to_merge: Maintainers
  require_code_owner_approval: true

# gitops-config repo (stricter)
main:
  allowed_to_push: No one
  allowed_to_merge: Maintainers (Platform team only)
  require_code_owner_approval: true
  required_approvals: 2
```

### CODEOWNERS

```
# services/service-a/CODEOWNERS
*                    @team-a-leads
.cicd/prod.yaml      @team-a-leads @sre-team
.gitlab-ci.yml       @team-a-leads @platform-team

# gitops-config/CODEOWNERS
*                    @platform-team
charts/              @platform-team @security-team
```

### CI/CD Variables Access

| Variable | Scope | Protected | Masked | Who Can Modify |
|----------|-------|-----------|--------|----------------|
| `CI_PUSH_TOKEN` | Group | No | Yes | Platform team |
| `ARGOCD_AUTH_TOKEN` | Group | Yes | Yes | Platform team |
| `SENTRY_DSN` | Project | No | Yes | Tech Lead |
| `PROD_*` | Project | Yes | Yes | Platform + Security |

---

## Kubernetes RBAC

### Namespace Access Matrix

| Role | dev namespace | staging namespace | prod namespace |
|------|:-------------:|:-----------------:|:--------------:|
| **Developer** | edit | view | - |
| **Tech Lead** | admin | edit | view |
| **Maintainer** | admin | admin | view |
| **SRE/Platform** | cluster-admin | cluster-admin | cluster-admin |
| **Security** | view (all) | view (all) | view (all) |

### ClusterRoles

```yaml
# Developer role - dev namespace only
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec", "services", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/exec", "pods/portforward"]
    verbs: ["create"]  # Debug access
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
---
# Tech Lead role - extended
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tech-lead
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services", "configmaps", "secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/exec", "pods/portforward"]
    verbs: ["create"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets"]
    verbs: ["get", "list", "watch", "patch"]  # Can scale
  - apiGroups: ["argoproj.io"]
    resources: ["applications"]
    verbs: ["get", "list", "watch", "sync"]  # Can trigger sync
```

### RoleBindings per Environment

```yaml
# Dev environment - developers have edit access
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developers-edit
  namespace: poc-dev
subjects:
  - kind: Group
    name: developers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit
  apiGroup: rbac.authorization.k8s.io
---
# Staging - developers view only
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developers-view
  namespace: poc-staging
subjects:
  - kind: Group
    name: developers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
---
# Prod - no developer access, only SRE
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: sre-admin
  namespace: poc-prod
subjects:
  - kind: Group
    name: sre-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
```

---

## Vault Policies

### Policy Hierarchy

```
vault/
├── policies/
│   ├── admin                    # Full access (Platform team)
│   ├── sre                      # Prod read/write, all envs read
│   ├── tech-lead                # Staging write, dev write, prod read
│   ├── developer                # Dev read only (via app)
│   └── {service}-{env}          # Service account policies
```

### Policy Examples

```hcl
# Developer policy - read dev secrets only (usually not direct access)
path "secret/data/{{identity.entity.aliases.auth_kubernetes_*.metadata.service_account_namespace}}/*" {
  capabilities = ["read", "list"]
}

# Tech Lead policy
path "secret/data/+/+/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/data/+/+/staging/*" {
  capabilities = ["create", "read", "update", "list"]
}
path "secret/data/+/+/prod/*" {
  capabilities = ["read", "list"]
}

# SRE policy
path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "sys/policies/*" {
  capabilities = ["read", "list"]
}
path "auth/kubernetes/role/*" {
  capabilities = ["read", "list"]
}

# Admin policy (Platform team)
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
```

### Auth Methods

```yaml
# Kubernetes auth (for services)
auth/kubernetes/role/{service}-{env}:
  bound_service_account_names: ["{service}", "default"]
  bound_service_account_namespaces: ["poc-{env}"]
  policies: ["{namespace}-{env}-read"]
  ttl: 1h

# OIDC auth (for humans via GitLab)
auth/oidc/role/developer:
  bound_audiences: ["vault"]
  allowed_redirect_uris: ["https://vault.example.com/ui/vault/auth/oidc/callback"]
  user_claim: "email"
  groups_claim: "groups"
  policies: ["developer"]

auth/oidc/role/sre:
  # ... similar with sre policy
```

---

## ArgoCD RBAC

### Project Structure

```yaml
# ArgoCD Projects
projects:
  - name: platform
    description: Platform infrastructure
    sourceRepos: ["https://gitlab.com/org/platform/*"]
    destinations:
      - namespace: "*"
        server: "*"
    roles:
      - name: admin
        groups: ["platform-team"]
        policies:
          - p, proj:platform:admin, applications, *, platform/*, allow

  - name: services-dev
    description: Dev environment services
    sourceRepos: ["https://gitlab.com/org/services/*"]
    destinations:
      - namespace: "poc-dev"
        server: "https://kubernetes.default.svc"
    roles:
      - name: developer
        groups: ["developers"]
        policies:
          - p, proj:services-dev:developer, applications, get, services-dev/*, allow
          - p, proj:services-dev:developer, applications, sync, services-dev/*, allow
      - name: tech-lead
        groups: ["tech-leads"]
        policies:
          - p, proj:services-dev:tech-lead, applications, *, services-dev/*, allow

  - name: services-prod
    description: Prod environment services
    sourceRepos: ["https://gitlab.com/org/services/*"]
    destinations:
      - namespace: "poc-prod"
        server: "https://kubernetes.default.svc"
    roles:
      - name: sre
        groups: ["sre-team"]
        policies:
          - p, proj:services-prod:sre, applications, *, services-prod/*, allow
      - name: viewer
        groups: ["tech-leads", "developers"]
        policies:
          - p, proj:services-prod:viewer, applications, get, services-prod/*, allow
```

### RBAC ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    # Platform team - full access
    g, platform-team, role:admin

    # SRE - admin on all apps
    p, role:sre, applications, *, */*, allow
    p, role:sre, clusters, get, *, allow
    p, role:sre, repositories, *, *, allow
    g, sre-team, role:sre

    # Tech Leads - sync dev/staging, view prod
    p, role:tech-lead, applications, get, */*, allow
    p, role:tech-lead, applications, sync, *-dev/*, allow
    p, role:tech-lead, applications, sync, *-staging/*, allow
    p, role:tech-lead, applications, action, *-dev/*, allow
    p, role:tech-lead, applications, action, *-staging/*, allow
    g, tech-leads, role:tech-lead

    # Developers - view all, sync dev only
    p, role:developer, applications, get, */*, allow
    p, role:developer, applications, sync, *-dev/*, allow
    g, developers, role:developer

    # Read-only for everyone else
    p, role:readonly, applications, get, */*, allow
    p, role:readonly, logs, get, */*, allow
```

---

## Monitoring Access

### Grafana Roles

| Grafana Role | Capabilities | Assigned To |
|--------------|--------------|-------------|
| **Viewer** | View dashboards | All authenticated |
| **Editor** | + Create/edit dashboards | Tech Leads, SRE |
| **Admin** | + Manage users, datasources | Platform team |

### Grafana RBAC (Enterprise) / Teams

```yaml
# Team-based folder access
teams:
  - name: platform
    folders: ["Infrastructure", "Platform"]
    permission: Admin

  - name: service-team-a
    folders: ["Service A"]
    permission: Editor

  - name: developers
    folders: ["*"]
    permission: Viewer
```

### Alert Notification Routing

```yaml
# AlertManager routing
route:
  receiver: 'default'
  routes:
    # Prod alerts -> SRE + On-call
    - match:
        env: prod
        severity: critical
      receiver: 'sre-pagerduty'
      continue: true

    - match:
        env: prod
      receiver: 'sre-slack'

    # Staging alerts -> Tech Leads
    - match:
        env: staging
      receiver: 'tech-leads-slack'

    # Dev alerts -> Service team
    - match:
        env: dev
      receiver: 'dev-slack'
```

---

## Audit & Compliance

### What to Audit

| System | Audit Events | Retention |
|--------|--------------|-----------|
| **GitLab** | Push, merge, CI runs, permission changes | 1 year |
| **Kubernetes** | All mutating API calls, exec, secrets access | 90 days |
| **Vault** | All auth, secret access, policy changes | 1 year |
| **ArgoCD** | Sync, rollback, settings changes | 90 days |

### Kubernetes Audit Policy

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log all secrets access at Metadata level
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets"]

  # Log pod exec at RequestResponse level
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["pods/exec", "pods/attach"]

  # Log all changes to RBAC
  - level: RequestResponse
    resources:
      - group: "rbac.authorization.k8s.io"
        resources: ["*"]
```

### Compliance Checklist

- [ ] All prod access requires MFA
- [ ] No shared accounts
- [ ] Service accounts have minimal permissions
- [ ] Secrets rotated every 90 days
- [ ] Access reviews quarterly
- [ ] Audit logs exported to SIEM
- [ ] Break-glass procedures documented

---

## Implementation Checklist

### Phase 1: GitLab Setup

- [ ] Create group structure (platform, services, api)
- [ ] Configure protected branches on all repos
- [ ] Add CODEOWNERS files
- [ ] Set up CI/CD variables at group level
- [ ] Configure member roles per group

### Phase 2: Kubernetes RBAC

- [ ] Create ClusterRoles (developer, tech-lead, sre)
- [ ] Create RoleBindings per namespace
- [ ] Configure OIDC/LDAP integration
- [ ] Test access with each role
- [ ] Enable audit logging

### Phase 3: Vault Policies

- [ ] Create policy hierarchy
- [ ] Configure Kubernetes auth
- [ ] Configure OIDC auth for humans
- [ ] Test service account access
- [ ] Test human access via UI/CLI

### Phase 4: ArgoCD RBAC

- [ ] Create projects per environment
- [ ] Configure RBAC ConfigMap
- [ ] Test sync permissions
- [ ] Integrate with OIDC

### Phase 5: Monitoring

- [ ] Configure Grafana teams/folders
- [ ] Set up AlertManager routing
- [ ] Test notification delivery
- [ ] Document escalation paths

---

## Quick Reference: Who Can Do What

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ACCESS QUICK REFERENCE                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  DEVELOPER          TECH LEAD           SRE/PLATFORM        SECURITY        │
│  ──────────         ─────────           ────────────        ────────        │
│  • Code & MR        • + Merge           • + Prod deploy     • Audit all     │
│  • Deploy dev       • + Deploy stg      • + Infra changes   • Policy approve│
│  • View staging     • + Secrets stg     • + All secrets     • Vuln mgmt     │
│  • Debug dev pods   • + ArgoCD sync     • + Break-glass     • Compliance    │
│                     • + Scale pods                                           │
│                                                                              │
│  GitLab: Developer  GitLab: Maintainer  GitLab: Owner       GitLab: Auditor │
│  K8s dev: edit      K8s dev: admin      K8s: cluster-admin  K8s: view       │
│  K8s stg: view      K8s stg: edit       Vault: admin        Vault: audit    │
│  K8s prod: -        K8s prod: view      ArgoCD: admin       ArgoCD: readonly│
│  Vault: read dev    Vault: write stg                                         │
│  ArgoCD: sync dev   ArgoCD: sync stg                                         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```
