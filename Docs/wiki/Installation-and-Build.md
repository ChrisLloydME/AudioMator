# Installation and Build

AudioMator is built from the Xcode project. A SwiftPM core-logic test target and build scripts are available for local validation.

## Requirements

- macOS development environment.
- Xcode capable of opening `AudioMator.xcodeproj`.
- Swift Package Manager for resolving `TagLibAudioMetadata` and Sparkle package references.
- Network access when resolving packages or using online app features.

The app target currently declares macOS `26.0` and iOS/iPadOS `26.0` deployment targets. The SwiftPM fast-test package declares macOS `.v15` because it includes only selected non-UI, non-TagLib, non-network core logic.

## Open the Project

Open the Xcode project:

```bash
open AudioMator.xcodeproj
```

Select the `AudioMator` scheme. macOS is the primary full desktop workflow. For iPadOS compile checks, prefer generic iOS destination builds unless simulator validation is specifically needed.

## Resolve Dependencies

Xcode usually resolves Swift packages automatically. To resolve them manually:

```bash
xcodebuild -resolvePackageDependencies -project AudioMator.xcodeproj
```

The current project resolution includes `https://github.com/ChrisLloydME/TagLibAudioMetadata.git` and `https://github.com/sparkle-project/Sparkle`.

## Fast Tests

Run the fastest local regression check:

```bash
swift test --filter AudioMatorCoreLogicTests
```

The GitHub Actions workflow in `.github/workflows/core-logic.yml` runs `swift test` on a macOS 15 runner for pull requests and pushes to `main`.

## Codex Build Script

Use `scripts/codex-build.sh` for local validation:

```bash
bash scripts/codex-build.sh
bash scripts/codex-build.sh --force
```

Without `--force`, the script checks whether the current working tree contains build-relevant changes. If not, it skips `xcodebuild`. With `--force` or `--full`, it runs a Debug generic macOS build. Derived data is written to `.deriveddata-codex`, and the build log is written to `.deriveddata-codex/xcodebuild.log`.

The build command is equivalent to:

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

The script also recognizes one known Codex CLI environment issue: `actool`/`ibtoold` may crash while compiling `AudioMator/AppIcon.icon`. When the log matches that known AppIcon failure and no other compiler error is present, the script treats it as an environment-specific false positive.

## TagLib Bridge Smoke Tool

For local bridge/package debugging:

```bash
bash scripts/build-taglib-bridge-smoke.sh
./.tmp/taglib_bridge_smoke read path/to/file.m4a
./.tmp/taglib_bridge_smoke raw path/to/file.m4a
./.tmp/taglib_bridge_smoke write-track path/to/file.m4a 07/12 2/3
./.tmp/taglib_bridge_smoke write-roundtrip path/to/file.m4a
```

This tool is useful for track/disc totals, MP4 `trkn`/`disk` behavior, text preservation versus numeric readback, and raw property-map inspection.
