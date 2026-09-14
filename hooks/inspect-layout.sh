#!/bin/sh
# Repository hook: inspect the qualified layout and record the result in the
# hook scratch directory. Uses only the documented ConClear variables and
# cleans up after itself.
set -eu
: "${CC_LAYOUT:?ConClear layout path}"
: "${CC_IMAGE_DIGEST:?ConClear image digest}"
: "${CC_PLATFORM:?ConClear platform}"
: "${CC_HOOK_SCRATCH:?ConClear hook scratch directory}"
: "${CC_TEST_INPUT_MANIFEST:?ConClear test-input manifest}"

report="${CC_HOOK_SCRATCH}/inspect-layout.json"
skopeo inspect --raw "oci:${CC_LAYOUT}" > "${report}"
jq -e '.schemaVersion == 2' "${report}" > /dev/null
jq -e --arg digest "${CC_IMAGE_DIGEST}" '.digest == $digest' "${CC_TEST_INPUT_MANIFEST}" > /dev/null
printf 'inspect-layout: %s %s ok\n' "${CC_PLATFORM}" "${CC_IMAGE_DIGEST}"
rm -f "${report}"
