# API Gateway Configuration Generator

Generates optimized Envoy configurations for gRPC and HTTP services with integrated authentication, rate limiting, TLS upstream support, and observability.

## Features

- gRPC-Web and HTTP routing
- External authorization (ext_authz)
- Per-method rate limiting
- Health checks and circuit breakers
- OpenTelemetry tracing
- **TLS upstream connections with Host header override**

## Quick Start

```bash
# Generate Envoy config
go run . -api-conf=config.yaml -out-envoy-conf=envoy.yaml

# Run tests
go test -v ./...
```

## Configuration

### Basic Structure

```yaml
api_route: /api/

clusters:
  - name: my_service
    addr: "service:9000"
    type: "grpc"  # or "http"

apis:
  - name: "MyService"
    cluster: "my_service"
    auth:
      policy: "required"  # required | optional | no-need
    methods:
      - name: "GetData"
        auth:
          policy: "required"
          rate_limit: {period: "1m", count: 100}
```

## TLS Upstream Support

Enable TLS for secure connections to upstream services. This is essential for:
- Connecting to external HTTPS APIs
- Cross-cluster communication via ingress controllers
- Secure internal service mesh connections

### Configuration

```yaml
clusters:
  - name: external_api
    addr: "api.example.com:443"
    type: "http"
    tls:
      enabled: true           # Enable TLS
      sni: "api.example.com"  # Optional: SNI for TLS + Host header (auto-detected if empty)
      ca_cert: "/path/to/ca"  # Optional: Custom CA certificate path
```

### TLS Fields

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `enabled` | Yes | `false` | Enable TLS for upstream connection |
| `sni` | No | hostname from `addr` | Server Name Indication for TLS handshake AND Host header for routing |
| `ca_cert` | No | system CA | Path to CA certificate bundle |

### Use Cases

#### 1. External HTTPS API

```yaml
clusters:
  - name: stripe_api
    addr: "api.stripe.com:443"
    type: "http"
    tls:
      enabled: true
      # SNI auto-detected as "api.stripe.com"
```

#### 2. Cross-Cluster Communication (Ingress Routing)

When connecting to another Kubernetes cluster's ingress controller, you need to:
1. Connect to ingress IP/hostname with TLS
2. Set correct Host header for ingress routing

```yaml
clusters:
  - name: remote_cluster_api
    addr: "10.0.0.50:443"              # Ingress IP address
    type: "http"
    tls:
      enabled: true
      sni: "api.remote-cluster.com"    # Virtual host for ingress routing
```

This generates:
- **TLS transport_socket** with SNI for TLS handshake
- **host_rewrite_literal** in routes for correct Host header

The ingress controller receives `Host: api.remote-cluster.com` and routes accordingly.

#### 3. Custom CA (Internal PKI)

```yaml
clusters:
  - name: internal_service
    addr: "secure.internal:443"
    type: "grpc"
    tls:
      enabled: true
      sni: "secure.internal"
      ca_cert: "/etc/ssl/company-ca.crt"
```

### Generated Envoy Config

For TLS-enabled clusters, the generator produces:

**Cluster with transport_socket:**
```yaml
- name: external_api
  transport_socket:
    name: envoy.transport_sockets.tls
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
      sni: "api.example.com"
      common_tls_context:
        validation_context:
          trusted_ca:
            filename: "/etc/ssl/certs/ca-certificates.crt"
        alpn_protocols: ["http/1.1"]  # or ["h2"] for gRPC
```

**Route with host_rewrite_literal:**
```yaml
- match: { prefix: "/api/MyService/" }
  route:
    cluster: external_api
    host_rewrite_literal: "api.example.com"
```

## Testing TLS

### Unit Tests

```bash
go test -v ./...
```

Tests cover:
- `TestTLSWithSNIOverride` - Custom SNI for ingress routing
- `TestTLSWithExampleCom` - Auto-detected SNI
- `TestGRPCWithTLS` - gRPC with h2 ALPN
- `TestBackwardCompatibility` - Non-TLS configs still work

### Manual Testing with Docker

1. Generate config with TLS example:

```bash
go run . -api-conf=config.tls-example.yaml -out-envoy-conf=/tmp/envoy-tls.yaml
```

2. Run Envoy:

```bash
docker run --rm -p 8080:8080 \
  -v /tmp/envoy-tls.yaml:/etc/envoy/envoy.yaml:ro \
  envoyproxy/envoy:v1.31-latest
```

3. Test request:

```bash
curl http://localhost:8080/api/Example/Get
```

## Other Features

### Health Checks

```yaml
clusters:
  - name: my_service
    addr: "service:8080"
    type: "http"
    health_check:
      path: "/health"
      interval_seconds: 30
      timeout_seconds: 5
      healthy_threshold: 2
      unhealthy_threshold: 3
```

### Circuit Breakers

```yaml
clusters:
  - name: my_service
    addr: "service:8080"
    type: "http"
    circuit_breaker:
      max_connections: 100
      max_pending_requests: 50
      max_requests: 200
      max_retries: 3
```

### Rate Limiting

```yaml
apis:
  - name: "MyService"
    cluster: "my_service"
    methods:
      - name: "ExpensiveOperation"
        auth:
          policy: "required"
          rate_limit:
            period: "1m"    # 1s, 1m, or 1h
            count: 10       # requests per period
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTH_ADAPTER_HOST` | `127.0.0.1` | ext_authz service host |
| `OPEN_TELEMETRY_HOST` | `127.0.0.1` | OpenTelemetry collector host |
| `OPEN_TELEMETRY_PORT` | `4317` | OpenTelemetry collector port |

## Building

```bash
# Build binary
go build -o api-gateway .

# Build Docker image
docker build -t api-gateway .
```
