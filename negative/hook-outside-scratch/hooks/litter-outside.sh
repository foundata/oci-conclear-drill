#!/bin/sh
# Negative case: a hook that ignores CC_HOOK_SCRATCH and leaves a rootless
# container store below the checkout. ConClear must retire the run only
# partially and name the path this user cannot remove.
set -eu
: "${CC_LAYOUT:?ConClear layout path}"
: "${CC_SOURCE_ROOT:?ConClear source root}"
store="${CC_SOURCE_ROOT}/.drill-litter/store"
runroot="${CC_SOURCE_ROOT}/.drill-litter/runroot"
mkdir -p "${store}" "${runroot}"
skopeo copy --quiet "oci:${CC_LAYOUT}" "containers-storage:[vfs@${store}+${runroot}]localhost/conclear-drill:litter"
printf 'litter-outside: store left below the checkout\n'
