#!/bin/sh
# Confirms the drill's one Java artifact is present and exits 0. The jar is
# never executed: no Java runtime is installed, and none is needed for what
# this image drills, which is the scanner's inventory of it.
set -eu
jar=/opt/drill/library-1.2.3.jar
test -s "${jar}"
printf 'conclear-drill java: %s present (%s bytes)\n' "${jar}" "$(wc -c < "${jar}")"
