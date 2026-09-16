#!/usr/bin/env bash
set -euo pipefail

case "${TAIL_SAMPLING_ENABLED:-true}" in
  true)
    export TAIL_SAMPLING_CONFIG=config-tail-sampling.yaml
    ;;
  false)
    export TAIL_SAMPLING_CONFIG=config-no-tail-sampling.yaml
    ;;
  *)
    echo "TAIL_SAMPLING_ENABLED must be true or false" >&2
    exit 2
    ;;
esac

exec docker compose "$@"