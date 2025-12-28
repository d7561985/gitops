# Деплой на Bare Metal (Homelab)

Руководство по развёртыванию Kubernetes на физических серверах.

## Обзор

Bare metal деплой использует **Pure GitOps** подход:

1. **talosctl** — создаёт и настраивает Talos ноды
2. **kubectl apply -k** — ONE-TIME bootstrap (Cilium, Gateway API, ArgoCD)
3. **ArgoCD** — управляет всем остальным, включая себя

## Методы установки

| Метод | Сложность | Автоматизация | Описание |
|-------|-----------|---------------|----------|
| **ISO Boot** | Низкая | Ручная | Загрузка с USB/DVD |
| **PXE Boot** | Средняя | Полная | Сетевая загрузка |
| **USB Install** | Низкая | Ручная | Запись ISO на USB |

## Требования

### Аппаратные

| Компонент | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 2 cores | 4+ cores |
| **RAM** | 4 GB | 8+ GB |
| **Disk** | 20 GB | 100+ GB SSD |
| **Network** | 1 Gbps | 10 Gbps |

### Сетевые

- Статические IP адреса или DHCP резервации
- Доступ к интернету для загрузки образов
- (Опционально) VIP для HA API server

## Подготовка

### 1. Определить IP адреса

```
Network: 192.168.1.0/24
Gateway: 192.168.1.1

Control Plane:
  - cp-1: 192.168.1.10
  - cp-2: 192.168.1.11 (для HA)
  - cp-3: 192.168.1.12 (для HA)

Workers:
  - worker-1: 192.168.1.20
  - worker-2: 192.168.1.21

VIP (для HA): 192.168.1.100
```

### 2. Определить диски

```bash
# На каждом сервере определить целевой диск
lsblk

# Обычно это /dev/sda или /dev/nvme0n1
```

## Установка через ISO

### 1. Скачать Talos ISO

```bash
# AMD64
curl -LO https://github.com/siderolabs/talos/releases/download/v1.9.1/metal-amd64.iso

# ARM64
curl -LO https://github.com/siderolabs/talos/releases/download/v1.9.1/metal-arm64.iso
```

### 2. Создать загрузочный USB

```bash
# macOS
diskutil list  # Найти USB диск
sudo dd if=metal-amd64.iso of=/dev/rdiskN bs=4m status=progress

# Linux
sudo dd if=metal-amd64.iso of=/dev/sdX bs=4M status=progress
```

### 3. Загрузиться с USB

1. Вставить USB в сервер
2. Войти в BIOS/UEFI (обычно F2, F12, или Del)
3. Выбрать загрузку с USB
4. Дождаться загрузки Talos в maintenance mode

### 4. Сгенерировать конфигурации

```bash
cd /path/to/gitops

# Сгенерировать конфиги для кластера
talosctl gen config my-cluster https://192.168.1.100:6443 \
  --config-patch @shared/talos/patches/common.yaml \
  --config-patch @shared/talos/patches/bare-metal.yaml \
  --output-dir ./talos-configs

# Это создаст:
# - controlplane.yaml
# - worker.yaml
# - talosconfig
```

### 5. Применить конфигурацию

```bash
# Применить к первому control plane
talosctl apply-config --insecure --nodes 192.168.1.10 --file ./talos-configs/controlplane.yaml

# Применить к остальным control planes (для HA)
talosctl apply-config --insecure --nodes 192.168.1.11 --file ./talos-configs/controlplane.yaml
talosctl apply-config --insecure --nodes 192.168.1.12 --file ./talos-configs/controlplane.yaml

# Применить к workers
talosctl apply-config --insecure --nodes 192.168.1.20 --file ./talos-configs/worker.yaml
talosctl apply-config --insecure --nodes 192.168.1.21 --file ./talos-configs/worker.yaml
```

### 6. Bootstrap первую control plane ноду

```bash
# Только на первом control plane
talosctl bootstrap --nodes 192.168.1.10 --talosconfig ./talos-configs/talosconfig
```

### 7. Получить kubeconfig

```bash
# Настроить talosctl
cp ./talos-configs/talosconfig ~/.talos/config
talosctl config endpoint 192.168.1.100  # VIP или первый CP
talosctl config nodes 192.168.1.10

# Получить kubeconfig
talosctl kubeconfig ~/.kube/homelab.yaml
export KUBECONFIG=~/.kube/homelab.yaml
```

### 8. ONE-TIME Bootstrap

```bash
# Установить Gateway API CRDs, Cilium, ArgoCD
kubectl apply -k shared/bootstrap/

# Дождаться пока все pods будут Ready
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

### 9. Запустить ArgoCD Bootstrap App

```bash
# ArgoCD теперь управляет всем
kubectl apply -f infra/poc/gitops-config/argocd/bootstrap-app.yaml

# Проверить статус
kubectl get applications -n argocd
```

## Конфигурация VIP для HA

Для HA кластера с несколькими control plane нодами используйте VIP:

```yaml
# shared/talos/patches/bare-metal.yaml
machine:
  network:
    interfaces:
      - interface: eth0
        dhcp: true
        vip:
          ip: 192.168.1.100  # Shared VIP
```

## Storage Options

### Local Path Provisioner

Простой storage для одной ноды:

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
```

### Longhorn

Distributed storage для HA:

```yaml
# Требует iSCSI extension в Talos
machine:
  install:
    extensions:
      - image: ghcr.io/siderolabs/iscsi-tools:v0.1.4
```

```bash
helm repo add longhorn https://charts.longhorn.io
helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace
```

## Сетевые особенности

### MetalLB для LoadBalancer

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.200-192.168.1.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
    - default-pool
```

### Tailscale для удалённого доступа

Добавить в Talos patch:

```yaml
machine:
  install:
    extensions:
      - image: ghcr.io/siderolabs/tailscale:1.56.1
```

## Обновление

### Talos Upgrade

```bash
# Rolling upgrade всего кластера
talosctl upgrade --nodes 192.168.1.10,192.168.1.11,192.168.1.12 \
  --image ghcr.io/siderolabs/talos:v1.10.0
```

### Kubernetes Upgrade

Kubernetes обновляется вместе с Talos.

## Troubleshooting

### Нода не загружается

```bash
# Проверить консоль сервера (IPMI/iLO/iDRAC)
# Проверить логи Talos
talosctl dmesg --nodes <ip> --insecure
```

### Нода не присоединяется к кластеру

```bash
# Проверить сетевую связность
talosctl get addresses --nodes <ip>

# Проверить etcd
talosctl get members --nodes <cp-ip>
```

### Cilium не запускается

```bash
# Проверить что CNI отключен в Talos
talosctl get nodeannotations --nodes <ip>

# Логи Cilium
kubectl logs -n kube-system -l app.kubernetes.io/name=cilium -c cilium-agent
```

## Рекомендации

1. **UPS** — защита от скачков питания
2. **IPMI/iLO/iDRAC** — удалённое управление
3. **Резервное копирование etcd** — `talosctl etcd snapshot`
4. **Мониторинг** — Prometheus + Grafana
5. **Документируй** — IP адреса, MAC, диски

## Pure GitOps Architecture

После bootstrap:

| Компонент | Управление |
|-----------|------------|
| Talos ноды | talosctl (вручную) |
| Gateway API CRDs | ArgoCD layer-0 |
| Cilium CNI | ArgoCD layer-0 |
| cert-manager | ArgoCD layer-0 |
| external-dns | ArgoCD layer-0 |
| ArgoCD | ArgoCD layer-0 (self-manage) |
| Platform services | ArgoCD platform-core |
| Applications | ArgoCD ApplicationSets |
