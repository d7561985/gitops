# Feature Request: Gateway API HTTPRoute Support

## Summary

Add support for Kubernetes Gateway API HTTPRoute resource as a modern alternative to Ingress. Gateway API is the successor to Ingress API and provides more expressive, extensible, and role-oriented routing capabilities.

## Motivation

### Why Gateway API?

1. **Ingress is frozen** - Kubernetes community has stopped adding new features to Ingress. All new development is happening in Gateway API.

2. **NGINX Ingress retirement** - NGINX Ingress Controller will be retired by March 2026, with only best-effort maintenance until then.

3. **Better expressiveness** - Gateway API supports:
   - Header-based routing
   - Query parameter matching
   - Traffic splitting (canary deployments)
   - Cross-namespace routing with explicit permissions
   - Multiple protocols (HTTP, HTTPS, gRPC, TCP, UDP)

4. **Role-oriented design** - Clear separation between infrastructure (Gateway) and application (HTTPRoute) concerns.

5. **Standardization** - No more vendor-specific annotations. Features like redirects, header modification, and traffic splitting are part of the spec.

### References

- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Migrating from Ingress](https://gateway-api.sigs.k8s.io/guides/migrating-from-ingress/)
- [Kong: Gateway API vs Ingress](https://konghq.com/blog/engineering/gateway-api-vs-ingress)
- [Kubernetes Gateway API Blog](https://kubernetes.io/blog/2023/10/25/introducing-ingress2gateway/)

## Proposed Implementation

### New Template: `templates/httproute.yaml`

```yaml
{{- if .Values.httpRoute }}
{{- if .Values.httpRoute.enabled }}
{{- $serviceName := include "name" . }}
{{- $servicePort := .Values.service.ports | first | default dict }}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ $serviceName }}-route
  namespace: {{ .Release.Namespace }}
  labels:
    app: {{ $serviceName }}
    chart: "{{ .Chart.Name }}-{{ .Chart.Version }}"
    release: "{{ .Release.Name }}"
    {{- if .Values.httpRoute.primaryHost }}
    app.kubernetes.io/primary-host: {{ .Values.httpRoute.primaryHost | quote }}
    {{- end }}
  {{- with .Values.httpRoute.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  parentRefs:
    {{- range .Values.httpRoute.parentRefs }}
    - name: {{ .name }}
      {{- if .namespace }}
      namespace: {{ .namespace }}
      {{- end }}
      {{- if .sectionName }}
      sectionName: {{ .sectionName }}
      {{- end }}
    {{- end }}

  {{- if .Values.httpRoute.hostnames }}
  hostnames:
    {{- range .Values.httpRoute.hostnames }}
    - {{ . | quote }}
    {{- end }}
  {{- end }}

  rules:
    {{- if .Values.httpRoute.rules }}
    {{- range .Values.httpRoute.rules }}
    - matches:
        {{- range .matches }}
        - {{- if .path }}
          path:
            type: {{ .path.type | default "PathPrefix" }}
            value: {{ .path.value | quote }}
          {{- end }}
          {{- if .headers }}
          headers:
            {{- range .headers }}
            - name: {{ .name }}
              value: {{ .value | quote }}
              {{- if .type }}
              type: {{ .type }}
              {{- end }}
            {{- end }}
          {{- end }}
          {{- if .method }}
          method: {{ .method }}
          {{- end }}
        {{- end }}
      {{- if .backendRefs }}
      backendRefs:
        {{- range .backendRefs }}
        - name: {{ .name | default (printf "%s-sv" $serviceName) }}
          port: {{ .port | default ($servicePort.externalPort | default 80) }}
          {{- if .namespace }}
          namespace: {{ .namespace }}
          {{- end }}
          {{- if .weight }}
          weight: {{ .weight }}
          {{- end }}
        {{- end }}
      {{- else }}
      backendRefs:
        - name: {{ $serviceName }}-sv
          port: {{ $servicePort.externalPort | default 80 }}
      {{- end }}
      {{- if .filters }}
      filters:
        {{- toYaml .filters | nindent 8 }}
      {{- end }}
    {{- end }}
    {{- else }}
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: {{ $serviceName }}-sv
          port: {{ $servicePort.externalPort | default 80 }}
    {{- end }}
{{- end }}
{{- end }}
```

### New Values in `values.yaml`

```yaml
# HTTPRoute - Gateway API routing (alternative to Ingress)
httpRoute:
  enabled: false

  # Annotations for the HTTPRoute resource
  annotations: {}

  # Primary host label (useful for tooling that manages mirror domains)
  # primaryHost: app.example.com

  # Parent Gateway references (required)
  parentRefs: []
    # - name: gateway-dev
    #   namespace: gateway-dev
    #   sectionName: https  # optional: specific listener

  # Hostnames to match (optional, matches all if empty)
  hostnames: []
    # - app.example.com
    # - www.app.example.com

  # Routing rules (optional, defaults to catch-all route to this service)
  rules: []
    # - matches:
    #     - path:
    #         type: PathPrefix
    #         value: /api
    #   backendRefs:
    #     - name: api-gateway-sv
    #       port: 8080
```

## Use Cases

### 1. Simple Frontend Service

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: gateway-prod
      namespace: gateway-prod
  hostnames:
    - app.example.com
```

### 2. Frontend with API Routing

Route `/api/*` to api-gateway, everything else to frontend:

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: gateway-prod
      namespace: gateway-prod
      sectionName: https-app
  hostnames:
    - app.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api-gateway-sv
          port: 8080
    - matches:
        - path:
            type: PathPrefix
            value: /
```

### 3. Header-Based Routing (A/B Testing)

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: gateway-prod
      namespace: gateway-prod
  hostnames:
    - app.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
          headers:
            - name: X-Version
              value: beta
      backendRefs:
        - name: frontend-beta-sv
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /
```

### 4. Traffic Splitting (Canary Deployment)

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: gateway-prod
      namespace: gateway-prod
  hostnames:
    - app.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: frontend-sv
          port: 80
          weight: 90
        - name: frontend-canary-sv
          port: 80
          weight: 10
```

### 5. Cross-Namespace Backend Reference

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: gateway-prod
      namespace: gateway-prod
  hostnames:
    - app.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /shared
      backendRefs:
        - name: shared-service-sv
          namespace: shared-services
          port: 8080
```

## Compatibility

- **Gateway API version**: v1.2.0 (GA)
- **Kubernetes**: 1.25+
- **Supported implementations**: Cilium, Envoy Gateway, NGINX Gateway Fabric, Istio, Contour, and others

## Prerequisites

Gateway API CRDs must be installed in the cluster:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
```

## Migration Path

The `httpRoute` configuration can coexist with existing `ingress` configuration. Users can gradually migrate:

1. Deploy Gateway and GatewayClass
2. Enable `httpRoute` alongside existing `ingress`
3. Verify traffic flows correctly through HTTPRoute
4. Disable `ingress` when ready

## Testing

### Unit Tests

Add tests to verify:
- HTTPRoute is not created when `httpRoute.enabled: false`
- HTTPRoute is created with correct structure when enabled
- Default backend refs use service name and port from `service.ports`
- Custom rules are rendered correctly
- Cross-namespace references work

### Integration Tests

- Deploy with Cilium Gateway API controller
- Deploy with Envoy Gateway
- Verify traffic routing works as expected

## Additional Considerations

### GRPCRoute Support (Future)

Gateway API also defines GRPCRoute for gRPC-specific routing. This could be added as a follow-up feature:

```yaml
grpcRoute:
  enabled: false
  parentRefs: []
  hostnames: []
  rules: []
```

### TCPRoute/TLSRoute Support (Future)

For TCP passthrough and TLS-based routing:

```yaml
tcpRoute:
  enabled: false
tlsRoute:
  enabled: false
```

## Checklist

- [ ] Add `templates/httproute.yaml`
- [ ] Add `httpRoute` section to `values.yaml`
- [ ] Update `README.md` with HTTPRoute documentation
- [ ] Add unit tests
- [ ] Test with Cilium Gateway API
- [ ] Test with Envoy Gateway
- [ ] Update CHANGELOG

## References

- [Gateway API Specification](https://gateway-api.sigs.k8s.io/reference/spec/)
- [HTTPRoute API Reference](https://gateway-api.sigs.k8s.io/api-types/httproute/)
- [ReferenceGrant for Cross-Namespace](https://gateway-api.sigs.k8s.io/api-types/referencegrant/)
- [Traffic Splitting](https://gateway-api.sigs.k8s.io/guides/traffic-splitting/)
