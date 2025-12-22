# =============================================================================
# Go Service Dockerfile (Distroless)
# =============================================================================
# Final image: gcr.io/distroless/static-debian12:nonroot (~2MB)
# Security: No shell, no package manager, runs as nonroot (uid 65532)
# Requirements: CGO_ENABLED=0 for static binary
#
# Usage: Copy to your repo as 'Dockerfile'
# Replace: {{SERVICE_NAME}} with your service name
# =============================================================================

FROM golang:1.23-alpine AS builder

WORKDIR /app

# Install git for private dependencies
RUN apk add --no-cache git ca-certificates

# Configure authentication for private GitLab repos
# Token must have read_api scope (not just read_repository)
ARG GITLAB_TOKEN
RUN if [ -n "$GITLAB_TOKEN" ]; then \
    echo "machine gitlab.com login gitlab-ci-token password ${GITLAB_TOKEN}" > ~/.netrc && \
    chmod 600 ~/.netrc; \
    fi

# Set GOPRIVATE to skip proxy and checksum for private repos
ENV GOPRIVATE=gitlab.com/gitops-poc-dzha/*
ENV GONOSUMDB=gitlab.com/gitops-poc-dzha/*
ENV GONOPROXY=gitlab.com/gitops-poc-dzha/*

# Use ash shell for proper .netrc support
SHELL ["/bin/ash", "-c"]

# Copy go mod files and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build static binary
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /{{SERVICE_NAME}} ./cmd/server

# =============================================================================
# Final distroless image
# =============================================================================
# - ~2MB (vs ~7MB alpine, ~800MB golang)
# - Includes ca-certificates and tzdata
# - No shell, no package manager (secure by default)
# - Runs as nonroot user (uid 65532)
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /{{SERVICE_NAME}} /{{SERVICE_NAME}}

EXPOSE 8081 9090

ENTRYPOINT ["/{{SERVICE_NAME}}"]
