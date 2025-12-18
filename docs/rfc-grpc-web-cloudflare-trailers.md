# RFC: gRPC-Web через Cloudflare Tunnel - Исследование и Решения

**Статус**: Draft
**Дата**: 2025-12-18
**Автор**: GitOps POC Team

---

## TL;DR - Выводы

1. **gRPC-Web через Cloudflare Tunnel Public Hostname официально НЕ поддерживается** - это подтверждено документацией и GitHub issues
2. **Причина**: Cloudflare Tunnel использует QUIC протокол по умолчанию, который не поддерживает HTTP trailers полностью
3. **Рабочие решения**:
   - **Решение A**: Использовать `--protocol http2` + `http2Origin: true` (экспериментально, но работает у некоторых пользователей)
   - **Решение B**: Connect Protocol вместо gRPC-Web (работает через любой прокси)
   - **Решение C**: Private Subnet Routing + WARP клиент (официально поддерживается)

---

## Содержание

1. [Архитектура текущей системы](#архитектура-текущей-системы)
2. [Что такое HTTP Trailers](#что-такое-http-trailers)
3. [Как работает gRPC-Web](#как-работает-grpc-web)
4. [Почему Cloudflare обрезает trailer frame](#почему-cloudflare-обрезает-trailer-frame)
5. [Исследование: что пробовали другие](#исследование-что-пробовали-другие)
6. [Доступные решения](#доступные-решения)
7. [Рекомендация](#рекомендация)
8. [Ссылки](#ссылки)

---

## Архитектура текущей системы

```
┌─────────┐     HTTPS      ┌─────────────────┐     QUIC      ┌─────────────┐
│ Browser │───────────────▶│ Cloudflare Edge │──────────────▶│ cloudflared │
│         │◀───────────────│    (CDN/WAF)    │◀──────────────│  (tunnel)   │
└─────────┘                └─────────────────┘               └──────┬──────┘
                                                                    │
                                                              HTTP/1.1
                                                                    │
                                                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                               │
│  ┌────────────────┐     HTTP/1.1      ┌─────────────┐      HTTP/2       │
│  │ Cilium Gateway │──────────────────▶│ api-gateway │──────────────────▶│
│  │ (Envoy inside) │◀──────────────────│   (Envoy)   │◀──────────────────│
│  └────────────────┘                   └──────┬──────┘                   │
│                                              │                          │
│                                         gRPC (H2)                       │
│                                              │                          │
│                                              ▼                          │
│                                       ┌─────────────┐                   │
│                                       │user-service │                   │
│                                       │   (gRPC)    │                   │
│                                       └─────────────┘                   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Текущая конфигурация cloudflared:

```yaml
# deployment.yaml
args:
  - tunnel
  - --no-autoupdate
  - --metrics
  - 0.0.0.0:2000
  - run
  - --token
  - $(TUNNEL_TOKEN)
```

**Проблема**: Используется протокол по умолчанию (QUIC), который не поддерживает HTTP trailers.

---

## Что такое HTTP Trailers

HTTP Trailers — заголовки, отправляемые **после** тела ответа. Определены в [RFC 7230 Section 4.1.2](https://datatracker.ietf.org/doc/html/rfc7230#section-4.1.2).

### HTTP/1.1 (chunked encoding):
```http
HTTP/1.1 200 OK
Transfer-Encoding: chunked
Trailer: grpc-status

5
Hello
0
grpc-status: 0
```

### HTTP/2:
```
HEADERS frame (:status 200)
DATA frame (body)
HEADERS frame (END_STREAM) ← trailers здесь
```

### Почему gRPC использует trailers?

1. **Статус после обработки**: `grpc-status` известен только после обработки всего запроса
2. **Streaming**: Для streaming RPC статус приходит после всех сообщений
3. **HTTP 200 ≠ gRPC OK**: HTTP status code показывает только "соединение установлено"

---

## Как работает gRPC-Web

gRPC-Web — адаптация gRPC для браузеров. Поскольку **браузеры не дают доступа к HTTP trailers**, gRPC-Web **кодирует их внутри тела ответа**.

### Формат фрейма gRPC-Web

```
┌─────────────────────────────────────────────────────┐
│          gRPC-Web Frame Format                      │
├─────────────────────────────────────────────────────┤
│ Byte 0   │ Bytes 1-4      │ Bytes 5+               │
│ Flag     │ Length (BE)    │ Payload                │
├──────────┼────────────────┼────────────────────────┤
│ 0x00     │ msg length     │ protobuf (DATA)        │
│ 0x80     │ trailer length │ "grpc-status:0\r\n"    │
└──────────┴────────────────┴────────────────────────┘
```

### Пример ответа gRPC-Web:

```
HTTP/1.1 200 OK
content-type: application/grpc-web+proto

[0x00][0x00 0x01 0x9c]<protobuf data - 412 bytes>
[0x80][0x00 0x00 0x0f]grpc-status:0\r\n
```

**Второй фрейм (0x80) — это "псевдо-trailer" внутри body!**

### Наша проблема

Декодированный ответ от браузера (417 bytes):
```
Frame 1: [0x00] DATA - 412 bytes (LoginResponse с токенами) ✓
Frame 2: [0x80] TRAILER - ОТСУТСТВУЕТ ✗
```

Клиент получает данные, но не видит `grpc-status`, поэтому возвращает ошибку `[unknown] missing trailer`.

---

## Почему Cloudflare обрезает trailer frame

### 1. QUIC Protocol (default)

cloudflared по умолчанию использует QUIC для связи с Cloudflare edge. Согласно [GitHub Issue #491](https://github.com/cloudflare/cloudflared/issues/491):

> "We determined that while HTTP/2 transport between cloudflared and edge could support trailers after testing, QUIC presents a more substantial challenge because their HTTP request proxy protocol over QUIC isn't HTTP/3, leaving them without the necessary framing for trailer support."

### 2. Cloudflare Edge Architecture

Cloudflare использует NGINX на edge, который имеет ограниченную поддержку trailers. Их решение (из [блога "Road to gRPC"](https://blog.cloudflare.com/road-to-grpc/)):

> "We convert gRPC messages to HTTP/1.1 messages without a trailer inside our network, and then convert them back to HTTP/2 before sending the request off to origin."

**Но это работает только для Cloudflare CDN (оранжевая иконка), НЕ для Tunnel!**

### 3. Response Buffering

Cloudflare буферизует ответы для оптимизации. При буферизации:
- `Transfer-Encoding: chunked` может быть заменен на `Content-Length`
- Trailers теряются при конвертации

### 4. Двойная трансляция в нашем стеке

```
Browser (gRPC-Web)
    → Cloudflare (HTTP/1.1, может удалить chunked)
    → cloudflared (QUIC - trailers не поддерживаются полностью)
    → Cilium Gateway (автоматически добавляет grpc_web filter!)
    → api-gateway Envoy (grpc_web filter)
    → user-service (gRPC)
```

**Cilium автоматически инжектит `envoy.filters.http.grpc_web`** в все HTTPRoute ([Issue #31933](https://github.com/cilium/cilium/issues/31933)). Это может вызывать double-translation.

---

## Исследование: что пробовали другие

### Успешные конфигурации

#### 1. HTTP/2 Protocol + http2Origin

Из [Cloudflare Community](https://community.cloudflare.com/t/cloudflare-tunnel-with-grpc-h2c-h2/395628):

> "Spun up a quick python grpcio server and it properly works via tunnel forced to http2/with http2 to origin. When QUIC is used instead of http2 it properly doesn't work as expected."

**Конфигурация:**
```yaml
# cloudflared config.yaml
tunnel: <tunnel-id>
credentials-file: ~/.cloudflared/<tunnel-id>.json
ingress:
  - hostname: grpc.example.com
    service: https://localhost:8443
    originRequest:
      http2Origin: true      # Использовать HTTP/2 к origin
      noTLSVerify: true      # Если self-signed cert
  - service: http_status:404
```

**Или через CLI:**
```bash
cloudflared --protocol http2 tunnel run --token <token>
```

#### 2. Private Subnet Routing (официально поддерживается)

Из [Cloudflare docs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/grpc/):

> "Cloudflare Tunnel supports gRPC traffic via private subnet routing. Public hostname deployments are not currently supported."

Это требует:
- WARP клиент на устройстве
- Enrollment в Zero Trust организацию
- Private IP routing через туннель

### Неуспешные попытки

1. **gRPC-Web через Public Hostname** - официально не поддерживается
2. **QUIC + gRPC** - trailers не работают
3. **Отключение grpc_web filter в Cilium** - закрыто как "not planned" ([#31933](https://github.com/cilium/cilium/issues/31933))

---

## Доступные решения

### Решение A: HTTP/2 Protocol для cloudflared

**Изменения в deployment.yaml:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: cloudflare
spec:
  template:
    spec:
      containers:
        - name: cloudflared
          image: cloudflare/cloudflared:latest
          args:
            - tunnel
            - --protocol
            - http2              # ДОБАВИТЬ: форсировать HTTP/2
            - --no-autoupdate
            - --metrics
            - 0.0.0.0:2000
            - run
            - --token
            - $(TUNNEL_TOKEN)
```

**Плюс в Cloudflare Dashboard** для ingress правила:
- Service Type: HTTPS (не HTTP!)
- URL: `https://cilium-gateway-gateway.poc-dev.svc.cluster.local:443`
- Origin Request: `http2Origin: true`, `noTLSVerify: true`

**Требования:**
- Origin должен поддерживать TLS (можно self-signed)
- Cilium Gateway должен слушать HTTPS

| Pros | Cons |
|------|------|
| Минимальные изменения | Экспериментально, не гарантировано |
| Сохраняет gRPC-Web | Требует TLS на origin |
| Работает у некоторых пользователей | Может перестать работать |

### Решение B: Connect Protocol

Connect — протокол от Buf, который не использует trailers.

**Как это работает:**

```
gRPC-Web (с trailers):
POST /user.v1.UserService/Login
Content-Type: application/grpc-web+proto
[0x00][length][protobuf]
[0x80][length]grpc-status:0

Connect (без trailers):
POST /user.v1.UserService/Login
Content-Type: application/json
{"email": "test@test.com", "password": "***"}

Response:
HTTP 200 OK
Content-Type: application/json
{"userId": "123", "accessToken": "..."}

Error:
HTTP 401 Unauthorized
Content-Type: application/json
{"code": "unauthenticated", "message": "invalid credentials"}
```

**Изменения:**

1. **Backend (user-service)** - добавить connect-go:
```go
import "connectrpc.com/connect"

mux := http.NewServeMux()
path, handler := userv1connect.NewUserServiceHandler(&UserServiceServer{})
mux.Handle(path, handler)
```

2. **Frontend** - использовать Connect transport:
```typescript
import { createConnectTransport } from '@connectrpc/connect-web';

const transport = createConnectTransport({
  baseUrl: '/api',
});
```

| Pros | Cons |
|------|------|
| Работает через любой прокси | Изменения в backend |
| JSON readable в DevTools | Не стандартный gRPC |
| Официально поддерживается Buf | Две реализации |
| Меньше bundle size |  |

### Решение C: Private Subnet Routing + WARP

**Архитектура:**
```
Browser + WARP → Cloudflare Network → Tunnel → Private IP → gRPC Backend
```

**Настройка:**
1. В Cloudflare Zero Trust → Networks → Tunnels → выбрать туннель
2. Добавить Private Network (CIDR вашего кластера)
3. На клиенте установить WARP и подключиться к организации

| Pros | Cons |
|------|------|
| Официально поддерживается | Требует WARP на клиенте |
| Полный gRPC (не только Web) | Не для публичного доступа |
| Zero Trust security | Сложнее настройка |

### Решение D: DNS-only режим Cloudflare

Отключить проксирование Cloudflare (серая иконка облака).

| Pros | Cons |
|------|------|
| Мгновенное решение | Потеря DDoS protection |
| gRPC-Web работает | Потеря CDN/WAF |
| Нет изменений в коде | Прямой доступ к IP |

---

## Рекомендация

### Для POC/Dev окружения: Решение A (HTTP/2 Protocol)

1. Изменить deployment cloudflared:
```yaml
args:
  - tunnel
  - --protocol
  - http2
  - ...
```

2. В Cloudflare Dashboard настроить origin как HTTPS с http2Origin

3. Настроить TLS на Cilium Gateway (cert-manager)

### Для Production: Решение B (Connect Protocol)

1. Добавить connect-go в user-service
2. Обновить frontend на Connect transport
3. Connect handler автоматически поддерживает и gRPC, и Connect

### Как протестировать Решение A сейчас

```bash
# 1. Обновить cloudflared deployment
kubectl patch deployment cloudflared -n cloudflare --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/2", "value": "--protocol"},
  {"op": "add", "path": "/spec/template/spec/containers/0/args/3", "value": "http2"}
]'

# 2. Проверить логи
kubectl logs -n cloudflare -l app=cloudflared -f

# 3. Проверить протокол в логах - должен быть HTTP/2
```

---

## Ссылки

### Официальная документация
- [Cloudflare gRPC Support](https://developers.cloudflare.com/network/grpc-connections/)
- [Cloudflare Tunnel gRPC Use Case](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/grpc/)
- [Cloudflare Origin Parameters](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/configure-tunnels/cloudflared-parameters/origin-parameters/)
- [Envoy gRPC-Web Filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/grpc_web_filter)
- [Connect Protocol Specification](https://connectrpc.com/docs/protocol)

### Блоги и статьи
- [Cloudflare: Road to gRPC](https://blog.cloudflare.com/road-to-grpc/) - как Cloudflare решали проблему trailers
- [Koyeb: gRPC and HTTP/2 with Envoy](https://www.koyeb.com/blog/enabling-grpc-and-http2-support-at-edge-with-kuma-and-envoy)

### GitHub Issues
- [cloudflared #491: gRPC Support](https://github.com/cloudflare/cloudflared/issues/491) - основной issue о поддержке gRPC
- [cloudflared #226: HTTP/2 Support](https://github.com/cloudflare/cloudflared/issues/226)
- [Cilium #31933: gRPC-Web Filter Injection](https://github.com/cilium/cilium/issues/31933) - проблема автоматического grpc_web filter
- [Envoy #9831: Trailers Dropped with Content-Length](https://github.com/envoyproxy/envoy/issues/9831)
- [grpc-web #1027: Missing Trailers через Cloudflare](https://github.com/grpc/grpc-web/issues/1027)

### Community
- [Cloudflare Community: Tunnel with gRPC](https://community.cloudflare.com/t/cloudflare-tunnel-with-grpc-h2c-h2/395628)

---

## Заключение

**gRPC-Web через Cloudflare Tunnel Public Hostname — это известная проблема без официального решения.**

Cloudflare:
- Поддерживает gRPC через CDN (оранжевая иконка) с конвертацией gRPC ↔ gRPC-Web
- НЕ поддерживает gRPC/gRPC-Web через Tunnel Public Hostname
- Поддерживает gRPC через Tunnel Private Subnet Routing (с WARP клиентом)

**Workaround с `--protocol http2` работает у некоторых пользователей**, но не гарантирован и может сломаться.

**Connect Protocol — самое надежное долгосрочное решение** для публичного API через любой HTTP прокси.
