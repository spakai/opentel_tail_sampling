# Specification: OpenTelemetry Tail-Sampling Demo

> Reverse-engineered from the current source, Docker Compose topology, and runtime configuration. This document describes the behavior that exists today; it is not an original product requirements document.

## 1. Purpose

Demonstrate a Java REST service whose traces are sent unsampled to an OpenTelemetry Collector. The Collector makes a tail-sampling decision after seeing the trace and exports retained traces to Jaeger.

The demo intentionally makes three outcomes easy to observe:

- healthy request: normally sampled at 0.01%
- slow request: retained at 100% when latency exceeds 5 seconds
- failed request: retained at 100% when the trace contains an `ERROR` span status

## 2. Scope

### In scope

- Spring Boot 3.4.3 REST application running on Java 21
- PostgreSQL 17 persistence
- OpenTelemetry Java agent 2.21.0
- OTLP over gRPC and HTTP into the Collector
- OpenTelemetry Collector Contrib 0.123.0 tail sampling
- Jaeger all-in-one 1.76.0 for local trace search
- Docker Compose startup and smoke testing

### Out of scope

- authentication and authorization
- business workflows beyond customer lookup
- persistent Jaeger storage
- metrics, logs, or profiles as observability pipelines
- production-grade Collector scaling and trace-ID routing
- Kubernetes deployment
- automated application or integration test classes

## 3. Runtime topology

```text
HTTP client
    |
    v
customer-service:8080
    |  JDBC
    v
PostgreSQL:5432

customer-service -- OTLP/gRPC, AlwaysOn --> otel-collector:4317
otel-collector -- retained traces --> jaeger:4317
Jaeger UI:16686
```

The application sends all candidate traces to the Collector by using `OTEL_TRACES_SAMPLER=always_on`. Sampling is therefore decided centrally by the Collector.

## 4. Functional requirements

### REQ-001: Customer lookup

`GET /customers/{id}` shall query the `customer` table by numeric ID and return a JSON customer object containing `id` and `name` when the row exists.

The seeded records are:

| ID | Name |
|---:|---|
| 1 | Ada Lovelace |
| 2 | Grace Hopper |
| 3 | Katherine Johnson |

### REQ-002: Healthy trace scenario

`GET /test/ok` shall execute `SELECT pg_sleep(0.05)` and return plain-text `OK` with HTTP 200 when PostgreSQL is available.

### REQ-003: Slow trace scenario

`GET /test/slow` shall execute `SELECT pg_sleep(6)` and return plain-text `SLOW` with HTTP 200. The request should exceed the Collector's 5,000 ms latency threshold and be retained.

### REQ-004: Error trace scenario

`GET /test/db-error` shall execute a query against a deliberately nonexistent table. It shall fail with HTTP 500 and produce an error-bearing trace eligible for 100% retention.

### REQ-005: Tail-sampling policy

The Collector shall wait up to 10 seconds and evaluate traces using these policies:

1. retain traces with status `ERROR`
2. retain traces with latency greater than 5,000 ms
3. retain 0.01% of remaining traces probabilistically

The policy order and thresholds are defined in `otel-collector-config.yaml`.

### REQ-006: Trace export

Retained traces shall be exported from the Collector to Jaeger over OTLP/gRPC. Jaeger shall expose its local UI at `http://localhost:16686`.

### REQ-007: Container startup

`docker compose up --build` shall build the application image from source and start PostgreSQL, Jaeger, the Collector, and the customer service. PostgreSQL must pass its health check before the application starts.

## 5. Configuration contract

| Setting | Current value | Meaning |
|---|---|---|
| `OTEL_SERVICE_NAME` | `customer-service` | Jaeger service name |
| `OTEL_TRACES_SAMPLER` | `always_on` | send all candidate traces to Collector |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-collector:4317` | Collector endpoint inside Compose |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` | OTLP transport |
| `OTEL_LOGS_EXPORTER` | `none` | no log export pipeline configured |
| `tail_sampling.decision_wait` | `10s` | trace decision buffer window |
| `tail_sampling.num_traces` | `100000` | Collector trace buffer capacity |
| `memory_limiter.limit_mib` | `512` | Collector memory limit |

Database credentials are demo-only values supplied through Compose and must not be reused in production.

## 6. Acceptance checks

1. `docker compose up --build` completes successfully.
2. `docker compose ps` shows all four services running and PostgreSQL healthy.
3. `/customers/1` returns HTTP 200 and Ada Lovelace.
4. `/test/ok` returns HTTP 200 and `OK`.
5. `/test/slow` takes approximately six seconds and returns HTTP 200 and `SLOW`.
6. `/test/db-error` returns HTTP 500.
7. Jaeger lists `customer-service` after the Collector decision window has elapsed.
8. Error and slow traces are searchable in Jaeger; healthy traces are retained only probabilistically.

## 7. Known limitations and risks

- Jaeger all-in-one uses development-oriented in-memory storage.
- The Collector is a single replica. Multiple tail-sampling replicas require trace-ID-based routing so every span for a trace reaches the same decision-maker.
- No application tests are currently committed; validation is build, Compose, endpoint, and Jaeger smoke testing.
- The demo exposes PostgreSQL and OTLP ports on the host without authentication or TLS.
- Missing customers rely on Spring/JDBC exception handling rather than an explicit API error contract.
- The slow and error endpoints are intentionally unsafe and must not be exposed in a production service.
