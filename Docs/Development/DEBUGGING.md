# Debugging

This document lists the supported diagnostic tools and the boundaries that protect user data and the external dependency.

## Build and Test Diagnosis

### Build log

`scripts/codex-build.sh` writes the complete `xcodebuild` output to:

```text
.deriveddata-codex/xcodebuild.log
```

Inspect it for compiler errors even when the script reports a known AppIcon tooling false positive.

### Focused tests

Run the smallest suite that covers the changed behavior:

```bash
swift test --filter AudioMatorCoreLogicTests

xcodebuild \
  -project AudioMator.xcodeproj \
  -scheme AudioMator \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:AudioMatorTests/TagLibReadWriteIntegrationTests \
  test
```

Use `-only-testing:AudioMatorTests/<ClassName>` for a single class. Do not add parallel-testing overrides; the test host is the app.

### Sandbox and cache failures

SwiftPM and `xcodebuild` need to write caches under the user Library and may launch their own sandbox. Errors such as:

```text
error opening '.../ModuleCache/...' for output: Operation not permitted
sandbox-exec: sandbox_apply: Operation not permitted
```

are environment restrictions. Run in a normal terminal with appropriate access; do not weaken project settings or disable tests.

## Runtime Diagnostics Inside the App

AudioMator deliberately does **not** write diagnostic `print`, `debugPrint`, or `NSLog` output in app code. `SensitiveLoggingPolicyTests` enforces this and also prevents reintroducing the removed metadata logger.

Available user-facing diagnostics:

- **Tag Inspector / metadata dump**: full properties, ID3v2 frames, legacy ID3v1 sections, and compatibility notes. The dump includes the file path and tag values; treat it as sensitive when sharing.
- **Save issue log**: Settings → Logs. Persisted locally at `Application Support/AudioMator/SaveIssueLog.json`, capped at 200 entries. Entries contain file names and backend messages, not full paths.
- **HUD and progress**: per-operation success, warning, failure, partial-batch, and reload-failure messages.

There is no telemetry, analytics, or crash-reporting SDK.

## TagLib Bridge Smoke Tool

The repository includes `scripts/taglib_bridge_smoke.mm` and `scripts/build-taglib-bridge-smoke.sh` for package-level debugging.

Build prerequisites:

- a bridge source directory containing `TagLibMetadataExtractor.mm`, found from `TAGLIB_BRIDGE_ROOT`, `AudioMator/TagLibBridge` (not present in this repository), or the SwiftPM checkout under `.deriveddata-codex`;
- TagLib sources (`<bridge>/taglib` or `ThirdParty/TagLib`) or a built `TagLib.framework` under `.deriveddata-codex`.

Commands:

```bash
bash scripts/build-taglib-bridge-smoke.sh
./.tmp/taglib_bridge_smoke read path/to/file.m4a
./.tmp/taglib_bridge_smoke raw path/to/file.m4a
./.tmp/taglib_bridge_smoke write-track path/to/file.m4a 07/12 2/3
./.tmp/taglib_bridge_smoke write-roundtrip path/to/file.m4a
```

Use temporary copies only. The write commands modify the file.

**Ownership boundary:** the script compiles sources from the `TagLibAudioMetadata` package checkout. AudioMator Agents must not build from, modify, or commit in that checkout. Maintainers may run the tool as a local debugging aid; defects found in the package should be reported to the package owner with a minimal reproduction.

## Performance Probes

The performance tests are app-hosted and use real fixtures/TagLib where noted:

```bash
xcodebuild ... \
  -only-testing:AudioMatorTests/MetadataIOPerformanceTests \
  test

xcodebuild ... \
  -only-testing:AudioMatorTests/MainMetadataFlowPerformanceTests \
  test

xcodebuild ... \
  -only-testing:AudioMatorTests/OnlineMetadataWorkbenchPerformanceTests \
  test
```

They print timing lines and attach medians to the test result. Treat the numbers as local, warm-fixture observations. Correctness/work-bound assertions are the regression gate; wall-clock values are not portable across machines or volumes.

## Inspecting Metadata Behavior

1. Reproduce on a **copy** of the file.
2. Use Tag Inspector to compare the stored values before and after the operation.
3. Use the metadata dump to see TagLib Properties, ID3v2 frames, and legacy sections.
4. For number behavior, check both the numeric values and the combined text.
5. For a write failure, check whether the outcome was "not written", "written and refreshed", or "written but not refreshed".

The bridge smoke tool is appropriate when the discrepancy is below the app layer (for example, `trkn`/`disk` or property-map round trips).

## External Dependency Boundary

- Do not inspect or modify a local `TagLibAudioMetadata` checkout while working as an AudioMator Agent unless the user explicitly grants access.
- Do not patch SwiftPM checkouts, caches, or symlinks to work around a package defect.
- If a package defect is suspected, record:
  - the affected API or source area,
  - observed versus expected behavior,
  - the AudioMator minimal reproduction,
  - the test the package should add.
- Keep any app-side mitigation narrow and labeled as a workaround.

Known dependency constraints are documented in [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md).

## Network Debugging

Provider tests use `URLProtocol` fakes and injected clients. To debug request construction:

- inspect `MusicBrainzRequestSchedulingTests`, `LRCLIBRequestBuilder`, and `ProviderNetworkFaultTests` for the expected shapes;
- confirm the 15-second timeout assertions;
- confirm that cancellation and operation IDs discard stale results.

Do not add live-network tests to the default suite. If live testing is necessary, use a separate manual procedure and do not commit secrets or user metadata.

## Related Documents

- [Build](BUILD.md)
- [Testing](TESTING.md)
- [Metadata Pipeline](../Architecture/METADATA_PIPELINE.md)
