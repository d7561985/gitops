FROM golang:1.23-alpine AS builder

WORKDIR /app

# Install git for private dependencies
RUN apk add --no-cache git ca-certificates

# Configure authentication for private GitLab repos
# Token must have read_api scope (not just read_repository)
# See: https://docs.gitlab.com/ee/user/project/use_project_as_go_package.html
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

# Copy source and build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /app/auth-adapter .

# Final image
FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/auth-adapter /app/auth-adapter
CMD ["/app/auth-adapter"]
