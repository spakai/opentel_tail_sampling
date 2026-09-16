#!/usr/bin/env bash
set -euo pipefail

requests="${REQUESTS:-1000}"
collector="opentel_tail_sampling-otel-collector-1"

if ! docker inspect "$collector" >/dev/null 2>&1; then
  echo "Collector container is not running. Start the stack first." >&2
  exit 1
fi

sample_memory() {
  docker stats --no-stream --format '{{.MemUsage}}' "$collector" | cut -d/ -f1 | tr -d ' '
}

echo "Generating ${requests} healthy requests..."
before="$(sample_memory)"
for ((request = 1; request <= requests; request++)); do
  curl -fsS http://localhost:8080/test/ok >/dev/null
done
sleep 12
after="$(sample_memory)"

printf 'tail_sampling_enabled=%s\n' "${TAIL_SAMPLING_ENABLED:-true}"
printf 'requests=%s\n' "$requests"
printf 'collector_memory_before=%s\n' "$before"
printf 'collector_memory_after=%s\n' "$after"
printf 'collector_memory_delta_bytes=%s\n' "$(python3 - "$before" "$after" <<'PY'
import re
import sys

units = {"B": 1, "KiB": 1024, "MiB": 1024**2, "GiB": 1024**3}

def to_bytes(value):
    match = re.fullmatch(r"([0-9.]+)([KMG]iB|B)", value)
    if not match:
        raise SystemExit(f"Unsupported docker stats value: {value}")
    return int(float(match.group(1)) * units[match.group(2)])

print(to_bytes(sys.argv[2]) - to_bytes(sys.argv[1]))
PY
)"