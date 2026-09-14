#!/bin/sh
# Preparation step: derive one secret and one public file from the fixture.
set -eu
input="${1:?input directory}"
secret_dir="${2:?secret output directory}"
public_dir="${3:?public output directory}"
umask 077
head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "${secret_dir}/token"
umask 022
printf '{"generated":"%s","source":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(cat "${input}/input.json" | tr -d '\n' | cut -c1-40)" > "${public_dir}/material.json"
