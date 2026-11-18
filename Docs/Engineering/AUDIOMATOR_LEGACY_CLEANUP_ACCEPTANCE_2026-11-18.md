# AudioMator legacy cleanup automated acceptance

Date: 2026-11-18. Status: dated engineering record. This record documents the automated acceptance evidence for the accumulated-code cleanup campaign on branch `codex/audiomator-legacy-cleanup-20261117`, and explicitly separates what the automated gate proves from what remains unexecuted or unresolved. It is not a current behavior contract; current guidance is in `Docs/Product`, `Docs/Architecture`, `Docs/Development`, `Docs/Reference` and `Docs/Security`.

Related records: [cleanup ledger](AUDIOMATOR_LEGACY_CLEANUP_LEDGER_2026-11-18.md), [cleanup plan](AUDIOMATOR_LEGACY_CLEANUP_PLAN_2026-11-17.md), [agent handoff prompt](AUDIOMATOR_LEGACY_CLEANUP_AGENT_PROMPT_2026-11-17.md), and [Engineering Notes index](README.md).

## 1. Identity and status

| Item | Value |
| --- | --- |
| Repository | AudioMator (this repository only) |
| Branch | `codex/audiomator-legacy-cleanup-20261117` |
| Baseline | `origin/main` `f36c2a2e` (2026-11-17), verified by `git merge-base origin/main HEAD` |
| Tested source revision | `28fe62a6914eab51e1be5e38b499cd91a975eaeb` (`28fe62a6`), recorded in `source.txt` |
| Tracked worktree at test time | clean (`git diff` empty; the SHA-256 in `source.txt` is the hash of an empty diff). The two handoff documents remain untracked by design. |
| Branch commits at that revision | 27 commits relative to `origin/main`. The handoff brief stated 28; the repository value is 27. This documentation commit follows the tested revision. |
| Dependency source | Published `Package.resolved` (normal project resolution; no local-package override) |
| Evidence directory | `.deriveddata-codex/Validation/20261118-104501-44211/` (git-ignored) |
| Gate result | `EXIT:0`; all phases passed |

The final gate command was:

```bash
bash scripts/validate-release.sh
```

It ran, in order, the policy tests, the SwiftPM core tests, the complete serial app-hosted suite through `xcodebuild` against the normal Xcode project using the published package resolution, a Release build, and the unsigned artifact validator. The exact expanded commands are the ones in [the build documentation](../Development/BUILD.md) and [the testing documentation](../Development/TESTING.md); the script is the canonical gate.

## 2. Dependency pin unchanged

| Item | Value |
| --- | --- |
| Package | `TagLibAudioMetadata` published exact version `0.8.1` |
| Revision | `b8ed5475761cb50bacdd7dcd4f6e2f61142303d0` |
| Mapping contract | `AM-TLAM-MAPPING-2.2` |
| `Package.resolved` origin hash | `05a92ac75743955086ea6bc0d6e66861ee659da97a5558d9ba22a385aed126bb` |
| TagLib binary | checksum-pinned 2.3.1 revision 2 asset, unchanged |
| Local package override | none; `--local-package` was not used for this acceptance |

`Package.resolved` is unchanged by the campaign. No package checkout, cache, resolved source, `Package.resolved` payload or binary asset was modified. `Package.swift` changes were limited to the in-repository Foundation-only fast-test harness: the source list went from 31 to 30 files and redundant `exclude` entries were reduced; the package dependency and app target graph were untouched.

## 3. Removed debris by area and commits

The campaign changed 117 tracked files: 108 modified, 8 deleted, 1 added; +3,046 / −8,544 lines overall (including the localization-catalog prune). Eight tracked files were deleted and one shared persistence file was added. The candidate-level detail, including every retained or deferred candidate, is in the [cleanup ledger](AUDIOMATOR_LEGACY_CLEANUP_LEDGER_2026-11-18.md).

