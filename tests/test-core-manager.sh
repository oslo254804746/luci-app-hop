#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manager=$repo_dir/root/usr/share/hop/hop-core
run_dir=$(mktemp -d "${TMPDIR:-/tmp}/hop-core-manager.XXXXXX")
trap 'rm -rf "$run_dir"' EXIT

release_root=$run_dir/releases
latest_dir=$release_root/latest/download
fixed_dir=$release_root/download/v0.2.8
mismatch_dir=$release_root/download/v0.2.9
invalid_root=$run_dir/invalid-releases
invalid_dir=$invalid_root/latest/download
build_dir=$run_dir/build
core_dir=$run_dir/core
mkdir -p "$latest_dir" "$fixed_dir" "$mismatch_dir" "$invalid_dir" "$build_dir"

make_release() {
	local version destination binary_dir asset

	version=$1
	destination=$2
	binary_dir=$build_dir/$version
	mkdir -p "$binary_dir"
	printf '%s\n' '#!/bin/sh' "printf 'hop-server $version\\n'" >"$binary_dir/hop-server"
	chmod 0755 "$binary_dir/hop-server"
	for asset in x86_64 aarch64; do
		tar -czf "$destination/hop-server-linux-${asset}-musl.tar.gz" \
			-C "$binary_dir" hop-server
	done
	(
		cd "$destination"
		sha256sum \
			hop-server-linux-aarch64-musl.tar.gz \
			hop-server-linux-x86_64-musl.tar.gz >SHA256SUMS
	)
}

make_release 0.2.0 "$latest_dir"
make_release 0.2.8 "$fixed_dir"
make_release 0.2.7 "$mismatch_dir"
make_release nightly "$invalid_dir"

manager_env=(
	HOP_ARCH=x86_64
	HOP_CORE_DIR="$core_dir"
	HOP_LOCK_DIR="$run_dir/hop-core.lock"
	HOP_CORE_VERSION=latest
	HOP_RELEASE_BASE="file://$release_root"
)

env "${manager_env[@]}" "$manager" install
test -x "$core_dir/hop-server"
test "$("$core_dir/hop-server" --version)" = 'hop-server 0.2.0'
test "$(cat "$core_dir/release")" = v0.2.0
env "${manager_env[@]}" "$manager" status | grep -Fq $'installed\tyes'
test "$(env HOP_ARCH=aarch64 "$manager" arch)" = aarch64

aarch64_core_dir=$run_dir/core-aarch64
env \
	HOP_ARCH=aarch64 \
	HOP_CORE_DIR="$aarch64_core_dir" \
	HOP_LOCK_DIR="$run_dir/hop-core-aarch64.lock" \
	HOP_CORE_VERSION=latest \
	HOP_RELEASE_BASE="file://$release_root" \
	"$manager" install
test -x "$aarch64_core_dir/hop-server"
test "$("$aarch64_core_dir/hop-server" --version)" = 'hop-server 0.2.0'
test "$(cat "$aarch64_core_dir/release")" = v0.2.0

fixed_env=(
	HOP_ARCH=x86_64
	HOP_CORE_DIR="$core_dir"
	HOP_LOCK_DIR="$run_dir/hop-core-fixed.lock"
	HOP_CORE_VERSION=v0.2.8
	HOP_RELEASE_BASE="file://$release_root"
)
env "${fixed_env[@]}" "$manager" install
test "$("$core_dir/hop-server" --version)" = 'hop-server 0.2.8'
test "$(cat "$core_dir/release")" = v0.2.8
env "${fixed_env[@]}" "$manager" ensure

before=$(sha256sum "$core_dir/hop-server" | awk '{ print $1 }')
before_release=$(cat "$core_dir/release")
printf 'tampered' >>"$fixed_dir/hop-server-linux-x86_64-musl.tar.gz"
if env "${fixed_env[@]}" "$manager" update >/dev/null 2>&1; then
	echo 'tampered core archive unexpectedly passed verification' >&2
	exit 1
fi
after=$(sha256sum "$core_dir/hop-server" | awk '{ print $1 }')
test "$after" = "$before"
test "$(cat "$core_dir/release")" = "$before_release"

mismatch_env=(
	HOP_ARCH=x86_64
	HOP_CORE_DIR="$core_dir"
	HOP_LOCK_DIR="$run_dir/hop-core-mismatch.lock"
	HOP_CORE_VERSION=v0.2.9
	HOP_RELEASE_BASE="file://$release_root"
)
if env "${mismatch_env[@]}" "$manager" update >/dev/null 2>&1; then
	echo 'release with a mismatched core version unexpectedly passed' >&2
	exit 1
fi
test "$(sha256sum "$core_dir/hop-server" | awk '{ print $1 }')" = "$before"
test "$(cat "$core_dir/release")" = "$before_release"

invalid_env=(
	HOP_ARCH=x86_64
	HOP_CORE_DIR="$run_dir/core-invalid"
	HOP_LOCK_DIR="$run_dir/hop-core-invalid.lock"
	HOP_CORE_VERSION=latest
	HOP_RELEASE_BASE="file://$invalid_root"
)
if env "${invalid_env[@]}" "$manager" install >/dev/null 2>&1; then
	echo 'invalid latest semantic version unexpectedly passed' >&2
	exit 1
fi
test ! -e "$run_dir/core-invalid/hop-server"

if env HOP_ARCH=mips "$manager" arch >/dev/null 2>&1; then
	echo 'unsupported architecture unexpectedly accepted' >&2
	exit 1
fi

echo 'Hop core manager tests passed'
