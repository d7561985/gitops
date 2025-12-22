# Service Groups - Universal External Access

## Overview

Service Groups - универсальный механизм публикации любых сервисов через домены.
Один template обрабатывает все группы - легко добавить новый сервис.

**Ключевые принципы:**
- Single Source of Truth - всё в values.yaml
- Один template для любого количества сервисов
- Multi-cluster ready - уникальный clusterName для каждого кластера
- Security - опциональный IP whitelist через CiliumNetworkPolicy

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CloudFlare DNS                                     │
│  argocd.poc.infra-01.work  → {tunnelId}.cfargotunnel.com                    │
│  grafana.poc.infra-01.work → {tunnelId}.cfargotunnel.com                    │
│  vault.poc.infra-01.work   → {tunnelId}.cfargotunnel.com                    │
│                                                                              │
│  ⚠️  Требуется Advanced Certificate: *.poc.infra-01.work (per cluster)      │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CloudFlare Tunnel                                    │
│  cloudflared (namespace: cloudflare)                                        │
│  ConfigMap: ingress rules для каждого hostname                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Namespace: platform                                       │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ Gateway: gateway-infrastructure                                        │  │
│  │   listener: http-argocd  (argocd.poc.infra-01.work)                   │  │
│  │   listener: http-grafana (grafana.poc.infra-01.work)                  │  │
│  │   listener: http-vault   (vault.poc.infra-01.work)                    │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ HTTPRoute: infrastructure-argocd  → backendRef: argocd.argocd         │  │
│  │ HTTPRoute: infrastructure-grafana → backendRef: grafana.monitoring    │  │
│  │ HTTPRoute: infrastructure-vault   → backendRef: vault.vault           │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
         │                              │                         │
         │ ReferenceGrant               │ ReferenceGrant          │ ReferenceGrant
         ▼                              ▼                         ▼
┌─────────────────┐          ┌──────────────────┐       ┌─────────────────┐
│ Namespace:argocd│          │Namespace:monitor.│       │ Namespace:vault │
│ argocd-server   │          │ grafana          │       │ vault           │
└─────────────────┘          └──────────────────┘       └─────────────────┘
```

## Формат домена

```
{subdomain}.{clusterName}.{baseDomain}
```

**Примеры:**
| subdomain | clusterName | baseDomain | Результат |
|-----------|-------------|------------|-----------|
| argocd | poc | infra-01.work | argocd.poc.infra-01.work |
| grafana | prod-eu | infra.mycompany.com | grafana.prod-eu.infra.mycompany.com |
| vault | staging | ops.example.com | vault.staging.ops.example.com |

## Конфигурация

### values.yaml

```yaml
serviceGroups:
  infrastructure:
    enabled: true

    # Базовый домен для группы (2nd level domain)
    # ⚠️  Требуется Advanced Certificate для *.*.{baseDomain}
    baseDomain: "infra-01.work"

    # Уникальное имя кластера (часть URL)
    clusterName: "poc"

    # Namespace для Gateway этой группы
    gatewayNamespace: "platform"

    # CloudFlare Zone ID
    zoneId: "your-zone-id"

    # Gateway configuration
    gateway:
      gatewayClassName: cilium
      protocol: HTTP
      port: 80

    # Security: IP whitelist (VPN/Office)
    security:
      ipWhitelist:
        enabled: false
        cidrs:
          - "10.8.0.0/24"     # VPN range
          - "192.168.1.0/24"  # Office network

    # Сервисы
    services:
      argocd:
        enabled: true
        subdomain: argocd
        namespace: argocd
        serviceName: argocd-server
        servicePort: 80
        path: /
        pathType: PathPrefix

      grafana:
        enabled: true
        subdomain: grafana
        namespace: monitoring
        serviceName: kube-prometheus-stack-grafana
        servicePort: 80
        path: /
        pathType: PathPrefix

      vault:
        enabled: true
        subdomain: vault
        namespace: vault
        serviceName: vault
        servicePort: 8200
        path: /
        pathType: PathPrefix
```

## Добавление нового сервиса

Добавить новый сервис - **5 строк в values.yaml**:

```yaml
serviceGroups:
  infrastructure:
    services:
      # Добавить новый сервис
      prometheus:
        enabled: true
        subdomain: prometheus         # prometheus.poc.infra.demo-poc-01.work
        namespace: monitoring
        serviceName: prometheus-server
        servicePort: 9090
        path: /
        pathType: PathPrefix