| Area | Representative removals | Commits |
| --- | --- | --- |
| App/Core/platform | Dead window-title statics, `MacPasteboard.image`, `NSImage.audiomatorPNGData`, three `NSColor` aliases, test-only `AudioTagNumberText.parsedPair`, unused `AppWindowTitle.rawMetadata`; 2.2 MB `AppIconPreview` imageset. | `e58fa61f` |
| Domain | Six legacy pipeline protocol surfaces (`writeTrackNumberText`, scalar raw property maps, no-version write/erase, `numberingInventory(at:)`; the separate unguarded payload initializer remains deferred), `FileCollectionCore`, dead merge/artwork helpers, `isExplicit` mirrors, unused Combine imports, exchange/template members, rename status/sanitizer/tokenizer duplication, number display projection, palettes. | `623ed1d8`, `2af7fb70`, `ae07d55f`, `97016668`, `fde7ecb7`, `f1ff0892`, `88d971b1`, `3d3b458f` |
| TagLib adapter | One throwing `metadataPatchForWrite(from:)` replaces the pure/throwing pair; legacy number-text route and warning helpers; scalar property-map read/write and conversion helpers; pipeline inventory forwarding; five dead date-projection overloads; stored inventory snapshot state; redundant artwork branch. | `c63882cb`, `97016668`, `fde7ecb7`, `f1ff0892`, `b6b07d4f`, `20532f7e` |
| File system and updates | Shared bookmark-collection persistence replaces two duplicated stores; unread load-state payload dropped; pre-Swift-6.2 deinit fallback removed; unused release-metadata fields removed. | `c3425cb7`, `6ce7f020`, `d60400a0` |
| Providers and browser features | Dead store members, dead query/model helpers, unused view initializers, duplicate field-order helper and dead AppKit helpers removed; comparison/query boundaries and routes retained. | `e993270e` |
| Features/Main | Unreachable views (`InspectorPopup`, `MergedMetadataSectionView`, `MiddleListHeaderContextMenuInstaller`), orphaned import-writer route, dead file-action/result/state helpers, duplicate batch-summary presenter, unreachable search-seed branch. | `0be0b842`, `2eb51315`, `2af7fb70`, `e6828955`, `c44b6d3e`, `a9e83a2c` |
| Metadata Editor, Filename tool, Settings, Inspector | Unreachable `MetadataInspectorSheet`, superseded SwiftUI preview clusters, dead editor fallbacks/storage, unused About helper and dead status guards. | `2deff969` |
| Localization | 91 unreferenced or superseded catalog keys pruned (952→861); locale slots and translations retained. | `28fe62a6` |
| Tests/build/scripts | Test-only compatibility scaffolding migrated or removed with its production surface; unused fake member and factory parameters; documented `--full` alias; redundant SwiftPM excludes. | `7662fc26`, `ae07d55f`, `97016668`, `fde7ecb7`, `f1ff0892`, `e6828955`, `2af7fb70`, `dcae77f3`, `bd149370` |

The eight deleted tracked files were `AppIconPreview.imageset/AppIconPreview.png`, `AppIconPreview.imageset/Contents.json`, `Domain/FileSources/FileCollectionCore.swift`, `Features/Main/ViewModels/AudioViewModel+MetadataFieldImportWrite.swift`, `Features/Main/Views/InspectorPopup.swift`, `Features/Main/Views/MergedMetadataSectionView.swift`, `Features/Main/Views/MiddleListHeaderContextMenuInstaller.swift` and `Features/MetadataInspector/Views/MetadataInspectorSheet.swift`. The added file is `Infrastructure/FileSystem/BookmarkCollectionPersistence.swift`.

## 4. Retained user-data compatibility and protections

The campaign removed obsolete internal Swift API compatibility only. It did not remove or rename persisted user data or user-file formats. Retained and protected in the tested revision:

