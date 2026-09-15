#!/bin/sh
# Negative case: a hook that ignores CC_HOOK_SCRATCH and runs a container from
# a rootless store below the checkout. The container writes files owned by
# subordinate user IDs, so ConClear can retire the run only partially and must
# name the path this user cannot remove.
set -eu
: "${CC_LAYOUT:?ConClear layout path}"
: "${CC_PLATFORM:?ConClear platform}"
: "${CC_SOURCE_ROOT:?ConClear source root}"

store="${CC_SOURCE_ROOT}/.drill-litter/store"
runroot="${CC_SOURCE_ROOT}/.drill-litter/runroot"
mkdir -p "${store}" "${runroot}"
skopeo copy --quiet "oci:${CC_LAYOUT}" "containers-storage:[vfs@${store}+${runroot}]localhost/conclear-drill:litter"
podman --root "${store}" --runroot "${runroot}" --storage-driver vfs run --rm \
  --platform "${CC_PLATFORM}" --network none --entrypoint /bin/sh \
  localhost/conclear-drill:litter -c 'id > /tmp/litter; cat /etc/os-release | head -1'
printf 'litter-outside: rootless store left below the checkout\n'
