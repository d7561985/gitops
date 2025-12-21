# Team Model & Responsibilities

## Обзор

Данный документ описывает модель команд в платформе: роли, ответственности и взаимодействие между Platform Team и Product Teams.

---

## Эволюция модели

### Традиционная модель (Dev + Ops)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     TRADITIONAL MODEL                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Development Team              Wall of Confusion              Ops Team  │
│  ────────────────              ─────────────────              ────────  │
│                                                                          │
│  ┌─────────────────┐          ┌─────────────┐          ┌─────────────┐ │
│  │                 │          │             │          │             │ │
│  │  • Write code   │  ─────►  │  "Deploy    │  ─────►  │ • kubectl   │ │
│  │  • Run tests    │          │   this!"    │          │ • helm      │ │
│  │  • Build image  │          │             │          │ • secrets   │ │
│  │                 │          │  Ticket     │          │ • config    │ │
│  └─────────────────┘          └─────────────┘          └─────────────┘ │
│                                                                          │
│  Problems:                                                               │
│  • Slow handoffs                                                         │
│  • Knowledge silos                                                       │
│  • Blame culture                                                         │
│  • Ops bottleneck                                                        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Платформенная модель (You Build It, You Run It)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PLATFORM MODEL                                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                    CROSS-FUNCTIONAL PRODUCT TEAMS                   ││
│  │                                                                      ││
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              ││
│  │  │  Team A      │  │  Team B      │  │  Team C      │              ││
│  │  │              │  │              │  │              │              ││
│  │  │  Full        │  │  Full        │  │  Full        │              ││
│  │  │  Ownership:  │  │  Ownership:  │  │  Ownership:  │              ││
│  │  │              │  │              │  │              │              ││
│  │  │ • Code       │  │ • Code       │  │ • Code       │              ││
│  │  │ • .cicd/     │  │ • .cicd/     │  │ • .cicd/     │              ││
│  │  │ • Secrets    │  │ • Secrets    │  │ • Secrets    │              ││
│  │  │ • Deploy dev │  │ • Deploy dev │  │ • Deploy dev │              ││
│  │  │ • Monitoring │  │ • Monitoring │  │ • Monitoring │              ││
│  │  │ • On-call    │  │ • On-call    │  │ • On-call    │              ││
│  │  │              │  │              │  │              │              ││
│  │  └──────────────┘  └──────────────┘  └──────────────┘              ││
│  │                                                                      ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│                              ▲ Self-Service                             │
│                              │                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                      PLATFORM TEAM                                   ││
│  │                                                                      ││
│  │  Provides:                        Maintains:                        ││
│  │  ─────────                        ──────────                        ││
│  │  • k8app Helm chart               • Kubernetes cluster             ││
│  │  • CI/CD templates                • Cilium/Gateway API             ││
│  │  • platform-bootstrap             • Vault/ArgoCD                   ││
│  │  • Proto generation               • Monitoring stack               ││
│  │  • Documentation                  • Security policies              ││
│  │  • Training                       • Cost optimization              ││
│  │                                                                      ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источник:** [`docs/embodiment/access-management.md`](../docs/embodiment/access-management.md)

---

## Роли в организации

### Определения ролей

| Роль | Описание | Типичные задачи |
|------|----------|-----------------|
| **Developer** | Разработчик в продуктовой команде | Код, unit-тесты, MR, debug в dev |
| **Tech Lead** | Технический лидер команды | Code review, merge, архитектура, on-call |
| **Maintainer** | Владелец сервиса/компонента | Release decisions, breaking changes |
| **SRE/Platform** | Site Reliability / Platform Engineer | Инфраструктура, prod access, incidents |
| **Security** | Security Engineer | Audit, policies, vulnerability management |
| **Manager/PO** | Product Owner / Engineering Manager | Visibility, metrics, не техн. доступ |

**Источник:** [`docs/embodiment/access-management.md:19-30`](../docs/embodiment/access-management.md)

