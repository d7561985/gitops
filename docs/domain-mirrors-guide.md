# Domain Mirrors Guide

Руководство по настройке зеркал доменов через GitOps.

## Обзор

Система поддерживает автоматическое управление зеркалами доменов. При добавлении зеркала в `values.yaml` автоматически создаются:

1. **Gateway listener** — принимает трафик для домена зеркала
2. **HTTPRoute** — маршрутизирует трафик на backend-сервисы
3. **DNS запись** — external-dns создаёт запись в CloudFlare
4. **Tunnel ingress** — cloudflared получает правило (если используется)

**Важно:** Зеркала НЕ требуют изменений в k8app/app chart! Они создают параллельные HTTPRoute, ссылающиеся на те же Service.

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              values.yaml                                    │
│                                                                             │
│  environments:                    domainMirrors:                            │
│    dev:                             defaultRoutes:                          │
│      domain: "app.demo-poc-01.work"   - path: /api                         │
│      mirrors:                           serviceName: api-gateway-sv        │
│        - domain: "mirror.example.com"  - path: /                           │
│          zoneId: "abc123..."            serviceName: sentry-frontend-sv    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Helm Templates                                    │
│                                                                             │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐ │
│  │ gateway.yaml        │  │ httproute-mirrors   │  │ cloudflared-config  │ │
│  │ → Gateway listeners │  │ → HTTPRoutes        │  │ → Tunnel rules      │ │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Resources                                │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                           Gateway (Cilium)                          │   │
│  │  listeners:                                                          │   │
│  │    - name: http-app        hostname: app.demo-poc-01.work           │   │
│  │    - name: http-mirror-0   hostname: mirror.example.com             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                              │
│              ┌───────────────┴───────────────┐                             │
│              ▼                               ▼                              │
│  ┌─────────────────────────┐   ┌─────────────────────────┐                 │
│  │ HTTPRoute (k8app)       │   │ HTTPRoute (mirrors)     │                 │
│  │ hostname: app.demo-...  │   │ hostname: mirror.exam..│                 │
│  │ /api → api-gateway-sv   │   │ /api → api-gateway-sv   │                 │
│  │ /    → sentry-frontend  │   │ /    → sentry-frontend  │                 │
│  └───────────┬─────────────┘   └───────────┬─────────────┘                 │
│              │                              │                               │
│              └──────────────┬───────────────┘                              │
│                             ▼                                               │
│              ┌─────────────────────────────┐                               │
│              │ Services (существующие)     │                               │
│              │ - api-gateway-sv:8080       │                               │
│              │ - sentry-frontend-sv:4200   │                               │
│              └─────────────────────────────┘                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Как это работает (техническая логика)

### 1. Gateway Listeners

Gateway создаёт отдельный listener для каждого домена:

```yaml
# Gateway в poc-dev namespace
spec:
  listeners:
    - name: http-app              # Основной домен
      hostname: "app.demo-poc-01.work"
      port: 80
    - name: http-mirror-0         # Первое зеркало
      hostname: "mirror.example.com"
      port: 80
```

Каждый listener имеет уникальное имя (`http-mirror-N`) для привязки HTTPRoute.

### 2. HTTPRoute → Gateway привязка

HTTPRoute привязывается к конкретному listener через `parentRefs.sectionName`:

```yaml
# HTTPRoute для зеркала
spec:
  hostnames:
    - "mirror.example.com"
  parentRefs:
    - name: gateway
      namespace: poc-dev
      sectionName: http-mirror-0    # ← Привязка к listener
  rules:
    - matches:
        - path: {type: PathPrefix, value: "/api"}
      backendRefs:
        - name: api-gateway-sv      # ← Тот же сервис что и основной
          port: 8080
```

### 3. external-dns → DNS записи

external-dns работает автоматически:

1. **Hostname** — читается из HTTPRoute `spec.hostnames` (создаётся k8app)
2. **Target** — читается из Gateway annotation `external-dns.../target`
3. **Proxied** — включён глобально флагом `--cloudflare-proxied`

```yaml
# Gateway (platform-core) — определяет target для DNS
metadata:
  annotations:
    external-dns.alpha.kubernetes.io/target: "<tunnel-id>.cfargotunnel.com"

# HTTPRoute (k8app) — определяет hostname (БЕЗ аннотаций external-dns!)
spec:
  hostnames:
    - "app.example.com"
```

**Результат в CloudFlare:**
```
app.example.com  CNAME  <tunnel-id>.cfargotunnel.com  (proxied)
```

**Важно:** Сервисы команд НЕ должны добавлять external-dns аннотации!
Всё работает автоматически благодаря глобальному флагу `--cloudflare-proxied`.

### 4. Полный путь запроса

```
Пользователь → mirror.example.com
      │
      ▼
CloudFlare (DNS CNAME → tunnel)
      │
      ▼
CloudFlare Tunnel (читает config.yaml)
      │ hostname: mirror.example.com → cilium-gateway-gateway.poc-dev.svc
      ▼
Gateway (Cilium) listener: http-mirror-0
      │
      ▼
HTTPRoute: mirror-0-api (sectionName: http-mirror-0)
      │ path: /api → api-gateway-sv:8080
      ▼
Service: api-gateway-sv → Pod
```

