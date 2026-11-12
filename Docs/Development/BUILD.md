# Build

This document describes how to build AudioMator from this repository and what the current build settings mean.

## Requirements

- macOS with the stable Xcode 27 toolchain installed at `/Applications/Xcode.app`.
- Swift Package Manager (bundled with Xcode).
- Network access the first time the `TagLibAudioMetadata` package is resolved.
- No sibling checkout of `TagLibAudioMetadata` is required.

Current checkout verified by source inspection on 2026-11-12:

| Item | Value |
| --- | --- |
| Toolchain | Xcode 27.2 (27B52), Apple Swift 6.4.2 |
| App deployment target | macOS 15.0 |
| Package pin | Exact published `0.7.3`; [release source](https://github.com/ChrisLloydME/TagLibAudioMetadata/tree/0.7.3), revision `7ca1b75326388a5902815f70145b600299944ae0` |
| Recorded release gate | [Published 0.7.3 release readiness](../Engineering/TAGLIB_073_RELEASE_READINESS_2026-11-12.md) |

The repository targets stable Xcode 27. Prerelease toolchains and older Xcode versions are not supported by project policy and were not tested. The dependency itself requires Swift tools 6.4; the separate Foundation-only SwiftPM harness in this repository declares Swift tools 6.0 and does not compile the dependency.

## Repository Setup

```bash
git clone https://github.com/ChrisLloydME/AudioMator.git
cd AudioMator
open AudioMator.xcodeproj
```

Select the `AudioMator` scheme and a macOS destination. Xcode resolves the remote package automatically. To resolve it manually:

```bash
xcodebuild -resolvePackageDependencies -project AudioMator.xcodeproj
```

The committed package requirement is **exact version `0.7.3`**. Resolve and validate using `AudioMator.xcodeproj`; no sibling checkout or local override is required. Keep the generated `Package.resolved` version and revision aligned with the published tag.

## Scheme and Configurations

There is one shared scheme, `AudioMator`. It builds the app and includes the app-hosted `AudioMatorTests` target for the Test action. The test target is marked non-parallel.

Both configurations target macOS 15.0, use Swift 5 language mode with complete strict concurrency and MainActor default isolation, and enable App Sandbox and Hardened Runtime. Debug and Release use different bundle identifiers, so they have separate sandbox containers, bookmarks, and preferences.

For the authoritative current version, build number, bundle identifiers, entitlements, preference keys, and CI settings, see [Configuration](../Reference/CONFIGURATION.md). Verify the values in `AudioMator.xcodeproj/project.pbxproj` before a release.

## Swift Package (Core Logic Tests)

`Package.swift` is a separate SwiftPM manifest used only to compile a selected set of 31 Foundation-only production files for fast tests.

```bash
swift test
swift test --filter AudioMatorCoreLogicTests
```

It is not the app dependency graph and is not linked into the app. It has no `TagLibAudioMetadata` dependency. See [Testing](TESTING.md#swiftpm-fast-target) for the file selection rules.

## Build Commands

### Repository build script

```bash
bash scripts/codex-build.sh
bash scripts/codex-build.sh --force
```

Behavior:

- Creates `.deriveddata-codex`.
- Runs `scripts/prune-app-bundles.sh`, which removes root-level `.deriveddata*` directories other than `.deriveddata-codex` and app bundles other than `.deriveddata-codex/Build/Products/Debug/AudioMator.app`.
- Without `--force`, skips `xcodebuild` when no build-relevant files changed.
- Runs a Debug generic macOS build with code signing disabled.
- Logs to `.deriveddata-codex/xcodebuild.log`.
- If the log contains the specific `actool`/`AppIcon.icon` crash markers, the script treats the result as a known environment false positive and exits 0. It does not prove there are no other errors, so always inspect the log.

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

An unsigned Release build verifies compilation, optimization, linking, and resource processing. It does not produce a distributable, signed, or notarized app.

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

The app-hosted test target launches the app as its test host. Always keep the serial flags for Agent-driven runs; each parallel runner launches another app instance.

### Unified release validation gate

```bash
bash scripts/validate-release.sh
```

This is the normal release gate. It runs the policy tests, the 62 Foundation-only tests, the complete serial app-hosted suite, the unsigned Release build, and `validate-macos-artifact.sh`. It records source identity, logs, the `.xcresult`, the test summary, the complete test tree, and acceptance JSON under `.deriveddata-codex/Validation/`. Any failed phase stops the gate. It never launches the app interactively.

The local candidate form is documented under [Local package candidate gate](#local-package-candidate-gate).

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

It does not verify signing, notarization, entitlements, architectures, bundle ID, or marketing/build versions.

## Build Settings That Affect Development

- **App Sandbox + user-selected read/write.** File access depends on user-selected URLs and security-scoped bookmarks.
- **Hardened Runtime.** Enabled in both configurations.
- **No incoming network connections.** Outgoing client only.
- **MainActor default isolation + complete strict concurrency.** New code must be isolation-clean; do not suppress warnings.
- **Swift 5 language mode.** The compiler is Swift 6.x, but the target language mode is 5.0.
- **Synchronized source root.** `AudioMator/` is attached through Xcode's file-system synchronized group. New files under that root are picked up automatically; configuration inputs stay in `Config/`.
- **No alternate derived-data roots.** Use `.deriveddata-codex` for Agent-triggered builds.

## Local Package Candidate Gate

```bash
bash scripts/validate-release.sh --local-package /absolute/path/TagLibAudioMetadata
```

This generates the ignored `.tmp/MappingIntegration.xcworkspace`, runs the same policy/core/app/Release/artifact phases with the candidate, and records the package commit, dirty status, diff hash, and untracked-file hashes. It does not use an alternate derived-data root. The default command still resolves the published lock; the local gate does not validate or change that remote release. Only use this form when explicitly evaluating a package candidate.

## Common Build Problems

### Cache or sandbox failures

Symptoms include inability to write SwiftPM manifests, Clang module caches, or Xcode caches under `~/Library`, or `sandbox-exec: sandbox_apply: Operation not permitted`. This is an environment restriction. Run in a normal terminal with access to the user Library; do not change the project to work around it.

### CI toolchain path

The GitHub Actions workflow sets `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and uses the `xcode-27` runner label. Those are CI-specific. A developer Mac with only `/Applications/Xcode.app` should use the same stable path, not an older versioned Xcode directory.

### AppIcon tool crash

`scripts/codex-build.sh` recognizes a specific `actool`/`ibtoold` crash while compiling `AudioMator/AppIcon.icon` and treats it as an environment false positive. Inspect `.deriveddata-codex/xcodebuild.log` for other errors.

### Missing package or fixture failures

Run dependency resolution first and verify `Package.resolved`. App-hosted tests copy fixtures from the test bundle; a stale or incomplete build product can break fixture lookup.

## Recorded Verification

The most recent recorded acceptance is the published 0.7.3 gate on 2026-11-12:

- 13 policy tests passed,
- 62 Foundation-only core tests passed with complete named execution,
- 579 serial app-hosted tests passed with zero failures, skips, or expected failures,
- the exact dependency/disclosure contract passed,
- the unsigned Release build and artifact validation passed,
- an additional unsigned Archive passed structure, architecture, license, and dependency-path checks.

See [Published 0.7.3 release readiness](../Engineering/TAGLIB_073_RELEASE_READINESS_2026-11-12.md) for the exact commands, evidence paths, and the manual distribution boundary. Earlier dated counts in engineering records are historical; re-run the current gate before quoting new numbers.

## Related Documents

- [Testing](TESTING.md)
- [Debugging](DEBUGGING.md)
- [Configuration](../Reference/CONFIGURATION.md)
- [Release Engineering](RELEASE.md)
