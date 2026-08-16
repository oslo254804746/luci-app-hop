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
controller=$repo_dir/ucode/controller/hop.uc
panel_index=$repo_dir/root/usr/share/hop/panel/index.html
panel_assets=$repo_dir/htdocs/hop/assets
sync_script=$repo_dir/scripts/sync-frontend.sh

required_files=(
	"$makefile"
	"$manager"
	"$init_script"
	"$uci_config"
	"$startup_config"
	"$luci_view"
	"$menu_json"
	"$acl_json"
	"$controller"
	"$panel_index"
	"$sync_script"
)
for path in "${required_files[@]}"; do
	test -f "$path"
done
test -x "$manager"
test -x "$init_script"
test -x "$repo_dir/tests/test-core-manager.sh"
test -x "$sync_script"
test -d "$panel_assets"
test -n "$(find "$panel_assets" -maxdepth 1 -type f -print -quit)"

shellcheck -s sh "$manager" "$init_script"
shellcheck "$repo_dir"/tests/*.sh "$repo_dir"/scripts/*.sh
bash -n "$repo_dir"/tests/*.sh "$repo_dir"/scripts/*.sh

if command -v node >/dev/null 2>&1; then
	node --check "$luci_view"
fi
if command -v ucode >/dev/null 2>&1; then
	ucode_output=$(mktemp)
	trap 'rm -f "$ucode_output"' EXIT
	ucode -c -o "$ucode_output" "$controller"
fi
python3 -m json.tool "$menu_json" >/dev/null
python3 -m json.tool "$acl_json" >/dev/null

grep -Fq 'PKG_NAME:=luci-app-hop' "$makefile"
grep -Fq 'PKGARCH:=all' "$makefile"
grep -Fq 'ucode-mod-socket (>=0)' "$makefile"
grep -Fq 'curl (>=0)' "$makefile"
grep -Fq 'define Build/Compile' "$makefile"
grep -Fq "\$(INSTALL_BIN) ./root/usr/share/hop/hop-core" "$makefile"
grep -Fq "\$(INSTALL_DATA) ./htdocs/luci-static/resources/view/hop/settings.js" "$makefile"
grep -Fq "\$(INSTALL_DATA) ./ucode/controller/hop.uc" "$makefile"
grep -Fq "\$(CP) ./htdocs/hop/assets/." "$makefile"
grep -Fq 'package_size" -gt 262144' "$repo_dir/.github/workflows/openwrt-sdk.yml"

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
grep -Fq "option core_version 'v0.2.4'" "$uci_config"
grep -Fq 'listen = "0.0.0.0:2222"' "$startup_config"
grep -Fq 'data_dir = "/var/lib/hop"' "$startup_config"
grep -Fq 'enabled = true' "$startup_config"
grep -Fq 'listen = "127.0.0.1:8083"' "$startup_config"
grep -Fq 'token = "change-me"' "$startup_config"
if grep -Eq '^\[(server|database|security|inventory)\]|token_file' "$startup_config"; then
	echo 'OpenWrt startup config still contains a pre-v0.2.1 field' >&2
	exit 1
fi
grep -Fq "\"\$CORE_MANAGER\" ensure" "$init_script"
grep -Fq "\"\$CORE\" --version" "$init_script"
grep -Fq 'gh-proxy.net/' "$luci_view"
grep -Fq "o.default = 'v0.2.4'" "$luci_view"
grep -Fq 'Third-party mirrors can replace both the archive and its checksum' "$luci_view"
grep -Fq '"function": "action_panel"' "$menu_json"
grep -Fq '"function": "action_api"' "$menu_json"
grep -Fq '/hop/assets/' "$panel_index"
grep -Fq 'name="hop-control-api-base"' "$panel_index"
grep -Fq "const API_ROUTE = '/admin/services/hop/api/v1'" "$controller"
grep -Fq "socket.addrinfo('127.0.0.1', 8083" "$controller"
grep -Fq "http.getenv('HTTP_AUTHORIZATION')" "$controller"
grep -Fq "path == '/known-hosts'" "$controller"
grep -Fq "method == 'POST' || method == 'PUT' || method == 'DELETE'" "$controller"

while IFS= read -r asset; do
	test -f "$repo_dir/htdocs${asset}"
done < <(grep -Eo '/hop/assets/[^"< ]+' "$panel_index" | sort -u)

panel_size=$(find "$panel_assets" -maxdepth 1 -type f -printf '%s\n' | awk '{ total += $1 } END { print total + 0 }')
if [ "$panel_size" -gt 614400 ]; then
	echo "embedded panel exceeds the 600 KiB uncompressed budget: $panel_size" >&2
	exit 1
fi

"$repo_dir/tests/test-core-manager.sh"

echo 'OpenWrt LuCI package structure is valid'