## Единый источник истины (GitOps)

### Принцип

**Все DNS записи управляются через `values.yaml`** — никаких ручных действий в CloudFlare Dashboard!

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              GitOps Flow                                     │
│                                                                             │
│  values.yaml ──▶ ArgoCD ──▶ Kubernetes ──▶ external-dns ──▶ CloudFlare     │
│  (Git)           (Sync)     (Gateway)      (читает           (DNS)          │
│                             (аннотации)    аннотации)                       │
│                                                                             │
│                    Единственное место изменений: values.yaml                │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Что создаётся автоматически

При добавлении домена или зеркала в `values.yaml`:

| Ресурс | Создаётся | Кем |
|--------|-----------|-----|
| Gateway listener | Автоматически | platform-core (Helm) |
| HTTPRoute | Автоматически | platform-core (Helm) |
| Tunnel ingress rule | Автоматически | platform-ingress (ConfigMap) |
| DNS CNAME запись | Автоматически | external-dns |

### Преимущества

| Аспект | Описание |
|--------|----------|
| **Воспроизводимость** | Любой может развернуть систему с нуля |
| **Аудит** | Git history показывает кто, когда, что изменил |
| **Откат** | `git revert` откатывает всё, включая DNS |
| **Масштабирование** | Копируй values.yaml для нового клиента/проекта |
| **Disaster Recovery** | Пересоздание кластера восстанавливает всё |

### Примеры использования

**Новый environment:**
```yaml
environments:
  staging:
    enabled: true
    domain: "app.staging.example.com"
```
→ `git push` → DNS создаётся автоматически

**Новое зеркало:**
```yaml
environments:
  dev:
    mirrors:
      - domain: "mirror.example.com"
        zoneId: "..."
```
→ `git push` → Gateway listener + HTTPRoute + DNS создаются автоматически

**Миграция на другой ingress:**
```yaml
ingress:
  provider: haproxy  # было: cloudflare-tunnel
  haproxy:
    loadBalancerIP: "203.0.113.10"
```
→ DNS автоматически меняется с CNAME (tunnel) на A запись (IP)

### Важно: НЕ редактируйте DNS вручную!

После настройки external-dns все DNS записи для доменов из `values.yaml` управляются автоматически:

- Добавили домен в values.yaml → DNS создаётся
- Удалили домен из values.yaml → DNS удаляется
- Изменили tunnelId → DNS target обновляется

Ручное редактирование в CloudFlare Dashboard будет перезаписано external-dns!

## Быстрый старт

### Шаг 0: Настроить CloudFlare API Token

Убедитесь что в `.env` файле есть токен:

```bash
# .env
CLOUDFLARE_API_TOKEN="your-cloudflare-api-token"
```

Токен должен иметь permissions:
- `Zone:Zone:Read`
- `Zone:DNS:Edit`
- `Account:Cloudflare Tunnel:Edit` (если используете tunnel)

### Шаг 1: Установить external-dns

```bash
# Токен загружается автоматически из .env
./infrastructure/external-dns/setup.sh

# Проверить что работает
kubectl logs -f deployment/external-dns -n external-dns
```

### Шаг 2: Получить Zone ID домена

Zone ID — уникальный идентификатор домена в CloudFlare. Нужен для каждого зеркала.

