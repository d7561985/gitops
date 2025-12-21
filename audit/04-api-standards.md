# API Standards: Buf + ConnectRPC

## Обзор

Данный документ описывает стандарты API в платформе: использование Protocol Buffers, Buf для генерации кода, и Connect Protocol для коммуникации.

---

## Ключевые компоненты

### 1. Protocol Buffers (Protobuf)

**Что это:** Язык описания интерфейсов (IDL) от Google для сериализации структурированных данных.

**Преимущества:**
- Строгая типизация
- Компактный бинарный формат
- Кодогенерация для множества языков
- Обратная совместимость

### 2. Buf

**Что это:** Современный инструмент для работы с Protobuf (замена protoc).

**Возможности:**
- Linting (проверка стиля)
- Breaking change detection
- Code generation
- BSR (Buf Schema Registry)

**Версия:** v2 (указано в `buf.yaml`)

### 3. Connect Protocol

**Что это:** Протокол от Buf для HTTP API, совместимый с gRPC.

**Преимущества перед gRPC-Web:**
- Не требует прокси
- Работает через любой HTTP/1.1+
- JSON debugging (cURL-friendly)
- TypeScript-first

**Источник анализа:** [`docs/embodiment/frontend-grpc-protocols-2025.md`](../docs/embodiment/frontend-grpc-protocols-2025.md)

---

## Принцип: Единый API Endpoint

### Архитектура маршрутизации

