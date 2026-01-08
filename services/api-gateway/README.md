# API Gateway Configuration Generator

Generates optimized Envoy configurations for gRPC and HTTP services with integrated authentication, rate limiting, TLS upstream support, and observability.

## Features

- gRPC-Web and HTTP routing
- External authorization (ext_authz)
- Per-method rate limiting
- Health checks and circuit breakers
- OpenTelemetry tracing
- TLS upstream connections with Host header override
- **Client IP forwarding (X-Real-IP) for services behind proxies**

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

## Client IP Forwarding (X-Real-IP)

When Envoy runs behind a load balancer or ingress controller, the direct connection IP is the proxy's IP, not the real client IP. This feature extracts the real client IP from the `X-Forwarded-For` header and forwards it to upstream services.

### How It Works

```
Client (1.2.3.4) → Ingress (10.0.0.1) → Envoy → Backend
                   │
                   └─ adds: X-Forwarded-For: 1.2.3.4
                                    │
                                    ▼
                         xff_num_trusted_hops: 1
                         extracts: 1.2.3.4 from XFF
                                    │
                                    ▼
                         X-Real-IP: 1.2.3.4 → Backend
```

### Configuration

The number of trusted proxy hops is controlled by the `XFF_NUM_TRUSTED_HOPS` environment variable:

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `XFF_NUM_TRUSTED_HOPS` | `1` | Number of trusted proxies in front of Envoy |

### Examples

#### Single Proxy (Kubernetes Ingress)

Most common setup: Client → Ingress → Envoy

```bash
# Default value (1) works for this setup
export XFF_NUM_TRUSTED_HOPS=1
go run . -api-conf=config.yaml -out-envoy-conf=envoy.yaml
```

#### Multiple Proxies (CloudFlare + Ingress)

Client → CloudFlare → Ingress → Envoy

```bash
export XFF_NUM_TRUSTED_HOPS=2
go run . -api-conf=config.yaml -out-envoy-conf=envoy.yaml
```

#### Direct Client Connection (Edge Deployment)

Client → Envoy (no proxy in front)

```bash
export XFF_NUM_TRUSTED_HOPS=0
go run . -api-conf=config.yaml -out-envoy-conf=envoy.yaml
```

### Example config.yaml

No special configuration needed - X-Real-IP is automatically added to all HTTP routes:

```yaml
api_route: /api/

clusters:
  - name: backend-api
    addr: "backend-service:8080"
    type: "http"
    health_check:
      path: "/health"
      interval_seconds: 10

apis:
  - name: myapp
    cluster: backend-api
    auth: {policy: no-need}
    methods:
      - name: users
        auth: {policy: required}
      - name: public
        auth: {policy: no-need}
```

Generate and run:

```bash
# Set trusted hops (1 for single ingress)
export XFF_NUM_TRUSTED_HOPS=1

# Generate Envoy config
go run . -api-conf=config.yaml -out-envoy-conf=envoy.yaml

# Verify X-Real-IP is added to routes
grep -A5 "x-real-ip" envoy.yaml
```

### Generated Envoy Config

The generator produces:

**HTTP Connection Manager settings:**
```yaml
use_remote_address: true
xff_num_trusted_hops: 1  # from XFF_NUM_TRUSTED_HOPS env var
```

**Route-level header injection (HTTP routes only):**
```yaml
request_headers_to_add:
  - header:
      key: "x-real-ip"
      value: "%DOWNSTREAM_REMOTE_ADDRESS_WITHOUT_PORT%"
    append_action: OVERWRITE_IF_EXISTS_OR_ADD
```

### Reading Client IP in Backend Services

After configuration, backend services receive the real client IP in the `X-Real-IP` header:

**Go:**
```go
func handler(w http.ResponseWriter, r *http.Request) {
    clientIP := r.Header.Get("X-Real-IP")
    // fallback to X-Forwarded-For if needed
    if clientIP == "" {
        clientIP = r.Header.Get("X-Forwarded-For")
    }
    log.Printf("Request from: %s", clientIP)
}
```

**Node.js:**
```javascript
app.get('/api/endpoint', (req, res) => {
    const clientIP = req.headers['x-real-ip'] || req.headers['x-forwarded-for'];
    console.log(`Request from: ${clientIP}`);
});
```

**PHP:**
```php
$clientIP = $_SERVER['HTTP_X_REAL_IP'] ?? $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'];
```

### Troubleshooting

**Problem:** Backend still sees proxy IP instead of client IP

**Solutions:**

1. **Check `XFF_NUM_TRUSTED_HOPS` value:**
   - Count the number of proxies between the client and Envoy
   - Set `XFF_NUM_TRUSTED_HOPS` to that number

2. **Verify ingress forwards X-Forwarded-For:**
   ```bash
   # For nginx-ingress, check ConfigMap
   kubectl get configmap -n ingress-nginx ingress-nginx-controller -o yaml | grep use-forwarded-headers
   ```

3. **Debug with access logs:**
   ```bash
   # Check Envoy logs for XFF header
   kubectl logs <envoy-pod> | grep "x-forwarded-for"
   ```

4. **Test header chain:**
   ```bash
   curl -H "X-Forwarded-For: 1.2.3.4" http://your-ingress/api/debug
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
| `XFF_NUM_TRUSTED_HOPS` | `1` | Number of trusted proxies for client IP extraction from X-Forwarded-For |

## Building

```bash
# Build binary
go build -o api-gateway .

# Build Docker image
docker build -t api-gateway .
```
