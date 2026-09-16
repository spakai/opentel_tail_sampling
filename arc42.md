# arc42 Architecture Documentation

> Current-state architecture reconstructed from the repository. Sections describe the implemented demo and explicitly call out assumptions or production gaps.

## 1. Introduction and Goals

### 1.1 Overview

This system demonstrates tail-based sampling for a Java REST service. The application handles customer lookup and synthetic healthy, slow, and database-error requests. OpenTelemetry instrumentation sends all candidate traces to an OpenTelemetry Collector. The Collector decides which complete traces to retain and sends retained traces to Jaeger.

### 1.2 Quality goals

| Priority | Quality goal | Concrete interpretation |
|---|---|---|
| 1 | Observability fidelity | Preserve complete error and slow traces, including preceding database spans. |
| 2 | Low normal overhead | Retain only 0.01% of healthy traces. |
| 3 | Reproducibility | Start the complete demo with Docker Compose from a clean checkout. |
| 4 | Diagnosability | Make healthy, slow, and failed requests easy to trigger and find in Jaeger. |

### 1.3 Stakeholders

- Developer: runs and modifies the demonstration.
- Operator/observability engineer: inspects Collector policy behavior and Jaeger traces.
- Application engineer: uses the pattern as a starting point for a database-backed service.

## 2. Constraints

- Java 21 and Spring Boot 3.4.3.
- Docker Compose is the local deployment mechanism.
- PostgreSQL 17 is the database.
- OpenTelemetry Java agent version 2.21.0 instruments the application without source-level tracing code.
- OpenTelemetry Collector Contrib version 0.123.0 performs tail sampling.
- Jaeger all-in-one version 1.76.0 is used for local visualization.
- The current system is a demo: credentials, networking, storage, and TLS are not production-grade.

## 3. Context and Scope

### 3.1 System context

```text
+-------------+       HTTP        +------------------+
| Test client | ----------------> | customer-service |
+-------------+                    +--------+---------+
                                           | JDBC
                                           v
                                     +-----------+
                                     | PostgreSQL |
                                     +-----------+

customer-service -- OTLP traces --> OpenTelemetry Collector -- retained traces --> Jaeger
                                                                                  |
                                                                                  v
                                                                                Browser
```

### 3.2 External interfaces

| Interface | Direction | Contract |
|---|---|---|
| HTTP :8080 | client to app | REST endpoints described in `spec.md` |
| JDBC :5432 | app to PostgreSQL | `customer` table and SQL test queries |
| OTLP/gRPC :4317 | app to Collector | OpenTelemetry spans |
| OTLP/HTTP :4318 | optional client to Collector | Collector receiver, not used by the Java agent default |
| OTLP/gRPC | Collector to Jaeger | retained trace export |
| HTTP :16686 | browser to Jaeger | Jaeger UI |

## 4. Solution Strategy

1. Instrument the application at runtime with the OpenTelemetry Java agent.
2. Use `always_on` at the application so the Collector sees complete candidate traces.
3. Delay the sampling decision in the Collector until enough of each trace has arrived.
4. Retain traces with errors or latency above 5 seconds.
5. Retain a very small probabilistic sample of healthy traces.
6. Export retained traces to Jaeger for inspection.
7. Keep the deployment small and reproducible with Docker Compose.

This strategy separates trace creation from retention policy. It avoids the fundamental limitation of head sampling, where a trace dropped at request start cannot be recovered after a later database failure.

## 5. Building Block View

### 5.1 Level 1: containers

| Container | Technology | Responsibility |
|---|---|---|
| `customer-service` | Spring Boot, Java 21, embedded Tomcat | REST API, JDBC access, runtime instrumentation |
| `postgres` | PostgreSQL 17 | Customer data and database fault/latency behavior |
| `otel-collector` | OTel Collector Contrib 0.123.0 | OTLP intake, memory limiting, tail sampling, batching, export |
| `jaeger` | Jaeger all-in-one 1.76.0 | Trace ingestion, in-memory storage, UI |

### 5.2 Level 2: customer-service internals

```text
TailSamplingApplication
    |
    +-- CustomerController -- JdbcTemplate --> customer table
    |
    +-- TestController ----- JdbcTemplate --> pg_sleep / invalid table
    |
    +-- OpenTelemetry Java Agent
             |
             +-- HTTP server spans
             +-- JDBC spans
             +-- OTLP exporter
```

The controllers are intentionally small. Database calls are instrumented by the Java agent and do not require manual span creation in application code.

### 5.3 Collector internals

```text
OTLP receiver
    -> memory_limiter (512 MiB)
    -> tail_sampling (10 s decision wait, 100,000 trace capacity)
       -> status ERROR: keep
       -> latency > 5,000 ms: keep
       -> remaining traces: 0.01% probabilistic keep
    -> batch
    -> OTLP Jaeger exporter
```

## 6. Runtime View

### 6.1 Normal request

