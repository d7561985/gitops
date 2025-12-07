### Build stage
FROM golang:1.23-alpine as build
WORKDIR /app/conf-generator
RUN apk add git
COPY go.mod go.sum ./
RUN go mod download
COPY ./ ./
RUN CGO_ENABLED=0 GOOS=linux go build -a -o conf-generator .

### main stage
FROM envoyproxy/envoy:v1.32.2

ENV LOG_LEVEL info

RUN apt-get update && apt-get install -y curl gettext-base && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /
COPY --from=build  /app/conf-generator/conf-generator /opt/conf-generator/conf-generator

ENTRYPOINT ["/entrypoint.sh"]