```

После `git push` → ArgoCD автоматически создаст:
- Gateway listener
- HTTPRoute
- ReferenceGrant (если namespace новый)
- DNS запись (через external-dns)
- Tunnel ingress rule

## Добавление новой группы

Для другого набора сервисов (например, databases):

```yaml
serviceGroups:
  infrastructure:
    # ... existing ...

  databases:
    enabled: true
    baseDomain: "db.demo-poc-01.work"
    clusterName: "poc"
    gatewayNamespace: "platform-db"
    zoneId: "your-zone-id"

    gateway:
      gatewayClassName: cilium
      protocol: HTTP
      port: 80

    # ВАЖНО: Базы данных только через VPN!
    security:
      ipWhitelist:
        enabled: true
        cidrs:
          - "10.8.0.0/24"  # Only VPN

    services:
      mongo-express:
        enabled: true
        subdomain: mongo
        namespace: infra-dev
        serviceName: mongo-express
        servicePort: 8081
        path: /
        pathType: PathPrefix
```

## Multi-Cluster Setup

Для каждого кластера используйте уникальный `clusterName`:

| Cluster | clusterName | Домен ArgoCD |
|---------|-------------|--------------|
| Dev local | poc | argocd.poc.infra-01.work |
| Staging EU | staging-eu | argocd.staging-eu.infra-01.work |
| Prod US | prod-us | argocd.prod-us.infra-01.work |

**Важно:**
- Используйте `--txt-owner-id` в external-dns для предотвращения конфликтов DNS записей между кластерами
- Добавьте wildcard в Advanced Certificate для каждого кластера:
  - `*.poc.infra-01.work`
  - `*.staging-eu.infra-01.work`
  - `*.prod-us.infra-01.work`

## IP Whitelist (VPN)

Для ограничения доступа к сервисам (только VPN/Office):

```yaml
serviceGroups:
  infrastructure:
    security:
      ipWhitelist:
        enabled: true
        cidrs:
          - "10.8.0.0/24"      # VPN range
          - "192.168.1.0/24"   # Office network
```

Это создаёт CiliumNetworkPolicy:
- Разрешает трафик только с указанных CIDR
- Автоматически разрешает трафик от CloudFlare Tunnel (cloudflared pods)
- Разрешает health checks из kube-system

## Генерируемые ресурсы

Для каждой enabled группы создаются:

| Ресурс | Namespace | Описание |
|--------|-----------|----------|
| Namespace | - | Namespace для Gateway |
| Gateway | {gatewayNamespace} | Gateway с listener на каждый сервис |
| HTTPRoute | {gatewayNamespace} | Маршрут для каждого сервиса |
| ReferenceGrant | {service.namespace} | Разрешение cross-namespace routing |
| CiliumNetworkPolicy | {gatewayNamespace} | IP whitelist (если enabled) |

Также обновляются:
- CloudFlare Tunnel ConfigMap (ingress rules)
- external-dns annotations на Gateway (DNS записи)

## CloudFlare Advanced Certificate (обязательно!)

Для инфраструктурного стека используется формат домена с **2+ уровнями subdomains**:
```
vault.poc.infra-01.work
  │    │      │
  │    │      └─ baseDomain (2nd level)
  │    └─ clusterName (1st subdomain level)
  └─ service (2nd subdomain level)
