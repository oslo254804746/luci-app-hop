#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
makefile=$repo_dir/Makefile
manager=$repo_dir/root/usr/share/hop/hop-core
init_script=$repo_dir/root/etc/init.d/hop
uci_config=$repo_dir/root/etc/config/hop
startup_config=$repo_dir/root/etc/hop/config.toml
luci_view=$repo_dir/htdocs/luci-static/resources/view/hop/settings.js
menu_json=$repo_dir/root/usr/share/luci/menu.d/luci-app-hop.json
acl_json=$repo_dir/root/usr/share/rpcd/acl.d/luci-app-hop.json

required_files=(
	"$makefile"
	"$manager"
	"$init_script"
	"$uci_config"
	"$startup_config"
	"$luci_view"
	"$menu_json"
	"$acl_json"
)
for path in "${required_files[@]}"; do
	test -f "$path"
done
test -x "$manager"
test -x "$init_script"
test -x "$repo_dir/tests/test-core-manager.sh"

shellcheck -s sh "$manager" "$init_script"
shellcheck "$repo_dir"/tests/*.sh
bash -n "$repo_dir"/tests/*.sh

if command -v node >/dev/null 2>&1; then
	node --check "$luci_view"
fi
python3 -m json.tool "$menu_json" >/dev/null
python3 -m json.tool "$acl_json" >/dev/null

grep -Fq 'PKG_NAME:=luci-app-hop' "$makefile"
grep -Fq 'PKGARCH:=all' "$makefile"
grep -Fq 'EXTRA_DEPENDS:=luci-base (>=0), curl (>=0), ca-bundle (>=0)' "$makefile"
grep -Fq 'define Build/Compile' "$makefile"
grep -Fq "\$(INSTALL_BIN) ./root/usr/share/hop/hop-core" "$makefile"
grep -Fq "\$(INSTALL_DATA) ./htdocs/luci-static/resources/view/hop/settings.js" "$makefile"

if grep -Eiq 'rust-package\.mk|Build/Compile/Cargo|HOP_SOURCE_|PKG_SOURCE|USE_SOURCE_DIR' "$makefile"; then
	echo 'LuCI package must not fetch or compile the Hop Rust core' >&2
	exit 1
fi

if grep -Eq '^[[:space:]]*DEPENDS[+:]?=' "$makefile"; then
	echo 'LuCI runtime dependencies must not trigger dependency compilation' >&2
	exit 1
fi

if find "$repo_dir" -path "$repo_dir/.git" -prune -o -type f \
	\( -name hop-server -o -name '*.ipk' -o -name '*.apk' -o -name '*.tar.gz' \) \
	-print -quit | grep -q .; then
	echo 'LuCI package source must not embed core or package binaries' >&2
	exit 1
fi

grep -Fq "hop-server-linux-\${arch}-musl.tar.gz" "$manager"
grep -Fq 'SHA256SUMS' "$manager"
grep -Fq 'sha256sum' "$manager"
grep -Fq 'x86_64 | amd64' "$manager"
grep -Fq 'aarch64 | arm64' "$manager"
grep -Fq "option enabled '0'" "$uci_config"
grep -Fq "option auto_download '1'" "$uci_config"
grep -Fq 'enabled = false' "$startup_config"

"$repo_dir/tests/test-core-manager.sh"

echo 'OpenWrt LuCI package structure is valid'