**Вариант A: Через Dashboard**
1. Откройте [CloudFlare Dashboard](https://dash.cloudflare.com/)
2. Выберите нужный домен
3. На странице **Overview** справа найдите **Zone ID**

**Вариант B: Через API**
```bash
# Список всех ваших зон с ID
curl -s "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" | jq '.result[] | {name, id}'

# Пример вывода:
# {
#   "name": "example.com",
#   "id": "abc123def456..."
# }
```

### Шаг 3: Добавить зеркало в values.yaml

```yaml
# gitops-config/platform/core.yaml

environments:
  dev:
    enabled: true
    domain: "app.demo-poc-01.work"
    mirrors:
      - domain: "mirror.example.com"
        zoneId: "your-cloudflare-zone-id"
```

### Шаг 4: Commit и push

```bash
cd gitops-config
git add .
git commit -m "feat: add mirror.example.com domain"
git push
```

### Шаг 5: ArgoCD синхронизация

```bash
# Проверить статус
argocd app get platform-core --grpc-web

# Принудительный sync
argocd app sync platform-core --grpc-web
```

### Шаг 6: Проверить

```bash
# Gateway listeners
kubectl get gateway gateway -n poc-dev -o yaml | grep -A10 listeners

# HTTPRoutes для зеркал
kubectl get httproutes -n poc-dev | grep mirror

# DNS записи (логи external-dns)
kubectl logs deployment/external-dns -n external-dns --tail=20

# Тест доступа
curl -I https://mirror.example.com
curl -I https://mirror.example.com/api/health
```

## Конфигурация

### Структура mirrors в values.yaml

```yaml
environments:
  dev:
    enabled: true
    domain: "app.demo-poc-01.work"
    mirrors:
      # Простой вариант — использует defaultRoutes
      - domain: "mirror1.example.com"
        zoneId: "abc123..."

      # Расширенный вариант — кастомные маршруты
      - domain: "mirror2.other.net"
        zoneId: "xyz789..."
        routes:
          - name: api-only
            path: /api
            pathType: PathPrefix
            serviceName: api-gateway-sv
            servicePort: 8080
          # Без frontend — только API
```

### Default Routes

Если `routes` не указаны, используются `domainMirrors.defaultRoutes`:

```yaml
domainMirrors:
  enabled: true
  defaultRoutes:
    # API Gateway
    - name: api
      path: /api
      pathType: PathPrefix
      serviceName: api-gateway-sv
      servicePort: 8080

    # Frontend (catch-all)
    - name: frontend
      path: /
      pathType: PathPrefix
      serviceName: sentry-frontend-sv
      servicePort: 4200
```

## Ingress провайдеры

### CloudFlare Tunnel (по умолчанию)

```yaml
ingress:
  provider: cloudflare-tunnel
  cloudflare:
    enabled: true
    tunnelId: "your-tunnel-uuid"
```

DNS записи создаются как CNAME на `<tunnel-id>.cfargotunnel.com`.

### HAProxy / Nginx / Внешний LB

```yaml
ingress:
  provider: haproxy  # или nginx, external
  haproxy:
    enabled: true
    loadBalancerIP: "203.0.113.10"
```

DNS записи создаются как A запись на IP.

**Важно:** Переключение провайдера НЕ требует изменений в зеркалах!

## Настройка CloudFlare Tunnel

### Новая установка (с нуля)

```bash
# Создаёт tunnel, secret с credentials, деплоит cloudflared
./infrastructure/cloudflare-tunnel/setup.sh

# Скрипт выведет tunnelId — добавьте в values.yaml:
# ingress.cloudflare.tunnelId: "ваш-tunnel-id"
```

### Миграция с remotely-managed

Если уже есть tunnel с настройками в Dashboard:
```bash
./infrastructure/cloudflare-tunnel/migrate-to-locally-managed.sh
```

После миграции удалите hostnames из Dashboard:
Zero Trust → Networks → Tunnels → [ваш tunnel] → Public Hostname → Delete all

## Troubleshooting

### HTTPRoute не создаётся

```bash
# Проверить что template генерируется
helm template platform-core ./charts/platform-core \
  | grep -A50 "kind: HTTPRoute" | grep mirror

# Проверить values
helm template platform-core ./charts/platform-core \
  --set "environments.dev.mirrors[0].domain=test.com" \
  --set "environments.dev.mirrors[0].zoneId=abc"
```

### DNS запись не создаётся

```bash
# Логи external-dns
kubectl logs deployment/external-dns -n external-dns --tail=50

# Проверить annotations на HTTPRoute
kubectl get httproute -n poc-dev -o yaml | grep -A5 annotations
```

### Трафик не маршрутизируется

```bash
# Проверить Gateway listeners
kubectl get gateway gateway -n poc-dev -o yaml | grep -B2 -A5 "hostname:"

# Проверить HTTPRoute parentRefs
kubectl get httproute -n poc-dev -o yaml | grep -A5 parentRefs

# Проверить что listener name совпадает с sectionName
# Gateway listener: name: http-mirror-0
# HTTPRoute parentRef: sectionName: http-mirror-0
```

### Tunnel не получает трафик

```bash
# Проверить ConfigMap
kubectl get configmap cloudflared-config -n cloudflare -o yaml

# Рестартнуть cloudflared
kubectl rollout restart deployment/cloudflared -n cloudflare
```

## Best Practices

1. **Тестируйте в dev** перед prod
2. **Используйте уникальные Zone ID** для каждого домена
3. **Мониторьте DNS propagation** — до 5 минут
4. **Проверяйте CloudFlare WAF** — может блокировать новые домены
5. **Один зеркальный домен** — один mirror entry (не дублируйте)

## Что создаётся автоматически

При добавлении зеркала `mirror.example.com`:

| Ресурс | Name | Namespace |
|--------|------|-----------|
| Gateway listener | `http-mirror-0` | poc-dev |
| HTTPRoute | `mirror-0-api` | poc-dev |
| HTTPRoute | `mirror-0-frontend` | poc-dev |
| DNS CNAME | `mirror.example.com` | CloudFlare |
| Tunnel rule | `hostname: mirror.example.com` | cloudflare |

## См. также

- [PREFLIGHT-CHECKLIST.md](./PREFLIGHT-CHECKLIST.md) — полный чеклист развёртывания
- [new-service-guide.md](./new-service-guide.md) — создание нового сервиса
- [preview-environments-guide.md](./preview-environments-guide.md) — preview для feature branches
- [service-groups-guide.md](./service-groups-guide.md) — инфраструктурные домены
- [gateway-api-plan.md](./gateway-api-plan.md) — архитектура Gateway API
