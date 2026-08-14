#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manager=$repo_dir/root/usr/share/hop/hop-core
run_dir=$(mktemp -d "${TMPDIR:-/tmp}/hop-core-manager.XXXXXX")
trap 'rm -rf "$run_dir"' EXIT

release_dir=$run_dir/releases/latest/download
build_dir=$run_dir/build
core_dir=$run_dir/core
mkdir -p "$release_dir" "$build_dir"

printf '%s\n' '#!/bin/sh' "printf 'hop-server 0.2.0\\n'" >"$build_dir/hop-server"
chmod 0755 "$build_dir/hop-server"
tar -czf "$release_dir/hop-server-linux-x86_64-musl.tar.gz" \
	-C "$build_dir" hop-server
tar -czf "$release_dir/hop-server-linux-aarch64-musl.tar.gz" \
	-C "$build_dir" hop-server
(
	cd "$release_dir"
	sha256sum \
		hop-server-linux-aarch64-musl.tar.gz \
		hop-server-linux-x86_64-musl.tar.gz >SHA256SUMS
)

manager_env=(
	HOP_ARCH=x86_64
	HOP_CORE_DIR="$core_dir"
	HOP_LOCK_DIR="$run_dir/hop-core.lock"
	HOP_CORE_VERSION=latest
	HOP_RELEASE_BASE="file://$run_dir/releases"
)

env "${manager_env[@]}" "$manager" install
test -x "$core_dir/hop-server"
test "$("$core_dir/hop-server" --version)" = 'hop-server 0.2.0'
env "${manager_env[@]}" "$manager" status | grep -Fq $'installed\tyes'
test "$(env HOP_ARCH=aarch64 "$manager" arch)" = aarch64

aarch64_core_dir=$run_dir/core-aarch64
env \
	HOP_ARCH=aarch64 \
	HOP_CORE_DIR="$aarch64_core_dir" \
	HOP_LOCK_DIR="$run_dir/hop-core-aarch64.lock" \
	HOP_CORE_VERSION=latest \
	HOP_RELEASE_BASE="file://$run_dir/releases" \
	"$manager" install
test -x "$aarch64_core_dir/hop-server"
test "$("$aarch64_core_dir/hop-server" --version)" = 'hop-server 0.2.0'

before=$(sha256sum "$core_dir/hop-server" | awk '{ print $1 }')
printf 'tampered' >>"$release_dir/hop-server-linux-x86_64-musl.tar.gz"
if env "${manager_env[@]}" "$manager" update >/dev/null 2>&1; then
	echo 'tampered core archive unexpectedly passed verification' >&2
	exit 1
fi
after=$(sha256sum "$core_dir/hop-server" | awk '{ print $1 }')
test "$after" = "$before"

if env HOP_ARCH=mips "$manager" arch >/dev/null 2>&1; then
	echo 'unsupported architecture unexpectedly accepted' >&2
	exit 1
fi

echo 'Hop core manager tests passed'
