# Testing Guide

AudioMator has two main test surfaces: SwiftPM fast core-logic tests and Xcode app-hosted tests. The build script provides compile validation.

## SwiftPM Fast Tests

Run:

```bash
swift test --filter AudioMatorCoreLogicTests
```

Or run the same command used by the current CI workflow:

```bash
swift test
```

`Package.swift` defines `AudioMatorCoreLogic` as a selected non-UI, non-TagLib, non-network target. Current fast coverage includes text editing, track/disc parsing, rename template parsing and sanitizing, rename collision policy, filename-to-metadata matching, metadata exchange CSV/import/export planning, LRCLIB request/ranking logic, iTunes artwork/request normalization, iTunes and MusicBrainz provider helpers, fuzzy matching, MuseAmp ID generation, audio-format support policy, file collection ordering/grouping, merged metadata policy, duplicate detection, and artwork replacement decisions.

## Xcode App-Hosted Tests

`AudioMatorTests/` contains app-hosted tests, including:

- `TagLibReadWriteIntegrationTests.swift`
- `MetadataEditorStoreTests.swift`
- `InspectorAndMetadataEditorWorkflowTests.swift`
- `TrackRenumberExecutionTests.swift`
- `FileRenameTransactionTests.swift`
- `DirectoryMonitoringPlanTests.swift`
- `UpdateCheckerTests.swift`
- `SensitiveLoggingPolicyTests.swift`
- MusicBrainz, iTunes, LRCLIB, metadata exchange, and filename template tests.

App-hosted coverage includes TagLib structured reads, raw metadata inspection, read/write round trips, artwork writes, full metadata erase, raw property-map removal, inspector-style clearing, and track/disc normalization.

## CI

`.github/workflows/core-logic.yml` defines the current `Core Logic` workflow:

- Triggers: pull requests and pushes to `main`.
- Runner: `macos-15`.
- Command: `swift test`.
- Timeout: 15 minutes.

## Build Validation

Regular Codex build:

```bash
bash scripts/codex-build.sh
```

If the working tree has no build-relevant changes, the script skips `xcodebuild`. To force a build:

```bash
bash scripts/codex-build.sh --force
```

The script uses `.deriveddata-codex`. Do not create alternate local build roots for agent validation.

## Bridge Smoke Testing

For TagLib bridge debugging:

```bash
bash scripts/build-taglib-bridge-smoke.sh
./.tmp/taglib_bridge_smoke read path/to/file.m4a
./.tmp/taglib_bridge_smoke raw path/to/file.m4a
./.tmp/taglib_bridge_smoke write-track path/to/file.m4a 07/12 2/3
./.tmp/taglib_bridge_smoke write-roundtrip path/to/file.m4a
```

Run destructive write smoke tests on temporary copies, not on a real music library.

## Known Coverage Gaps

`Tests/FAST_TEST_GAPS.md` lists remaining risks:

- No committed aiff or opus fixture exists, so those formats are not claimed as integration-tested.
- Full `AudioViewModel` selection sync, HUDs, watched-folder scans, filesystem writes, and user-initiated batch actions still need app-hosted or integration validation.
- Live MusicBrainz/iTunes/LRCLIB requests, remote rate limits, and API drift remain nondeterministic network boundaries.
- Platform-specific SwiftUI/AppKit/iPad interactions are best covered by UI automation, app-hosted tests, or compile/build checks.
