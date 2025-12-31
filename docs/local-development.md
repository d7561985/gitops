# Локальная разработка с Talos Linux

Пошаговая инструкция для запуска Kubernetes кластера на базе Talos Linux
на macOS/Linux с использованием Docker.

## Архитектура и разделение ответственности

```
┌───────────────────────────────────────────────────────────────────────┐
│                         Локальная машина                              │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│   LAYER 0 (setup-talos.sh)           LAYER 1-3 (setup-infrastructure.sh)
│   ────────────────────────           ─────────────────────────────────
│                                                                       │
│   ┌─────────────────────┐             ┌─────────────────────────┐    │
│   │  talosctl cluster   │             │  helm install ...       │    │
│   │  create             │             │                         │    │
│   │                     │             │  Устанавливает:         │    │
│   │  Создаёт:           │     ───▶    │  • Gateway API CRDs     │    │
│   │  • Docker контейнер │             │  • Cilium CNI           │    │
│   │  • Talos OS         │             │  • cert-manager         │    │
│   │  • etcd + K8s API   │             │  • Vault + VSO          │    │
│   │  • kubeconfig       │             │  • ArgoCD               │    │
│   └─────────────────────┘             │  • Monitoring           │    │
│              │                        │  • External-DNS         │    │
│              │                        │  • Cloudflare Tunnel    │    │
│              │                        └─────────────────────────┘    │
│              │                                    │                   │
│              │                                    ▼                   │
│              │                        ┌─────────────────────────┐    │
│              │                        │  LAYER 4 (ArgoCD)       │    │
│              │                        │  Управляет только       │    │
│              │                        │  приложениями:          │    │
│              │                        │  • platform-core        │    │
│              │                        │  • service-groups       │    │
│              │                        │  • preview-envs         │    │
│              │                        │  • ingress-cloudflare   │    │
│              │                        └─────────────────────────┘    │
│              ▼                                                        │
│   ┌─────────────────────────────────────────────────────────────┐    │
│   │                        Docker                                │    │
│   │   ┌─────────────────────────────────────────────────────┐   │    │
│   │   │  talos-local-controlplane-1                         │   │    │
│   │   │                                                     │   │    │
│   │   │  Talos Linux + Kubernetes                          │   │    │
│   │   │  :XXXXX → 6443 (K8s API)                           │   │    │
│   │   │  :XXXXX → 50000 (Talos API)                        │   │    │
│   │   └─────────────────────────────────────────────────────┘   │    │
│   └─────────────────────────────────────────────────────────────┘    │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

### Разделение ответственности

| Layer | Компонент | Управление |
|-------|-----------|------------|
| 0 | Talos кластер | `setup-talos.sh` (talosctl) |
| 1 | Gateway API, Cilium | `setup-infrastructure.sh` (helm) |
| 2 | cert-manager, Vault | `setup-infrastructure.sh` (helm) |
| 3 | ArgoCD, Monitoring | `setup-infrastructure.sh` (helm) |
| 4 | Applications | ArgoCD (GitOps) |

ArgoCD **НЕ** управляет инфраструктурой (self-manage отключен).

## Требования

### Программы

```bash
# Docker Desktop (или Colima для macOS)
brew install --cask docker

# talosctl - CLI для управления Talos
brew install siderolabs/tap/talosctl

# kubectl
brew install kubectl
```

### Ресурсы

| Компонент | Минимум | Рекомендуется |
|-----------|---------|---------------|
| CPU | 2 cores | 4 cores |
| RAM | 4 GB | 8 GB |
| Disk | 10 GB | 20 GB |

## Подготовка

### 1. Отключите Kubernetes в Docker Desktop

Docker Desktop имеет встроенный Kubernetes, который может конфликтовать.
Отключите его:

1. Docker Desktop → Settings → Kubernetes
2. Снимите галочку "Enable Kubernetes"
3. Apply & Restart

## Запуск кластера

### Быстрый старт (рекомендуется)

```bash
cd /path/to/gitops

# Шаг 1: Создать Talos кластер (Layer 0)
./shared/scripts/setup-talos.sh

# Шаг 2: Установить инфраструктуру (Layer 1-3)
export KUBECONFIG=~/.kube/talos-local.yaml
./shared/scripts/setup-infrastructure.sh

# Шаг 3: Bootstrap ArgoCD (Layer 4) - одна команда!
kubectl apply -f infra/poc/gitops-config/argocd/bootstrap-app.yaml

# Проверить статус
kubectl get applications -n argocd
```

### Пошагово (для понимания)

<details>
<summary>Шаг 1: Создать Talos кластер</summary>

```bash
# Скрипт автоматически:
# 1. Удалит старый кластер (с подтверждением)
# 2. Создаст Talos кластер в Docker
# 3. Настроит kubeconfig

