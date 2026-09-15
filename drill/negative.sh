#!/usr/bin/env bash
# Materialize every negative case as a throwaway repository and require the
# expected rejection. Each case directory holds the files that replace their
# counterparts in the drill clone and an `expect` file naming the check
# identifier (or `cleanup` for cases judged by cleanup behaviour).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
drill_parse_arguments "$@"
version="$(cat "${DRILL_WORKSPACE}/drill-version.current")"
status=passed
for case_dir in "${DRILL_REPOSITORY}"/negative/*/; do
  name="$(basename "${case_dir}")"
  expect="$(cat "${case_dir}/expect")"
  target="${DRILL_WORKSPACE}/negative/${name}"
  rm -rf "${target}"; mkdir -p "$(dirname "${target}")"
  git clone -q "${DRILL_WORKSPACE}/project" "${target}"
  git -C "${target}" remote set-url origin https://github.com/foundata/oci-conclear-drill.git
  # Merge the case over the clone: `cp -r hooks .` would nest the directory
  # inside the existing one, so the case's files must be copied content-first.
  (cd "${target}" && cp -a "${case_dir}/." . && rm -f expect image \
    && git -c user.name="ConClear drill" -c user.email="drill@invalid" add -A \
    && git -c user.name="ConClear drill" -c user.email="drill@invalid" commit -q -m "drill: negative case ${name}" \
    && git tag -f "v${version}" >/dev/null)
  revision="$(git -C "${target}" rev-parse HEAD)"
  image="$(cat "${case_dir}/image" 2>/dev/null || echo service)"
  (cd "${target}" && drill_run "negative-${name}" "${DRILL_CLI}" qualify --revision "${revision}" --image "${image}" --platform linux/amd64 --version "${version}" --format json) || true
  outcome="$(jq -r '.status // "none"' "${DRILL_WORKSPACE}/artifacts/negative-${name}.json" 2>/dev/null || echo none)"
  found="$(jq -r '[.findings[]?.checkId] | unique | join(",")' "${DRILL_WORKSPACE}/artifacts/negative-${name}.json" 2>/dev/null || true)"
  message="$(jq -r '.message // ""' "${DRILL_WORKSPACE}/artifacts/negative-${name}.json" 2>/dev/null || true)"
  if [ "${outcome}" = operationalFailure ]; then
    # The environment failed, not the case: a rate-limited registry, a missing
    # tool or an unreachable service. Say so instead of claiming a wrong check.
    status=failed
    drill_log "negative ${name}: OPERATIONAL FAILURE, case not exercised: ${message:0:200}"
    continue
  fi
  if [ "${expect#retire:}" != "${expect}" ]; then
    # Judged by cleanup: retiring the run must stop at content this user cannot
    # remove and name it; the drill then removes it through the user namespace.
    pattern="${expect#retire:}"
    run_id="$(jq -r '.data.runId // empty' "${DRILL_WORKSPACE}/artifacts/negative-${name}.json" 2>/dev/null || true)"
    if [ -z "${run_id}" ]; then
      status=failed; drill_log "negative ${name}: no run to retire (outcome=${outcome})"; continue
    fi
    if (cd "${target}" && drill_run "negative-${name}-retire" "${DRILL_CLI}" cleanup "${run_id}" --retire --format json); then
      status=failed; drill_log "negative ${name}: UNEXPECTED retire succeeded"; continue
    fi
    retire_message="$(jq -r '.message // ""' "${DRILL_WORKSPACE}/artifacts/negative-${name}-retire.json" 2>/dev/null || true)"
    if printf '%s' "${retire_message}" | grep -q "retired only partially" && printf '%s' "${retire_message}" | grep -q "${pattern}"; then
      drill_log "negative ${name}: retire stopped and named ${pattern} as expected"
      podman unshare rm -rf "${XDG_STATE_HOME}/conclear/runs/${run_id}/checkout/.drill-litter" 2>/dev/null || true
      (cd "${target}" && drill_run "negative-${name}-retire-again" "${DRILL_CLI}" cleanup "${run_id}" --retire --format json) || { status=failed; drill_log "negative ${name}: second retire FAILED"; }
    else
      status=failed; drill_log "negative ${name}: UNEXPECTED retire message: ${retire_message:0:200}"
    fi
    continue
  fi
  if [ "${outcome}" = ruleRejection ] && { [ "${found}" = "${expect}" ] || printf '%s' "${message}" | grep -q "${expect}"; }; then
    drill_log "negative ${name}: rejected by ${expect} as expected"
  else
    status=failed; drill_log "negative ${name}: UNEXPECTED outcome=${outcome} checks=${found} message=${message:0:160} (expected ${expect})"
  fi
done
drill_record negative "${status}" "$(jq -cn '{}')"
[ "${status}" = passed ]
