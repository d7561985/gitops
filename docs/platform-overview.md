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
│  Управление: ArgoCD + Git                                              │
└─────────────────────────────────────────────────────────────────────────┘
                                   ▲
                                   │ Sync
                                   │
┌─────────────────────────────────────────────────────────────────────────┐
│                    Layer 3: Platform Services                           │
│  ArgoCD Apps → Vault, Monitoring, CloudFlare Tunnel                    │
│  Управление: ArgoCD + Helm Charts                                      │
└─────────────────────────────────────────────────────────────────────────┘
                                   ▲
                                   │ ArgoCD
                                   │
┌─────────────────────────────────────────────────────────────────────────┐
│                    Layer 2: Layer-0 (Infrastructure)                    │
│  Cilium CNI, Gateway API, cert-manager, external-dns, ArgoCD           │
│  Управление: ArgoCD layer-0 (self-manage)                              │
└─────────────────────────────────────────────────────────────────────────┘
                                   ▲
                                   │ ONE-TIME Bootstrap
                                   │
┌─────────────────────────────────────────────────────────────────────────┐
│                    Layer 1: Bootstrap                                   │
│  kubectl apply -k shared/bootstrap/ (Cilium, Gateway API CRDs, ArgoCD) │
│  Управление: kubectl (один раз)                                        │
└─────────────────────────────────────────────────────────────────────────┘
                                   ▲
                                   │ Provision
                                   │
┌─────────────────────────────────────────────────────────────────────────┐
│                Layer 0: Infrastructure (Talos Linux)                    │
│  VMs/Containers, Networks, Storage                                     │
│  Управление: talosctl (вручную)                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

## Инструменты по слоям

| Слой | Инструмент | Ресурсы |
|------|-----------|---------|
| **Layer 0** | talosctl | Talos ноды, machine config |
| **Layer 1** | kubectl apply -k | Bootstrap: Cilium, Gateway API, ArgoCD |
| **Layer 2** | ArgoCD layer-0 | Cilium, cert-manager, external-dns, ArgoCD self-manage |
| **Layer 3** | ArgoCD | Vault, Monitoring, CloudFlare Tunnel |
| **Layer 4** | ArgoCD ApplicationSets | Микросервисы, приложения |

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
- **Self-manage** — ArgoCD управляет собой через layer-0

### Layer-0 (ArgoCD)

Infrastructure management via GitOps:

- **Gateway API CRDs** (wave -100)
- **Cilium** (wave -99)
- **cert-manager** (wave -98)
- **external-dns** (wave -97)
- **ArgoCD self-manage** (wave -96)

### Vault

Secrets management:

- **Vault Secrets Operator** — автосинхронизация в Kubernetes Secrets
- **Kubernetes Auth** — аутентификация через ServiceAccount
- **Dynamic Secrets** — ротация секретов

## Потоки данных

### Bootstrap Flow

```
talosctl cluster create
         │
         ▼
   Talos Nodes Ready (no CNI)
         │
         ▼
kubectl apply -k shared/bootstrap/
         │
         ├── Gateway API CRDs
         ├── Cilium CNI
         └── ArgoCD
                │
                ▼
kubectl apply -f bootstrap-app.yaml
                │
                ▼
         ArgoCD syncs layer-0
                │
                ├── Cilium (takes over from bootstrap)
                ├── cert-manager
                ├── external-dns
                └── ArgoCD (self-manage)
                        │
                        ▼
                 Platform Apps
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
