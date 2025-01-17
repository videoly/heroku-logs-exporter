FROM golang:1.21.6-alpine

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

ADD . .

RUN go build -o /heroku-logs-exporter

ENTRYPOINT ["/heroku-logs-exporter"]
