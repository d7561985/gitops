# Архитектура платформы

Обзор архитектуры Kubernetes платформы на базе Talos Linux.

## Принципы

1. **Immutable Infrastructure** — OS и конфигурация неизменны после деплоя
2. **Pure GitOps** — все K8s изменения через Git, ArgoCD синхронизирует состояние
3. **API-First** — управление только через API (Talos, Kubernetes)
4. **Reproducibility** — одинаковый результат на любой платформе

## Архитектурные слои

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Layer 4: Applications                            │
│  ArgoCD ApplicationSets → Services (api-gateway, frontend, etc.)       │
│  Управление: ArgoCD + Git (gitops-config)                              │
└─────────────────────────────────────────────────────────────────────────┘
                                   ▲
                                   │ ArgoCD Sync
                                   │
┌─────────────────────────────────────────────────────────────────────────┐
│                    Layer 1-3: Infrastructure                            │
│  Cilium, Gateway API, cert-manager, Vault, ArgoCD, Monitoring          │
│  Управление: setup-infrastructure.sh (Helm)                            │
└─────────────────────────────────────────────────────────────────────────┘
                                   ▲
                                   │ Helm install
                                   │
┌─────────────────────────────────────────────────────────────────────────┐
│                Layer 0: Talos Kubernetes Cluster                        │
│  VMs/Containers, etcd, K8s API                                         │
│  Управление: setup-talos.sh (talosctl)                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

## Инструменты по слоям

| Слой | Инструмент | Ресурсы |
|------|-----------|---------|
| **Layer 0** | `setup-talos.sh` | Talos кластер, kubeconfig |
| **Layer 1** | `setup-infrastructure.sh` | Gateway API CRDs, Cilium CNI |
| **Layer 2** | `setup-infrastructure.sh` | cert-manager, Vault + VSO |
| **Layer 3** | `setup-infrastructure.sh` | ArgoCD, Monitoring, External-DNS |
| **Layer 4** | ArgoCD | Applications (bootstrap-app.yaml → gitops-config)

## Компоненты

### Talos Linux

Минималистичная, immutable OS для Kubernetes:

- **12 бинарников** в системе (вместо тысяч в обычном Linux)
- **Нет SSH** — только API через talosctl
- **Неизменяемая файловая система** — read-only rootfs
- **API-driven** — все изменения через gRPC API

### Cilium CNI

eBPF-based сетевой стек:

- **Gateway API** — замена Ingress
- **kube-proxy replacement** — более эффективная маршрутизация
- **Hubble** — network observability
- **Network Policies** — L3/L4/L7 безопасность

### ArgoCD

GitOps controller:

- **App of Apps** — иерархия приложений
- **ApplicationSets** — генерация приложений из шаблонов
- **Sync Waves** — порядок деплоя
- **Layer 4 Only** — ArgoCD управляет только приложениями, не инфраструктурой

### Infrastructure (setup-infrastructure.sh)

Инфраструктура устанавливается скриптом (не через ArgoCD):

- **Gateway API CRDs** — API для ingress/routing
- **Cilium CNI** — eBPF-based сетевой стек
- **cert-manager** — автоматические TLS сертификаты
- **Vault + VSO** — управление секретами
- **ArgoCD** — GitOps controller
- **Monitoring** — Prometheus + Grafana

### Vault

Secrets management:

- **Vault Secrets Operator** — автосинхронизация в Kubernetes Secrets
- **Kubernetes Auth** — аутентификация через ServiceAccount
- **Dynamic Secrets** — ротация секретов

## Потоки данных

### Bootstrap Flow

```
./shared/scripts/setup-talos.sh
         │
         └── Talos cluster + kubeconfig (talosctl)
                │
                ▼
./shared/scripts/setup-infrastructure.sh
                │
                ├── Gateway API CRDs
                ├── Cilium CNI
                ├── cert-manager
                ├── Vault + VSO
                ├── ArgoCD
                ├── Monitoring
                └── External-DNS
                        │
                        ▼
kubectl apply -f bootstrap-app.yaml
                        │
                        ▼
                 ArgoCD syncs gitops-config
                        │
                        ├── platform-core
                        ├── service-groups
                        ├── preview-environments
                        └── ingress-cloudflare
                                │
                                ▼
                         Applications
```

### GitOps Flow

