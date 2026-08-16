# LuCI support for Hop

[简体中文配置指南](docs/configuration.zh-CN.md)

[![LuCI package](https://github.com/oslo254804746/luci-app-hop/actions/workflows/openwrt-sdk.yml/badge.svg?branch=dev)](https://github.com/oslo254804746/luci-app-hop/actions/workflows/openwrt-sdk.yml?query=branch%3Adev)

This repository contains the lightweight OpenWrt control package for Hop. It
does **not** compile or embed the Rust daemon. `luci-app-hop` is an `all`
architecture package containing only:

- the full static Hop management panel and LuCI service page;
- a LuCI-authenticated, path-restricted proxy to the loopback Control API;
- a procd init script and UCI service settings;
- a small downloader that installs a verified, architecture-specific core;
- the strict Hop startup configuration.

When Hop is enabled and no usable core exists, the init script downloads the
matching prebuilt binary from
[`oslo254804746/hop-rs` Releases](https://github.com/oslo254804746/hop-rs/releases),
checks it against the release `SHA256SUMS`, runs `hop-server --version`, and
atomically installs it at `/etc/hop/core/hop-server`. A failed download,
checksum, archive, or self-check leaves the current core untouched.

## Release asset contract

Every Hop core release used by OpenWrt must publish these files:

```text
hop-server-linux-x86_64-musl.tar.gz
hop-server-linux-aarch64-musl.tar.gz
SHA256SUMS
```

Each archive contains one executable named `hop-server`. The two supported
router machine families are `x86_64`/`amd64` and `aarch64`/`arm64`.

The default `core_version` is pinned to `v0.2.3` to match the bundled panel. It
can be changed to `latest` or another version in LuCI or UCI. `release_base`
defaults to the official Hop GitHub Releases URL; the LuCI combobox also offers
`gh-proxy.net` and accepts a custom HTTPS GitHub-compatible mirror.

## Install and start

Install the generated `.ipk` or `.apk`, then enable Hop in LuCI under
**Services → Hop**, or use UCI:

```sh
uci set hop.main.enabled='1'
uci commit hop
/etc/init.d/hop enable
/etc/init.d/hop start
```

The first enabled start downloads the missing core. It can also be managed
explicitly:

```sh
/usr/share/hop/hop-core status
/usr/share/hop/hop-core install
/usr/share/hop/hop-core update
```

Set `auto_download` to `0` if startup must fail rather than download a missing
core.

The management panel is available at **Services → Hop → Management Panel**.
Its document is served only after LuCI authentication. The browser supplies the
Hop management Token in memory, and the narrow controller proxy forwards only
the documented API methods and paths to `127.0.0.1:8083`.

## Configuration boundary

UCI owns only service and core-delivery concerns:

- enablement and startup configuration path;
- automatic core download, release version, and release base URL;
- stdout/stderr forwarding to the OpenWrt log.

Assets, credentials, Access Keys, and key-to-asset allowlists remain in the Hop
Catalog. They can be managed from the bundled panel, the local CLI, or the
strict startup configuration. The shipped `/etc/hop/config.toml` enables the
Control API only on loopback; no API port is exposed to LAN clients.

The daemon runs as the unprivileged `hop` user. The downloader alone runs as
root because it owns `/etc/hop/core`; it accepts only the named release asset,
verifies SHA-256 before extraction, and never reads or edits the Catalog.

The [Chinese configuration guide](docs/configuration.zh-CN.md) documents the
panel, LuCI/UCI fields, download mirrors, Token rotation, startup configuration,
firewall scope, and backup.

## Cloud validation

Pushes to `dev` run structural tests and two official SDK packaging checks:

- OpenWrt 24.10.4, which emits an IPK;
- OpenWrt 25.12.5, which emits an APK.

Only x86/64 SDKs are needed because the package itself is architecture
independent. The downloaded Hop core is selected on the router at runtime.
The workflow verifies every SDK checksum. Runtime dependencies are recorded in
the package metadata without fetching or compiling LuCI feeds, and the workflow
does not check out or compile `hop-rs`. A 256 KiB compressed package-size gate
prevents an architecture-specific Hop core from being embedded accidentally;
the bundled panel remains a small static asset set and requires no Node.js on
the router.

Run the fast repository tests locally with:

```sh
./tests/validate-package.sh
```
