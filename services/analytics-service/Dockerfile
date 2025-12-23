FROM golang:1.24-alpine AS builder

WORKDIR /app

# Install git for dependencies
RUN apk add --no-cache git ca-certificates

# Copy go mod files
COPY go.mod go.sum* ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /server ./cmd/server

# Final distroless image (~2MB, secure by default)
# Includes ca-certificates, no shell, runs as nonroot (uid 65532)
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /server /server
EXPOSE 8081 9090
ENTRYPOINT ["/server"]