```text
Client -> Service: GET /test/ok
Service -> PostgreSQL: SELECT pg_sleep(0.05)
PostgreSQL --> Service: success
Service -> Collector: HTTP + JDBC spans
Collector -> Collector: wait and evaluate
Collector -> Collector: probabilistic 0.01% decision
Collector --> Jaeger: export only if retained
Service --> Client: 200 OK
```

### 6.2 Slow request

```text
Client -> Service: GET /test/slow
Service -> PostgreSQL: SELECT pg_sleep(6)
PostgreSQL --> Service: success after 6 seconds
Service -> Collector: complete trace
Collector -> Collector: latency > 5,000 ms
Collector --> Jaeger: retain and export whole trace
Service --> Client: 200 SLOW
```

### 6.3 Error request

```text
Client -> Service: GET /test/db-error
Service -> PostgreSQL: query nonexistent table
PostgreSQL --> Service: SQL error
Service -> Collector: error-bearing HTTP/JDBC trace
Collector -> Collector: status ERROR
Collector --> Jaeger: retain and export whole trace
Service --> Client: 500
```

## 7. Deployment View

```text
Docker Compose network

+------------------+       +------------------+
| customer-service | ----> | otel-collector   |
| host :8080       |       | host :4317/:4318 |
+--------+---------+       +--------+---------+
         |                          |
         v                          v
+------------------+       +------------------+
| postgres         |       | jaeger           |
| host :5432       |       | host :16686      |
+------------------+       +------------------+
```

The application waits for PostgreSQL's Compose health check. The Collector depends on Jaeger startup. The application depends on PostgreSQL health and Collector process startup.

The Dockerfile uses two stages: Maven/Eclipse Temurin 21 to compile and package, then Eclipse Temurin 21 JRE to run the jar with the OpenTelemetry agent.

## 8. Cross-Cutting Concepts

### 8.1 Sampling

Sampling is intentionally performed only after export from the application to the Collector. The application uses `always_on`; the Collector owns retention policy.

### 8.2 Error and latency semantics

Database failures become application request failures and agent-recorded span errors. The Collector's status policy retains traces containing `ERROR`. The latency policy measures the complete trace and retains traces over 5 seconds.

### 8.3 Configuration

Application and database settings are environment-driven. Collector policy is mounted from `otel-collector-config.yaml`. Image and dependency versions are explicitly specified in the Dockerfile, Compose file, and Maven descriptor.

### 8.4 Data and storage

PostgreSQL data is initialized by Spring SQL initialization. Jaeger all-in-one stores traces in development-oriented memory; data is lost when the container is removed.

### 8.5 Security posture

The demo has no authentication, authorization, TLS, secret manager integration, or network isolation beyond the Compose network. Demo credentials are visible in Compose and are not suitable for production.

## 9. Architecture Decisions

### ADR-1: Collector-owned tail sampling

**Decision:** Use application `always_on` sampling and Collector tail sampling.

**Reason:** Error and latency conditions are often known only after a request executes. Head sampling cannot recover spans discarded at request start.

### ADR-2: OpenTelemetry Java agent

**Decision:** Instrument HTTP and JDBC automatically with the Java agent.

**Reason:** Keeps demonstration application code small and exercises standard Spring/JDBC instrumentation.

### ADR-3: Jaeger all-in-one

**Decision:** Use Jaeger all-in-one for local development.

**Reason:** Provides a low-friction OTLP destination and UI in one container. It is not a production storage choice.

### ADR-4: Docker Compose

**Decision:** Package all dependencies in a four-service Compose topology.

**Reason:** Makes the example reproducible without requiring local PostgreSQL, Collector, or Jaeger installations.

## 10. Quality Requirements

- Build reproducibility from a clean checkout.
- Service startup after PostgreSQL becomes healthy.
- Error traces retained at 100% under the configured policy.
- Slow traces retained at 100% above 5 seconds.
- Healthy trace retention constrained to approximately 0.01%.
- Trace continuity preserved when all spans reach one Collector instance.
- Local smoke-test commands documented and repeatable.

## 11. Risks and Technical Debt

| Risk | Impact | Mitigation / next step |
|---|---|---|
| One Collector replica | unsafe horizontal scaling | add trace-ID-based load balancing before scaling |
| In-memory Jaeger storage | trace loss on restart | use persistent production backend |
| No automated tests | regressions may be discovered late | add unit, integration, and Compose smoke tests |
| Demo credentials and open ports | unauthorized access in shared environments | use secrets, TLS, and restricted networking |
| Tail buffer sizing is static | memory pressure under load | load test and monitor Collector metrics |
| Test endpoints are public | intentional failure behavior could be abused | remove or protect outside local demos |

## 12. Glossary

- **Head sampling:** deciding whether to retain a trace when it starts.
- **Tail sampling:** deciding after a trace or enough of it has arrived.
- **OTLP:** OpenTelemetry Protocol used to transfer telemetry.
- **Span:** one timed operation within a trace.
- **Trace:** the complete operation graph for one request.
- **Collector:** OpenTelemetry service that receives, processes, and exports telemetry.
- **Jaeger:** tracing backend and UI used by this demo.
