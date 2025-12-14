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


# 
   ADMIN_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJhcmdvY2QiLCJzdWIiOiJhZG1pbjpsb2dpbi
   IsImV4cCI6MTc2NTY1ODc4NSwibmJmIjoxNzY1NTcyMzg1LCJpYXQiOjE3NjU1NzIzODUsImp0aSI6ImZiNjQ4OTFjLTVmNj
   ItNGI2Ny05NzI3LTU1MjIzMzcyZDEzYiJ9.TpcFf6MFdIcXBI6U28tDSqj_1KgBqlXVy4JhWO1W03c"
   curl -s -k -X POST 'http://localhost:8083/api/v1/account/ci-readonly/token' \
     -H "Authorization: Bearer $ADMIN_TOKEN" \
     -H 'Content-Type: application/json' \
     -d '{"name":"gitlab-ci"}'
   Generate token for ci-readonly account