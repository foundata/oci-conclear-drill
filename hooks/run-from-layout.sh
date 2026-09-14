#!/bin/sh
# Repository hook: copy the qualified layout into a private Podman store
# below the hook scratch directory and run one command from it. The store is
# left behind on purpose: its files belong to subordinate user IDs, so this
# drills ConClear's removal of hook scratch content through the container user
# namespace.
set -eu
: "${CC_LAYOUT:?ConClear layout path}"
: "${CC_PLATFORM:?ConClear platform}"
: "${CC_HOOK_SCRATCH:?ConClear hook scratch directory}"

store="${CC_HOOK_SCRATCH}/store"
runroot="${CC_HOOK_SCRATCH}/runroot"
mkdir -p "${store}" "${runroot}"
skopeo copy --quiet "oci:${CC_LAYOUT}" "containers-storage:[vfs@${store}+${runroot}]localhost/conclear-drill:hook"
podman --root "${store}" --runroot "${runroot}" --storage-driver vfs run --rm \
  --platform "${CC_PLATFORM}" --network none --entrypoint /bin/sh \
  localhost/conclear-drill:hook -c 'cat /etc/os-release | head -1'
printf 'run-from-layout: %s ok; store left for ConClear to remove\n' "${CC_PLATFORM}"
