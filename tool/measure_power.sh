#!/usr/bin/env bash
# Rough host-side power proxy for the app running on the iOS Simulator.
# CPU% via `top` needs no sudo. Set POWERMETRICS=1 to also sample energy
# (needs sudo -> in Claude Code, run it with the `!` prefix, e.g.:
#     ! POWERMETRICS=1 sudo tool/measure_power.sh 30 )
#
# Usage: tool/measure_power.sh [seconds]
set -euo pipefail
SECS="${1:-30}"

PID="$(pgrep -n -f 'Runner.app/Contents/MacOS/Runner' \
      || pgrep -n -f 'Runner.app/Runner' \
      || pgrep -n Runner \
      || true)"
if [[ -z "${PID}" ]]; then
  echo "Runner process not found. Is the app running on the simulator?" >&2
  exit 1
fi
echo "Sampling Runner pid=${PID} for ${SECS}s ..."

top -l "$((SECS + 1))" -s 1 -pid "${PID}" -stats pid,cpu \
  | awk -v pid="${PID}" '$1 == pid {sum+=$2; n++}
         END {if (n>0) printf "avg CPU%% over %d samples: %.1f\n", n, sum/n;
              else print "no CPU samples captured"}'

if [[ "${POWERMETRICS:-0}" == "1" ]]; then
  echo "--- powermetrics (package/CPU/GPU power) ---"
  sudo powermetrics --samplers cpu_power,gpu_power -i 1000 -n "${SECS}" 2>/dev/null \
    | awk '/Combined Power|CPU Power|GPU Power|Package Power/ {print}'
fi
