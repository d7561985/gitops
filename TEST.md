## Фишки релиза

- Фронтенд
- Реплики
- ИЗменить реурсы
- Health Check
- Canary / Blue/Green

# TEST API

## === web-http ==== ##

```bash
# Basic HTTP request through gateway (mendhak/http-https-echo)
# Возвращает JSON со всеми входящими headers
curl -s 'http://127.0.0.1:8080/api/HttpService/health' | jq .

# Expected: HTTP 200 with JSON containing path, headers, method, etc.
```

## auth-adapter

```bash
# Без токена - должен вернуть 401 Unauthorized
curl http://localhost:8080/api/HttpService/protected

# С валидным токеном - должен вернуть 200
# Ответ содержит JSON со всеми headers (включая насыщенные от auth-adapter)
curl -s -H "Cookie: token=demo-token" http://localhost:8080/api/HttpService/protected | jq .

# Проверка только headers в ответе
curl -s -H "Cookie: token=demo-token" http://localhost:8080/api/HttpService/protected | jq '.headers'

# Expected headers от auth-adapter: X-User-Id, X-User-Email, X-User-Role и др.
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



## Test Secrets

1. Тест секрет добавился в сервис
2. Показывает как создаются пути в Vault и что сервис ждет загрузки секретов 

## Test Deploy

1. Релиз нескольких окружений одновременно
2. Как релизить через Ingress + LB ( Claudflare)