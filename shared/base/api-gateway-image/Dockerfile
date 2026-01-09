# =============================================================================
# API Gateway Golden Image
# =============================================================================
# Base image containing Envoy proxy + Go config generator.
# Does NOT include config.yaml - that comes from api-gw repo.
#
# Usage:
#   This image is extended by api-gw repo which adds config.yaml
#   See: services/api-gw/Dockerfile
#
# Versioning:
#   - Tagged releases: v1.0.0, v1.1.0, etc.
#   - Used as base image in api-gw
# =============================================================================

### Build stage
FROM golang:1.23-alpine as build
WORKDIR /app/conf-generator
RUN apk add git
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -a -o conf-generator .

### Main stage
FROM envoyproxy/envoy:v1.32.2

ENV LOG_LEVEL info

RUN apt-get update && apt-get install -y curl gettext-base && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 entrypoint.sh /
COPY --from=build /app/conf-generator/conf-generator /opt/conf-generator/conf-generator

# Note: config.yaml is NOT included here
# It will be added by the api-gw repo's Dockerfile

ENTRYPOINT ["/entrypoint.sh"]
