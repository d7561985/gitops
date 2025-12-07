FROM golang:1.23-alpine as builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download

COPY . .

ENV GOOS=linux
ENV GOARCH=amd64
ENV CGO_ENABLED=0
RUN go build -o server .

FROM alpine:3.19
WORKDIR /app
COPY --from=builder /build/server /bin/server
ENTRYPOINT ["/bin/server"]
