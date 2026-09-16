# SPEC-002: Toggle Tail Sampling and Compare Memory

## Status

Proposed and implemented on branch `spec-002-tail-sampling-toggle`.

## Goal

Allow the demo to run with tail sampling enabled or disabled without changing application code, then provide a repeatable comparison of OpenTelemetry Collector memory usage under the same request load.

## Configuration contract

`TAIL_SAMPLING_ENABLED` is read by `compose.sh`, which selects the Collector config filename before invoking Docker Compose.

| Value | Collector configuration | Behavior |
|---|---|---|
| `true` or omitted | `otel-collector-config.yaml` | buffers traces for up to 10 seconds and applies error, latency, and probabilistic policies |
| `false` | `otel-collector-config-no-tail-sampling.yaml` | forwards received traces through memory limiting and batching without tail-sampling decisions |

The application remains `OTEL_TRACES_SAMPLER=always_on` in both modes. This keeps the comparison focused on Collector behavior and ensures the no-tail mode does not accidentally discard traces in the application.

## Acceptance criteria

1. `docker compose config -q` succeeds with the default flag.
2. `TAIL_SAMPLING_ENABLED=false ./compose.sh config -q` succeeds.
3. The default Collector starts with the tail-sampling config.
4. The disabled Collector starts with the no-tail config.
5. `memory-test.sh` runs the same number of healthy requests in both modes and reports before/after Collector memory and a byte delta.
6. The script waits beyond the 10-second tail decision window before taking the final sample when tail sampling is enabled.
7. The result is treated as an observational comparison, not a benchmark: Docker memory values depend on JVM, Collector, host, traffic, and timing.

## Test procedure

```bash
# Mode A: tail sampling enabled
./compose.sh down
./compose.sh up -d
REQUESTS=1000 TAIL_SAMPLING_ENABLED=true ./memory-test.sh

# Mode B: tail sampling disabled
./compose.sh down
TAIL_SAMPLING_ENABLED=false ./compose.sh up -d
REQUESTS=1000 TAIL_SAMPLING_ENABLED=false ./memory-test.sh
```

Compare `collector_memory_delta_bytes` and the final `collector_memory_after` values. Repeat each mode several times for a useful observation. The script does not claim that one run proves a general memory profile.

## Limitations

- The comparison measures the Collector container only, not total stack memory.
- Healthy requests are sequential and do not model high concurrency.
- The script uses Docker's instantaneous `MemUsage` sample rather than a time-series profiler.
- Tail sampling's main memory cost is expected to appear when many traces are concurrently buffered; a high-concurrency/load-test variant would be needed for capacity planning.