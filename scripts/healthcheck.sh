#!/bin/sh
# Ready when the entrypoint has written its marker.
set -eu
test -f "${CONCLEAR_DRILL_STATE_DIR:-/run/conclear-drill}/ready"