```
Developer → Git Push → GitLab/GitHub
                              │
                              ▼
                         ArgoCD Sync
                              │
                    ┌─────────┴─────────┐
                    │                   │
                    ▼                   ▼
           Helm Release          Raw Manifests
                    │                   │
                    └─────────┬─────────┘
                              │
                              ▼
                      Kubernetes API
                              │
                              ▼
                        Running Pods
```

## Поддерживаемые платформы

| Платформа | Использование | Особенности |
|-----------|---------------|-------------|
| **Docker** | Local Dev | Single-node, быстрый старт |
| **Bare Metal** | Homelab/Prod | Full control, VIP support |

## Сетевая архитектура

### Local (Docker)

```
┌─────────────────────────────────────────────┐
│                  macOS Host                  │
│  ┌─────────────────────────────────────────┐ │
│  │           Docker Container              │ │
│  │  ┌───────────────────────────────────┐  │ │
│  │  │         Talos Linux               │  │ │
│  │  │  ┌─────────────────────────────┐  │  │ │
│  │  │  │      Kubernetes             │  │  │ │
│  │  │  │  ┌───────┐  ┌───────┐      │  │  │ │
│  │  │  │  │Cilium │  │ Pods  │      │  │  │ │
│  │  │  │  └───────┘  └───────┘      │  │  │ │
│  │  │  └─────────────────────────────┘  │  │ │
│  │  └───────────────────────────────────┘  │ │
│  └─────────────────────────────────────────┘ │
│                     ▲                        │
│                     │ Port 6443              │
│                     ▼                        │
│               localhost:6443                 │
└─────────────────────────────────────────────┘
```

### Bare-Metal (Homelab)

```
                    Internet
                        │
                        ▼
               ┌────────────────┐
               │      VIP       │
               │   (Talos VIP)  │
               └───────┬────────┘
                       │
       ┌───────────────┼───────────────┐
       │               │               │
       ▼               ▼               ▼
  ┌─────────┐    ┌─────────┐    ┌─────────┐
  │ CP-1    │    │ CP-2    │    │ CP-3    │
  │ (Talos) │    │ (Talos) │    │ (Talos) │
  └────┬────┘    └────┬────┘    └────┬────┘
       │              │              │
       └──────────────┼──────────────┘
                      │
            Private Network (10.0.0.0/8)
                      │
       ┌──────────────┼──────────────┐
       │              │              │
       ▼              ▼              ▼
  ┌─────────┐   ┌─────────┐   ┌─────────┐
  │Worker-1 │   │Worker-2 │   │Worker-3 │
  │ (Talos) │   │ (Talos) │   │ (Talos) │
  └─────────┘   └─────────┘   └─────────┘
```

## Безопасность

### Talos Security

- **Нет SSH** — уменьшенная поверхность атаки
- **Read-only rootfs** — нельзя модифицировать систему
- **mTLS** — все коммуникации зашифрованы
- **Secure Boot** — поддержка (опционально)

### Kubernetes Security

- **Network Policies** — Cilium L3/L4/L7
- **Pod Security Standards** — enforced
- **Secrets Encryption** — at rest
- **RBAC** — role-based access control

### GitOps Security

- **Git as Source of Truth** — аудит всех изменений
- **ArgoCD RBAC** — контроль доступа к приложениям
- **Vault Integration** — secrets не в Git

## Масштабирование

### Horizontal Scaling

1. **Workers**: добавить ноды через talosctl
2. **Pods**: HPA/KEDA
3. **Multi-cluster**: Omni для управления

### Vertical Scaling

1. **Node size**: изменить server type
2. **Resources**: requests/limits в Helm values

## Обновления

### Talos Upgrade

```bash
# Rolling upgrade
talosctl upgrade --nodes <ip> --image ghcr.io/siderolabs/talos:v1.10.0
```

### Kubernetes Upgrade

Kubernetes версия привязана к Talos. При обновлении Talos обновляется и Kubernetes.

### Application Upgrades

Через ArgoCD:
1. Update Helm chart version в Git
2. ArgoCD автоматически синхронизирует

## Мониторинг

### Компоненты

- **Prometheus** — metrics collection
- **Grafana** — visualization
- **Hubble** — network flows
- **AlertManager** — alerting

### Ключевые метрики

- Node health (CPU, Memory, Disk)
- Pod health (Restarts, OOMKills)
- Network flows (Hubble)
- API server latency
- etcd health

## Связанные документы

- [Локальная разработка](./local-development.md)
- [Bare Metal деплой](./bare-metal-deployment.md)
