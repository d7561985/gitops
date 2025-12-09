# TEST API

## === web-http ==== ##

```bash
# Basic HTTP request through gateway
curl -v 'http://127.0.0.1:8080/api/HttpService/health'

# Expected: HTTP 200 with JSON response from fake-service
```

## auth-adapter

```bash
# Без токена - должен вернуть 401 Unauthorized
curl http://localhost:8080/api/HttpService/protected

# С валидным токеном - должен вернуть 200
curl -H "Cookie: token=demo-token" http://localhost:8080/api/HttpService/protected
```


## === web-grpc ==== ##

```bash
# Simple call (empty request)
grpcwebcli  -url http://127.0.0.1:8080/api -method FakeService/Handle
```

## === health-demo ==== ##

```bash
# Server streaming (gRPC-Web over HTTP)
grpcwebcli -url http://127.0.0.1:8080/api -method grpc.health.v1.Health/Watch  -stream -timeout 10s

# gRPC Health Check with JSON response
grpcwebcli -url http://127.0.0.1:8080/api -method grpc.health.v1.Health/Check
```

## Фишки релиза

1. Реплики
2. ИЗменить реурсы
3. Health Check

## Test Secrets

1. Тест секрет добавился в сервис
2. Показывает как создаются пути в Vault и что сервис ждет загрузки секретов 

## Test Deploy

1. Релиз нескольких окружений одновременно
2. Как релизить через Ingress + LB ( Claudflare)