#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

test -f "$repo_dir/Makefile"
test -x "$repo_dir/files/hop.init"
test -f "$repo_dir/files/hop.uci"
test -f "$repo_dir/files/hop.toml"

shellcheck -s sh "$repo_dir/files/hop.init"

grep -Fq '$(RUST_ARCH_DEPENDS)' "$repo_dir/Makefile"
grep -Fq 'Build/Compile/Cargo,crates/hop-server' "$repo_dir/Makefile"
grep -Fq 'HOP_SOURCE_VERSION' "$repo_dir/Makefile"
grep -Fq 'HOP_MIRROR_HASH' "$repo_dir/Makefile"
grep -Fq 'api.enabled' "$repo_dir/README.md"

if grep -Eiq 'node(js)?|docker|luci-base' "$repo_dir/Makefile"; then
	echo "hop core package must not depend on LuCI, Node.js, or Docker" >&2
	exit 1
fi

grep -Fq "option enabled '0'" "$repo_dir/files/hop.uci"
grep -Fq 'enabled = false' "$repo_dir/files/hop.toml"

echo "OpenWrt hop package structure is valid"
