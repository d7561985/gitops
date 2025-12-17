FROM golang:1.23-alpine AS builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o server .

# Final distroless image (2MB vs 7MB alpine)
# Includes ca-certificates, no shell, runs as nonroot (uid 65532)
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /build/server /server
ENTRYPOINT ["/server"]
