# Published TagLibAudioMetadata 0.7.2 adoption

> Historical record. Superseded by [published 0.7.3 acceptance](TAGLIB_073_RELEASE_READINESS_2026-11-12.md). The failing 0.7.2 regressions below remain dated evidence and are mandatory passing tests on 0.7.3.

Date: 2026-11-11. Application baseline: `c778987d`, with existing documentation changes preserved. Branch: `codex/taglib-0.7.2-upgrade`. Environment: stable Xcode 27.2 at `/Applications/Xcode.app`, macOS 27.2, arm64. This record concerns the published dependency and normal `AudioMator.xcodeproj`; the historical local-override workspace was not used.

## Verdict

Dependency adoption is complete, but release acceptance is **blocked** by A072-01 below. A successful build or a passing subset must not replace the red full test gate. No signing, notarization, publication or interactive application acceptance was performed.

## Dependency and legal changes

- Exact package requirement and generated lock: `0.7.2`, revision `5e6f604b0e9df244f4b69608261407d2ab758788`, remote source-control resolution from GitHub.
- In-app Acknowledgements and current dependency/build/legal documentation now identify 0.7.2.
- The package MIT text matches the published 0.7.2 `LICENSE` exactly after trimming file-end whitespace. The TagLib 2.3.1 revision 2 binary URL/checksum matches the previous pin; no license-resource replacement is needed.
- The dependency contract test now requires the remote lock and exact release revision. A missing lock or an arbitrary 40-character revision no longer passes.
- Removed a dangling comment describing a date-companion workaround whose implementation had already been removed. Semantic writes still contain only requested fields; no companion or raw-write workaround was added.

## A072-01 — P1 — MP4 Comment/Lyrics writes reject when YEAR is absent and standalone DATE is present

Status: **Reproduced in published 0.7.2; open package defect.**

Affected API: `TagLibMetadataManager.applyMetadataPatch`, surfaced through `TagLibAudioMetadataPipeline.writeMetadata` for Comment. A public-package Lyrics patch independently reproduces the same error. A user can encounter this through a Comment edit in Inspector, CSV import or another semantic workflow on a file with this date layout. The new app test asserts the requested patch contains only Comment.

Minimal reproduction on a temporary M4A copy:

```swift
try TagLibMetadataManager.applyMetadataPatch(.init(fields: [
    .year: .remove,
    .standaloneDate: .text("2008-03-04")
]), to: url)

// Snapshot: YEAR is absent; independent DATE is 2008-03-04.
try TagLibMetadataManager.applyMetadataPatch(.init(fields: [
    .comment: .text("Comment only") // .lyrics also reproduces
]), to: url)
```

Expected: save only the requested text, keep YEAR absent and preserve DATE exactly. Observed: `verificationFailed(["Unedited native date field year changed during the patch."])`. The original file bytes remain unchanged on rejection; no committed data loss was observed.

Permanent normal regressions:

- `MappingPackageConformanceTests.testAppMP4CommentPreservesAbsentYearWithStandaloneDate`
- `MappingPackageConformanceTests.testPackageMP4LyricsPreservesAbsentYearWithStandaloneDate`

The focused class runs five tests: three previous controls pass and both new regressions fail. Neither is skipped or marked expected failure. No sibling package checkout/cache was entered, inspected, modified or built directly.

Package-owner follow-up: add the minimal absent-YEAR/present-DATE layout to Comment and Lyrics set/replace/remove matrices, including DATE arrays and malformed existing text. Check all untouched native date owners and original bytes on failed transactions. A likely investigation area is MP4 text writes that pass through the engine PropertyMap projection; this is a hypothesis from the public behavior, not a source-confirmed root cause. The package must not require AudioMator to synthesize an unedited Year/Date companion or switch semantic writes to raw writes.

## A072-02 — Test evidence gap — CSV operation order hid the combination

The existing CSV field matrix writes many fields into one fixture while iterating a dictionary. Its initial complete run failed once in that method, but an isolated repeat passed. Eight fresh-process repetitions produced five passes and three failures, each failing Comment with absent YEAR and present DATE. Therefore the earlier green local-override runs were insufficient evidence for this date combination.

The CSV test now reports the failed field, requested semantic identities and date context, and compares the original bytes on rejection. The two independent fresh-fixture regressions above make the missed combination deterministic. The existing CSV matrix and all its success assertions remain enabled.

## Verification

Normal project resolution was performed with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -resolvePackageDependencies -project AudioMator.xcodeproj \
  -scheme AudioMator -derivedDataPath .deriveddata-codex
```

The first `bash scripts/validate-release.sh` run passed all 62 core tests, then ran 574 app tests: 573 passed and the CSV matrix failed. The release gate stopped at that failure. In that full run the provider preview/save journeys, Inspector dirty-state cases, Inspector/Metadata Editor workflows, independent dates, Store ID and Content Group tests passed. This is scoped evidence, not proof that all files or interactive UI flows are correct.

Focused command for the new deterministic reproductions:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .deriveddata-codex \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:AudioMatorTests/MappingPackageConformanceTests \
  CODE_SIGNING_ALLOWED=NO test
```

Initial full-gate evidence: `.deriveddata-codex/Validation/20261111-202911-82283/`. Focused logs: `/tmp/audiomator-072-minimal-repro.log`; order-reproduction log: `/tmp/audiomator-072-csv-repetitions.log`. The final complete Debug suite executed 576 tests: 573 passed and three failed (the two deterministic regressions plus the original CSV path). The result bundle is `.deriveddata-codex/Validation/TagLib072Final-20261111.xcresult`, with log `/tmp/audiomator-072-final-app.log`. Build output, result bundles and local logs remain uncommitted.

## Final build and artifact checks

The separate unsigned Release build against the normal 0.7.2 dependency succeeded for arm64 and x86_64. `scripts/validate-macos-artifact.sh .deriveddata-codex/Build/Products/Release/AudioMator.app 15.0` passed: the app executable reports minimum macOS 15.0, and the bundled TagLib framework reports 13.0. Logs: `/tmp/audiomator-072-release-build.log` and `/tmp/audiomator-072-artifact.log`. This establishes compilation and artifact consistency, not release acceptance; the three failing Debug regressions still block the release gate.

The final `.xcresult` machine-readable summary is `.deriveddata-codex/Validation/TagLib072Final-summary.json`: 576 total, 573 passed, three failed, zero skipped. Local documentation targets and `git diff --check` passed. No commit, push or package change was performed.

## Remaining boundaries

- This branch adopts 0.7.2; it does not authorize editing the independently maintained package. A package repair and new published version are separate work.
- ID3v2.3 independent dates, MP4 RATE typed writes, unknown-advisory assignment and limited audio-content identity layouts retain their explicit capability boundaries.
- Existing test-target concurrency diagnostics remain visible. They are not suppressed or counted as repaired by this dependency upgrade.
- No live provider service or user audio was used. Tests use repository fixtures and generated temporary files. Interactive SwiftUI acceptance remains maintainer-owned.
