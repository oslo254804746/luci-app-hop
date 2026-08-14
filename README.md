# Hop for OpenWrt

[![OpenWrt SDK](https://github.com/oslo254804746/luci-app-hop/actions/workflows/openwrt-sdk.yml/badge.svg?branch=dev)](https://github.com/oslo254804746/luci-app-hop/actions/workflows/openwrt-sdk.yml?query=branch%3Adev)

This repository is the OpenWrt packaging boundary for the Hop v0.2 core
daemon. The `hop` package contains only the Rust binary, a procd service, a
strict startup configuration, and a small UCI service shell.

UCI owns only service concerns:

- `enabled`
- the Hop startup config path
- stdout/stderr logging

Assets, credentials, Access Keys, and key-to-asset allowlists are never copied
into UCI. They are written to the Hop SQLite Catalog through `hop apply`, the
local CLI, or the optional Control API. `api.enabled` is false in the shipped
configuration, so installing and enabling the package does not create an HTTP
listener.

## Reproducible source pin

The package definition deliberately requires release automation or an SDK
invocation to provide all three immutable source values:

```sh
HOP_SOURCE_DATE=YYYY-MM-DD
HOP_SOURCE_VERSION=<full-git-commit>
HOP_MIRROR_HASH=<sha256-from-openwrt-download-fixture>
```

No branch, moving tag, or `PKG_MIRROR_HASH=skip` fallback is present. A release
is not considered OpenWrt-buildable until these values are recorded in its
release metadata.

## SDK validation targets

The first required SDK builds are:

- x86/64 (`x86_64`)
- armsr/armv8 (`aarch64`)

OpenWrt 25.12 emits `.apk` packages. Older release branches may emit `.ipk`,
but the package definition itself uses the release branch's standard packaging
backend.

Install this directory as a custom feed package and build with the official
OpenWrt SDK and packages feed (the package uses the current official
`lang/rust/rust-package.mk` interface):

```sh
make package/hop/clean
make package/hop/compile V=sc \
  HOP_SOURCE_DATE=... \
  HOP_SOURCE_VERSION=... \
  HOP_MIRROR_HASH=...
```

Run the repository-local structural checks with:

```sh
./tests/validate-package.sh
```

## GitHub Actions validation

Pushes to `dev` run package-boundary checks and parallel official OpenWrt
25.12.5 SDK builds for x86/64 and armsr/armv8. The workflow verifies the SDK
SHA-256 before extraction, pins the OpenWrt packages feed commit, uploads the
resulting APK plus checksums and size metadata, and never publishes a release.

Push builds use `hop-rs@main`. A manual workflow dispatch accepts any branch,
tag, or full commit in the `hop_ref` input, which is the required path for
testing a not-yet-merged Hop core branch. CI uses `USE_SOURCE_DIR`, so the
all-zero mirror hash in that validation command is ignored; release builds must
still supply the real immutable source commit, date, and mirror hash described
above.

## LuCI boundary

An optional `luci-app-hop` may later manage the service shell and call the
versioned `/api/v1` Control API. It must not edit Hop's SQLite database or
duplicate Catalog resources in UCI. No LuCI implementation is included in the
core package and it is not a delivery dependency.
