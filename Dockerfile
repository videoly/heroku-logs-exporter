FROM golang:1.21.6-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Build for linux/amd64 (most common server architecture)
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /heroku-logs-exporter

FROM alpine:latest

RUN apk --no-cache add ca-certificates

COPY --from=builder /heroku-logs-exporter /heroku-logs-exporter

ENTRYPOINT ["/heroku-logs-exporter"]