- persisted preference/bookmark state: `hasLaunchedBefore`, watched-folder and file-access-grant bookmark records and keys, `metadata.conflictPolicy`, `settings.selectedTab` legacy aliases, welcome completion/version keys, suppress-discard warning, MuseAmp compatibility and the MuseAmp ID algorithm/JSON in user comments;
- file-format/user-data compatibility: CSV header aliases (`DATE`=YEAR rule), exchange profile v1/v2 markers and `<remove>` semantics, unknown-version rejection and resource limits, independent YEAR/DATE/RELEASE DATE/ORIGINAL RELEASE DATE identities, ID3 versions, private numbering provenance handling and best-effort erase behavior;
- integrity protections: guarded writes fail closed, exact raw deltas, expected-version and fingerprint/audio-identity guards, no commit retry or version clearing, `FileMutationCoordinator` reservation ownership, committed-but-durability-uncertain reporting, bounded reload with stale-result rejection, and fail-closed `refreshRequiredFileIDs` recovery;
- provider/state protections: bounded provider fan-out and fallback order, cancellation/late-result rejection, captured write plans with unchecked-field preservation, single selection owner, batch-summary cancellation semantics and HUD vocabulary;
- dependency, legal and localization protections: package pin and mapping contract unchanged, license resources and disclosures unchanged, 25 dynamic field-label keys and dormant locale translations retained.

The ledger’s retained-candidate register (§4) records the consumer and invariant for each retained candidate family; the audits’ per-file evidence is normalized in §2 of the ledger.

## 5. Actual fixed defects

One fixed defect is claimed, evidenced by a behavior change and a regression test. No other fixed defect is claimed; the rest of the campaign was intended to be behavior-preserving.

**Fixed defect — unsupported advisory import on the conflict path returned a no-write success.** At the baseline, `MetadataConflictResolver.writeMetadata` planned a patch with the non-throwing `TagLibAudioMetadataPipeline.metadataPatchForWrite(from:)` builder. If the only unresolved pending change was an unsupported content-advisory import (`MetadataEditPayload.unsupportedAdvisoryImport != nil`) while the file revision was unchanged, the planned semantic patch could be empty, and the resolver returned a no-write success instead of rejecting the unsupported advisory code. Commit `c63882cb` consolidated the two builders into one throwing `metadataPatchForWrite(from:) throws` that validates `unsupportedAdvisoryImport` before encoding, and the conflict resolver now calls it with `try` on both planning paths (unchanged-revision and conflict-merge). An unsupported advisory import therefore throws `CocoaError(.featureUnsupported)` before any write or conflict inspection. Commit `726e6ec9` added `MetadataConflictStrategyTests.testConflictWriteRejectsUnsupportedAdvisoryImportWithoutTouchingTheFile`, which asserts the thrown domain/code and exact user message, unchanged file bytes and unchanged package file version. The two semantic write entry points already funnelled through the same validation; the consolidation did not add a write-path fallback or file I/O during planning.

Everything else recorded as `refactor`, `build`, `style`, `chore` or `test` is a cleanup or coverage change, not a defect claim. In particular: the removed legacy number-text route and raw property-map route had zero production callers; the removed file-system persistence code is behavior-preserving by its tests; and the deferred candidates in the ledger are not defect fixes.

## 6. Deleted-test and rewritten-assertion replacement coverage

Test inventory moved from 622 app-hosted tests at baseline to 629 at the tested revision (+7 net), and core tests stayed at 62. The net change is: +3 regression tests in `726e6ec9`, +4 GitHub-client tests in `d60400a0`, +2 stale-bookmark-refresh tests in `c3425cb7`, −1 orphaned import-writer test in `e6828955`, and −2 legacy number-text tests +1 typed-path replacement test in `97016668`.

