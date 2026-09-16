# OpenTelemetry Tail Sampling Demo

A small Spring Boot REST service backed by PostgreSQL. The OpenTelemetry Java agent sends every trace to an OpenTelemetry Collector, which keeps errors and slow traces at 100% and samples healthy traffic at 0.01% before exporting to Jaeger.

## Run it

Prerequisites: Docker with Compose v2.

```bash
./compose.sh up --build
```

The first build downloads the Maven dependencies and OpenTelemetry agent inside the Docker build. No local Maven installation or pre-built jar is required.

The service is available at `http://localhost:8080` and the Jaeger UI at `http://localhost:16686`.

Tail sampling is enabled by default. Use the repository wrapper to select the mode. To disable it for a run, start the stack with:

```bash
TAIL_SAMPLING_ENABLED=false ./compose.sh up --build
```

With the flag disabled, the Collector forwards traces without waiting for tail-sampling decisions. The application remains `always_on` in both modes.

## Try the sampling rules

```bash
curl http://localhost:8080/customers/1
curl http://localhost:8080/test/ok
curl http://localhost:8080/test/slow
curl http://localhost:8080/test/db-error
```

Check the container status and service response:

```bash
./compose.sh ps
curl -i http://localhost:8080/customers/1
```

The customer request should return HTTP 200 and JSON. `/test/ok` should return HTTP 200, `/test/slow` should take about six seconds and return HTTP 200, and `/test/db-error` should return HTTP 500.

In Jaeger, select the `customer-service` service and click **Find Traces**. The successful request is usually dropped by the 0.01% probabilistic policy; the six-second request and database error are retained by the latency and error policies.

To stop the stack and remove its containers:

```bash
./compose.sh down
```

## How it works

The app uses `OTEL_TRACES_SAMPLER=always_on`, so the Collector receives all candidate spans. When enabled, its `tail_sampling` processor waits up to ten seconds for the trace, evaluates the complete trace, and keeps it when it contains an error or exceeds five seconds. The last policy retains a tiny random fraction of healthy traffic. When disabled, the Collector uses a pass-through trace pipeline with memory limiting and batching but no tail-sampling decision.

In production with multiple Collector replicas, route all spans for a trace to the same Collector instance using trace-ID-based load balancing. Otherwise no single Collector can see the whole trace.

## Compare Collector memory

Run the same request load in each mode. The script reports the Collector's Docker memory before and after the load and the byte delta:

```bash
./compose.sh down
./compose.sh up -d
REQUESTS=1000 TAIL_SAMPLING_ENABLED=true ./memory-test.sh

./compose.sh down
TAIL_SAMPLING_ENABLED=false ./compose.sh up -d
REQUESTS=1000 TAIL_SAMPLING_ENABLED=false ./memory-test.sh
```

The script waits 12 seconds after generating requests so the enabled mode has passed its 10-second decision window. Repeat each run several times; this is an observational comparison, not a capacity benchmark. See [spec-002.md](spec-002.md) for the full contract and limitations.
