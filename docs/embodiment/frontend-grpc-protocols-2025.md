# Frontend + Protobuf: Protocols Comparison 2025

Исследование современных протоколов коммуникации фронтенда с бэкендом при использовании Protobuf/gRPC.

## Содержание

- [Executive Summary](#executive-summary)
- [gRPC-Web: Проблемы](#grpc-web-проблемы)
- [Connect-RPC: Современная альтернатива](#connect-rpc-современная-альтернатива)
- [tRPC: TypeScript-only подход](#trpc-typescript-only-подход)
- [Envoy JSON Transcoding](#envoy-json-transcoding)
- [WebTransport: Будущее](#webtransport-будущее)
- [Сравнительная таблица](#сравнительная-таблица)
- [Рекомендация](#рекомендация)
- [Источники](#источники)

---

## Executive Summary

| Сценарий | Лучший выбор | Почему |
|----------|--------------|--------|
| **Новый проект с gRPC бэкендом** | **Connect-RPC** | Нет прокси, TypeScript-first, JSON debugging |
| **Полностью TypeScript stack** | **tRPC** | Без codegen, максимальный DX |
| **Legacy gRPC-Web** | Мигрировать на **Connect-RPC** | Совместим, лучше DX |
| **REST для фронтенда** | **Envoy JSON Transcoding** | gRPC бэкенд, REST/JSON для фронта |

**Тренд 2024-2025:** Миграция с gRPC-Web на Connect-RPC. Google's gRPC-Web теряет популярность из-за плохого TypeScript support и необходимости прокси.

---

## gRPC-Web: Проблемы

### Архитектурные ограничения

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       gRPC-Web ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Browser                    Proxy (Envoy)              gRPC Backend     │
│  ────────                   ──────────────             ────────────     │
│  gRPC-Web    ──HTTP/1.1──►  Translate    ──HTTP/2──►   Native gRPC     │
│  Client                     gRPC-Web→gRPC              Server           │
│                                                                          │
│  Проблемы:                                                               │
│  ├── Дополнительный hop (latency)                                       │
│  ├── Ещё один компонент для мониторинга                                 │
│  └── Конфигурация CORS на прокси                                        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Известные проблемы

| Проблема | Описание | Влияние |
|----------|----------|---------|
| **Требует прокси** | Envoy или nginx необходим для трансляции | Усложняет инфраструктуру |
| **Плохой TypeScript** | "Half-hearted experiment" (официально) | Плохой DX |
| **Setters/Getters** | Сгенерированный код как "decade-old Java" | Не идиоматичный TS |
| **Только CommonJS** | Нет ES Modules support | Большие бандлы |
| **Opaque responses** | Все ответы: `200 OK` + binary | Невозможно дебажить |
| **Лимит streams** | 6 connections per domain (browser) | Проблемы масштабирования |

### Streaming ограничения

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    gRPC-Web STREAMING SUPPORT                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Тип streaming          │ gRPC (native) │ gRPC-Web                      │
│  ───────────────────────┼───────────────┼──────────────────────────────│
│  Unary                  │     ✅        │     ✅                        │
│  Server streaming       │     ✅        │     ⚠️  (grpcwebtext only)    │
│  Client streaming       │     ✅        │     ❌  НЕ ПОДДЕРЖИВАЕТСЯ     │
│  Bidirectional          │     ✅        │     ❌  НЕ ПОДДЕРЖИВАЕТСЯ     │
│                                                                          │
│  Причина: Browser HTTP API не даёт контроль над HTTP/2 frames           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Roadmap gRPC-Web:**
- Client streaming: ждёт WebTransport (Safari блокирует)
- Bidirectional: ждёт WebTransport
- WebSockets: **НЕ ПЛАНИРУЕТСЯ** (несовместимо с HTTP инфраструктурой)

---

## Connect-RPC: Современная альтернатива

### Обзор

Connect-RPC — семейство библиотек от Buf для building browser и gRPC-compatible APIs. Присоединился к CNCF в 2024.

**Production использование:** CrowdStrike, PlanetScale, RedPanda, Chick-fil-A, Bluesky, Dropbox

### Архитектура

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Connect-RPC ARCHITECTURE                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Browser                              Backend (Go/Node/etc.)            │
│  ────────                             ──────────────────────            │
│  Connect                              Connect Handler                   │
│  Client     ───── HTTP/1.1+ ────────► (native support)                  │
│                                                                          │
│  Поддерживаемые протоколы:                                               │
│  ├── Connect Protocol (native, JSON-friendly)                           │
│  ├── gRPC Protocol (full compatibility)                                 │
│  └── gRPC-Web Protocol (для legacy)                                     │
│                                                                          │
│  Преимущества:                                                           │
│  ├── НЕТ ПРОКСИ (сервер понимает все протоколы)                        │
│  ├── JSON debugging (cURL-friendly)                                     │
│  └── Переключение протокола = 1 строка кода                            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Пример кода

```typescript
// Connect-RPC: Idiomatic TypeScript
import { createClient } from "@connectrpc/connect";
import { createConnectTransport } from "@connectrpc/connect-web";
import { UserService } from "./gen/user_pb";

const transport = createConnectTransport({
  baseUrl: "https://api.example.com",
});

const client = createClient(UserService, transport);

// Type-safe, auto-complete работает!
const user = await client.getUser({ id: "123" });
console.log(user.name); // ← полный type inference
```

### Сравнение с gRPC-Web

| Feature | gRPC-Web | Connect-RPC |
|---------|----------|-------------|
| **Прокси требуется** | Да (Envoy) | Нет |
| **TypeScript support** | Плохой | Native, idiomatic |
| **JSON debugging** | Нет (binary only) | Да (cURL-friendly) |
| **ES Modules** | Нет | Да |
| **HTTP версии** | HTTP/1.1, HTTP/2 | HTTP/1.1, HTTP/2, HTTP/3 |
| **Протоколы** | gRPC-Web only | gRPC + gRPC-Web + Connect |
| **Bundle size** | ~10.8 KB | ~13 KB |
| **Code style** | Java-like | TypeScript-native |

### NPM Downloads (December 2024)

| Package | Weekly Downloads |
|---------|-----------------|
| `@connectrpc/connect` | ~805,000 |
| `@connectrpc/connect-web` | ~290,000 |
| `grpc-web` | ~100,000 |

**Тренд:** Connect-RPC обогнал gRPC-Web по популярности.

### Миграция с gRPC-Web

```typescript
// БЫЛО: gRPC-Web
import { UserServiceClient } from "./gen/user_grpc_web_pb";
const client = new UserServiceClient("https://api.example.com");
const request = new GetUserRequest();
request.setId("123");
client.getUser(request, {}, (err, response) => {
  console.log(response.getName());
});

// СТАЛО: Connect-RPC
import { createClient } from "@connectrpc/connect";
import { UserService } from "./gen/user_pb";
const client = createClient(UserService, transport);
const user = await client.getUser({ id: "123" });
console.log(user.name);
```

---

## tRPC: TypeScript-only подход

### Когда использовать

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         tRPC vs gRPC                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  tRPC                              gRPC/Connect                          │
│  ────────────────────────────      ────────────────────────────          │
│  • TypeScript ONLY                 • Multi-language (Go, Java, etc.)    │
│  • Нет .proto файлов               • .proto как контракт                │
│  • Нет code generation             • Требует codegen                    │
│  • JSON over HTTP/1.1              • Binary Protobuf                    │
│  • Monorepo friendly               • Microservices friendly             │
│  • Next.js/Remix интеграция        • Any backend                        │
│                                                                          │
│  Когда выбрать:                                                          │
│  ─────────────────────────────────────────────────────────────────────  │
│  tRPC  → Fullstack TypeScript (Next.js, Remix, monorepo)                │
│  gRPC  → Polyglot microservices, высокая производительность             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Performance Comparison (2025)

| Metric | gRPC | tRPC | REST |
|--------|------|------|------|
| **Latency** | Лучший | Хороший | Базовый |
| **Throughput** | +44% vs REST | ~REST | Базовый |
| **Payload size** | Минимальный (binary) | JSON | JSON |
| **CPU usage** | Низкий | Средний | Средний |

### Гибридный подход

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      HYBRID ARCHITECTURE                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Frontend (React/Next.js)                                                │
│  │                                                                       │
│  ├── tRPC ──────────► BFF (Node.js/TypeScript)                          │
│  │   (type-safe)      │                                                 │
│  │                    ├── gRPC ──► User Service (Go)                    │
│  │                    ├── gRPC ──► Payment Service (Java)               │
│  │                    └── gRPC ──► Game Engine (Go)                     │
│  │                                                                       │
│  Преимущества:                                                           │
│  ├── Максимальный DX на фронте (tRPC)                                   │
│  ├── Высокая производительность между сервисами (gRPC)                  │
│  └── Type-safety end-to-end                                              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Envoy JSON Transcoding

### Когда использовать

Фронтенд должен работать с REST/JSON, а бэкенд на gRPC.

### Архитектура

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    ENVOY JSON TRANSCODING                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Frontend            Envoy Proxy              gRPC Backend              │
│  (REST/JSON)         (transcoding)            (Protobuf)                │
│  ────────────        ─────────────            ──────────────            │
│                                                                          │
│  GET /v1/users/123   ──────────────►  Translate  ──────►  GetUser()    │
│                      ◄──────────────  JSON↔Proto  ◄──────              │
│  {"name":"John"}                                          User{}        │
│                                                                          │
│  Конфигурация:                                                           │
│  ├── .proto с google.api.http annotations                               │
│  ├── Proto descriptor (.pb file)                                        │
│  └── Envoy grpc_json_transcoder filter                                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Proto annotations

```protobuf
syntax = "proto3";

import "google/api/annotations.proto";

service UserService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = {
      get: "/v1/users/{user_id}"
    };
  }

  rpc CreateUser(CreateUserRequest) returns (User) {
    option (google.api.http) = {
      post: "/v1/users"
      body: "*"
    };
  }
}
```

### Плюсы и минусы

| Плюсы | Минусы |
|-------|--------|
| Фронтенд использует обычный `fetch()` | Overhead на transcoding |
| Swagger/OpenAPI совместимость | Нет streaming |
| Нет gRPC библиотек на фронте | Дополнительная конфигурация |
| Legacy systems support | Proto descriptor management |

---

## WebTransport: Будущее

### Статус 2025

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    WebTransport BROWSER SUPPORT                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Browser              Status              Notes                          │
│  ───────────────────  ─────────────────   ─────────────────────────────│
│  Chrome               ✅ Supported        Since Chrome 97               │
│  Firefox              ✅ Supported        Since Firefox 114             │
│  Edge                 ✅ Supported        Chromium-based                │
│  Safari               ❌ NOT SUPPORTED    BLOCKER для production!       │
│                                                                          │
│  Что даст WebTransport для gRPC:                                        │
│  ├── Full-duplex streaming в браузере                                   │
│  ├── Client streaming (наконец!)                                         │
│  ├── Bidirectional streaming                                             │
│  └── Native gRPC protocol support                                        │
│                                                                          │
│  Прогноз: Production-ready 2026-2027                                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### gRPC-Web Roadmap

| Feature | Status | Timeline |
|---------|--------|----------|
| Fetch cancellation | In progress | 2024 |
| Performance improvements | In progress | 2024 |
| Keep-alive via Envoy | Planned | 2024+ |
| Client streaming | Waiting for WebTransport | 2026+ |
| Bidirectional streaming | Waiting for WebTransport | 2026+ |
| WebSockets support | **NOT PLANNED** | Never |

**Connect-RPC позиция:** Также ждут Safari WebTransport support перед реализацией full streaming.

---

## Сравнительная таблица

### Feature Matrix

| Feature | gRPC-Web | Connect-RPC | tRPC | REST+JSON |
|---------|----------|-------------|------|-----------|
| **Популярность 2025** | ↓ Падает | ↑ Растёт | → Стабильная | → Стабильная |
| **TypeScript DX** | Плохой | Отличный | Лучший | Хороший |
| **Performance** | Высокая | Высокая | Средняя | Базовая |
| **Прокси нужен** | Да | Нет | Нет | Нет |
| **Code generation** | Да | Да | Нет | Опционально |
| **Multi-language** | Да | Да | Нет (TS only) | Да |
| **Streaming** | Частичный | Частичный | Нет | WebSocket |
| **Debugging** | Сложный | Простой | Простой | Простой |
| **CNCF** | Да | Да (2024) | Нет | N/A |
| **Bundle size** | ~10.8 KB | ~13 KB | ~20 KB | N/A |

### Protocol Comparison

| Aspect | gRPC | gRPC-Web | Connect |
|--------|------|----------|---------|
| **Transport** | HTTP/2 | HTTP/1.1+ | HTTP/1.1+ |
| **Encoding** | Protobuf | Protobuf | Protobuf or JSON |
| **Browser support** | Нет | Через прокси | Native |
| **Streaming** | Full | Limited | Limited |
| **Debugging** | Binary | Binary | JSON option |

---

## Рекомендация

### Для текущего проекта (POC GitOps)

Учитывая существующий стек:
- gRPC бэкенд на Go
- Buf для proto generation
- Cilium + Envoy инфраструктура
- Angular/React фронтенд

**Рекомендация: Connect-RPC**

```yaml
Причины:
  1. Совместим с существующими .proto файлами
  2. Buf нативно поддерживает Connect codegen
  3. Не нужен дополнительный прокси
  4. TypeScript-first с отличным DX
  5. Постепенная миграция (поддерживает gRPC-Web protocol)
  6. CNCF проект — долгосрочная поддержка

Миграция:
  - Добавить connect-es плагин в buf.gen.yaml
  - Обновить фронтенд клиенты
  - Убрать gRPC-Web прокси конфигурацию
```

### Buf Configuration

```yaml
# buf.gen.yaml
version: v2
plugins:
  # Protobuf messages
  - remote: buf.build/bufbuild/es
    out: gen
    opt: target=ts

  # Connect-RPC client/server
  - remote: buf.build/connectrpc/es
    out: gen
    opt: target=ts
```

### Decision Matrix

| Если... | То выбирай... |
|---------|---------------|
| Новый проект + gRPC бэкенд | Connect-RPC |
| Fullstack TypeScript (Next.js) | tRPC |
| Legacy фронтенд (REST only) | Envoy JSON Transcoding |
| Миграция с gRPC-Web | Connect-RPC |
| Streaming критичен | Ждать WebTransport / WebSocket fallback |

---

## Источники

### Официальная документация

- [Connect RPC Documentation](https://connectrpc.com/)
- [gRPC-Web GitHub](https://github.com/grpc/grpc-web)
- [Buf Documentation](https://buf.build/docs/)
- [tRPC Documentation](https://trpc.io/)

### Статьи и блоги

- [Connect-Web: Protobuf and gRPC in the browser - Buf](https://buf.build/blog/connect-web-protobuf-grpc-in-the-browser)
- [Connect RPC joins CNCF - Buf](https://buf.build/blog/connect-rpc-joins-cncf)
- [The state of gRPC in the browser - gRPC.io](https://grpc.io/blog/state-of-grpc-web/)
- [gRPC in 2025: Why Top Companies Are Switching - Medium](https://medium.com/@miantalha.t08/grpc-in-2025-why-top-companies-are-switching-from-rest-36e3c6e2ec4c)
- [tRPC vs gRPC: API Performance Battle 2025 - Bedda](https://www.metatech.dev/blog/2025-05-04-trpc-vs-grpc-vs-rest-api-performance-battle-2025)

### Сравнения

- [Calico vs Cilium: gRPC-Web - Tigera](https://www.tigera.io/learn/guides/cilium-vs-calico/)
- [Browser Client to gRPC Server Routing - DEV](https://dev.to/stevenacoffman/browser-client-to-grpc-server-routing-options-connect-grpc-web-grpc-gateway-and-more-52cm)
- [gRPC vs REST vs GraphQL: 2025 - Medium](https://medium.com/@sharmapraveen91/grpc-vs-rest-vs-graphql-the-ultimate-api-showdown-for-2025-developers-188320b4dc35)

### Streaming & Future

- [gRPC-Web streaming roadmap - GitHub](https://github.com/grpc/grpc-web/blob/master/doc/streaming-roadmap.md)
- [WebTransport Status - MDN](https://developer.mozilla.org/en-US/docs/Web/API/WebTransport)

### Performance

- [Envoy gRPC-JSON transcoder - Envoy Docs](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/grpc_json_transcoder_filter)
- [gRPC TypeScript in 2025 - Caisy](https://caisy.io/blog/grpc-typescript)

---

*Документ создан: 2025-12-18*
*Версия: 1.0*
