#!/usr/bin/env bash
# Independent verification of the promoted drill releases, archive
# verification and one authoritative rescan; then cleanup of every run.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
drill_parse_arguments "$@"
version="$(cat "${DRILL_WORKSPACE}/drill-version.current")"
auth="${XDG_CONFIG_HOME}/conclear/drill-auth.json"
public_key="${XDG_CONFIG_HOME}/conclear/drill-cosign.pub"
status=passed
for image in service systemd oneshot java; do
  reference="${DRILL_REGISTRY}/drill-${image}:${version}"
  if skopeo inspect --authfile "${auth}" --raw "docker://${reference}" > "${DRILL_WORKSPACE}/artifacts/verify-${image}-index.json" 2>>"${DRILL_WORKSPACE}/logs/verify.log"; then
    drill_log "${image} ${version} platforms: $(jq -r '[.manifests[]? | .platform.os + "/" + .platform.architecture] | join(",")' "${DRILL_WORKSPACE}/artifacts/verify-${image}-index.json")"
  else
    status=failed; drill_log "${image} ${version}: index not readable"
  fi
  DOCKER_CONFIG="$(mktemp -d)"; cp "${auth}" "${DOCKER_CONFIG}/config.json"; export DOCKER_CONFIG
  cosign verify --key "${public_key}" "${reference}" > /dev/null 2>>"${DRILL_WORKSPACE}/logs/verify.log" && drill_log "cosign verify ${image} ok" || { status=failed; drill_log "cosign verify ${image} FAILED"; }
  cosign verify-attestation --key "${public_key}" --type slsaprovenance1 "${reference}" > /dev/null 2>>"${DRILL_WORKSPACE}/logs/verify.log" \
    && drill_log "verify-attestation slsaprovenance1 ${image} ok" \
    || { status=failed; drill_log "verify-attestation slsaprovenance1 ${image} FAILED"; }
  # The SBOM is attached to each platform manifest, not to the index, so it is
  # verified exactly the way ConClear's README tells consumers to. A
  # single-platform image has no index: its own digest is the manifest digest.
  digests="$(jq -r '.manifests[]?.digest // empty' "${DRILL_WORKSPACE}/artifacts/verify-${image}-index.json" 2>/dev/null)"
  [ -n "${digests}" ] || digests="$(skopeo inspect --authfile "${auth}" --format '{{.Digest}}' "docker://${reference}" 2>>"${DRILL_WORKSPACE}/logs/verify.log")"
  [ -n "${digests}" ] || { status=failed; drill_log "no manifest digest for ${image}"; }
  for digest in ${digests}; do
    cosign verify-attestation --key "${public_key}" --type spdxjson "${DRILL_REGISTRY}/drill-${image}@${digest}" > /dev/null 2>>"${DRILL_WORKSPACE}/logs/verify.log" \
      && drill_log "verify-attestation spdxjson ${image}@${digest%%:*}:${digest#*:} ok" \
      || { status=failed; drill_log "verify-attestation spdxjson ${image}@${digest} FAILED"; }
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
  # The latest archive is the java release, so an expired Java database makes
  # this rescan take the CC0507 path too.
  drill_run_java rescan "${DRILL_CLI}" rescan --archive "${latest}" --profile "${DRILL_PROFILE}" --authoritative --format json || status=failed
fi
drill_record verify "${status}" "$(jq -cn --arg v "${version}" '{version: $v}')"
# Cleanup: retire every run of this drill; the disposable repositories keep the
# promoted tags until the next prepare empties them. Its result is its own, so
# a failed verification does not read as a failed cleanup.
cleanup_status=passed
for run in "${XDG_STATE_HOME}"/conclear/runs/*/; do
  [ -d "${run}" ] || continue
  drill_run "cleanup-$(basename "${run}")" "${DRILL_CLI}" cleanup "$(basename "${run}")" --profile "${DRILL_PROFILE}" --retire --abandon --format json || cleanup_status=failed
done
drill_record cleanup "${cleanup_status}" "$(jq -cn '{}')"
[ "${status}" = passed ] && [ "${cleanup_status}" = passed ]