```

**CloudFlare Universal SSL покрывает только 1 уровень** (`*.infra-01.work`).
Для multi-level subdomains требуется **Advanced Certificate** с wildcard для каждого clusterName.

### Настройка Advanced Certificate

1. **CloudFlare Dashboard** → выбрать домен (например `infra-01.work`)

2. **SSL/TLS** → **Edge Certificates**

3. **Order Advanced Certificate**:
   - Type: **Advanced**
   - Hostnames:
     - `infra-01.work`
     - `*.infra-01.work`
     - `*.poc.infra-01.work` ← для clusterName=poc
     - `*.staging.infra-01.work` ← для clusterName=staging (если нужно)
     - `*.prod.infra-01.work` ← для clusterName=prod (если нужно)
   - Certificate validity: 1 year
   - Certificate Authority: Let's Encrypt или Google Trust Services

   > **Важно:** `*.*.domain.com` НЕ поддерживается (ограничение CA/Browser Forum).
   > Нужно указывать wildcard для каждого clusterName отдельно.

4. **Стоимость**: $10/month за домен

5. **Проверить статус**: SSL/TLS → Edge Certificates → должен быть Active

### Альтернативы (если не хотите платить)

| Вариант | Описание |
|---------|----------|
| 1 уровень subdomain | `poc-vault.infra-01.work` вместо `vault.poc.infra-01.work` |
| Total TLS | Бесплатно, но требует Enterprise или специальные условия |
| Без CloudFlare proxy | DNS-only (серое облако) + cert-manager, но теряется DDoS protection |

## Быстрый старт

### 1. Заказать Advanced Certificate

См. секцию выше - **обязательно для multi-level subdomains!**

### 2. Получить Zone ID

```bash
# CloudFlare Dashboard → infra-01.work → API section → Zone ID
```

### 3. Обновить values.yaml

```yaml
serviceGroups:
  infrastructure:
    enabled: true
    zoneId: "your-zone-id"  # ← Вставить Zone ID
```

### 4. Применить изменения

```bash
git add .
git commit -m "feat: enable infrastructure domains"
git push

# Синхронизировать ArgoCD
argocd app sync platform-service-groups --grpc-web
```

### 5. Проверить

```bash
# DNS записи
dig argocd.poc.infra-01.work

# HTTP доступ (после активации Advanced Certificate!)
curl -I https://argocd.poc.infra-01.work
curl -I https://grafana.poc.infra-01.work
curl -I https://vault.poc.infra-01.work
```

## Troubleshooting

### SSL Handshake Failure (ERR_SSL_VERSION_OR_CIPHER_MISMATCH)

**Симптомы:**
```bash
curl: (35) SSL handshake failure
# или в браузере: ERR_SSL_VERSION_OR_CIPHER_MISMATCH
```

**Причина:** CloudFlare Universal SSL не покрывает multi-level subdomains.

**Решение:**
1. Заказать Advanced Certificate с `*.{clusterName}.infra-01.work`
   - Например: `*.poc.infra-01.work` для clusterName=poc
   - `*.*.domain.com` НЕ поддерживается (ограничение CA/Browser Forum)
2. Подождать 5-15 минут пока сертификат станет Active
3. Проверить: SSL/TLS → Edge Certificates → Status: Active

### DNS не резолвится

```bash
# Проверить external-dns logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Проверить Gateway annotations
kubectl get gateway -n platform gateway-infrastructure -o yaml | grep -A5 annotations
```

### 502 Bad Gateway

```bash
# Проверить что целевой сервис существует
kubectl get svc -n argocd argocd-server
kubectl get svc -n monitoring kube-prometheus-stack-grafana
kubectl get svc -n vault vault

# Проверить ReferenceGrant
kubectl get referencegrant -n argocd
kubectl get referencegrant -n monitoring
kubectl get referencegrant -n vault
```

### CloudFlare Tunnel не видит сервис

```bash
# Проверить ConfigMap
kubectl get cm -n cloudflare cloudflared-config -o yaml

# Проверить checksum annotation (должен меняться при изменении config)
kubectl get deployment -n cloudflare cloudflared -o jsonpath='{.spec.template.metadata.annotations}'
```

> **Note:** cloudflared автоматически перезапускается при изменении ConfigMap
> благодаря checksum annotation. Ручной restart не требуется.

## Автоматический restart cloudflared

При изменении `values.yaml` происходит:
1. Helm генерирует новый ConfigMap
2. Helm вычисляет SHA256 от содержимого ConfigMap
3. Checksum записывается в annotation Deployment
4. Kubernetes видит изменение annotation → запускает rolling restart

Это реализовано через Helm template:
```yaml
annotations:
  checksum/config: {{ $configContent | sha256sum }}
```

## Связанные документы

- [Domain Mirrors Guide](domain-mirrors-guide.md) — зеркала доменов для приложений
- [Preview Environments Guide](preview-environments-guide.md) — preview для feature branches
- [New Service Guide](new-service-guide.md) — создание нового сервиса
- [Gateway API Plan](gateway-api-plan.md) — архитектура Gateway API
- [PREFLIGHT-CHECKLIST](PREFLIGHT-CHECKLIST.md) — настройка CloudFlare
