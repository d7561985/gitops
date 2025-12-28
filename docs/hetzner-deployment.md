# Деплой на Hetzner Cloud

Руководство по развёртыванию Kubernetes кластера на Hetzner Cloud.

> **Статус**: Hetzner provider ещё не реализован. Этот документ описывает планируемую архитектуру.

## Требования

### Аккаунт и токены

1. **Hetzner Cloud аккаунт** — [console.hetzner.cloud](https://console.hetzner.cloud)
2. **API Token** с Read/Write permissions
3. (Опционально) **CloudFlare API Token** для DNS

### Инструменты

- Все инструменты из [локальной разработки](./local-development.md)
- `hcloud` CLI (опционально)

```bash
brew install hcloud
```

## Архитектура

### Single-Node Dev

```
                    Internet
                        │
                        ▼
               ┌────────────────┐
               │   Hetzner LB   │
               │   (Optional)   │
               └───────┬────────┘
                       │
                       ▼
                 ┌─────────┐
                 │  CP-1   │
                 │ (cpx21) │
                 │ Talos   │
                 └─────────┘
```

### HA Production

```
                    Internet
                        │
                        ▼
               ┌────────────────┐
               │  Floating IP   │
               │  (API VIP)     │
               └───────┬────────┘
                       │
       ┌───────────────┼───────────────┐
       │               │               │
       ▼               ▼               ▼
  ┌─────────┐    ┌─────────┐    ┌─────────┐
  │ CP-1    │    │ CP-2    │    │ CP-3    │
  │ (cpx21) │    │ (cpx21) │    │ (cpx21) │
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
  │ (cpx31) │   │ (cpx31) │   │ (cpx31) │
  └─────────┘   └─────────┘   └─────────┘
```

## Конфигурация

### Pulumi Stack

```bash
cd shared/platform
pulumi stack init hetzner-dev
cp stacks/Pulumi.hetzner-dev.yaml Pulumi.hetzner-dev.yaml
```

### Настройка секретов

```bash
# Hetzner API Token
pulumi config set hcloud:token --secret

# (Опционально) CloudFlare для DNS
pulumi config set cloudflare:apiToken --secret
```

### Параметры кластера

```yaml
# Pulumi.hetzner-dev.yaml
config:
  talos-platform:clusterName: talos-hetzner-dev
  talos-platform:provider: hetzner
  talos-platform:talosVersion: v1.9.1

  hetzner:location: fsn1                    # Falkenstein
  hetzner:controlPlaneServerType: cpx21     # 3 vCPU, 4 GB RAM
  hetzner:workerServerType: cpx31           # 4 vCPU, 8 GB RAM
  hetzner:controlPlaneCount: 1              # 1 или 3 для HA
  hetzner:workerCount: 2
  hetzner:networkCidr: "10.0.0.0/8"
```

## Деплой

### 1. Preview изменений

```bash
pulumi preview
```

### 2. Применить

```bash
pulumi up
```

Это создаст:
1. Private Network
2. Floating IP (для HA)
3. Control Plane серверы
4. Worker серверы
5. Talos machine configuration
6. Bootstrap cluster
7. Install Cilium + ArgoCD

### 3. Получить kubeconfig

```bash
pulumi stack output kubeconfig --show-secrets > ~/.kube/config
kubectl get nodes
```

## Hetzner Cloud Controller Manager

CCM автоматически устанавливается через Talos patch (`shared/talos/patches/hetzner.yaml`):

- **LoadBalancer Services** → Hetzner Load Balancers
- **Node lifecycle** → автоматическое обновление node info
- **Zone labels** → proper scheduling

## Hetzner CSI Driver

Для persistent storage добавить в ArgoCD:

```yaml
# В platform-modules.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hcloud-csi
  namespace: argocd
spec:
  project: gitops-poc-dzha
  source:
    repoURL: https://charts.hetzner.cloud
    chart: hcloud-csi
    targetRevision: 2.5.1
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
```

## Networking

### Private Network

Все ноды в одной private network для:
- etcd communication
- Pod-to-pod traffic
- Reduced egress costs

### Floating IP

Для control plane HA:
- Один IP для API server
- Автоматический failover

### Firewall

Рекомендуемые правила:

| Port | Protocol | Source | Description |
|------|----------|--------|-------------|
| 6443 | TCP | Any | Kubernetes API |
| 50000 | TCP | Admin IPs | Talosctl |
| 443 | TCP | Any | HTTPS (Gateway) |
| 80 | TCP | Any | HTTP redirect |

## Стоимость

### Development (Single-Node)

| Ресурс | Тип | Стоимость/мес |
|--------|-----|---------------|
| Control Plane | CPX21 | ~€4.50 |
| **Total** | | **~€4.50** |

### Production (HA)

| Ресурс | Тип | Количество | Стоимость/мес |
|--------|-----|------------|---------------|
| Control Plane | CPX21 | 3 | ~€13.50 |
| Workers | CPX31 | 3 | ~€21.00 |
| Floating IP | | 1 | ~€3.00 |
| Load Balancer | LB11 | 1 | ~€5.00 |
| **Total** | | | **~€42.50** |

## Обновление

### Talos Upgrade

```bash
# Изменить версию в конфиге
pulumi config set talos-platform:talosVersion v1.10.0

# Применить (rolling upgrade)
pulumi up
```

### Worker Scaling

```bash
# Изменить количество workers
pulumi config set hetzner:workerCount 5

# Применить
pulumi up
```

## Мониторинг

После деплоя доступны:

- **Grafana**: через Gateway или port-forward
- **Prometheus**: metrics от всех компонентов
- **Hubble**: network observability

## Troubleshooting

### Сервер не бутится

```bash
# Проверить логи в Hetzner Console
hcloud server list
hcloud server logs <server-id>
```

### Talos не отвечает

```bash
# Использовать публичный IP
talosctl --nodes <public-ip> health --insecure
```

### CCM не работает

```bash
# Проверить секрет с токеном
kubectl get secret hcloud -n kube-system

# Проверить логи
kubectl logs -n kube-system -l app=hcloud-cloud-controller-manager
```

## Удаление

```bash
# Удалить все ресурсы
pulumi destroy

# Проверить в Hetzner Console что всё удалено
hcloud server list
hcloud network list
hcloud floating-ip list
```

## Следующие шаги

1. Настроить DNS (External-DNS + CloudFlare)
2. Настроить TLS (cert-manager + Let's Encrypt)
3. Настроить CloudFlare Tunnel для ingress
4. Добавить мониторинг и алертинг