| Removed or rewritten coverage | Commit | Replacement evidence |
| --- | --- | --- |
| `InspectorAndMetadataEditorWorkflowTests.testImportMetadataFieldValuesWritesChosenFieldInTargetOrderAndRefreshesLoadedFiles` (orphaned route) | `e6828955` | Retained plan-write routes assert ordered per-file writes and refresh: `testApplyFilenameMetadataPlanWritesExtractedFieldsAndRefreshesSelection`, `testApplyMetadataExchangeWriteEntriesWritesImportedFieldsAndRefreshesSelection`, `testApplyMusicBrainzTaggingPlanPreservesFieldOrderAndRefreshesSelection`, plus `MetadataSaveJourneyTests` provider/editor journeys. |
| `TagLibReadWriteIntegrationTests.testTrackAndDiscTextWritesRoundTripNumericValuesAcrossWritableAudioFixtures` and `testTrackNumberOnlyWriteDoesNotWarnWhenExistingTotalIsPreserved` (legacy route only) | `97016668` | New typed-path regression `testTrackAndDiscNumberIntentWritesRoundTripNumericValuesAcrossWritableAudioFixtures`; number-only preservation remains covered by `TagLibUpgradeContractTests.testSemanticNumberOnlyEditsPreserveExistingTotals` and the boundary/save-journey suites. The deleted branch had no production consumer. |
| 14 raw property-map read assertions and the property-map half of the existential dispatch assertion | `fde7ecb7` | Rewritten in place as exact `RawMetadataValueMap` array assertions (order, duplicates, removals and opaque values preserved); `TagLibUpgradeContractTests` keeps the value-map delta contract. No test function was deleted. |
| Two `numberingInventory(at:)` adapter assertions | `f1ff0892` | Rewritten to call `TagLibMetadataManager.numberingInventory(at:)` directly, the same package boundary the production loader uses; behavioral claims unchanged. |
| 20 no-version write/erase pipeline call sites | `ae07d55f` | Mechanical migration to explicit `expectedVersion:` on the retained requirements; no assertion change. |
| 24 forced `writeTrackNumberText` fake methods in 15 test files | `97016668` | Removed with the protocol requirement; remaining fakes conform only to retained requirements. |
| Two core helper tests (`AudioMetadataModelCore` merge/artwork decisions and `FileCollectionCore`) | `88d971b1` | Two replacement core tests keep the 62-test floor: retained `mergedValue` behavior and `AudioFileFingerprint` equality/hashing. |
| Seven tests calling the pure patch builder | `c63882cb` | Rewritten to call `try` on the single throwing builder; assertions unchanged. |
| `removeFromList` test call | `2af7fb70` | Migrated to the retained `removeQuickImportFile(id:)`; selection/draft pruning assertions unchanged. |
| `didReloadFile` and `rollbackError` assertions | `2af7fb70`, `2eb51315` | Migrated to `reloadedFile`/`reloadErrorDescription` and `rollbackErrors`; nothing became untested. |
| Assertions in `InspectorFieldConfigurationTests` and `FileRenameTransactionTests` that referenced removed helpers | `2eb51315` | Updated to retained field-guide names and `rollbackErrors`; the four frozen editor/Inspector critical identities stayed in the gate set. |

No test was skipped, marked as an expected failure or deleted merely to pass the gate. The evidence gate still requires exact source-to-`xcresult` identity equality, the frozen CRITICAL identities, the 579 app-test floor, and the 62 core-test floor.

## 7. Verification commands, results and evidence

| Phase | Command (expanded by the gate) | Result | Evidence file |
| --- | --- | --- | --- |
| Policy | `python3 -m unittest discover -s scripts/tests` | 13 tests passed, `OK` | `policy.log` |
| Core | `swift test --filter AudioMatorCoreLogicTests` | 62 expected / 62 executed, 0 missing, 0 unexpected, accepted | `core.log`, `core-gate.json` |
| App-hosted | `xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'platform=macOS' -derivedDataPath .deriveddata-codex -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -resultBundlePath … CODE_SIGNING_ALLOWED=NO test` | 629/629 passed; 0 failed, 0 skipped, 0 expected failures; `Executed 629 tests, with 0 failures (0 unexpected) in 169.455 (169.754) seconds`; `** TEST SUCCEEDED **` | `app.log`, `test-summary.json`, `test-tree.json`, `test-gate.json`, `AppTests.xcresult` |
| Release build | `xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Release -destination 'generic/platform=macOS' -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build` | `** BUILD SUCCEEDED **` | `release.log` |
| Artifact validation | `bash scripts/validate-macos-artifact.sh .deriveddata-codex/Build/Products/Release/AudioMator.app 15.0` | Validated bundle minimum 15.0 and 2 Mach-O files (`AudioMator` minOS 15.0; packaged TagLib framework minOS 13.0) | `artifact.log` |
| Source identity | recorded by the gate | HEAD `28fe62a6914eab51e1be5e38b499cd91a975eaeb`; published `Package.resolved`; clean tracked diff | `source.txt` |
| Gate runner exit | `bash scripts/validate-release.sh` | `EXIT:0` | `.tmp/cleanup/final-gate-1.log` (local run log) |

