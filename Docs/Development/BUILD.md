# Build

This document describes how to build AudioMator from this repository and what
the current build settings mean.

## Requirements

- macOS with the stable Xcode 27 toolchain installed at `/Applications/Xcode.app`.
- Swift Package Manager (bundled with Xcode).
- Network access the first time the `TagLibAudioMetadata` package is resolved.
- No sibling checkout of `TagLibAudioMetadata` is required.

Verified in this audit:

| Item | Value |
| --- | --- |
| Host | macOS 27 |
| Xcode | 27.1 (27A9275) |
| Swift compiler | Apple Swift 6.4 |
| App deployment target | macOS 15.0 |
| Package pin | `TagLibAudioMetadata` 0.5.3, revision `03473c9ae199026b806a5f75c387ca036e325284` |

The repository targets stable Xcode 27. Prerelease toolchains and older Xcode
versions are not supported by project policy and were not tested.

## Repository Setup

```bash
git clone https://github.com/ChrisLloydME/AudioMator.git
cd AudioMator
open AudioMator.xcodeproj
```

Select the `AudioMator` scheme and a macOS destination. Xcode resolves the
remote package automatically. To resolve it manually:

```bash
xcodebuild -resolvePackageDependencies -project AudioMator.xcodeproj
```

The package requirement is an **exact version** (`0.5.3`). Do not point the
project at an unreleased branch or a local checkout as part of normal
development.

## Scheme and Configurations

There is one shared scheme, `AudioMator`. It builds the app and includes the
app-hosted `AudioMatorTests` target for the Test action. The test target is
marked non-parallel.

Both configurations target macOS 15.0, use Swift 5 language mode with complete
strict concurrency and MainActor default isolation, and enable App Sandbox and
Hardened Runtime. Debug and Release use different bundle identifiers, so they have
separate sandbox containers, bookmarks, and preferences.

For the authoritative current version, build number, bundle identifiers,
entitlements, and preference keys, see
[Configuration](../Reference/CONFIGURATION.md). Verify the values in
`AudioMator.xcodeproj/project.pbxproj` before a release.

## Swift Package (Core Logic Tests)

`Package.swift` is a separate SwiftPM manifest used only to compile a selected
set of Foundation-only production files for fast tests.

```bash
swift test
swift test --filter AudioMatorCoreLogicTests
```

It is not the app dependency graph and is not linked into the app. It has no
`TagLibAudioMetadata` dependency.

## Build Commands

### Repository build script

```bash
bash scripts/codex-build.sh
bash scripts/codex-build.sh --force
```

Behavior:

- Creates `.deriveddata-codex`.
- Runs `scripts/prune-app-bundles.sh`, which removes root-level `.deriveddata*`
  directories other than `.deriveddata-codex` and app bundles other than
  `.deriveddata-codex/Build/Products/Debug/AudioMator.app`.
- Without `--force`, skips `xcodebuild` when no build-relevant files changed.
- Runs a Debug generic macOS build with code signing disabled.
- Logs to `.deriveddata-codex/xcodebuild.log`.
- Treats one specific `actool`/`AppIcon.icon` crash as a known environment false
  positive; other failures exit non-zero.

The script does **not** run tests, archive, sign, notarize, or package.

### Direct build

```bash
xcodebuild \
  -project AudioMator.xcodeproj \
  -scheme AudioMator \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Release build (unsigned)

```bash
xcodebuild \
  -project AudioMator.xcodeproj \
  -scheme AudioMator \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  CODE_SIGNING_ALLOWED=NO \
  build
```

An unsigned Release build verifies compilation, optimization, linking, and
resource processing. It does not produce a distributable, signed, or notarized
app.

### Tests

```bash
swift test

xcodebuild \
  -project AudioMator.xcodeproj \
  -scheme AudioMator \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  test
```

The app-hosted test target launches the app as its test host. Always keep the
serial flags for Agent-driven runs; each parallel runner launches another app
instance.

### Artifact compatibility check

```bash
scripts/validate-macos-artifact.sh \
  .deriveddata-codex/Build/Products/Release/AudioMator.app \
  15.0
```

The script checks:

- `LSMinimumSystemVersion` exactly equals the expected value,
- every Mach-O under `Contents` has `platform MACOS`,
- every Mach-O has an `LC_BUILD_VERSION` minimum, and
- every minimum is at most the expected macOS version.

It does not verify signing, notarization, entitlements, architectures, bundle ID,
or marketing/build versions.

## Build Settings That Affect Development

- **App Sandbox + user-selected read/write.** File access depends on
  user-selected URLs and security-scoped bookmarks.
- **Hardened Runtime.** Enabled in both configurations.
- **No incoming network connections.** Outgoing client only.
- **MainActor default isolation + complete strict concurrency.** New code must be
  isolation-clean; do not suppress warnings.
- **Swift 5 language mode.** The compiler is Swift 6.x, but the target language
  mode is 5.0.
- **Synchronized source root.** `AudioMator/` is attached through Xcode's
  file-system synchronized group. New files under that root are picked up
  automatically; configuration inputs stay in `Config/`.
- **No alternate derived-data roots.** Use `.deriveddata-codex` for
  Agent-triggered builds.

## Common Build Problems

### Cache or sandbox failures

Symptoms include inability to write SwiftPM manifests, Clang module caches, or
Xcode caches under `~/Library`, or `sandbox-exec: sandbox_apply: Operation not
permitted`. This is an environment restriction. Run in a normal terminal with
access to the user Library; do not change the project to work around it.

### CI toolchain path

The GitHub Actions workflow sets
`DEVELOPER_DIR=/Applications/Xcode_27.0.app/Contents/Developer` and uses the
`xcode-27` runner label. Those are CI-specific. A developer Mac with only
`/Applications/Xcode.app` should not copy that value.

### AppIcon tool crash

`scripts/codex-build.sh` recognizes a specific `actool`/`ibtoold` crash while
compiling `AudioMator/AppIcon.icon` and treats it as an environment false
positive. Inspect `.deriveddata-codex/xcodebuild.log` for other errors.

### Missing package or fixture failures

Run dependency resolution first and verify `Package.resolved`. App-hosted tests
copy fixtures from the test bundle; a stale or incomplete build product can
break fixture lookup.

## Verification Performed for This Documentation

On 2026-10-17, with Xcode 27.1:

```text
swift test
  Executed 61 tests, with 0 failures

bash scripts/codex-build.sh --force
  ** BUILD SUCCEEDED **
```

A focused app-hosted run also passed:

```text
xcodebuild ... -only-testing:AudioMatorTests/TagLibReadWriteIntegrationTests test
  Executed 33 tests, with 0 failures
```

An unsigned Release generic build also passed and produced a universal executable
(`x86_64 arm64`). `scripts/validate-macos-artifact.sh` accepted the bundle with
minimum macOS 15.0.

The full app-hosted suite was not run during this documentation audit; see
[Testing](TESTING.md) for its scope and the resulting gap.

## Related Documents

- [Testing](TESTING.md)
- [Debugging](DEBUGGING.md)
- [Configuration](../Reference/CONFIGURATION.md)
- [Release Engineering](RELEASE.md)
