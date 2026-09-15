#!/bin/busybox sh
# Lifecycle fixture: become ready by writing a marker into the declared
# writable directory, then wait for SIGTERM and exit 0.
set -eu
state="${CONCLEAR_DRILL_STATE_DIR:-/run/conclear-drill}"
terminate() {
  rm -f "${state}/ready"
  exit 0
}
trap terminate TERM INT
sleep 1
: > "${state}/ready"
echo "conclear-drill lifecycle: ready"
while :; do
  sleep 1 &
  wait $!
done
