# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Prometheus exporter for Heroku applications written in Go. It receives logs from Heroku Log Drain via HTTP and converts them into Prometheus metrics. The exporter is designed to be deployed as a standalone service that Heroku can send logs to.

## Development Commands

### Building
```bash
# Build the binary
go build -o heroku-logs-exporter

# Build with Docker
docker build -t heroku-logs-exporter .
```

### Running
```bash
# Run locally with default settings (listens on :9841)
go run main.go

# Run with custom configuration
go run main.go -web.listen-address=":8080" -web.logs-token-param-value="your-secret-token"

# Run with Docker
docker run -p 9841:9841 heroku-logs-exporter
```

### Testing
```bash
# Run all tests
go test ./...

# Run tests with verbose output
go test -v ./...

# Run tests for a specific package
go test ./metrics
go test ./heroku_log
```

### Dependencies
```bash
# Download dependencies
go mod download

# Update dependencies
go mod tidy

# Verify dependencies
go mod verify
```

## Architecture

### Core Components

**main.go**: Entry point that sets up HTTP server with three endpoints:
- `/` - Simple health check endpoint
- `/logs` - Accepts POST requests from Heroku Log Drain with log data
- `/metrics` - Prometheus metrics endpoint

**heroku_log package**: Parses Heroku log format into structured data
- `HerokuLog` struct contains: AppName, Time, Host, Source, Dyno, and the raw log Line
- `ParseHerokuLog()` splits the log line header and body
- `Value()` and `ValueOrUnknown()` extract key-value pairs from log lines

**metrics package**: Converts Heroku logs into Prometheus metrics
- `HerokuMetricGroup` interface defines metric groups that can update from logs
- `HerokuMetric` interface defines individual metrics (Counter, Gauge, Summary, Histogram)
- Each metric type wraps Prometheus client metrics and provides Heroku-specific parsing

### Metric Groups

Each metric group implements `HerokuMetricGroup` interface with `UpdateFromLog()` method:

1. **HerokuSystemMetrics** (heroku_system.go): Tracks Heroku platform errors (R10, H12, etc.)
2. **HerokuRuntimeMetrics** (heroku_runtime.go): Memory, load, and swap metrics from runtime logs (requires log-runtime-metrics lab enabled)
3. **HerokuPostgresMetrics** (heroku_postgres.go): Database size, connections, cache hit rates, load averages
4. **HerokuPgbouncerMetrics** (heroku_pgbouncer.go): Connection pooling metrics (server idle/active, client waiting)
5. **HerokuRouterMetrics** (heroku_router.go): HTTP request metrics (connect/service duration as histograms and summaries)
6. **RackTimeoutMetrics** (rack_timeout.go): Ruby rack-timeout gem wait/service duration metrics

### Data Flow

1. Heroku Log Drain sends POST to `/logs?app_name=<app>&token=<token>`
2. `logsHandler()` validates token and scans request body line-by-line
3. Each line is parsed by `ParseHerokuLog()` into `HerokuLog` struct
4. Each `HerokuMetricGroup` processes the log via `UpdateFromLog()`
5. Groups check log Source and format, then update relevant Prometheus metrics
6. Metrics are exposed on `/metrics` endpoint for Prometheus to scrape

### Metric Lifecycle

- **Update**: Metrics are updated when matching log lines are received
- **Delete**: Runtime metrics are deleted when dyno goes down (State changed to down)
- **Labels**: All metrics use labels like app_name, dyno, status, method for multi-dimensional tracking

## Configuration

The exporter accepts command-line flags:
- `-web.listen-address` (default: `:9841`) - Address to listen on
- `-web.telemetry-path` (default: `/metrics`) - Metrics endpoint path
- `-web.logs-path` (default: `/logs`) - Log drain endpoint path
- `-web.logs-token-param-name` (default: `token`) - Token parameter name for authentication
- `-web.logs-token-param-value` (default: empty) - Token value for authentication

## Heroku Setup

### Enable Runtime Metrics
```bash
heroku labs:enable log-runtime-metrics -a your-app
heroku restart -a your-app
```

### Add Log Drain
```bash
heroku drains:add "http://example.com:9841/logs?app_name=your-app&token=secret-token" -a your-app
```

## Important Implementation Details

- Log parsing is whitespace-based and assumes Heroku's standard log format: `<header parts> - <log body>`
- Histogram buckets are pre-configured for connect/service durations with specific ranges optimized for web request timings
- Summary metrics use fixed quantiles (0.01, 0.1, 0.5, 0.9, 0.95, 0.99) with specific error bounds
- All metrics are automatically registered with Prometheus via `promauto` package
- The exporter processes logs synchronously per request - each log drain batch is processed before responding
- Metric deletion is triggered by dyno state change events (dyno going down) to prevent stale metrics