The gate prints “Debug test gate passed (published Package.resolved); interactive UI acceptance remains manual” only for `--tests-only`; the canonical run used above also ran Release and artifact phases and printed “Build/test gate passed (published Package.resolved); interactive UI acceptance remains manual.” The evidence directory contains no failure/skip records: `test-summary.json` reports `failedTests: 0`, `skippedTests: 0`, `expectedFailures: 0`, and the gate accepted the exact 629-name inventory with no missing or unexpected identities. The policy phase log ends with `Ran 13 tests … OK`; the core gate JSON and test gate JSON both report `accepted: true` with empty `missing`/`unexpected` arrays.

Baseline comparison: `.deriveddata-codex/Validation/20261118-094024-15062/` records the pre-cleanup Debug-only gate at `f36c2a2e`: 13 policy, 62 core and 622 app-hosted tests, `EXIT:0`, Release/artifact skipped by request. The campaign therefore increased app coverage from 622 to 629 and kept core coverage at 62.

## 8. Test inventory at the tested revision

Recounted from source with the release-gate inventory rule (files under `AudioMatorTests`; attribute each `func test…` to the preceding `XCTestCase` class): 629 source-declared tests, 80 `XCTestCase` classes and 83 Swift files. The core SwiftPM target has 62 tests in 4 classes across 3 files. The policy suite has 13 tests. `Package.swift` compiles 30 Foundation-only source files.

| App-hosted area | Files | Tests |
| --- | ---: | ---: |
| `Application/MetadataEditing` | 15 | 170 |
| `Application/MetadataExchange` | 4 | 66 |
| `Application/Rename` | 4 | 24 |
| `Application/WatchedFolders` | 4 | 23 |
| `Concurrency` | 3 | 25 |
| `Integration/Network` | 5 | 42 |
| `Integration/TagLib` | 10 | 102 |
| `Performance` | 4 | 20 |
| `Unit/Core` | 18 | 87 |
| `Unit/Presentation` | 11 | 54 |
| Root policy/inventory tests | 2 | 16 |
| `TestSupport` (helpers, no tests) | 3 | 0 |
| **Total** | **83** | **629** |

## 9. Warning, skip and expected-failure summary

- Skips: 0. Expected failures: 0. Failures: 0. No `XCTSkip`, `XCTExpectFailure`, warning suppression, test gating or reduced inventory was added by the campaign.
- The `test-summary.json` runtime-warning list contains exactly one runtime warning: the pre-existing SwiftUI warning in `OnlineMetadataWorkbenchPerformanceTests` (`Accessing State<Bool>` value before installation on a View). The same warning was recorded in the prior 0.8.1 Debug adoption evidence, so it is not introduced by this campaign.
- The Debug test build log contains 431 warning-line occurrences. Its 214 warning-location lines are all under `AudioMatorTests/` and are the known test-target isolation warning debt (XCTestCase `init()`/`init(selector:)`/`init(invocation:)` actor-isolation overrides and related `@MainActor` override notes, `TST-17` in the ledger); the remaining lines are compiler note/continuation lines plus the informational AppIntents extraction note. No app-source compiler warning is present in the final Debug build log.
- The Release build log contains eight app-source warning lines across two warning sites (four repeated diagnostic lines per site): `ActorIsolatedCall` at `AudioViewModel+FileRename.swift:474` and `ImplicitStrongCapture` at `ContentView.swift:636`. The same two warning classes at the same code sites, with line numbers shifted by the deletions, are present in the baseline Debug build log; no new app-source warning class is claimed and the campaign added no suppression. The Release log also contains the pre-existing informational AppIntents extraction note (`no AppIntents.framework dependency found`).
- The warning counts are not like-for-like between baseline and final runs because Xcode re-emits compiler diagnostics only for recompiled files in incremental builds. The record claims only what the logs show: zero skipped/expected-failure/failed tests, one pre-existing runtime warning, known isolation warnings, and no new app-source warning class evidenced.

## 10. Unexecuted and out-of-scope checks

