# Локальная разработка с Talos Linux

Пошаговая инструкция для запуска Kubernetes кластера на базе Talos Linux
на macOS/Linux с использованием Docker.

## Архитектура и разделение ответственности

```
┌───────────────────────────────────────────────────────────────────────┐
│                         Локальная машина                              │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│   РУЧНОЙ ЭТАП (talosctl)              РУЧНОЙ ЭТАП (kubectl)          │
│   ─────────────────────               ─────────────────────           │
│                                                                       │
│   ┌─────────────────────┐             ┌─────────────────────────┐    │
│   │  talosctl cluster   │             │   kubectl apply -k      │    │
│   │  create             │             │   shared/bootstrap/     │    │
│   │                     │             │                         │    │
│   │  Создаёт:           │     ───▶    │  ONE-TIME установка:    │    │
│   │  • Docker контейнер │             │  • Gateway API CRDs     │    │
│   │  • Talos OS         │             │  • Cilium CNI           │    │
│   │  • etcd + K8s API   │             │  • ArgoCD               │    │
│   └─────────────────────┘             └─────────────────────────┘    │
│              │                                    │                   │
│              │                                    ▼                   │
│              │                        ┌─────────────────────────┐    │
│              │                        │  ArgoCD bootstrap app   │    │
│              │                        │  layer-0 → self-manage  │    │
│              │                        │  Всё остальное → GitOps │    │
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

### Pure GitOps

После bootstrap ArgoCD управляет **всем**, включая себя:

| Компонент | Управление |
|-----------|------------|
| Talos ноды | talosctl (вручную) |
| Gateway API CRDs | ArgoCD layer-0 |
| Cilium CNI | ArgoCD layer-0 |
| cert-manager | ArgoCD layer-0 |
| ArgoCD | ArgoCD layer-0 (self-manage) |
| Все остальное | ArgoCD |

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

### Шаг 1: Очистить старые контексты (если есть)

При пересоздании кластера talosctl добавляет суффиксы к контекстам (-1, -2, ...).
Рекомендуется очистить перед созданием:

```bash
# Удалить старый кластер если есть
talosctl cluster destroy --name talos-local 2>/dev/null || true
rm -rf ~/.talos/clusters/talos-local
rm -f ~/.kube/talos-local.yaml
```

### Шаг 2: Создать Talos кластер

```bash
cd /path/to/gitops

# Создать кластер с Docker-специфичным патчем
# --wait=false - не ждать Ready (ноды станут Ready после установки Cilium)
talosctl cluster create \
  --name talos-local \
  --config-patch @shared/talos/patches/docker.yaml \
  --wait=false

# Дождаться только API server
sleep 30  # или talosctl health --wait-timeout 2m
```

<details>
<summary>Что делает эта команда?</summary>

1. Скачивает Talos image
2. Создаёт Docker контейнеры (controlplane + worker)
3. Генерирует PKI и machine configs
4. Bootstraps etcd и Kubernetes API
5. Сохраняет talosconfig в `~/.talos/config`

</details>

### Шаг 3: Настроить kubeconfig

```bash
# Получить динамический порт
API_PORT=$(docker port talos-local-controlplane-1 6443 | cut -d: -f2)

# Экспортировать kubeconfig
talosctl kubeconfig ~/.kube/talos-local.yaml --nodes 10.5.0.2

# Заменить IP на localhost с правильным портом
sed -i '' "s|server: https://10.5.0.2:6443|server: https://127.0.0.1:$API_PORT|g" ~/.kube/talos-local.yaml

export KUBECONFIG=~/.kube/talos-local.yaml
```

### Шаг 4: ONE-TIME Bootstrap

```bash
# Установить Gateway API CRDs, Cilium, ArgoCD
./shared/bootstrap/bootstrap.sh

# Скрипт автоматически:
# 1. Установит Gateway API CRDs
# 2. Установит Cilium CNI
# 3. Установит ArgoCD
# 4. Дождётся готовности pods
```

### Шаг 5: Запустить ArgoCD Bootstrap App

```bash
# ArgoCD теперь управляет всем
kubectl apply -f infra/poc/gitops-config/argocd/bootstrap-app.yaml

# Проверить статус
kubectl get applications -n argocd
```

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
# Полная очистка
talosctl cluster destroy --name talos-local
rm -rf ~/.talos/clusters/talos-local
rm -f ~/.kube/talos-local.yaml

# Создать заново
talosctl cluster create --name talos-local \
  --config-patch @shared/talos/patches/docker.yaml

# Bootstrap
API_PORT=$(docker port talos-local-controlplane-1 6443 | cut -d: -f2)
talosctl kubeconfig ~/.kube/talos-local.yaml --nodes 10.5.0.2
sed -i '' "s|server: https://10.5.0.2:6443|server: https://127.0.0.1:$API_PORT|g" ~/.kube/talos-local.yaml
export KUBECONFIG=~/.kube/talos-local.yaml

kubectl apply -k shared/bootstrap/
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
kubectl patch application layer-0 -n argocd -p '{"operation": {"initiatedBy": {"username": "admin"},"sync": {}}}' --type=merge

# Или через argocd CLI
argocd app sync layer-0
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
