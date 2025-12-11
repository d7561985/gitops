# Gateway API + CloudFlare Tunnel Integration Plan

## Текущее состояние

### Frontend (sentry-frontend)
- **Статус**: Running в poc-dev namespace
- **Сервис**: `sentry-frontend-sv:4200` (ClusterIP)
- **Проблема с API endpoint**: Angular использует `environment.apiUrl = 'http://localhost:8080'` - захардкожен на этапе билда
- **Nginx**: Отдаёт статику, нет proxy для API

### API Gateway
- **Статус**: Running в poc-dev namespace
- **Сервис**: `api-gateway-sv:8080` (ClusterIP)

### Gateway API
- **GatewayClass**: `cilium` (Ready: True)
- **Gateway**: Не создан (gateway.enabled: false в values.yaml)
- **HTTPRoute**: Не создано

### CloudFlare Tunnel
- **Namespace**: cloudflare (пустой)
- **Статус**: Не развёрнут
- **Скрипт**: `infrastructure/cloudflare-tunnel/setup.sh` готов

### k8app Chart
- **Версия**: 3.5.2 (используется), 3.6.0 (доступна с HTTPRoute)
- **HTTPRoute поддержка**: Есть в 3.6.0

---

## Архитектура (Target State)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CloudFlare Edge                                │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │ app.demo-poc-01 │  │ api.demo-poc-01 │  │admin.demo-poc-01│             │
│  │     .work       │  │     .work       │  │     .work       │             │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘             │
│           │                    │                    │                       │
│           └──────────────┬─────┴─────┬──────────────┘                       │
│                          ▼           ▼                                      │
│                    ┌─────────────────────┐                                  │
│                    │   CloudFlare Tunnel │                                  │
│                    │   (QUIC/H2 outbound)│                                  │
│                    └──────────┬──────────┘                                  │
└───────────────────────────────┼─────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                           Minikube Cluster                                 │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │                    cloudflare namespace                             │   │
│  │  ┌──────────────────────────────────────────────────────────────┐  │   │
│  │  │ cloudflared deployment (2 replicas)                          │  │   │
│  │  │ Routes ALL traffic to Gateway                                │  │   │
│  │  └──────────────────────────┬───────────────────────────────────┘  │   │
│  └─────────────────────────────┼──────────────────────────────────────┘   │
│                                ▼                                           │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │                    gateway-dev namespace                            │   │
│  │  ┌──────────────────────────────────────────────────────────────┐  │   │
│  │  │ Gateway: gateway-dev (Cilium)                                │  │   │
│  │  │ Listeners:                                                    │  │   │
│  │  │   - https-app: app.demo-poc-01.work                          │  │   │
│  │  │   - https-api: api.demo-poc-01.work                          │  │   │
│  │  └──────────────────────────┬───────────────────────────────────┘  │   │
│  │                             │                                       │   │
│  │  ┌──────────────────────────┴───────────────────────────────────┐  │   │
│  │  │ Certificate: *.demo-poc-01.work (Let's Encrypt via DNS01)   │  │   │
│  │  └──────────────────────────────────────────────────────────────┘  │   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                │                                           │
│                ┌───────────────┴───────────────┐                          │
│                ▼                               ▼                          │
│  ┌─────────────────────────┐     ┌─────────────────────────┐             │
│  │      HTTPRoute          │     │      HTTPRoute          │             │
│  │  app.demo-poc-01.work   │     │  api.demo-poc-01.work   │             │
│  │    Path: /*             │     │    Path: /api/*         │             │
│  └───────────┬─────────────┘     └───────────┬─────────────┘             │
│              ▼                               ▼                            │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                        poc-dev namespace                            │  │
│  │  ┌─────────────────────┐        ┌─────────────────────┐            │  │
│  │  │ sentry-frontend-sv  │        │  api-gateway-sv     │            │  │
│  │  │     :4200           │        │      :8080          │            │  │
│  │  └─────────────────────┘        └─────────────────────┘            │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## Проблема с Frontend API URL

### Текущее состояние
Angular build-time конфигурация в `environment.prod.ts`:
```typescript
export const environment = {
  production: true,
  apiUrl: 'http://localhost:8080',  // ❌ Захардкожено
};
```

### Варианты решения

#### Вариант A: Относительный URL (Рекомендуется)
Изменить `apiUrl` на относительный путь:
```typescript
apiUrl: '/api'  // Или '' если API на том же домене
```

**Плюсы**:
- Работает в любом окружении
- Браузер сам добавит текущий домен

**Минусы**:
- Требует пересборки образа

#### Вариант B: Runtime конфигурация
Загружать config.json при старте Angular приложения:
```typescript
// app.module.ts
export function initializeApp(http: HttpClient) {
  return () => http.get('/config.json').toPromise()
    .then(config => environment.apiUrl = config.apiUrl);
}
```

**Плюсы**:
- Не требует пересборки при смене окружения

**Минусы**:
- Дополнительный HTTP запрос при старте
- Усложняет код

#### Вариант C: Path-based routing через Gateway (Рекомендуется)
Все запросы идут через один домен, Gateway роутит по path:
- `app.demo-poc-01.work/*` → frontend
- `app.demo-poc-01.work/api/*` → api-gateway

Frontend использует `apiUrl: ''` (пустой), все API вызовы через `/api/...`

**Это наш выбор** (обсуждали ранее - Variant B).

---

## План действий

### Фаза 1: Подготовка CloudFlare Tunnel

#### 1.1 Создать API Token для Tunnel
**Где**: https://dash.cloudflare.com/profile/api-tokens

**Permissions** (Account-scoped, НЕ Zone-scoped!):
- `Account > Cloudflare Tunnel > Edit` - для создания и управления туннелями
- `Zone > DNS > Edit` - для автоматического создания DNS записей (уже есть)

Примечание: Это ДРУГОЙ токен, не тот что для cert-manager DNS01.

#### 1.2 Создать Tunnel
**Где**: https://one.dash.cloudflare.com/ → Networks → Tunnels

1. Click "Create a tunnel"
2. Type: Cloudflared
3. Name: `minikube-dev` (или `gitops-poc-dev`)
4. Environment: Docker
5. **Скопировать Tunnel Token** (формат: `eyJhIjo...`)

#### 1.3 Добавить в .env
```bash
# CloudFlare Tunnel for local K8s access
CLOUDFLARE_TUNNEL_TOKEN="eyJhIjo..."
```

### Фаза 2: Настройка Gateway API

#### 2.1 Обновить platform-bootstrap values.yaml
```yaml
gateway:
  enabled: true  # ← Включить
  gatewayClassName: cilium

  certManager:
    enabled: true
    clusterIssuer: letsencrypt-staging  # Сначала staging для тестов

  listeners:
    https-app:
      hostname: "app.demo-poc-01.work"
      protocol: HTTPS
      port: 443

    https-api:
      hostname: "api.demo-poc-01.work"
      protocol: HTTPS
      port: 443
```

#### 2.2 Создать ReferenceGrant (уже есть в templates)
Разрешает HTTPRoute из poc-dev роутить на Gateway в gateway-dev.

### Фаза 3: Обновить k8app до 3.6.0 + HTTPRoute

#### 3.1 Обновить версию в platform-bootstrap
```yaml
global:
  k8app:
    version: "3.6.0"  # ← Обновить с 3.5.2
```

#### 3.2 Добавить HTTPRoute в frontend конфигурацию
`services/sentry-demo/frontend/.cicd/default.yaml`:
```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: gateway-dev
      namespace: gateway-dev
      sectionName: https-app
  hostnames:
    - app.demo-poc-01.work
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: sentry-frontend-sv
          port: 4200
```

#### 3.3 Добавить HTTPRoute в api-gateway конфигурацию
`services/api-gateway/.cicd/default.yaml`:
```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: gateway-dev
      namespace: gateway-dev
      sectionName: https-app  # Тот же домен что и frontend
  hostnames:
    - app.demo-poc-01.work
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api-gateway-sv
          port: 8080
```

### Фаза 4: Исправить Frontend API URL

#### 4.1 Изменить environment.prod.ts
```typescript
export const environment = {
  production: true,
  sentryDsn: '...',
  apiUrl: '',  // ← Пустой - все через /api/
  version: '1.0.90'
};
```

#### 4.2 Пересобрать и запушить образ
```bash
cd services/sentry-demo
git add frontend/src/environments/
git commit -m "fix: use relative API URL for production"
git push
```

### Фаза 5: Deploy CloudFlare Tunnel

#### 5.1 Запустить setup script
```bash
./infrastructure/cloudflare-tunnel/setup.sh
```

#### 5.2 Настроить Public Hostname в CloudFlare Dashboard
**Где**: https://one.dash.cloudflare.com/ → Networks → Tunnels → minikube-dev → Public Hostname

| Public Hostname | Service |
|-----------------|---------|
| app.demo-poc-01.work | http://gateway-dev-cilium-gateway.gateway-dev.svc:80 |
| api.demo-poc-01.work | http://gateway-dev-cilium-gateway.gateway-dev.svc:80 |

### Фаза 6: Проверка

#### 6.1 Проверить Gateway и HTTPRoutes
```bash
kubectl get gateway -n gateway-dev
kubectl get httproute -n poc-dev
kubectl get certificate -n gateway-dev
```

#### 6.2 Проверить tunnel connectivity
```bash
kubectl logs -n cloudflare -l app=cloudflared
```

#### 6.3 Тест в браузере
1. Открыть https://app.demo-poc-01.work
2. Проверить DevTools Network - API запросы должны идти на /api/*
3. Проверить что frontend загружается
4. Проверить что API отвечает

---

## Необходимые токены CloudFlare

| Токен | Scope | Permissions | Использование |
|-------|-------|-------------|---------------|
| DNS Token (есть) | Zone: demo-poc-01.work | DNS:Edit | cert-manager DNS01 challenge |
| **Tunnel Token (нужен)** | Account | Cloudflare Tunnel:Edit | Создание/управление туннелем |

---

## Риски и митигация

| Риск | Митигация |
|------|-----------|
| Let's Encrypt rate limit | Использовать letsencrypt-staging для тестов |
| Frontend билд с неправильным URL | Использовать относительный путь `/api` |
| CloudFlare Tunnel downtime | 2 реплики cloudflared |
| Gateway не принимает трафик | Проверить allowedRoutes в Gateway spec |

---

## Чеклист для выполнения

- [ ] Создать Tunnel API Token в CloudFlare
- [ ] Создать Tunnel в CloudFlare Dashboard
- [ ] Добавить CLOUDFLARE_TUNNEL_TOKEN в .env
- [ ] Обновить gateway.enabled: true в values.yaml
- [ ] Настроить listeners для demo-poc-01.work
- [ ] Обновить k8app version до 3.6.0
- [ ] Добавить httpRoute в frontend config
- [ ] Добавить httpRoute в api-gateway config
- [ ] Исправить apiUrl в environment.prod.ts
- [ ] Пересобрать frontend image
- [ ] Deploy CloudFlare Tunnel
- [ ] Настроить Public Hostname в CloudFlare
- [ ] Протестировать в браузере
