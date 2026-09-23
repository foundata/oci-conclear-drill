#!/usr/bin/env bash
# Shared helpers for the drill scripts. Source, do not execute.
# Every script takes --workspace <dir>; prepare.sh also takes --wheel <path>.
set -euo pipefail

drill_usage() {
  printf 'usage: %s --workspace <dir> [--wheel <path>] [--registry <namespace>] [--profile <name>] [--local-only] [--version <x.y.z>]\n' "${0##*/}" >&2
  exit 64
}

drill_parse_arguments() {
  DRILL_WORKSPACE=""; DRILL_WHEEL=""; DRILL_REGISTRY="quay.io/conclear-drill"; DRILL_PROFILE="drill"; DRILL_LOCAL_ONLY=no; DRILL_VERSION=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --workspace) DRILL_WORKSPACE="$2"; shift 2 ;;
      --wheel) DRILL_WHEEL="$2"; shift 2 ;;
      --registry) DRILL_REGISTRY="$2"; shift 2 ;;
      --profile) DRILL_PROFILE="$2"; shift 2 ;;
      --local-only) DRILL_LOCAL_ONLY=yes; shift ;;
      --version) DRILL_VERSION="$2"; shift 2 ;;
      *) drill_usage ;;
    esac
  done
  [ -n "${DRILL_WORKSPACE}" ] || drill_usage
  DRILL_WORKSPACE="$(realpath -m "${DRILL_WORKSPACE}")"
  DRILL_REPOSITORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  DRILL_CLI="${DRILL_WORKSPACE}/wheel-env/bin/conclear"
  DRILL_MANIFEST="${DRILL_WORKSPACE}/manifest.json"
  export XDG_CONFIG_HOME="${DRILL_WORKSPACE}/consumer/config"
  export XDG_STATE_HOME="${DRILL_WORKSPACE}/consumer/state"
  export XDG_CACHE_HOME="${DRILL_WORKSPACE}/consumer/cache"
}

drill_log() {
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "${DRILL_WORKSPACE}/logs/drill.log" >&2
}

# drill_record <stage> <status> <json-details>: append one stage result to the index.
drill_record() {
  python3 - "${DRILL_MANIFEST}" "$1" "$2" "$3" <<'PY'
import json, sys
from datetime import datetime, timezone
path, stage, status, details = sys.argv[1:]
manifest = json.load(open(path))
manifest.setdefault("results", {})[stage] = {
    "status": status,
    "recorded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "details": json.loads(details),
}
json.dump(manifest, open(path, "w"), indent=2, sort_keys=True)
PY
}

# drill_note <text>: append a free-text observation to the index.
drill_note() {
  python3 - "${DRILL_MANIFEST}" "$1" <<'PY'
import json, sys
path, text = sys.argv[1:]
manifest = json.load(open(path))
manifest.setdefault("observations", []).append(text)
json.dump(manifest, open(path, "w"), indent=2, sort_keys=True)
PY
}

# drill_run <name> <command...>: run one ConClear command, keep its JSON result
# and stderr, return its exit status.
drill_run() {
  local name="$1"; shift
  drill_log "RUN ${name}: $*"
  set +e
  "$@" > "${DRILL_WORKSPACE}/artifacts/${name}.json" 2> "${DRILL_WORKSPACE}/logs/${name}.stderr"
  local status=$?
  set -e
  drill_log "END ${name} exit=${status}"
  return "${status}"
}

drill_json() {
  jq -r "$2" "${DRILL_WORKSPACE}/artifacts/$1.json"
}

# drill_platforms <image>: the platforms the drill clone declares for an image.
drill_platforms() {
  python3 - "${DRILL_WORKSPACE}/project/conclear.toml" "$1" <<'PY'
import sys, tomllib
config, image = sys.argv[1], sys.argv[2]
with open(config, "rb") as handle:
    data = tomllib.load(handle)
for item in data["images"]:
    if item["id"] == image:
        print("\n".join(item["platforms"]))
PY
}

# drill_run_java <name> <command...>: run a command that assesses the java
# image. While upstream's Java database has expired, ConClear must first reject
# the image with CC0507; the retry with --accept-stale-java-database must then
# pass and record the acceptance. With a fresh Java database the plain run
# passes. Any other rejection fails. Sets DRILL_JAVA_ACCEPTED to yes or no.
drill_run_java() {
  local name="$1"; shift
  DRILL_JAVA_ACCEPTED=no
  if drill_run "${name}" "$@"; then
    return 0
  fi
  if [ "$(drill_json "${name}" '[.findings[]?.checkId] | index("CC0507") != null')" != true ]; then
    return 1
  fi
  drill_log "${name}: rejected by CC0507 while the Java database is expired, as expected; retrying with the recorded acceptance"
  DRILL_JAVA_ACCEPTED=yes
  drill_run "${name}-accepted" "$@" --accept-stale-java-database
}

# drill_source_revision: the head of the throwaway drill clone.
drill_source_revision() {
  git -C "${DRILL_WORKSPACE}/project" rev-parse HEAD
}
