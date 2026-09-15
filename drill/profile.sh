#!/usr/bin/env bash
# Render the drill release profile into a workspace and install the operator's
# credentials under the names the drill scripts expect.
#
# The credential directory must contain, created by the operator and never by
# this script:
#   auth.json           registry authentication of the drill robot account
#   cosign.key          disposable signing key
#   cosign.pub          its public key
#   cosign-passphrase   the key's passphrase
#   quay-api.token      API token with repository administration scope
#
# usage: profile.sh --workspace <dir> --credentials <dir> [--name drill]
#                   [--registry-host quay.io] [--builder-id <uri>]
set -euo pipefail
workspace=""; credentials=""; name="drill"; host="quay.io"; builder=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace) workspace="$2"; shift 2 ;;
    --credentials) credentials="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --registry-host) host="$2"; shift 2 ;;
    --builder-id) builder="$2"; shift 2 ;;
    *) printf 'usage: %s --workspace <dir> --credentials <dir> [--name drill] [--registry-host quay.io] [--builder-id <uri>]\n' "${0##*/}" >&2; exit 64 ;;
  esac
done
[ -n "${workspace}" ] && [ -n "${credentials}" ] || { printf 'workspace and credentials are required\n' >&2; exit 64; }
workspace="$(realpath -m "${workspace}")"
credentials="$(realpath "${credentials}")"
config="${workspace}/consumer/config/conclear"
: "${builder:=https://conclear-drill.invalid/builder/$(hostname -s)-drill-v1/}"

mkdir -p "${config}" "${workspace}/archives"
chmod 0700 "${config}" "${workspace}/archives"
for pair in "auth.json:drill-auth.json" "cosign.key:drill-cosign.key" "cosign.pub:drill-cosign.pub" "cosign-passphrase:drill-cosign-passphrase" "quay-api.token:drill-quay-api.token"; do
  source_name="${pair%%:*}"; target_name="${pair##*:}"
  [ -f "${credentials}/${source_name}" ] || { printf 'missing credential: %s/%s\n' "${credentials}" "${source_name}" >&2; exit 66; }
  install -m 0600 "${credentials}/${source_name}" "${config}/${target_name}"
done

template="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/profile-template.toml"
sed -e "s|@CONFIG@|${config}|g" -e "s|@WORKSPACE@|${workspace}|g" \
    -e "s|@REGISTRY_HOST@|${host}|g" -e "s|@BUILDER_ID@|${builder}|g" \
    "${template}" > "${config}/${name}.toml"
chmod 0600 "${config}/${name}.toml"
printf '%s\n' "${config}/${name}.toml"
