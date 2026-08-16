#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
frontend_dir=${1:-"$repo_dir/../hop-rs-frontend"}
asset_dir=$repo_dir/htdocs/hop/assets
panel_dir=$repo_dir/root/usr/share/hop/panel

test -f "$frontend_dir/package.json"
grep -Fq '"name": "hop-rs-frontend"' "$frontend_dir/package.json"

npm --prefix "$frontend_dir" run build:openwrt

test -f "$frontend_dir/dist/index.html"
test -d "$frontend_dir/dist/assets"

mkdir -p "$asset_dir" "$panel_dir"
find "$asset_dir" -mindepth 1 -maxdepth 1 -type f -delete
cp -p "$frontend_dir"/dist/assets/* "$asset_dir"/
cp -p "$frontend_dir/dist/index.html" "$panel_dir/index.html"

printf 'Synced Hop OpenWrt panel from %s\n' "$frontend_dir"
