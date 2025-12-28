# Миграция с Minikube на Talos

Руководство по миграции с существующего Minikube setup на Talos Linux.

## Обзор изменений

| Аспект | Minikube | Talos |
|--------|----------|-------|
| **Управление** | `minikube` CLI | `talosctl` + `kubectl apply -k` |
| **OS** | Configurable | Talos Linux (immutable) |
| **SSH** | Есть | Нет |
| **Конфигурация** | Bash скрипты | GitOps (ArgoCD) |
| **CNI** | Bridge/Calico | Cilium |
| **Ingress** | Ingress Controller | Gateway API |

## Что сохраняется

1. **ArgoCD конфигурация** — `bootstrap-app.yaml`, `platform-modules.yaml`
2. **Helm values** — `shared/infrastructure/*`
3. **Application definitions** — ApplicationSets, Projects
4. **Vault secrets** — миграция через backup/restore

## Что изменяется

1. **Способ создания кластера** — talosctl вместо minikube
2. **Bootstrap** — `kubectl apply -k shared/bootstrap/` вместо bash скриптов
3. **CNI** — Cilium вместо minikube CNI
4. **Ingress** — Gateway API вместо Ingress
5. **Management** — ArgoCD layer-0 управляет инфраструктурой

## Пошаговая миграция

### 1. Backup данных из Minikube

```bash
# Backup Vault data
kubectl exec -n vault vault-0 -- vault operator raft snapshot save /vault/data/backup.snap
kubectl cp vault/vault-0:/vault/data/backup.snap ./vault-backup.snap

# Export ArgoCD applications (опционально)
kubectl get applications -n argocd -o yaml > argocd-apps-backup.yaml
```

### 2. Остановить Minikube

```bash
minikube stop
minikube delete
```

### 3. Создать Talos кластер

```bash
cd /path/to/gitops

# Docker (local dev)
talosctl cluster create \
  --name talos-local \
  --config-patch @shared/talos/patches/docker.yaml
```

### 4. Настроить kubeconfig

```bash
API_PORT=$(docker port talos-local-controlplane-1 6443 | cut -d: -f2)
talosctl kubeconfig ~/.kube/talos-local.yaml --nodes 10.5.0.2
sed -i '' "s|server: https://10.5.0.2:6443|server: https://127.0.0.1:$API_PORT|g" ~/.kube/talos-local.yaml
export KUBECONFIG=~/.kube/talos-local.yaml
```

### 5. Bootstrap

```bash
# ONE-TIME: установка Cilium, Gateway API CRDs, ArgoCD
kubectl apply -k shared/bootstrap/

# Дождаться ready
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Запустить ArgoCD bootstrap
kubectl apply -f infra/poc/gitops-config/argocd/bootstrap-app.yaml
```

### 6. Restore Vault (если нужно)

```bash
# После того как Vault pod запущен
kubectl cp ./vault-backup.snap vault/vault-0:/vault/data/backup.snap
kubectl exec -n vault vault-0 -- vault operator raft snapshot restore /vault/data/backup.snap
```

## Pure GitOps Architecture

После миграции:

| Компонент | Управление |
|-----------|------------|
| Talos ноды | talosctl (вручную) |
| Gateway API CRDs | ArgoCD layer-0 |
| Cilium CNI | ArgoCD layer-0 |
| cert-manager | ArgoCD layer-0 |
| ArgoCD | ArgoCD layer-0 (self-manage) |
| Platform services | ArgoCD platform-core |
| Applications | ArgoCD ApplicationSets |

## Troubleshooting

### Pods не запускаются

```bash
# Проверить Cilium
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium

# Логи
kubectl logs -n kube-system -l app.kubernetes.io/name=cilium -c cilium-agent
```

### ArgoCD не синхронизирует

```bash
# Проверить статус
kubectl get applications -n argocd

# Синхронизировать вручную
kubectl patch application layer-0 -n argocd -p '{"operation": {"sync": {}}}' --type=merge
```
