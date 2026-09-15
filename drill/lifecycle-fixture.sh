#!/usr/bin/env bash
# Materialize the single-image fixture that ConClear's repeat-release network
# test (tests/network/test_release_lifecycle.py) releases twice: the drill
# clone with lifecycle/conclear.toml as its configuration, a changelog heading
# and a tag for the scenario version, and the disposable repository.
# usage: lifecycle-fixture.sh --workspace <dir> --version <x.y.z> [--registry <namespace>]
set -euo pipefail
workspace=""; version=""; registry="quay.io/conclear-drill"; destination=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace) workspace="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    --registry) registry="$2"; shift 2 ;;
    --repository) destination="$2"; shift 2 ;;
    *) printf 'usage: %s --workspace <dir> --version <x.y.z> [--registry <namespace>] [--repository <reference>]\n' "${0##*/}" >&2; exit 64 ;;
  esac
done
[ -n "${workspace}" ] && [ -n "${version}" ] || { printf 'workspace and version are required\n' >&2; exit 64; }
repository="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$(realpath -m "${workspace}")/lifecycle-fixture"
rm -rf "${target}"
git clone -q "${repository}" "${target}"
git -C "${target}" remote set-url origin https://github.com/foundata/oci-conclear-drill.git
(
  cd "${target}"
  cp lifecycle/conclear.toml conclear.toml
  if [ -n "${destination}" ]; then
    # The lifecycle test needs a repository its resource manifest owns, which
    # need not follow the drill naming.
    sed -i "s|^repository = .*|repository = \"${destination}\"|" conclear.toml
  else
    sed -i "s|quay.io/conclear-drill/|${registry}/|g" conclear.toml
  fi
  python3 - "${version}" <<'PY'
import sys
from datetime import date
from pathlib import Path
version = sys.argv[1]
path = Path("CHANGELOG.md"); text = path.read_text(encoding="utf-8")
marker = "## [Unreleased]\n\n- Nothing worth mentioning right now.\n"
assert marker in text
path.write_text(text.replace(marker, marker + f"\n\n## [{version}] - {date.today().isoformat()}\n\n### Added\n\n- Lifecycle fixture {version}.\n", 1), encoding="utf-8")
PY
  git -c user.name="ConClear drill" -c user.email="drill@invalid" commit -q -am "drill: lifecycle fixture ${version} into ${registry}"
  git tag "v${version}"
)
printf '%s\n' "${target}"
printf 'revision %s\n' "$(git -C "${target}" rev-parse HEAD)" >&2
