# Implementation Plan: OpenTelemetry Tail-Sampling Demo

> Reverse-engineered implementation plan. The repository is already implemented; this plan records the delivered slices, verification evidence, and the next hardening steps.

## 1. Objective

Provide a reproducible Docker Compose demonstration of tail-based trace sampling for a Java REST service with PostgreSQL and Jaeger.

## 2. Delivered implementation

### Step 1: Service foundation

- Create a Spring Boot 3.4.3 application targeting Java 21.
- Add web and JDBC dependencies.
- Configure datasource values through environment variables with local defaults.
- Seed a `customer` table with three records at startup.

**Verification:** `mvn clean package` succeeds.

### Step 2: Observable request scenarios

- Add customer lookup at `GET /customers/{id}`.
- Add a healthy database-backed request at `GET /test/ok`.
- Add a six-second slow database request at `GET /test/slow`.
- Add a deliberate database failure at `GET /test/db-error`.

**Verification:** endpoint smoke tests return the expected 200, delayed 200, and 500 responses.

### Step 3: Application instrumentation

- Build a multi-stage image with Maven and Eclipse Temurin 21.
- Download and attach the OpenTelemetry Java agent 2.21.0.
- Configure `always_on` application sampling so no candidate trace is discarded before tail sampling.
- Export OTLP/gRPC traces to the Collector.
- Disable log export because the demo has no logs pipeline.

**Verification:** application logs show the agent and Spring Boot startup without exporter configuration errors.

### Step 4: Collector policy

- Receive OTLP over gRPC and HTTP.
- Apply a memory limiter.
- Buffer traces for up to 10 seconds.
- Keep error traces and traces over 5 seconds.
- Probabilistically retain 0.01% of remaining traces.
- Batch and export retained traces to Jaeger.

**Verification:** Jaeger lists `customer-service`; generated slow and error requests produce retained traces.

### Step 5: Local orchestration

- Define PostgreSQL, customer service, Collector, and Jaeger in Compose.
- Gate application startup on PostgreSQL health.
- Publish service, Jaeger UI, and OTLP ports for local testing.
- Document startup, endpoint checks, trace search, and shutdown.

**Verification:** `docker compose build`, `docker compose up -d`, `docker compose ps`, and endpoint smoke tests succeed.

## 3. Test plan

### Build checks

```bash
mvn -q clean package
docker compose config -q
docker compose build
```

### Runtime checks

```bash
docker compose up -d
docker compose ps
curl -i http://localhost:8080/customers/1
curl -i http://localhost:8080/test/ok
time curl -i http://localhost:8080/test/slow
curl -i http://localhost:8080/test/db-error
```

Expected results:

- customer lookup: HTTP 200 with JSON
- healthy scenario: HTTP 200 with `OK`
- slow scenario: HTTP 200 after approximately six seconds with `SLOW`
- error scenario: HTTP 500

### Trace checks

1. Generate `/test/db-error` and `/test/slow`.
2. Wait at least 10 seconds for tail-sampling decisions.
3. Open `http://localhost:16686`.
4. Select service `customer-service`.
5. Search traces.
6. Confirm the error and slow traces are present.
7. Generate many `/test/ok` requests if probabilistic retention needs to be demonstrated; 0.01% means a small sample may produce no retained healthy trace.

### Cleanup

```bash
docker compose down
```

## 4. Follow-up hardening plan

### P1: Add automated tests

- Add controller tests for status codes and response bodies.
- Add a repository/integration test using PostgreSQL Testcontainers.
- Add a Compose smoke-test script that waits for port readiness before requests.

### P1: Make deployment production-safe

- Replace demo credentials with secrets.
- Remove host exposure for PostgreSQL and Collector ingestion unless needed.
- Enable TLS/authentication between telemetry components where required.
- Pin and regularly update base images, Java agent, Collector, and Jaeger versions.

### P1: Scale tail sampling safely

- Add a trace-ID-based load-balancing tier when using multiple Collector replicas.
- Define capacity alerts for `num_traces`, memory usage, dropped spans, and decision latency.
- Choose persistent Jaeger storage or a production tracing backend.

### P2: Improve API behavior

- Add an explicit not-found response for unknown customers.
- Replace test-only failure endpoints with controlled fault injection.
- Add request validation and a stable error response schema.

### P2: Expand observability

- Add Collector metrics and health endpoints.
- Add dashboards and alerts for sampling decisions and export failures.
- Add domain attributes such as job ID, operation, retry number, and phase when adapting the demo to rerating workloads.

## 5. Completion criteria

The current demo plan is complete when the build, Compose, endpoint, and Jaeger checks pass. The follow-up plan is complete when automated tests, production-safe configuration, scalable trace routing, and operational monitoring are implemented and verified.