./shared/scripts/setup-talos.sh

# Или вручную:
talosctl cluster create \
  --name talos-local \
  --config-patch @shared/talos/patches/docker.yaml \
  --wait=false

API_PORT=$(docker port talos-local-controlplane-1 6443 | cut -d: -f2)
talosctl kubeconfig ~/.kube/talos-local.yaml --nodes 10.5.0.2
sed -i '' "s|server: https://10.5.0.2:6443|server: https://127.0.0.1:$API_PORT|g" ~/.kube/talos-local.yaml
```

</details>

<details>
<summary>Шаг 2: Установить инфраструктуру</summary>

```bash
export KUBECONFIG=~/.kube/talos-local.yaml

# Скрипт автоматически устанавливает:
# Layer 1: Gateway API CRDs, Cilium CNI
# Layer 2: cert-manager, Vault + VSO
# Layer 3: ArgoCD, Monitoring, External-DNS, Cloudflare Tunnel

./shared/scripts/setup-infrastructure.sh
```

</details>

<details>
<summary>Шаг 3: Bootstrap ArgoCD</summary>

```bash
# Одна команда - автоматически применит project.yaml и все модули
kubectl apply -f infra/poc/gitops-config/argocd/bootstrap-app.yaml

# Проверить статус
kubectl get applications -n argocd
```

</details>

## Доступ к сервисам

### ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Логин: admin
# Пароль:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Открыть
open https://localhost:8080
```

### Hubble UI (Cilium)

```bash
kubectl port-forward svc/hubble-ui -n kube-system 12000:80
open http://localhost:12000
```

## Управление кластером

### Остановить (сохранить данные)

```bash
docker stop talos-local-controlplane-1
```

### Запустить снова

```bash
docker start talos-local-controlplane-1

# Дождаться готовности
talosctl health
```

### Удалить полностью

```bash
# Удалить Talos кластер
talosctl cluster destroy --name talos-local
rm -rf ~/.talos/clusters/talos-local
rm -f ~/.kube/talos-local.yaml
```

### Пересоздать с нуля

```bash
# Используйте скрипты - они автоматически очистят и пересоздадут:
./shared/scripts/setup-talos.sh
export KUBECONFIG=~/.kube/talos-local.yaml
./shared/scripts/setup-infrastructure.sh
kubectl apply -f infra/poc/gitops-config/argocd/bootstrap-app.yaml
```

## Патч конфигурации

Файл `shared/talos/patches/docker.yaml`:

```yaml
cluster:
  network:
    cni:
      name: none      # Cilium устанавливается через bootstrap
  proxy:
    disabled: true    # Cilium заменяет kube-proxy
machine:
  features:
    hostDNS:
      enabled: true
      forwardKubeDNSToHost: true  # Для Docker DNS resolution
```

## Troubleshooting

### Ноды не становятся Ready

```bash
# Проверить Cilium
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium

# Логи Cilium
kubectl logs -n kube-system -l app.kubernetes.io/name=cilium -c cilium-agent
```

### Ошибка сертификатов talosctl

```
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

Это происходит когда `~/.talos/config` содержит старые контексты.

```bash
# Проверить контексты
grep -E "^context:|^    [a-z].*:$" ~/.talos/config

# Если есть talos-local-1, talos-local-2, etc - нужно переключиться
talosctl config context talos-local-3  # или последний

# Или полностью пересоздать
talosctl cluster destroy --name talos-local
rm -rf ~/.talos/clusters/talos-local
```

### Kubeconfig не работает

```bash
# Проверить порт в kubeconfig
cat ~/.kube/talos-local.yaml | grep server

# Должен совпадать с
docker port talos-local-controlplane-1 6443
```

### ArgoCD Applications в OutOfSync

```bash
# Синхронизировать вручную
argocd app sync platform-core

# Или через kubectl
kubectl patch application platform-core -n argocd -p '{"operation": {"sync": {}}}' --type=merge
```

## Сравнение с другими провайдерами

| Аспект | Docker (Local) | Bare-Metal |
|--------|---------------|------------|
| Создание кластера | `talosctl` вручную | `talosctl` вручную |
| Bootstrap | `kubectl apply -k` | `kubectl apply -k` |
| Control Planes | 1 | 1-3 |
| Workers | 0 | N |
| VIP | Нет | Talos VIP |
| Storage | Ephemeral | Longhorn |
| Upgrade | Пересоздание | Rolling |

## Следующие шаги

1. [Bare Metal деплой](./bare-metal-deployment.md)
2. [Архитектура платформы](./platform-overview.md)