- Interactive UI acceptance: not run. The application was not launched manually or through automation; launch, drag-and-drop, accessibility, visual layout and onboarding remain maintainer checks.
- Signing, notarization, distribution and publication: not run or claimed. The Release build was unsigned (`CODE_SIGNING_ALLOWED=NO`); no archive or Gatekeeper check was part of the acceptance.
- Local-package candidate gate: not run (`--local-package` was not used). Normal published-package resolution was verified.
- Bridge smoke tooling (`scripts/build-taglib-bridge-smoke.sh`, `scripts/taglib_bridge_smoke.mm`): not run; the tool compiles from package sources and is maintainer-only (`SCR-03`/`TST-18`).
- Live network behavior, provider service availability, iTunes/MusicBrainz/LRCLIB API drift and WebKit subresource behavior: not tested; provider tests use URLProtocol/injected fakes.
- CI runner provisioning (`xcode-27` label) and hosted-CI execution of this branch: not verified in this environment.
- Performance measurement/regression comparison: not established; the performance suites ran as work-bound regression sensors, not benchmarks.
- Deferred cleanup candidates: not implemented in this campaign; see §11 and the ledger §6/§7. Their safety is not established by this gate.

## 11. Unresolved investigate items

The campaign did not resolve every investigate item. The open items are: `APP-01` first-launch window sizing; `RES-02` AppIcon watchOS platform metadata; `PRJ-03` localization configuration intent; `PRJ-04` build-number documentation drift; `SCR-03`/`TST-18` bridge smoke tooling; `INF-08` package durability-throw reachability; `ITC-1` test-only iTunes provider core; `MF-08` skipped-row fallback text; `WEL-04` onboarding localization; `HLP-02` Domain label-catalog drift; `X-06` editor state placement; `FM-I01`–`FM-I09` feature/state investigations; `TST-11` CI core duplication; and `TST-17` test-target isolation warning debt. The exact unknown and smallest resolution for each is recorded in the ledger §5. `TST-17` is a build-setting decision and was not used to justify suppressing or skipping any warning.

Deferred but decided cleanup candidates (not investigations): the ledger §6 lists remaining material duplication and §7 lists the 33 audit-proposed changes not implemented, with reasons. They are explicit backlog, not completion claims.

## 12. Acceptance statement

The automated gate for the code-complete revision `28fe62a6` passed and its evidence is recorded above. This record is not yet the campaign’s final acceptance statement, because the documentation revision produced after the code-complete revision must run the same gate before the campaign can be finalized.

> **Placeholder — to be completed by the Lead after the final docs-revision gate.** automated cleanup acceptance passed for `<final-docs-revision>` on `<date>`, with evidence `<validation-directory>`: 13 policy tests, 62 core tests, 629/629 serial app-hosted tests passed, 0 failures/skips/expected failures, Release build passed, artifact validation passed, and gate exit status 0. The retained-behavior and user-data protections in [the cleanup ledger](AUDIOMATOR_LEGACY_CLEANUP_LEDGER_2026-11-18.md) §4 remain in force. Manual UI acceptance, signing, notarization and distribution remain out of scope.

A further final release-gate run on the committed docs revision follows. If that run fails, this record must instead state “not accepted/blocked” with the exact failing phase, and the placeholder above must not be finalized as a pass. The Lead owns that final gate and final statement.

## 13. References

- [Cleanup ledger](AUDIOMATOR_LEGACY_CLEANUP_LEDGER_2026-11-18.md): file audit, candidate/decision ledger, retained register, investigate register and remaining duplication.
- [Cleanup plan](AUDIOMATOR_LEGACY_CLEANUP_PLAN_2026-11-17.md) and [agent handoff prompt](AUDIOMATOR_LEGACY_CLEANUP_AGENT_PROMPT_2026-11-17.md): preserved 2026-11-17 handoff documents, not current behavior contracts.
- [Engineering Notes index](README.md).
- [Testing](../Development/TESTING.md), [Build](../Development/BUILD.md), [Metadata Pipeline](../Architecture/METADATA_PIPELINE.md), [Dependency Rules](../Architecture/DEPENDENCY_RULES.md), [Project Structure](../Reference/PROJECT_STRUCTURE.md), [Security and Data Integrity](../Security/SECURITY_AND_DATA_INTEGRITY.md).

