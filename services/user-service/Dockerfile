FROM golang:1.24-alpine AS builder

WORKDIR /app

# Install git for private dependencies
RUN apk add --no-cache git ca-certificates

# Configure authentication for private GitLab repos
# Solution based on: https://gist.github.com/MicahParks/1ba2b19c39d1e5fccc3e892837b10e21
ARG GITLAB_TOKEN
RUN if [ -n "$GITLAB_TOKEN" ]; then \
    echo "machine gitlab.com login gitlab-ci-token password ${GITLAB_TOKEN}" > ~/.netrc && \
    chmod 600 ~/.netrc; \
    fi

# Set GOPRIVATE to skip proxy and checksum for our private repos
# GONOSUMDB and GONOPROXY ensure Go doesn't try to verify private modules
ENV GOPRIVATE=gitlab.com/gitops-poc-dzha/*
ENV GONOSUMDB=gitlab.com/gitops-poc-dzha/*
ENV GONOPROXY=gitlab.com/gitops-poc-dzha/*

# Use ash shell for proper .netrc support (Alpine default sh doesn't handle it well)
SHELL ["/bin/ash", "-c"]

# Copy go mod files
COPY go.mod go.sum* ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /server ./cmd/server

# Final distroless image (2MB vs 7MB alpine)
# Includes ca-certificates and tzdata, no shell, runs as nonroot (uid 65532)
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /server /server
EXPOSE 8081 9090
ENTRYPOINT ["/server"]
