# Build

This document describes how to build AudioMator from this repository and what the current build settings mean.

## Requirements

- macOS with the stable Xcode 27 toolchain installed at `/Applications/Xcode.app`.
- Swift Package Manager (bundled with Xcode).
- Network access the first time the `TagLibAudioMetadata` package is resolved.
- No sibling checkout of `TagLibAudioMetadata` is required.

Environment and project values verified by source inspection on 2026-11-18 (no build was run for this audit):

| Item | Value |
| --- | --- |
| Toolchain | Xcode 27.2 (27B52), Apple Swift 6.4.2 |
| App deployment target | macOS 15.0 |
| Package pin | Exact published `0.8.1`; [release source](https://github.com/ChrisLloydME/TagLibAudioMetadata/tree/0.8.1), revision `b8ed5475761cb50bacdd7dcd4f6e2f61142303d0` |
| Package resolution file | `AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` |
| Marketing version / build | `2.7` / `26112` in both app configurations |
| Bundle identifiers | Debug `com.TheLloydME.AudioMator.Beta`; Release `com.LloydME.AudioMator` |
| Recorded Debug adoption | [Published 0.8.1 Debug adoption](../Engineering/TAGLIB_081_DEBUG_ADOPTION_2026-11-17.md) |

The repository targets stable Xcode 27. Prerelease toolchains and older Xcode versions are not supported by project policy and were not tested. The external package's own manifest is authoritative for its toolchain requirements; the separate Foundation-only SwiftPM harness in this repository declares Swift tools 6.0 and does not compile the dependency.

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

The committed package requirement is **exact version `0.8.1`**. Resolve and validate using `AudioMator.xcodeproj`; no sibling checkout or local override is required. Keep the generated `Package.resolved` version and revision aligned with the published tag.

## Scheme and Configurations

There is one shared scheme, `AudioMator`. It builds the app and includes the app-hosted `AudioMatorTests` target for the Test action. The test target is marked non-parallel.

Both configurations target macOS 15.0, use Swift 5 language mode with complete strict concurrency and MainActor default isolation, and enable App Sandbox and Hardened Runtime. Debug and Release use different bundle identifiers, so they have separate sandbox containers, bookmarks, and preferences.

For the authoritative current version, build number, bundle identifiers, entitlements, preference keys, and CI settings, see [Configuration](../Reference/CONFIGURATION.md). Verify the values in `AudioMator.xcodeproj/project.pbxproj` before a release; the values in this document were checked there on 2026-11-18.

## Swift Package (Core Logic Tests)

`Package.swift` is a separate SwiftPM manifest used only to compile a selected set of 33 Foundation-only production files for fast tests.

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

- Fails closed. Without `--force`, it runs two checked Git discovery commands: tracked changes against HEAD with rename detection disabled, and nonignored untracked paths. Names are NUL-delimited, so paths containing newlines or trailing spaces are evaluated correctly. A failed HEAD lookup, failed tracked-change read or failed untracked-path read exits nonzero with instructions to use `--force`; discovery failure is never reported as a skip.
- Treats every nonignored path under `AudioMator/`, `AudioMatorTests/`, `AudioMator.xcodeproj/` and `Config/` as build-relevant, plus this helper. That covers the synchronized source roots, project settings, package-resolution lockfile, resources such as `Localizable.xcstrings`, audio and artwork fixtures, and bundled licenses. Documentation-only, SwiftPM-only and policy-script changes can skip this Xcode wrapper and must run their own gates.
- A successful discovery with no build-relevant paths prints `CODEX_BUILD_SKIPPED` and exits 0 without invoking Xcode. The skip creates no build directories and deletes nothing. **A skip is not compilation evidence.**
- `--force` intentionally skips Git discovery and always builds. Automation that needs build evidence uses the direct Xcode command or `--force`.
- Creates `.deriveddata-codex` and runs a Debug generic macOS build with code signing disabled.
- Logs to `.deriveddata-codex/xcodebuild.log` and records the `xcodebuild` and `tee` (log capture) statuses independently.
- On a compile failure, keeps the Xcode exit status (for example 65) and prints no completed marker. The recognized `actool`/`AppIcon.icon` crash markers add diagnostic advice but no longer convert the run to success.
- A failed log capture returns nonzero even when compilation completed, because an uncaptured log is not valid evidence.
- Only when both `xcodebuild` and log capture succeed does it print `CODEX_BUILD_COMPLETED` and exit 0.
- Does not prune. It never removes alternate derived-data directories or app bundles. `scripts/prune-app-bundles.sh` remains available as an explicit, destructive maintainer cleanup and is not invoked by this helper.
- Accepts only `--force`; any other argument prints usage and exits 2. The old undocumented `--full` alias was removed (commit `dcae77f3`).

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

This is the normal release gate. It runs the policy tests, the 94 Foundation-only tests, the complete serial app-hosted suite, the unsigned Release build, and `validate-macos-artifact.sh`. It records source identity, logs, the `.xcresult`, the test summary, the complete test tree, and acceptance JSON under `.deriveddata-codex/Validation/`. Any failed phase stops the gate. It never launches the app interactively.

The local candidate form is documented under [Local package candidate gate](#local-package-candidate-gate). The test-only form is `bash scripts/validate-release.sh --tests-only`, which skips the Release build and artifact phases.

### Compile-clean diagnostic check (AM-19)

The release gate proves behavior, not absence of concurrency warnings. For the AM-19 cleanup, a
separate cold-build check compiles the app and app-hosted test target in both configurations from a
disposable candidate checkout and requires zero actor-isolation, Swift 6 migration, `Sendable` and
implicit-strong-capture diagnostics. Diagnostics are extracted from the full logs and keyed by
target/file/line/category, de-duplicated by `(target, file, line, message)`; package, toolchain,
linker and unrelated warnings are reported separately and never suppressed, and incremental builds
are not valid evidence.

```bash
# from a clean disposable copy of the exact candidate
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build-for-testing
```

The Release `build-for-testing` phase is required so the app-hosted test target compiles under
Release; a plain Release `build` compiles only the app. The settings the check must preserve are
Swift 5 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION =
MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` for both targets and configurations. Dated
evidence (source revision, Xcode version, commands, log paths, per-category counts and remaining
non-campaign diagnostics) belongs in the matching Engineering acceptance record.

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

It does not verify signing, notarization, entitlements, architectures, bundle ID, marketing/build versions, or bundled license texts.

## Build Settings That Affect Development

- **App Sandbox + user-selected read/write.** File access depends on user-selected URLs and security-scoped bookmarks.
- **Hardened Runtime.** Enabled in both configurations.
- **No incoming network connections.** Outgoing client only.
- **MainActor default isolation + complete strict concurrency.** New code must be isolation-clean; do not suppress warnings. App-hosted `XCTestCase` subclasses are declared `nonisolated` with explicit `@MainActor` only on members that own app models/AppKit; pure value types and helpers stay `nonisolated`. The candidate must compile with zero actor-isolation, Swift 6 migration, `Sendable` and implicit-capture diagnostics in both targets and both configurations (see the compile-clean diagnostic check below).
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

`scripts/codex-build.sh` recognizes a specific `actool`/`ibtoold` crash while compiling `AudioMator/AppIcon.icon` and prints additional diagnostic advice. It does not treat the crash as success: the helper keeps the Xcode exit status and does not print `CODEX_BUILD_COMPLETED`, so the run is not build evidence. Inspect `.deriveddata-codex/xcodebuild.log` for other errors, and validate the `.icon` asset with Xcode on the desktop or retry on a host whose asset tooling works.

### Missing package or fixture failures

Run dependency resolution first and verify `Package.resolved`. App-hosted tests copy fixtures from the test bundle; a stale or incomplete build product can break fixture lookup.

## Recorded Verification

Current published 0.8.1 adoption results are recorded in [Debug adoption](../Engineering/TAGLIB_081_DEBUG_ADOPTION_2026-11-17.md). The 0.8.0 results in older engineering records are historical and are not acceptance evidence for this dependency. The most recent full repository gate with the published 0.8.1 pin is the 2026-11-18 cleanup acceptance; see [Testing](TESTING.md#release-gate-evidence) for the enforced phases and evidence location.

## Related Documents

- [Testing](TESTING.md)
- [Debugging](DEBUGGING.md)
- [Configuration](../Reference/CONFIGURATION.md)
- [Release Engineering](RELEASE.md)
