#!/usr/bin/env bash
# Independent verification of the promoted drill releases, archive
# verification and one authoritative rescan; then cleanup of every run.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
drill_parse_arguments "$@"
version="$(cat "${DRILL_WORKSPACE}/drill-version.current")"
auth="${XDG_CONFIG_HOME}/conclear/drill-auth.json"
public_key="${XDG_CONFIG_HOME}/conclear/drill-cosign.pub"
status=passed
for image in service systemd oneshot; do
  reference="${DRILL_REGISTRY}/drill-${image}:${version}"
  if skopeo inspect --authfile "${auth}" --raw "docker://${reference}" > "${DRILL_WORKSPACE}/artifacts/verify-${image}-index.json" 2>>"${DRILL_WORKSPACE}/logs/verify.log"; then
    drill_log "${image} ${version} platforms: $(jq -r '[.manifests[]? | .platform.os + "/" + .platform.architecture] | join(",")' "${DRILL_WORKSPACE}/artifacts/verify-${image}-index.json")"
  else
    status=failed; drill_log "${image} ${version}: index not readable"
  fi
  DOCKER_CONFIG="$(mktemp -d)"; cp "${auth}" "${DOCKER_CONFIG}/config.json"; export DOCKER_CONFIG
  cosign verify --key "${public_key}" "${reference}" > /dev/null 2>>"${DRILL_WORKSPACE}/logs/verify.log" && drill_log "cosign verify ${image} ok" || { status=failed; drill_log "cosign verify ${image} FAILED"; }
  for type in slsaprovenance1 spdxjson; do
    cosign verify-attestation --key "${public_key}" --type "${type}" "${reference}" > /dev/null 2>>"${DRILL_WORKSPACE}/logs/verify.log" && drill_log "verify-attestation ${type} ${image} ok" || { status=failed; drill_log "verify-attestation ${type} ${image} FAILED"; }
  done
  rm -rf "${DOCKER_CONFIG}"; unset DOCKER_CONFIG
done
cd "${DRILL_WORKSPACE}/project"
for archive in "${DRILL_WORKSPACE}"/archives/release-*.tar.gz; do
  [ -f "${archive}" ] || continue
  drill_run "archive-verify-$(basename "${archive}" .tar.gz)" "${DRILL_CLI}" archive verify "${archive}" --profile "${DRILL_PROFILE}" --format json || status=failed
done
latest="$(ls -t "${DRILL_WORKSPACE}"/archives/release-*.tar.gz 2>/dev/null | head -1 || true)"
if [ -n "${latest}" ]; then
  drill_run rescan "${DRILL_CLI}" rescan --archive "${latest}" --profile "${DRILL_PROFILE}" --authoritative --format json || status=failed
fi
drill_record verify "${status}" "$(jq -cn --arg v "${version}" '{version: $v}')"
# Cleanup: retire every run of this drill; the disposable repositories keep the
# promoted tags until the next prepare empties them.
for run in "${XDG_STATE_HOME}"/conclear/runs/*/; do
  [ -d "${run}" ] || continue
  drill_run "cleanup-$(basename "${run}")" "${DRILL_CLI}" cleanup "$(basename "${run}")" --profile "${DRILL_PROFILE}" --retire --abandon --format json || status=failed
done
drill_record cleanup "${status}" "$(jq -cn '{}')"
[ "${status}" = passed ]
