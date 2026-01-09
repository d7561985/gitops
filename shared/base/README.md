# Shared Base Images

Базовые "золотые" образы платформы. Эти образы используются как основа для сервисов и не деплоятся напрямую.

## Содержимое

| Образ | Описание | Используется в |
|-------|----------|----------------|
| `api-gateway-image` | Envoy proxy + Go config generator | `services/api-gw` |
| `auth-adapter` | gRPC ext_authz сервис | `api-gw` как sidecar |

## Архитектура

```
shared/base/
├── api-gateway-image/    ← Golden image (меняется редко)
│   ├── *.go              ← Source code
│   ├── Dockerfile        ← Build golden image
│   └── .gitlab-ci.yml    ← Build only, semantic versioning
│
└── auth-adapter/         ← Sidecar service
    ├── *.go              ← Source code
    ├── Dockerfile
    └── .gitlab-ci.yml    ← Build only
```

## Принцип использования

1. **Golden images** собираются отдельно и тегируются версиями (v1.0.0, v1.1.0)
2. **Service repos** (например `api-gw`) используют golden image как базу
3. Команды работают только с **service repos**, не трогая golden images

```dockerfile
# services/api-gw/Dockerfile
FROM registry.gitlab.com/.../api-gateway-image:v1.0.0
COPY config.yaml /opt/config-source/config.yaml
```

## Версионирование

- `vX.Y.Z` — стабильные релизы для production
- `latest` — последняя версия из main branch
- `<sha>` — конкретный коммит для тестирования