**Ключевой принцип: ВСЕ API доступны через единый домен и path `/api/*`**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     SINGLE DOMAIN API ROUTING                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ВМЕСТО:                         ИСПОЛЬЗУЕМ:                             │
│  ────────                        ───────────                             │
│  api-users.example.com           example.com/api/user/*                 │
│  api-payment.example.com    →    example.com/api/payment/*              │
│  api-game.example.com            example.com/api/game/*                 │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                                                                     │ │
│  │  Client (Browser/Mobile)                                           │ │
│  │  ─────────────────────────                                         │ │
│  │  POST https://app.example.com/api/user/user.v1.UserService/Login  │ │
│  │  POST https://app.example.com/api/game/calculate                  │ │
│  │  POST https://app.example.com/api/payment/process                 │ │
│  │                                                                     │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                          │                                               │
│                          ▼                                               │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  Cilium Gateway (HTTPRoute)                                         │ │
│  │  ────────────────────────────                                       │ │
│  │  /api/*  → api-gateway-sv:8080                                     │ │
│  │  /*      → frontend-sv:4200                                        │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                          │                                               │
│                          ▼                                               │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  API Gateway (Envoy)                                                │ │
│  │  ───────────────────                                                │ │
│  │  /api/user/*      → user-service:8081      (strip /api/user)       │ │
│  │  /api/game/*      → game-engine:8082       (strip /api/game)       │ │
│  │  /api/payment/*   → payment-service:8083   (strip /api/payment)    │ │
│  │  /api/wager/*     → wager-service:8084     (strip /api/wager)      │ │
│  │                                                                     │ │
│  │  Connect Protocol routes:                                           │ │
│  │  /api/userconnect/*     → user-service     (Connect RPC)           │ │
│  │  /api/gameconnect/*     → game-engine      (Connect RPC)           │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Преимущества

| Аспект | Отдельные домены | Единый /api/* |
|--------|-----------------|---------------|
| **SSL сертификаты** | N сертификатов | 1 сертификат |
| **CORS** | Сложная настройка | Не нужен (same-origin) |
| **DNS записи** | N записей | 1 запись |
| **CloudFlare Tunnel** | N ingress rules | 1 ingress rule |
| **Cookies/Auth** | Cross-domain issues | Автоматически работает |
| **Мониторинг** | Разрозненные метрики | Единая точка входа |

### Конфигурация

**HTTPRoute (Cilium Gateway):**

```yaml
# services/api-gateway/.cicd/default.yaml
httpRoute:
  enabled: true
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api           # ← Все API через /api
      backendRefs:
        - name: api-gateway-sv
          port: 8080
```

**API Gateway (Envoy) routing:**

```yaml
# services/api-gateway/config.yaml
api_route: /api/

clusters:
  - name: user
    cluster: user-service
    prefix: /user               # /api/user/* → user-service
    strip_prefix: true

  - name: game
    cluster: sentry-game-engine
    prefix: /game               # /api/game/* → game-engine
    strip_prefix: true

  - name: payment
    cluster: sentry-payment
    prefix: /payment            # /api/payment/* → payment-service
    strip_prefix: true
```

**Источник:** [`services/api-gateway/config.yaml`](../services/api-gateway/config.yaml), [`services/api-gateway/.cicd/default.yaml:157-171`](../services/api-gateway/.cicd/default.yaml)

### Guidelines для команд

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     API ROUTING GUIDELINES                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ✅ DO:                                                                  │
│  ─────                                                                   │
│  • Регистрируйте новый сервис в api-gateway/config.yaml                │
│  • Используйте /api/{service}/* pattern                                │
│  • Используйте Connect Protocol для новых API                          │
│  • Frontend вызывает /api/... (relative path)                          │
│                                                                          │
│  ❌ DON'T:                                                               │
│  ────────                                                                │
│  • НЕ создавайте отдельные домены для API                              │
│  • НЕ создавайте отдельные HTTPRoutes для backend сервисов             │
│  • НЕ используйте absolute URLs с разными доменами                     │
│  • НЕ обходите api-gateway для внешних вызовов                         │
│                                                                          │
│  ДОБАВЛЕНИЕ НОВОГО API:                                                  │
│  ──────────────────────                                                  │
│  1. Добавьте cluster в api-gateway/config.yaml                         │
│  2. Укажите prefix (/api/{service})                                    │
│  3. Укажите backend cluster                                             │
│  4. Протестируйте через curl https://domain/api/{service}/endpoint    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Архитектура API Registry

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        API REGISTRY ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  api/                                                                    │
│  ├── proto/                          ← Proto definitions (source)      │
│  │   ├── user-service/                                                  │
│  │   │   ├── buf.yaml                                                   │
│  │   │   ├── buf.gen.yaml                                               │
│  │   │   └── proto/v1/                                                  │
│  │   │       ├── user.proto                                             │
│  │   │       └── auth.proto                                             │
│  │   │                                                                   │
│  │   ├── game-engine/                                                   │
│  │   ├── payment-service/                                               │
│  │   └── wager-service/                                                 │
│  │                                                                       │
│  └── gen/                            ← Generated code (artifacts)       │
│      ├── go/                         → go get ...                       │
│      ├── nodejs/                     → npm install ...                  │
│      ├── php/                        → composer require ...             │
│      ├── python/                     → pip install ...                  │
│      └── angular/                    → npm install ...                  │
│                                                                          │
│  CI Flow:                                                                │
│  ────────                                                                │
│  git push proto/ → CI lint → breaking check → buf generate → publish   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источник:** [`api/proto/`](../api/proto/), [`docs/proto-grpc-infrastructure.md`](../docs/proto-grpc-infrastructure.md)

---

## Proto Definition Structure

### Directory Layout

```
api/proto/{service}/
├── buf.yaml              # Module configuration
├── buf.gen.yaml          # Code generation configuration
└── proto/
    └── v1/
        ├── service.proto # Service definitions
        └── types.proto   # Message types
```

### Example: user-service

```protobuf
// api/proto/user-service/proto/v1/user.proto

syntax = "proto3";

package user.v1;

option go_package = "github.com/gitops-poc-dzha/api-gen/go/user/v1;userv1";

// Service definition
service UserService {
  // Unary RPC
  rpc GetUser(GetUserRequest) returns (GetUserResponse);

  // Unary RPC for registration
  rpc Register(RegisterRequest) returns (RegisterResponse);

  // Unary RPC for login
  rpc Login(LoginRequest) returns (LoginResponse);
}

// Request/Response messages
message GetUserRequest {
  string user_id = 1;
}

message GetUserResponse {
  User user = 1;
}

message User {
  string id = 1;
  string email = 2;
  string name = 3;
  google.protobuf.Timestamp created_at = 4;
}

message RegisterRequest {
  string email = 1;
  string password = 2;
  string name = 3;
}

message RegisterResponse {
  string user_id = 1;
  string access_token = 2;
}
```

---

## Buf Configuration

### buf.yaml (Module Config)

```yaml
# api/proto/user-service/buf.yaml
version: v2

modules:
  - path: proto

breaking:
  use:
    - FILE

lint:
  use:
    - DEFAULT
  except:
    - PACKAGE_VERSION_SUFFIX
```

### buf.gen.yaml (Generation Config)

```yaml
# api/proto/user-service/buf.gen.yaml
version: v2

plugins:
  # Go
  - remote: buf.build/protocolbuffers/go
    out: gen/go
    opt: paths=source_relative

  - remote: buf.build/connectrpc/go
    out: gen/go
    opt: paths=source_relative

  # TypeScript/JavaScript
  - remote: buf.build/bufbuild/es
    out: gen/ts
    opt: target=ts

  - remote: buf.build/connectrpc/es
    out: gen/ts
    opt: target=ts

  # PHP
  - remote: buf.build/protocolbuffers/php
    out: gen/php

  # Python
  - remote: buf.build/protocolbuffers/python
    out: gen/python
```

**Источник:** [`docs/proto-grpc-infrastructure.md`](../docs/proto-grpc-infrastructure.md)

---

## Code Generation Flow

### CI Pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PROTO GENERATION CI PIPELINE                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  TRIGGER: git push to api/proto/{service}/                              │
│                                                                          │
│  STAGE 1: Lint                                                           │
│  ─────────────                                                           │
│  buf lint                                                                │
│  • Check naming conventions                                              │
│  • Validate proto syntax                                                 │
│  • Style enforcement                                                     │
│                                                                          │
│  STAGE 2: Breaking Change Detection                                      │
│  ───────────────────────────────────                                     │
│  buf breaking --against .git#branch=main                                │
│  • Detect removed fields                                                 │
│  • Detect type changes                                                   │
│  • Detect renamed methods                                                │
│  • BLOCKS merge if breaking                                              │
│                                                                          │
│  STAGE 3: Generate                                                       │
│  ────────────────                                                        │
│  buf generate                                                            │
│  • Go code                                                               │
│  • TypeScript code                                                       │
│  • PHP code                                                              │
│  • Python code                                                           │
│                                                                          │
│  STAGE 4: Publish                                                        │
│  ───────────────                                                         │
│  • Push to api/gen/ repository                                          │
│  • Tag with version                                                      │
│  • Trigger downstream builds                                             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Versioning

| Branch | Version | Use Case |
|--------|---------|----------|
| `dev` | `v0.0.0-{sha}` | Development snapshots |
| `main` + tag | `v1.2.3` | Stable releases |

**Источник:** [`docs/proto-grpc-infrastructure.md`](../docs/proto-grpc-infrastructure.md)

---

## Connect Protocol

### Why Connect over gRPC-Web

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   gRPC-Web vs Connect COMPARISON                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                    gRPC-Web                    Connect                   │
│                    ────────                    ───────                   │
│  Architecture:                                                           │
│  ┌─────────┐      ┌─────────┐      ┌────────┐   ┌─────────┐   ┌────────┐│
│  │ Browser │─────►│ Envoy   │─────►│ gRPC   │   │ Browser │──►│Connect │││
│  │         │      │ (proxy) │      │ Server │   │         │   │Server  │││
│  └─────────┘      └─────────┘      └────────┘   └─────────┘   └────────┘│
│                                                                          │
│  ✗ Requires proxy                  ✓ No proxy needed                   │
│  ✗ Binary only debugging           ✓ JSON debugging (cURL-friendly)    │
│  ✗ Poor TypeScript support         ✓ TypeScript-first                  │
│  ✗ CommonJS only                   ✓ ES Modules                        │
│  ✗ Complex trailers handling       ✓ Standard HTTP semantics           │
│                                                                          │
│  CloudFlare Issue:                                                       │
│  ─────────────────                                                       │
│  gRPC-Web trailers stripped by CloudFlare Tunnel (QUIC protocol)        │
│  Connect works through any HTTP proxy                                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источник:** [`docs/rfc-grpc-web-cloudflare-trailers.md`](../docs/rfc-grpc-web-cloudflare-trailers.md)

### Connect Implementation

#### Backend (Go)

```go
// user-service/main.go

package main

import (
    "net/http"

    "connectrpc.com/connect"
    "github.com/gitops-poc-dzha/user-service/gen/user/v1/userv1connect"
)

func main() {
    mux := http.NewServeMux()

    // Connect handler supports:
    // - Connect Protocol (native)
    // - gRPC Protocol
    // - gRPC-Web Protocol
    path, handler := userv1connect.NewUserServiceHandler(&UserServiceServer{})
    mux.Handle(path, handler)

    http.ListenAndServe(":8081", mux)
}
```

#### Frontend (TypeScript)

```typescript
// frontend/src/services/user.service.ts

import { createClient } from "@connectrpc/connect";
import { createConnectTransport } from "@connectrpc/connect-web";
import { UserService } from "./gen/user/v1/user_pb";

const transport = createConnectTransport({
  baseUrl: "/api/user",  // Proxied through api-gateway
});

const client = createClient(UserService, transport);

// Type-safe, auto-complete works!
async function getUser(userId: string) {
  const response = await client.getUser({ userId });
  console.log(response.user?.name);  // Full type inference
}
```

**Источник:** [`docs/connect-migration-architecture.md`](../docs/connect-migration-architecture.md)

---

## API Gateway Integration

### Envoy Routing

```yaml
# api-gateway/config.yaml

clusters:
  - name: user-service
    addr: "user-service-sv:8081"
    type: "http"              # NOT grpc!
    health_check:
      path: "/health"

apis:
  - name: user
    cluster: user-service
    methods:
      - name: user.v1.UserService/Register
        auth: {policy: no-need}
      - name: user.v1.UserService/Login
        auth: {policy: no-need}
      - name: user.v1.UserService/GetUser
        auth: {policy: jwt-required}
```

### Request Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     CONNECT REQUEST FLOW                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Browser                                                                 │
│  ───────                                                                 │
│  POST /api/user/user.v1.UserService/Register                            │
│  Content-Type: application/json                                          │
│  {"email": "test@test.com", "password": "***", "name": "John"}          │
│                                                                          │
│       │                                                                  │
│       ▼                                                                  │
│                                                                          │
│  CloudFlare Tunnel → Cilium Gateway → HTTPRoute                         │
│                                                                          │
│       │                                                                  │
│       ▼                                                                  │
│                                                                          │
│  api-gateway (Envoy)                                                     │
│  ────────────────────                                                    │
│  Route: /api/user/* → user-service cluster                              │
│  Strip: /api/user prefix                                                 │
│  Forward: /user.v1.UserService/Register                                 │
│                                                                          │
│       │                                                                  │
│       ▼                                                                  │
│                                                                          │
│  user-service (Connect Handler)                                          │
│  ──────────────────────────────                                          │
│  Accepts: Connect, gRPC, gRPC-Web                                       │
│  Response: application/json                                              │
│  {"userId": "123", "accessToken": "eyJhbGciOiJ..."}                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источник:** [`docs/rfc-grpc-web-cloudflare-trailers.md:29-46`](../docs/rfc-grpc-web-cloudflare-trailers.md)

---

## Generated Code Usage

### Go

```go
// Import generated code
import (
    userv1 "github.com/gitops-poc-dzha/api-gen/go/user/v1"
    "github.com/gitops-poc-dzha/api-gen/go/user/v1/userv1connect"
)

// Create client
client := userv1connect.NewUserServiceClient(
    http.DefaultClient,
    "http://user-service:8081",
)

// Type-safe call
resp, err := client.GetUser(ctx, connect.NewRequest(&userv1.GetUserRequest{
    UserId: "123",
}))
```

### TypeScript/Angular

```typescript
// Import generated code
import { UserService } from "@gitops-poc-dzha/api-gen-ts/user/v1/user_pb";
import { createClient } from "@connectrpc/connect";
import { createConnectTransport } from "@connectrpc/connect-web";

// Create client
const transport = createConnectTransport({ baseUrl: "/api/user" });
const client = createClient(UserService, transport);

// Type-safe call
const user = await client.getUser({ userId: "123" });
console.log(user.name);
```

### PHP

```php
<?php
// Import generated code
use User\V1\UserServiceClient;
use User\V1\GetUserRequest;

// Create client
$client = new UserServiceClient('user-service:50051', [
    'credentials' => \Grpc\ChannelCredentials::createInsecure(),
]);

// gRPC call
$request = new GetUserRequest();
$request->setUserId("123");
[$response, $status] = $client->GetUser($request)->wait();
```

### Python

```python
# Import generated code
from user.v1 import user_pb2, user_pb2_grpc
import grpc

# Create client
channel = grpc.insecure_channel('user-service:50051')
stub = user_pb2_grpc.UserServiceStub(channel)

# gRPC call
request = user_pb2.GetUserRequest(user_id="123")
response = stub.GetUser(request)
print(response.user.name)
```

---

## Breaking Change Detection

### What is Detected

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     BREAKING CHANGE DETECTION                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  WIRE-BREAKING (блокирует merge):                                       │
│  ─────────────────────────────────                                       │
│  • Removing a field                                                      │
│  • Changing field number                                                 │
│  • Changing field type                                                   │
│  • Removing RPC method                                                   │
│  • Changing RPC request/response type                                   │
│                                                                          │
│  SOURCE-BREAKING (предупреждение):                                       │
│  ──────────────────────────────────                                      │
│  • Renaming message                                                      │
│  • Renaming field                                                        │
│  • Renaming enum value                                                   │
│                                                                          │
│  SAFE CHANGES (разрешены):                                               │
│  ─────────────────────────                                               │
│  • Adding new field                                                      │
│  • Adding new RPC method                                                 │
│  • Adding new message                                                    │
│  • Adding new enum value                                                 │
│  • Changing comments                                                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### CI Check

```bash
# In CI pipeline
buf breaking --against .git#branch=main

# Example output on breaking change:
# proto/v1/user.proto:15:3:Field "1" on message "User" changed type from "string" to "int64".
# Error: breaking changes detected
```

---

## Best Practices

### Naming Conventions

```protobuf
// Package naming
package user.v1;                    // domain.version

// Service naming
service UserService {}              // {Domain}Service

// RPC naming
rpc GetUser(GetUserRequest)         // Verb + Noun
    returns (GetUserResponse);

// Message naming
message GetUserRequest {            // {RPC}Request
  string user_id = 1;               // snake_case
}

// Enum naming
enum UserStatus {
  USER_STATUS_UNSPECIFIED = 0;      // {ENUM}_UNSPECIFIED = 0
  USER_STATUS_ACTIVE = 1;           // {ENUM}_{VALUE}
  USER_STATUS_INACTIVE = 2;
}
```

### Versioning Strategy

```protobuf
// Use package versioning
package user.v1;                    // Current stable
package user.v2;                    // New version (breaking changes)

// Coexistence during migration:
// - v1 endpoints: /user.v1.UserService/GetUser
// - v2 endpoints: /user.v2.UserService/GetUser
```

### Documentation

```protobuf
// Document everything
service UserService {
  // GetUser retrieves a user by their unique identifier.
  // Returns NOT_FOUND if the user does not exist.
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
}

message User {
  // Unique identifier for the user (UUID format).
  string id = 1;

  // Email address (must be unique across the system).
  string email = 2;
}
```

---

## Migration from gRPC-Web

### Step-by-Step

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     MIGRATION TO CONNECT                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  STEP 1: Update buf.gen.yaml                                            │
│  ───────────────────────────────                                         │
│  + - remote: buf.build/connectrpc/es                                    │
│  +   out: gen/ts                                                        │
│  +   opt: target=ts                                                     │
│                                                                          │
│  STEP 2: Update backend                                                  │
│  ─────────────────────                                                   │
│  - grpc.Server → http.Server + connectrpc.com/connect                   │
│  - Same proto files, different handler                                   │
│                                                                          │
│  STEP 3: Update frontend                                                 │
│  ──────────────────────                                                  │
│  - grpc-web client → @connectrpc/connect-web                            │
│  - createGrpcWebTransport → createConnectTransport                      │
│                                                                          │
│  STEP 4: Update api-gateway                                              │
│  ───────────────────────────                                             │
│  - cluster type: "grpc" → "http"                                        │
│  - No grpc_web filter needed                                             │
│                                                                          │
│  Backward Compatibility:                                                 │
│  ─────────────────────────                                               │
│  Connect handler accepts ALL protocols:                                  │
│  • Connect (new)                                                         │
│  • gRPC (native)                                                         │
│  • gRPC-Web (legacy)                                                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Источник:** [`docs/connect-migration-plan.md`](../docs/connect-migration-plan.md)

---

## Benefits of API Registry

### For Development Teams

| Benefit | Description |
|---------|-------------|
| **Type Safety** | Compile-time errors instead of runtime |
| **Auto-complete** | IDE support for all API calls |
| **Documentation** | Proto comments → generated docs |
| **Consistency** | Same contract across all languages |

### For Organization

| Benefit | Description |
|---------|-------------|
| **Discoverability** | Centralized API catalog |
| **Reusability** | Import packages instead of copy-paste |
| **Governance** | Breaking change detection |
| **Versioning** | Clear upgrade path |

---

## Связанные документы

- [Executive Summary](./00-executive-summary.md)
- [Developer Experience](./03-developer-experience.md)
- [RFC: gRPC-Web CloudFlare](../docs/rfc-grpc-web-cloudflare-trailers.md)
- [Connect Migration](../docs/connect-migration-architecture.md)

---

*Документ создан на основе аудита кодовой базы GitOps POC*
*Дата: 2025-12-21*
