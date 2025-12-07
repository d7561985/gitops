FROM golang:1.23-alpine

WORKDIR /app
RUN apk add ca-certificates git && update-ca-certificates
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -o /app/auth-adapter .

CMD /app/auth-adapter
