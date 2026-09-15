#!/bin/sh
# Negative case: a hook that ignores CC_HOOK_SCRATCH and writes below the
# checkout from inside a rootless container. The directory and file it leaves
# belong to a subordinate user ID, so the invoking user cannot unlink them and
# ConClear must retire the run only partially, naming the blocking path.
set -eu
: "${CC_LAYOUT:?ConClear layout path}"
: "${CC_PLATFORM:?ConClear platform}"
: "${CC_SOURCE_ROOT:?ConClear source root}"

litter="${CC_SOURCE_ROOT}/.drill-litter"
store="${litter}/store"
runroot="${litter}/runroot"
output="${litter}/output"
mkdir -p "${store}" "${runroot}" "${output}"
skopeo copy --quiet "oci:${CC_LAYOUT}" "containers-storage:[vfs@${store}+${runroot}]localhost/conclear-drill:litter"
podman --root "${store}" --runroot "${runroot}" --storage-driver vfs run --rm \
  --platform "${CC_PLATFORM}" --network none --user 0 \
  --volume "${output}:/out:Z" --entrypoint /bin/sh \
  localhost/conclear-drill:litter -c 'install -d -m 0700 -o 4242 -g 4242 /out/state && install -m 0600 -o 4242 -g 4242 /dev/null /out/state/data'
printf 'litter-outside: subordinate-owned output left below the checkout\n'
