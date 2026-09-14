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
  (cd "${target}" && find "${case_dir}" -mindepth 1 -maxdepth 1 ! -name expect -exec cp -r {} . \; \
    && git -c user.name="ConClear drill" -c user.email="drill@invalid" add -A \
    && git -c user.name="ConClear drill" -c user.email="drill@invalid" commit -q -m "drill: negative case ${name}" \
    && git tag -f "v${version}" >/dev/null)
  revision="$(git -C "${target}" rev-parse HEAD)"
  image="$(cat "${case_dir}/image" 2>/dev/null || echo service)"
  (cd "${target}" && drill_run "negative-${name}" "${DRILL_CLI}" qualify --revision "${revision}" --image "${image}" --platform linux/amd64 --version "${version}" --format json) && outcome=accepted || outcome=rejected
  found="$(jq -r '[.findings[]?.checkId] | unique | join(",")' "${DRILL_WORKSPACE}/artifacts/negative-${name}.json" 2>/dev/null || true)"
  message="$(jq -r '.message // ""' "${DRILL_WORKSPACE}/artifacts/negative-${name}.json" 2>/dev/null || true)"
  if [ "${outcome}" = rejected ] && { [ "${found}" = "${expect}" ] || printf '%s' "${message}" | grep -q "${expect}"; }; then
    drill_log "negative ${name}: rejected by ${expect} as expected"
  else
    status=failed; drill_log "negative ${name}: UNEXPECTED outcome=${outcome} checks=${found} message=${message:0:160} (expected ${expect})"
  fi
done
drill_record negative "${status}" "$(jq -cn '{}')"
[ "${status}" = passed ]
