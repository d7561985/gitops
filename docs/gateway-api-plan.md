# Gateway API + CloudFlare Tunnel Integration

## Архитектура

```
┌─────────────────────────────────────────────────────────────────┐
│                        CloudFlare Edge                          │
│                                                                  │
│    app.demo-poc-01.work ──────┐                                 │
│                               ▼                                  │
│                    ┌──────────────────┐                         │
│                    │ CloudFlare Tunnel │                         │
│                    └────────┬─────────┘                         │
└─────────────────────────────┼───────────────────────────────────┘
                              │ (outbound QUIC/H2)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Minikube Cluster                            │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                 cloudflare namespace                     │    │
│  │  cloudflared (2 replicas)                               │    │
│  │  Routes to: cilium-gateway-gateway.poc-dev.svc:80       │    │
│  └─────────────────────────┬───────────────────────────────┘    │
│                            │                                     │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   poc-dev namespace                      │    │
│  │                                                          │    │
│  │  ┌──────────────────────────────────────────────────┐   │    │
│  │  │ Gateway: gateway (Cilium GatewayClass)           │   │    │
│  │  │ Listener: https-app (app.demo-poc-01.work:443)   │   │    │
│  │  │ TLS: cert-manager (letsencrypt-staging)          │   │    │
│  │  └──────────────────────────────────────────────────┘   │    │
│  │                            │                             │    │
│  │         ┌──────────────────┴──────────────────┐         │    │
│  │         ▼                                     ▼         │    │
│  │  ┌─────────────────┐              ┌─────────────────┐   │    │
│  │  │   HTTPRoute     │              │   HTTPRoute     │   │    │
│  │  │   Path: /api/*  │              │   Path: /*      │   │    │
│  │  └────────┬────────┘              └────────┬────────┘   │    │
│  │           ▼                                ▼            │    │
│  │  ┌─────────────────┐              ┌─────────────────┐   │    │
│  │  │ api-gateway-sv  │              │sentry-frontend-sv│   │    │
│  │  │    :8080        │              │     :4200       │   │    │
│  │  └─────────────────┘              └─────────────────┘   │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Настроенные компоненты

### 1. Gateway (poc-dev namespace)
- **Name**: `gateway`
- **GatewayClass**: `cilium`
- **Listener**: `https-app` на `app.demo-poc-01.work:443`
- **TLS**: автоматический через cert-manager (letsencrypt-staging)
- **Service**: Cilium создаёт `cilium-gateway-gateway` (LoadBalancer)

### 2. HTTPRoutes

**sentry-frontend** (Path: `/`):
```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: gateway
      namespace: poc-dev
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

**api-gateway** (Path: `/api`):
```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: gateway
      namespace: poc-dev
      sectionName: https-app
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

### 3. Frontend API URL
Production build использует относительный путь:
```typescript
apiUrl: ''  // API calls go to /api/* on same domain
```

## CloudFlare Tunnel Configuration

### В CloudFlare Dashboard
**Networks → Tunnels → [your-tunnel] → Public Hostname**:

| Setting | Value |
|---------|-------|
| Public hostname | `app.demo-poc-01.work` |
| Type | HTTP |
| URL | `cilium-gateway-gateway.poc-dev.svc:80` |

### Токены

| Токен | Назначение | Где создать |
|-------|------------|-------------|
| `CLOUDFLARE_API_TOKEN` | cert-manager DNS01 | [API Tokens](https://dash.cloudflare.com/profile/api-tokens) - Zone:DNS:Edit |
| `CLOUDFLARE_TUNNEL_TOKEN` | cloudflared runtime | [Zero Trust](https://one.dash.cloudflare.com/) → Networks → Tunnels |

## Проверка

```bash
# Gateway создан
kubectl get gateway -n poc-dev

# HTTPRoutes созданы
kubectl get httproute -n poc-dev

# Cilium service для Gateway
kubectl get svc -n poc-dev | grep cilium-gateway

# Certificate выдан
kubectl get certificate -n poc-dev

# Tunnel работает
kubectl logs -n cloudflare -l app=cloudflared

# Тест в браузере
open https://app.demo-poc-01.work
```
