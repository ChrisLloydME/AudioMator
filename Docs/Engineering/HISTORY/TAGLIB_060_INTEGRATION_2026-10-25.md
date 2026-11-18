# TagLibAudioMetadata 0.6.0 Integration

Date: 2026-10-25. AudioMator baseline: `78a66311`. Working branch: `codex/upgrade-taglib-0.6.0`. The supplied audit described an older `001938d3` baseline; its findings were rechecked against the current implementation. This is a dated engineering record, not the current API contract.

## Decision

The branch pins remote release 0.6.0 at `c135fe0a3c52ba76054731e2afe3e56b83f6d40e`. It is **not ready to merge or distribute** because semantic FLAC comment writes fail inside the dependency. No package checkout or cache source was inspected or modified, no raw fallback was added, and no test was skipped or marked as an expected failure.

## Findings and Changes

| Audit item | Result |
| --- | --- |
| F-1: version mismatch | Exact project requirement, resolved version/revision, acknowledgements and current version docs now agree. A repository policy test checks project/disclosure consistency. |
| F-2 / N-05: same-inode audio replacement | Loader and conflict reads opt into package audio identity. Changed revisions require equal non-nil tokens; typed/raw commits preserve both the original audio token and exact current version. Metadata Editor baseline refresh uses the same continuity check. Unsupported/ambiguous formats require explicit reload after a revision change. |
| F-3: FLAC comments | Reproduced with the direct public API. Retained as an enabled failing regression; see the package-owner reproduction below. |
| F-4: stale total-only guards | Removed planner and shared write-boundary guards. Individual component clearing retains the other component. Pair serialization emits `/total`. Complete-pair clearing and non-numeric semantic rejection remain. |
| F-5: stale number tests | MP3 disc-only edits, AAC total clearing, AAC combined text and all six fixture total-only pairs now require successful readback. Field-transfer combinations exercise the new contract. |
| F-6: artwork import | File and byte normalization use the concurrent executor; clipboard reads encoded PNG/TIFF before background ImageIO processing. Newer imports, clear/keep actions and Inspector reset cancel stale publication. Byte and pixel caps remain. A gated decoder verifies main-actor responsiveness. |
| F-7: extension dispatch | `rawMetadataPropertyMap` is a protocol requirement, so the specialized projection dispatches through an existential. Removed the duplicate value-map delta writer and retained the shared extension implementation. A real-fixture existential contract test verifies projection and exact arrays. |
| Post-rename loading | Moved the production reload onto a detached worker, matching the existing fallback's execution boundary. |
| Redundant file publication | Build the source list locally and publish recovery-preserving visible files once. |
| Test-host preferences warning | Isolated shared test-host preferences to the main actor; no warning suppression. |
| Test counts and Derived Data | Recounted 499 app-hosted / 62 SwiftPM tests and documented explicit CLI Derived Data override of personal IDE settings. |

The application still resolves conflicts conservatively by semantic group. Numeric equality alone does not prove convergence when raw aliases, multiple values or native roles differ. Two nil audio identities never prove continuity. Unchanged exact revisions retain the no-snapshot fast path and final package version guard.

The package's 0.6.0 audio identity API exists even though the supplied audit described it as missing. Supported layouts are native FLAC, RIFF WAVE and AIFF/AIFF-C; other formats or ambiguous layouts return no identity. Tokens are session values, not persisted recording identifiers. Hashing adds O(audio size) streaming I/O with bounded working memory, without a new app-owned parser.

## Dependency-owner Reproduction: FLAC Comment Verification

Affected API: `TagLibMetadataManager.applyMetadataPatch(_:to:expectedVersion:)`, `.comment: .text(...)`.

1. Copy `AudioMatorTests/Fixtures/Audio/testAudioFile.flac` to a temporary writable URL.
2. Save its original bytes.
3. Run:

```swift
try TagLibMetadataManager.applyMetadataPatch(
    MetadataPatch(fields: [.comment: .text("Probe Comment")]), to: url
)
```

Expected: successful commit and `readMetadataResult(from: url).comment == "Probe Comment"`.

Observed: `verificationFailed(["Patched native comment collection differs after save."])`; bytes remain unchanged. This is reproducible independently of AudioMator's payload mapping. The raw `COMMENT` alternative does not establish a valid semantic fix and is not used as an automatic fallback.

Package-owner coverage should set, replace and clear FLAC comments, verify exact readback, cover pre-existing native comments/multiple values, and assert original-byte preservation on rejection. `TagLibUpgradeContractTests.testFLACSemanticCommentSetReplaceAndClearContract` retains the desired success contract and verifies byte preservation before rethrowing the current failure. It stops at the first failed set; replacement and clear assertions cannot be reached until the package fix is available.

Do not silently retag 0.6.0 or substitute a branch/local checkout. Adopt an independently released package fix through the normal exact-pin upgrade process, then rerun the complete suite before merging.

## Validation

All Xcode commands use stable `/Applications/Xcode.app`, `AudioMator.xcodeproj`, scheme `AudioMator`, and `.deriveddata-codex`. App-hosted tests use `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1` and `CODE_SIGNING_ALLOWED=NO`. Only the test host was launched; no interactive app launch or UI automation occurred.

