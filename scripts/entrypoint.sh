#!/bin/sh
# Long-running drill service: becomes ready by writing a marker into the
# declared writable directory, optionally reads generated test material, then
# waits for SIGTERM and exits 0.
set -eu

state_dir="${CONCLEAR_DRILL_STATE_DIR:-/run/conclear-drill}"
material="${CONCLEAR_DRILL_MATERIAL:-}"

terminate() {
  printf 'conclear-drill: terminating\n'
  rm -f "${state_dir}/ready"
  exit 0
}
trap terminate TERM INT

if [ -n "${material}" ] && [ -f "${material}" ]; then
  printf 'conclear-drill: material %s\n' "$(jq -r '.generated' "${material}")"
fi

# A brief warm-up makes readiness observable as a real probe sequence.
sleep 2
printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${state_dir}/ready"
printf 'conclear-drill: ready\n'

while :; do
  sleep 1 &
  wait $!
done
