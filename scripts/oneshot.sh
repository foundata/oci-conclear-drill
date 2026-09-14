#!/bin/sh
# Reads the mounted fixture, writes a derived result and exits 0.
set -eu
input="${1:?input path}"
output="${2:?output path}"
jq '{name: .name, items: (.items | length), processed: true}' "${input}" > "${output}"
printf 'conclear-drill one-shot: processed %s\n' "${input}"
