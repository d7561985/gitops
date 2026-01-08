# API Gateway Golden Image

Base image containing Envoy proxy + Go config generator.

## Architecture

```
api-gateway-image (this repo)     api-gw (config repo)
├── *.go (config generator)       ├── config.yaml (routes/clusters)
├── Dockerfile                    ├── Dockerfile (FROM this image)
└── entrypoint.sh                 └── .cicd/ (deployment values)
         │                                 │
         ▼                                 ▼
   Golden Image                      Micro Image
   (rarely changes)                (changes with config)
```

## Usage

This image is NOT deployed directly. It's used as a base for the `api-gw` repo:

```dockerfile
# api-gw/Dockerfile
FROM registry.gitlab.com/gitops-poc-dzha/services/api-gateway-image:v1.0.0
COPY config.yaml /opt/config-source/config.yaml
```

## Versioning

- `v1.0.0` - Stable releases (used in production)
- `abc1234` - Commit SHA (for testing)

## Building Locally

```bash
docker build -t api-gateway-image:local .
```

## Testing

```bash
go test -v ./...
```
