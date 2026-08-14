# LuCI support for Hop

[![LuCI package](https://github.com/oslo254804746/luci-app-hop/actions/workflows/openwrt-sdk.yml/badge.svg?branch=dev)](https://github.com/oslo254804746/luci-app-hop/actions/workflows/openwrt-sdk.yml?query=branch%3Adev)

This repository contains the lightweight OpenWrt control package for Hop. It
does **not** compile or embed the Rust daemon. `luci-app-hop` is an `all`
architecture package containing only:

- the LuCI service page;
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

The default `core_version` is `latest`. It can be pinned to `v0.2.0` (or
`0.2.0`) in LuCI or UCI. `release_base` defaults to the official Hop GitHub
Releases URL.

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

## Configuration boundary

UCI owns only service and core-delivery concerns:

- enablement and startup configuration path;
- automatic core download, release version, and release base URL;
- stdout/stderr forwarding to the OpenWrt log.

Assets, credentials, Access Keys, and key-to-asset allowlists remain in the Hop
Catalog. They are managed through strict manifests, the local CLI, or the
optional local Control API. The shipped `/etc/hop/config.toml` keeps
`api.enabled = false`, so installation does not expose an HTTP listener.

The daemon runs as the unprivileged `hop` user. The downloader alone runs as
root because it owns `/etc/hop/core`; it accepts only the named release asset,
verifies SHA-256 before extraction, and never reads or edits the Catalog.

## Cloud validation

Pushes to `dev` run structural tests and two official SDK packaging checks:

- OpenWrt 24.10.4, which emits an IPK;
- OpenWrt 25.12.5, which emits an APK.

Only x86/64 SDKs are needed because the package itself is architecture
independent. The downloaded Hop core is selected on the router at runtime.
The workflow verifies every SDK checksum and pins both the OpenWrt packages and
LuCI feed commits. It does not check out or compile `hop-rs`.

Run the fast repository tests locally with:

```sh
./tests/validate-package.sh
```