---

## RACI Matrix

### Легенда

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

**Источник:** [`docs/embodiment/access-management.md:59-133`](../docs/embodiment/access-management.md)

---

## Access Control

### GitLab Access Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     GITLAB GROUP STRUCTURE                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  gitlab.com/your-org/                                                    │
│  ├── platform/                    ← Platform team only                  │
│  │   ├── gitops-config/          ← Maintainer: Platform, Guest: All    │
│  │   └── infrastructure/         ← Maintainer: Platform only           │
│  │                                                                       │
│  ├── services/                    ← Service teams                       │
│  │   ├── service-a/              ← Team A access                       │
│  │   ├── service-b/              ← Team B access                       │
│  │   └── shared-libs/            ← Maintainer: Leads, Developer: All   │
│  │                                                                       │
│  └── api/                         ← Proto definitions                   │
│      ├── proto/                   ← Developer: All (propose changes)   │
│      └── gen/                     ← Read-only (auto-generated)          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### GitLab Role Mapping

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

**Источник:** [`docs/embodiment/access-management.md:136-203`](../docs/embodiment/access-management.md)

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

### ClusterRoles Example

```yaml
# Developer role - dev namespace only
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/exec", "pods/portforward"]
    verbs: ["create"]  # Debug access
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
```

**Источник:** [`docs/embodiment/access-management.md:206-304`](../docs/embodiment/access-management.md)

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
```

**Источник:** [`docs/embodiment/access-management.md:306-378`](../docs/embodiment/access-management.md)

---

## ArgoCD RBAC

### Project Structure

```yaml
projects:
  - name: platform
    description: Platform infrastructure
    roles:
      - name: admin
        groups: ["platform-team"]
        policies:
          - p, proj:platform:admin, applications, *, platform/*, allow

  - name: services-dev
    description: Dev environment services
    roles:
      - name: developer
        groups: ["developers"]
        policies:
          - p, proj:services-dev:developer, applications, get, services-dev/*, allow
          - p, proj:services-dev:developer, applications, sync, services-dev/*, allow

  - name: services-prod
    description: Prod environment services
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

**Источник:** [`docs/embodiment/access-management.md:380-433`](../docs/embodiment/access-management.md)

---

## Monitoring Access

### Grafana Roles

| Grafana Role | Capabilities | Assigned To |
|--------------|--------------|-------------|
| **Viewer** | View dashboards | All authenticated |
| **Editor** | + Create/edit dashboards | Tech Leads, SRE |
| **Admin** | + Manage users, datasources | Platform team |

### Alert Routing

```yaml
# AlertManager routing
route:
  routes:
    # Prod alerts → SRE + On-call
    - match:
        env: prod
        severity: critical
      receiver: 'sre-pagerduty'

    # Staging alerts → Tech Leads
    - match:
        env: staging
      receiver: 'tech-leads-slack'

    # Dev alerts → Service team
    - match:
        env: dev
      receiver: 'dev-slack'
```

**Источник:** [`docs/embodiment/access-management.md:476-530`](../docs/embodiment/access-management.md)

---

## Quick Reference

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

---

## Platform Team Responsibilities

### What Platform Team Provides

| Category | Components |
|----------|------------|
| **Infrastructure** | Kubernetes, Cilium, Vault, ArgoCD |
| **Templates** | k8app chart, CI/CD templates, service-repo template |
| **Automation** | platform-bootstrap, proto generation |
| **Observability** | Prometheus, Grafana, Hubble |
| **Documentation** | PREFLIGHT-CHECKLIST, new-service-guide |
| **Support** | Training, troubleshooting, consulting |

### What Platform Team Does NOT Do

| Action | Responsible |
|--------|-------------|
| Write application code | Product Teams |
| Configure .cicd/ for services | Product Teams |
| Create Vault secrets (dev/staging) | Tech Leads |
| Troubleshoot application bugs | Product Teams |
| Deploy to dev environment | Product Teams |

---

## Product Team Responsibilities

### Full Ownership

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PRODUCT TEAM OWNERSHIP                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Code:                                                                   │
│  ─────                                                                   │
│  • Application code                                                      │
│  • Unit tests, integration tests                                         │
│  • Dockerfile                                                            │
│                                                                          │
│  Configuration:                                                          │
│  ──────────────                                                          │
│  • .cicd/default.yaml - service configuration                           │
│  • .cicd/dev.yaml, staging.yaml - environment overrides                 │
│  • Vault secrets (via UI or CLI)                                        │
│                                                                          │
│  Operations:                                                             │
│  ───────────                                                             │
│  • Deploy to dev (via git push)                                         │
│  • Rollback own services                                                 │
│  • Monitor dashboards                                                    │
│  • On-call for own services                                             │
│                                                                          │
│  API:                                                                    │
│  ────                                                                    │
│  • Proto definitions                                                     │
│  • Breaking change management                                            │
│  • API documentation                                                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Collaboration Model

### Shared Responsibilities

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     COLLABORATION MODEL                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Production Deployments:                                                 │
│  ───────────────────────                                                 │
│  • Product Team: Prepares, tests, creates MR                            │
│  • SRE/Platform: Approves, monitors, rollback if needed                 │
│                                                                          │
│  Infrastructure Changes:                                                 │
│  ────────────────────────                                                │
│  • Product Team: Requests via issue                                     │
│  • Platform Team: Implements, reviews, deploys                          │
│  • Security: Reviews for compliance                                     │
│                                                                          │
│  Incidents:                                                              │
│  ──────────                                                              │
│  • SRE/Platform: Initial triage, infrastructure issues                  │
│  • Product Team: Application issues, root cause analysis                │
│  • Both: Post-mortem, prevention                                        │
│                                                                          │
│  New Service Onboarding:                                                 │
│  ────────────────────────                                                │
│  • Product Team: Creates repo, configures .cicd/                        │
│  • Platform Team: Adds to platform-bootstrap, creates Vault paths       │
│  • Both: Validate deployment                                             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Guidelines для Platform Team

### Принципы развития архитектуры

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PLATFORM EVOLUTION PRINCIPLES                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. BACKWARDS COMPATIBILITY                                              │
│  ──────────────────────────                                              │
│  • Изменения в k8app НЕ должны ломать существующие .cicd/ конфиги      │
│  • Deprecation warnings минимум за 1 версию                             │
│  • Semantic versioning: MAJOR.MINOR.PATCH                               │
│                                                                          │
│  2. SELF-SERVICE FIRST                                                   │
│  ─────────────────────                                                   │
│  • Любая новая функциональность должна быть self-service                │
│  • Если нужно ручное действие — это технический долг                   │
│  • Цель: 0 тикетов на стандартные операции                             │
│                                                                          │
│  3. ABSTRACTION OVER COMPLEXITY                                          │
│  ─────────────────────────────                                           │
│  • k8app абстрагирует K8s complexity                                    │
│  • platform-bootstrap абстрагирует platform setup                       │
│  • Разработчик видит только values файлы                               │
│                                                                          │
│  4. AUTOMATION MULTIPLIER                                                │
│  ────────────────────────                                                │
│  • Каждое улучшение должно умножать эффективность                      │
│  • Автоматизация > документация > ручной процесс                       │
│  • DRY: template once, use everywhere                                   │
│                                                                          │
│  5. OBSERVABILITY BY DEFAULT                                             │
│  ───────────────────────────                                             │
│  • Новые компоненты должны экспортировать метрики                      │
│  • ServiceMonitor/PodMonitor создаются автоматически                   │
│  • Grafana dashboards как часть поставки                               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Roadmap развития

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PLATFORM EVOLUTION ROADMAP                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  MULTIPLIER OPPORTUNITIES                                                │
│  ────────────────────────                                                │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ k8app Extensions                                                  │   │
│  │ • Auto-scaling policies (HPA based on custom metrics)           │   │
│  │ • Circuit breaker patterns                                        │   │
│  │ • Canary deployments                                              │   │
│  │ • A/B testing infrastructure                                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ platform-bootstrap Extensions                                     │   │
│  │ • Auto-provision new brands (namespacePrefix)                    │   │
│  │ • Cost allocation per namespace                                   │   │
│  │ • Automated backup policies per env                              │   │
│  │ • Disaster recovery automation                                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Observability Extensions                                          │   │
│  │ • Distributed tracing (OpenTelemetry)                            │   │
│  │ • SLO/SLI dashboards                                              │   │
│  │ • Automated anomaly detection                                     │   │
│  │ • Cost per request metrics                                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Checklist для добавления новой функциональности

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     NEW PLATFORM FEATURE CHECKLIST                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  DESIGN                                                                  │
│  ──────                                                                  │
│  [ ] Self-service: разработчик активирует через values.yaml            │
│  [ ] Backwards compatible: существующие конфиги работают               │
│  [ ] Документация: guide в docs/ + пример в templates/                 │
│                                                                          │
│  IMPLEMENTATION                                                          │
│  ──────────────                                                          │
│  [ ] Template добавлен в k8app или platform-bootstrap                  │
│  [ ] Default values разумные (convention over configuration)           │
│  [ ] Feature flag (enabled: true/false)                                │
│                                                                          │
│  OBSERVABILITY                                                           │
│  ─────────────                                                           │
│  [ ] Метрики экспортируются                                             │
│  [ ] ServiceMonitor/PrometheusRule если нужно                          │
│  [ ] Grafana dashboard (если визуализация полезна)                     │
│                                                                          │
│  TESTING                                                                 │
│  ───────                                                                 │
│  [ ] Протестировано на dev environment                                  │
│  [ ] Проверена совместимость с существующими сервисами                 │
│  [ ] Rollback протестирован                                             │
│                                                                          │
│  ROLLOUT                                                                 │
│  ───────                                                                 │
│  [ ] CHANGELOG обновлён                                                 │
│  [ ] Version bumped (semantic versioning)                               │
│  [ ] Анонс командам (если breaking change)                              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Maintenance Guidelines

| Компонент | Частота обновлений | Ответственность |
|-----------|-------------------|-----------------|
| **k8app chart** | По необходимости | Platform Team |
| **platform-bootstrap** | При добавлении сервисов/environments | Platform Team |
| **Cilium** | Quarterly + security patches | Platform Team |
| **ArgoCD** | Quarterly | Platform Team |
| **Vault** | Quarterly + security patches | Platform Team |
| **kube-prometheus** | Quarterly | Platform Team |

---

## Audit & Compliance

### What to Audit

| System | Audit Events | Retention |
|--------|--------------|-----------|
| **GitLab** | Push, merge, CI runs, permission changes | 1 year |
| **Kubernetes** | All mutating API calls, exec, secrets access | 90 days |
| **Vault** | All auth, secret access, policy changes | 1 year |
| **ArgoCD** | Sync, rollback, settings changes | 90 days |

### Compliance Checklist

- [ ] All prod access requires MFA
- [ ] No shared accounts
- [ ] Service accounts have minimal permissions
- [ ] Secrets rotated every 90 days
- [ ] Access reviews quarterly
- [ ] Audit logs exported to SIEM
- [ ] Break-glass procedures documented

**Источник:** [`docs/embodiment/access-management.md:533-579`](../docs/embodiment/access-management.md)

---

## Связанные документы

- [Executive Summary](./00-executive-summary.md)
- [Platform Architecture](./01-platform-architecture.md)
- [Developer Experience](./03-developer-experience.md)

---

*Документ создан на основе аудита кодовой базы GitOps POC*
*Дата: 2025-12-21*
