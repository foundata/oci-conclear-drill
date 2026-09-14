#!/usr/bin/env bash
# Run the drill stages in dependency order. Stages 1 and 2 need no registry;
# the rest need the disposable registry, its credentials and the drill profile.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
drill_parse_arguments "$@"
cd "${DRILL_WORKSPACE}/project"
version="$(cat "${DRILL_WORKSPACE}/drill-version.current")"
revision="$(drill_source_revision)"
platforms=(linux/amd64 linux/arm64)

# 1. Installed identity and static checks for every image.
drill_run identity "${DRILL_CLI}" version --format json
for image in service systemd oneshot helper; do
  drill_run "check-${image}" "${DRILL_CLI}" check --image "${image}" --format json || true
  drill_run "pins-check-${image}" "${DRILL_CLI}" pins check --image "${image}" --format json || true
done
drill_record static "$( for i in service systemd oneshot helper; do drill_json "check-${i}" .status; drill_json "pins-check-${i}" .status; done | grep -qv '^success$' && echo failed || echo passed)" \
  "$(jq -cn '{}')"

# 2. Local qualification of every release image and platform without a profile:
#    build, runtime tests, scans, SBOM, set-ID inventory, footprint. No registry.
status=passed
for image in service systemd oneshot; do
  for platform in "${platforms[@]}"; do
    name="qualify-local-${image}-${platform//\//-}"
    if drill_run "${name}" "${DRILL_CLI}" qualify --revision "${revision}" --image "${image}" --platform "${platform}" --version "${version}" --format json; then
      drill_log "${name}: $(drill_json "${name}" '.details // [] | join("; ")')"
    else
      status=failed; drill_log "${name} FAILED: $(drill_json "${name}" '[.findings[]? | .checkId + " " + .message] | join("; ")')"
    fi
  done
done
drill_record qualify-local "${status}" "$(jq -cn --arg v "${version}" '{version: $v}')"
[ "${status}" = passed ] || { drill_log "stopping before registry stages"; exit 1; }
if [ "${DRILL_LOCAL_ONLY}" = yes ]; then
  drill_log "local-only drill complete; registry stages skipped"
  "$(dirname "${BASH_SOURCE[0]}")/negative.sh" --workspace "${DRILL_WORKSPACE}" --registry "${DRILL_REGISTRY}" --profile "${DRILL_PROFILE}"
  exit 0
fi

# 3. Part A: complete release of the service image.
if drill_run release-service "${DRILL_CLI}" release --revision "${revision}" --image service --version "${version}" --profile "${DRILL_PROFILE}" --format json; then
  drill_record release-service passed "$(drill_json release-service '.data')"
else
  drill_record release-service failed "$(drill_json release-service '{message, findings}')"; exit 1
fi

# 4. Part B: composable path on the systemd image, one worker per platform.
transports=(); digests=()
first_db=""; first_start=""
for platform in "${platforms[@]}"; do
  key="${platform//\//-}"
  extra=()
  [ -n "${first_db}" ] && extra=(--database-digest "${first_db}" --qualification-started-at "${first_start}")
  drill_run "b-qualify-${key}" "${DRILL_CLI}" qualify --revision "${revision}" --image systemd --platform "${platform}" --version "${version}" --profile "${DRILL_PROFILE}" "${extra[@]}" --format json || { drill_record composable failed "$(drill_json "b-qualify-${key}" '{message, findings}')"; exit 1; }
  run_id="$(drill_json "b-qualify-${key}" .data.runId)"
  [ -n "${first_db}" ] || { first_db="$(drill_json "b-qualify-${key}" .data.databaseDigest)"; first_start="$(drill_json "b-qualify-${key}" .data.qualificationWindow.startedAt)"; }
  tar="${DRILL_WORKSPACE}/artifacts/systemd-${key}.tar"; rm -f "${tar}"
  drill_run "b-export-${key}" "${DRILL_CLI}" transport export "${run_id}" --platform "${platform}" --output "${tar}" --format json || exit 1
  transports+=("${tar}"); digests+=("$(drill_json "b-export-${key}" .data.transportDigest)")
done
args=(); for i in "${!transports[@]}"; do args+=(--transport "${transports[$i]}" "${digests[$i]}"); done
drill_run b-assemble "${DRILL_CLI}" assemble --revision "${revision}" --image systemd --version "${version}" --profile "${DRILL_PROFILE}" "${args[@]}" --format json || exit 1
coordinator="$(drill_json b-assemble .data.runId)"
for step in provenance publish attest verify; do
  drill_run "b-${step}" "${DRILL_CLI}" "${step}" "${coordinator}" $([ "${step}" = provenance ] || printf -- '--profile %s' "${DRILL_PROFILE}") --format json || { drill_record composable failed "$(drill_json "b-${step}" '{message, findings}')"; exit 1; }
done
drill_run b-promote "${DRILL_CLI}" promote "${coordinator}" --profile "${DRILL_PROFILE}" --version "${version}" --format json || exit 1
drill_record composable passed "$(jq -cn --arg c "${coordinator}" '{coordinator: $c}')"

# 5. Part C: one-shot release, then the negative cases.
drill_run release-oneshot "${DRILL_CLI}" release --revision "${revision}" --image oneshot --version "${version}" --profile "${DRILL_PROFILE}" --format json && drill_record release-oneshot passed "$(drill_json release-oneshot '.data')" || drill_record release-oneshot failed "$(drill_json release-oneshot '{message, findings}')"
"$(dirname "${BASH_SOURCE[0]}")/negative.sh" --workspace "${DRILL_WORKSPACE}" --registry "${DRILL_REGISTRY}" --profile "${DRILL_PROFILE}"
