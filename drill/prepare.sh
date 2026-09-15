#!/usr/bin/env bash
# Prepare one drill workspace: install the candidate wheel, create the
# throwaway drill clone with its drill-only commit, and start the evidence
# index. Needs no registry.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
drill_parse_arguments "$@"
[ -n "${DRILL_WHEEL}" ] || drill_usage
[ -f "${DRILL_WHEEL}" ] || { printf 'wheel not found: %s\n' "${DRILL_WHEEL}" >&2; exit 66; }

mkdir -p "${DRILL_WORKSPACE}"/{artifacts,logs,archives,consumer/config/conclear,consumer/state,consumer/cache}
if [ ! -f "${DRILL_MANIFEST}" ]; then
  python3 - "${DRILL_MANIFEST}" "${DRILL_WHEEL}" "${DRILL_REGISTRY}" <<'PY'
import json, sys, hashlib
from datetime import datetime, timezone
path, wheel, registry = sys.argv[1:]
digest = hashlib.sha256(open(wheel, "rb").read()).hexdigest()
json.dump({
    "schemaVersion": 1,
    "purpose": "ConClear release drill; see DEVELOPMENT.md of oci-conclear-drill",
    "created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "candidate": {"wheel": wheel, "wheel_sha256": "sha256:" + digest},
    "registry": {"namespace": registry, "repositories": [f"{registry}/drill-service", f"{registry}/drill-systemd", f"{registry}/drill-oneshot"]},
    "results": {},
    "observations": [],
}, open(path, "w"), indent=2, sort_keys=True)
PY
fi

# 1. Candidate wheel into a clean environment.
rm -rf "${DRILL_WORKSPACE}/wheel-env"
uv venv -q "${DRILL_WORKSPACE}/wheel-env"
uv pip install -q --python "${DRILL_WORKSPACE}/wheel-env/bin/python" "${DRILL_WHEEL}"
revision="$("${DRILL_CLI}" version --format json | jq -r .sourceRevision)"
drill_log "candidate ${revision}"
python3 - "${DRILL_MANIFEST}" "${revision}" <<'PY'
import json, sys
# The index may have been created by the operator, for instance when it also
# serves as the resource manifest of ConClear's network tests, so the drill
# adds its own keys instead of assuming it owns the file.
path, revision = sys.argv[1:]
manifest = json.load(open(path))
manifest.setdefault("candidate", {})["revision"] = revision
json.dump(manifest, open(path, "w"), indent=2, sort_keys=True)
PY

# 2. Throwaway clone with one drill-only commit: disposable registry, changelog
#    heading and tag for the drill version. Only the version counter file in
#    the workspace persists between runs.
# The counter lives beside the workspaces, not inside one, so repeated drills
# against the same registry never reuse a version another drill promoted.
counter="$(dirname "${DRILL_WORKSPACE}")/.drill-version"
if [ -z "${DRILL_VERSION}" ]; then
  next=$(( $(cat "${counter}" 2>/dev/null || echo 0) + 1 )); printf '%s\n' "${next}" > "${counter}"
  DRILL_VERSION="0.1.${next}"
fi
rm -rf "${DRILL_WORKSPACE}/project"
git clone -q "${DRILL_REPOSITORY}" "${DRILL_WORKSPACE}/project"
git -C "${DRILL_WORKSPACE}/project" remote set-url origin https://github.com/foundata/oci-conclear-drill.git
(
  cd "${DRILL_WORKSPACE}/project"
  sed -i "s|quay.io/conclear-drill/|${DRILL_REGISTRY}/|g" conclear.toml
  python3 - "${DRILL_VERSION}" <<'PY'
import sys
from pathlib import Path
version = sys.argv[1]
path = Path("CHANGELOG.md"); text = path.read_text(encoding="utf-8")
marker = "## [Unreleased]\n\n- Nothing worth mentioning right now.\n"
assert marker in text
from datetime import date
entry = marker + f"\n\n## [{version}] - {date.today().isoformat()}\n\n### Added\n\n- Drill release {version}.\n"
path.write_text(text.replace(marker, entry, 1), encoding="utf-8")
PY
  git -c user.name="ConClear drill" -c user.email="drill@invalid" commit -q -am "drill: release ${DRILL_VERSION} into ${DRILL_REGISTRY}"
  git tag "v${DRILL_VERSION}"
)
printf '%s\n' "${DRILL_VERSION}" > "${DRILL_WORKSPACE}/drill-version.current"
drill_log "drill clone $(drill_source_revision) version ${DRILL_VERSION}"
drill_record prepare passed "$(jq -cn --arg r "${revision}" --arg v "${DRILL_VERSION}" --arg c "$(drill_source_revision)" '{candidate: $r, drill_version: $v, clone_head: $c}')"
printf 'prepared %s for candidate %s; profile %s must exist in %s\n' "${DRILL_WORKSPACE}" "${revision}" "${DRILL_PROFILE}" "${XDG_CONFIG_HOME}/conclear"
