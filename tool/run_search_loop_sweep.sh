#!/usr/bin/env bash
# Runs the live OpenRouter research-loop sweep.
#
# Reads OPENROUTER_API_KEY from .env (gitignored) unless it is already set in
# the environment, so the key never has to be typed on a command line or
# committed. Any OR_* knob the test reads (OR_MODELS, OR_PROBES, OR_REPORT)
# can be exported before calling this, or set in .env alongside the key.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${OPENROUTER_API_KEY:-}" && -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo "OPENROUTER_API_KEY is not set and .env does not define it." >&2
  echo "Add it to .env as: OPENROUTER_API_KEY=sk-or-..." >&2
  exit 1
fi

exec flutter test \
  --reporter expanded \
  --concurrency 1 \
  test/integration/openrouter_search_loop_live_test.dart "$@"