- Dependency resolution: passed for remote 0.6.0. The first sandboxed attempt could not write SwiftPM/Clang caches; repeating with appropriate access succeeded.
- `swift test --filter AudioMatorCoreLogicTests`: 62 tests passed, zero failures. Log: `.deriveddata-codex/upgrade-060-core.log`.
- Final full serial app-hosted run: 499 tests, 494 passed, five failed. Log: `.deriveddata-codex/upgrade-060-final-tests.log`.
- The five failures all report the same FLAC semantic comment verification error: the new direct contract test plus `testEraseAllMetadataClearsCommonFieldsAcrossWritableAudioFixtures`, `testFieldTransferCutNumberWithoutTotalRoundTripsOrPreservesFileOnFailure`, `testFieldTransferPaddedTextAndWhitespaceOnlySourceOnDisk`, and `testFieldTransferTextMatchesPreviewOnDisk`.
- Both same-inode replacement tests passed, including typed/raw rejection and raw-editor baseline checks. All 29 conflict-strategy tests passed; existing same-audio metadata-only positive controls and final-version race rejection remain enabled. Unavailable M4A continuity, existential dispatch, exact pins, total-only provider/CSV writes and the gated artwork decoder passed.
- Intermediate runs exposed stale 0.5.3 assertions and missing guarded overload forwarding in a test double; these were repaired. One newly added test initially omitted `try` in an assertion and was corrected before the full run completed.

Commands (with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`):

```bash
xcodebuild -resolvePackageDependencies -project AudioMator.xcodeproj -scheme AudioMator -derivedDataPath .deriveddata-codex
swift test --filter AudioMatorCoreLogicTests
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'platform=macOS' -derivedDataPath .deriveddata-codex -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 CODE_SIGNING_ALLOWED=NO test
bash scripts/codex-build.sh --force
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Release -destination 'generic/platform=macOS' -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build
```

The first 498-test full run preceded a final Inspector-reset/deinit cancellation hook and a test-only actor annotation. A subsequent focused run passed 17 tests covering artwork concurrency/preview, rename refresh safety, test-host isolation and pin disclosures (log: `.deriveddata-codex/upgrade-060-final-focused.log`). After the number-only correction below and cancelled-import error guard, the final Debug (`bash scripts/codex-build.sh --force`) and generic macOS Release builds both succeeded. Logs: `.deriveddata-codex/upgrade-060-debug.log` and `.deriveddata-codex/upgrade-060-release.log`. Neither reported a Swift compile warning; both reported the AppIntents metadata-extraction notice because the app has no AppIntents framework dependency.

A final preservation probe discovered another app integration error: semantic number-only text cleared existing track/disc totals on all six fixtures (12 failed assertions), while the legacy `writeTrackNumberText` method preserved them. The edit model intentionally retained the totals for CSV/filename imports. The adapter now includes those model totals explicitly in its complete-pair semantic patch. `testSemanticNumberOnlyEditsPreserveExistingTotals` covers track/disc values and unchanged titles across all six formats. The probe failure is retained in `.deriveddata-codex/upgrade-060-number-preservation.log`; the final 499-test full run includes the corrected regression and it passes.

The focused command selects `ArtworkImportConcurrencyTests`, `InspectorArtworkPreviewTests`, `RenameRefreshSafetyTests`, `TestHostIsolationTests`, and `TagLibUpgradeContractTests/testExactDependencyPinMatchesProjectAndCurrentDisclosures` with the same serial Debug test command above. The final rerun after the cancelled-import error guard passed all 17 tests. `git diff --check` and local file-link checks for changed Markdown documents also pass.

## Legal and Network Review

The public 0.5.3 and 0.6.0 manifests reference the identical TagLib 2.3.1-r2 dynamic artifact and checksum `d7a36b2492266a17fcd97bd776cd841d9fc85275270bc0c3cb9621395b3178c7`. The 0.6.0 MIT license matches the bundled `TagLibAudioMetadata-MIT.txt`. Existing TagLib/utfcpp license texts therefore remain appropriate; the package acknowledgement version and notices were updated. No application network behavior changed.

Sources: [0.6.0 release](https://github.com/ChrisLloydME/TagLibAudioMetadata/releases/tag/0.6.0), [audio continuity contract](https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/0.6.0/docs/AUDIO_CONTENT_CONTINUITY.md), [0.6.0 manifest](https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/0.6.0/Package.swift), [0.5.3 manifest](https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/0.5.3/Package.swift), [MIT license](https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/0.6.0/LICENSE).

## Remaining Evidence Gaps

No new memory experiment was performed for retained artwork/baselines, so no arbitrary eviction or cap was introduced. Synchronous commit timeout behavior remains the existing design. AIFF/Opus fixtures, live networks, OS-level bookmark/provider integration, network-volume races and manual UI acceptance remain outside this run. The gated artwork test checks execution placement and responsiveness, not real-image latency or clipboard-provider behavior. Existing test-target actor-isolation warnings remain; production compilation must not add suppressions.

## Commit Sequence

1. `d6aff29e` — Upgrade the exact dependency and version disclosures.
2. `608eac6d` — Add audio-identity guarded rebases, total-only pairs, existential dispatch and regression coverage.
3. `79942912` — Move artwork normalization and post-rename reloads off the main actor.
4. `d4e29dc9` — Preserve retained totals in semantic number-only imports.
5. `de56362f` — Ignore errors from cancelled artwork imports.
6. The documentation commit containing this record reconciles current guidance and records final validation and the unresolved upstream blocker.
