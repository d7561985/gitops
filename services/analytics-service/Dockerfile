FROM golang:1.24-alpine AS builder

WORKDIR /app

# Install git for private dependencies
RUN apk add --no-cache git ca-certificates

# Configure authentication for private GitLab repos
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

# Copy go mod files
COPY go.mod go.sum* ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /server ./cmd/server

# Final distroless image (~2MB, secure by default)
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /server /server
EXPOSE 8081 9090
ENTRYPOINT ["/server"]
