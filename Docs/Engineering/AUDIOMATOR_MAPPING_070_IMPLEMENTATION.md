> Superseded candidate status: [0.7.1 joint acceptance](MAPPING_071_JOINT_ACCEPTANCE.md). Earlier 0.7.0 blocker findings remain historical evidence; do not read them as current candidate results.

# AudioMator TagLibAudioMetadata 0.7.0 / mapping contract 2.2 implementation ledger

Date: 2026-11-09. Branch: `codex/metadata-mapping-spec`. This is a dated implementation record for the
application adoption of **TagLibAudioMetadata 0.7.0** and **`AM-TLAM-MAPPING-2.2`**. It is not a
cross-repository conformance claim: the package owns native mapping and verification, AudioMator owns edit
intent and presentation.

## Baseline (before implementation)

| Item | Baseline value |
| --- | --- |
| Package pin | exact `0.6.0`, revision `c135fe0a3c52ba76054731e2afe3e56b83f6d40e` |
| Build settings | macOS 15.0 deployment target, Swift 5 language mode, complete strict concurrency, MainActor default isolation |
| Dirty worktree | none at start (`git status --porcelain` empty) |
| Debug build | not rerun against 0.6.0 in this session; the first build after the pin change is recorded below |
| SwiftPM core tests | not reused from history; final run below |
| App-hosted suite | not reused from history; final run below |

The 0.6.0 baseline is historical. Current results are recorded under "Verification evidence" below and were
re-run after the change; they are not inherited from earlier records.

## Route inventory (semantic vs raw)

| Route | Entry point | Intent model | Classification |
| --- | --- | --- | --- |
| Inspector single edit | `InspectorPane` → `SingleFileEditModel` → `MetadataEditPayload` | semantic | migrated to `.year`, `.standaloneDate`, `.releaseDate`, `.originalReleaseDate` |
| Inspector multi edit | `MultiFileEditModel` → `SingleFileEditModel` → payload | semantic | independent date fields and mixed tracking added |
| Metadata Editor (raw) | `MetadataEditorWindow` → `RawMetadataPatch` | raw | unchanged low-level exception; label stays raw |
| CSV / text exchange | `MetadataExchangePlanner` → `MetadataExchangeWriteEntry` → `SingleFileEditModel` | semantic | versioned profile with independent date columns |
| Field transfer | `MetadataFieldTransferPlanner` | semantic | independent date identities added |
| Filename extraction | `FilenameMetadataExtractionCore` / `FileRenameMetadataField` | semantic | YEAR token stays stored YEAR; separate date tokens added |
| Renumbering | `AudioViewModel+TrackRenumbering` | semantic | component-aware number intent, totals preserved |
| MusicBrainz apply | `MusicBrainzProviderCore` / tagging workbench | semantic | provider release date targets RELEASEDATE only |
| iTunes apply | `iTunesProviderCore` / tagging workbench | semantic | provider release date targets RELEASEDATE only |
| Raw property-map editor | `MetadataEditorWindow` | raw | explicit raw delta and baseline; reserved native-number keys stay reserved |
| Number cleanup | `NumberNormalization` preview/apply | structured package plan | new focused action; captured plan, no regeneration |

Prior Year/date projections found by audit: `MetadataEditPayload.year` → `.date`; `BasicMetadata.year` used for
display; `releaseDate` → `.releaseDate`; provider release date → `releaseDate`; filename `%year%` →
`SingleFileEditModel.year`; CSV `year`/`releaseDate` columns; conflict group `[.date, .releaseDate]`. All
semantic `.date` uses are replaced with `.year`. Raw PropertyMap `DATE` behavior remains raw-only and is
labelled as the engine dialect.

## Acceptance ledger

Status values: **complete** (implemented and verified), **partial** (implemented with a stated empirical or package gap), **blocked** (external), **not run**. Code completion is separate from package-level empirical coverage.

| ID | Requirement | Implementation | Evidence | Status |
| --- | --- | --- | --- | --- |
| A01 | Exact 0.7.0 pin/revision/disclosure, contract capability, no path override | `project.pbxproj` exact 0.7.0; `Package.resolved` revision `0f89fbe8…`; `LicenseDisclosure` 0.7.0; AGENTS/BUILD/CONFIGURATION/notices updated | `TagLibUpgradeContractTests.testExactDependencyPinMatchesProjectAndCurrentDisclosures` asserts version, revision, remote URL, absence of `XCLocalSwiftPackageReference`, contract 2.2, YEAR/DATE identities, MP4 DATE write target and RATE read-only | complete |
| A02 | Six committed formats, independent dates, per-version Date shape, field-scoped set/clear | `.year`/`.standaloneDate`/`.releaseDate`/`.originalReleaseDate` intents; `TagLibDateCompanion` alias coexistence; native oracles in tests | `TagLibDateMappingIntegrationTests` (all six formats, full example, per-field set/clear, MP4 Year) and `TagLibReadWriteIntegrationTests` date tests | **partial**: complete for MP3/M4A/FLAC/Ogg/AAC/WAV with 0.7.0; **ID3v2.3 TDAT/TDRL blocked** (safe rejection, unchanged bytes) |
| A03 | Full YEAR text survives read/copy/unrelated edit/export/reload | Basic YEAR read directly; no `prefix(4)`; conflict comparison uses native year | `TagLibDateMappingIntegrationTests.testFullYearTextSurvivesCopyUnrelatedEditExportAndReload`; `MetadataExchangeField.year` carries `2004-07-15` | complete |
| A04 | Inspector/multi-edit unchanged/set/remove/mixed for four dates; MP4 Year editable; all-or-nothing rejection | `InspectorMetadataField` date rows, `MultiFileEditableTextField` cases, payload per-field deltas, capability gating and container section | `IndependentDateIntentTests` (single/mixed/set/remove/multi apply), `TagLibDateMappingIntegrationTests.testMP4YearIsEditable…`, existing workflow suites | complete |
| A05 | Providers change only selected RELEASEDATE and explicit fields | Provider stores map release date to `edit.releaseDate` only; local comparison no longer falls back to YEAR; shared payload pipeline | `IndependentDateIntentTests.testProviderReleaseDateApply…`; `TagLibMappingContractIntegrationTests.testProviderReleaseDateExecutionLeavesOtherDatesAndReloads` | complete (mocked provider values; no live network) |
| A06 | Versioned CSV/text round-trip four dates and advisories; omitted vs remove; legacy/remap; unknown profile; preview matches save | `MetadataExchangeProfile` v2 marker, independent columns, unquoted `<remove>` sentinel vs quoted literal, legacy DATE header guard, unknown-version rejection; date/filename tokens | `MetadataExchangeProfileTests` (6 tests); `TagLibMappingContractIntegrationTests.testExchangeDateEntryAppliesAndWritesOnlyThatDate`; rename template tests | complete |
| A07 | Number component preservation across formats | Typed `.track`/`.trackTotal`/`.disc`/`.discTotal` deltas; only changed components submitted; totals preserved; unsupported layouts reject | `TagLibMappingContractIntegrationTests.testNumberComponentEditsPreserveUntouchedComponents` on all six fixtures; `TrackRenumberExecutionTests` | complete |
| A08 | Native vs legacy total conflicts surfaced; no guessing; private/lookalike handling | `numberingInventory` exposed on `AudioFile`; ambiguous candidates block component edits; lookalike keys preserved; no broad cleanup | `TagLibMappingContractIntegrationTests.testLegacyTrackTotalRecovery…`, `testAmbiguousLegacyTotalsAreSurfaced…`, `testTrackCleanupPreservesDiscGroup…` | partial: private-atom seeding through the public API is refused, so exact four private identities were not fixture-seeded |
| A09 | Cleanup preview/apply uses same captured plan; stale plan rejects; track preserves disc; no implicit private cleanup | `NumberNormalizationPreview` captures package plan/version; Apply refuses regeneration; Inspector sheet; stale version rejected | `testLegacyTrackTotalRecoveryAndCapturedPlanCleanup`, `testTrackCleanupPreservesDiscGroup…`; `TagLibNumberNormalizationSheet` UI | partial: same private-atom seeding gap; plan/version/group behavior is verified |
| A10 | Advisory absent/0/1/2 and unknown preservation | `ContentAdvisory` four-state intent, `advisoryRawValue` display/preservation, typed `explicitAdvisory` patch, export carries exact raw code | `TagLibMappingContractIntegrationTests.testAdvisoryStatesRoundTripAndUnknownCodeIsPreserved` (including explicit removal of unknown code 4) | complete |
| A11 | MP4 exclusive typed shapes/capabilities; RATE read-only; MKV not advertised | Typed `ContainerFieldValue` editor/capability classification for all 26 registered exclusives; typed patch path; present zero/false; unknown media code; RATE classified read-only; Matroska TV unsupported | `testMP4ExclusiveTypedShapesAndReadOnlyRate` (including `tvsn=0`, `pgap=false`, `stik=4`, 26-field classification); registry queries | complete (MP4 fixture; MKV availability is a negative capability test) |
| A12 | contentGroup/grouping/work independent; raw DATE meaning; arrays/artwork preserved | Separate model properties/payload fields; raw DATE remains a raw dialect; custom arrays/artwork untouched by typed date edits | `testContentGroupGroupingWorkAreIndependent`, `testRawDateKeepsPropertyMapMeaning…`, `testDateEditPreservesCustomArraysAndArtwork` | complete |
| A13 | Existing conflict/replacement/cancellation/durability behavior; independent date groups; shared number pair protected | `MetadataConflictResolver` date groups use native projections; number pair group retained; version/audio/same-entry guards unchanged | `testIndependentDateConflictDoesNotBlockYearEdit`, `testSharedNumberPairConflictStillBlocksAComponentDraft`, `MetadataConflictStrategyTests` (29), existing replacement/cancellation suites | complete |
| A14 | Debug/Release builds, core tests, focused and full serial app-hosted suite, docs | Builds and suites run with stable Xcode; docs updated; ledger linked | See "Verification evidence" | complete |

## Package defect disclosures

These are external 0.7.0 limitations. AudioMator fails safely and the tests assert unchanged bytes rather than hiding the failure.

| Area | Observed | AudioMator behavior |
| --- | --- | --- |
| FLAC semantic `.comment` write | `verificationFailed(["Patched native comment collection differs after save."])` | Rejects; bytes unchanged; no raw fallback |
| ID3v2.3 TDAT/TDRL | TagLib flattens TYER+TDAT into TDRC; `.standaloneDate` reads empty; writes fail verification | Rejects; YEAR remains writable; no coercion |
| YEAR/DATE PropertyMap alias | DATE writes/removals can trip “Unedited PropertyMap field DATE changed” or Xiph YEAR writes drop DATE | Narrow `TagLibDateCompanion` repeats the exact captured sibling; ambiguous siblings fail safely |
| ID3 `musicBrainzTrackID` removal | Bridge reports an invalid ID3 frame ID | The app does not force this removal |
| Formatted number text `7/0` | Rejected as `ambiguousNumberRecovery(..., identities: [])` | Typed component path is used; text is not repaired or guessed |
| Private number-text seeding | Public custom-field writes to `AUDIOMATOR_*`/`TAGLIBAUDIOMETADATA_*` fail verification | Preserved when present; no new private atoms are created; exact seeding coverage gap remains |

## Verification evidence

Run on 2026-11-09 with stable `/Applications/Xcode.app` (Xcode 27.2, build 27B52; Apple Swift 6.4.2), `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, branch `codex/metadata-mapping-spec`, base commit `906bbbab`. The sandbox denied SwiftPM/Clang caches under `~/Library`, so the commands below were rerun with cache access; this was an environment permission issue, not a project failure. Xcode builds used `.deriveddata-codex` and `CODE_SIGNING_ALLOWED=NO`.

| Check | Command | Result |
| --- | --- | --- |
| Foundation-only tests | `swift test --filter AudioMatorCoreLogicTests` | **62 passed, 0 failures** |
| Debug build | `xcodebuild … -configuration Debug -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build` | **BUILD SUCCEEDED**, no project warnings |
| Release build | `xcodebuild … -configuration Release -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build` | **BUILD SUCCEEDED**, no project warnings |
| Release artifact validation | `bash scripts/validate-macos-artifact.sh .deriveddata-codex/Build/Products/Release/AudioMator.app 15.0` | passed; bundle minimum 15.0, 2 Mach-O files |
| Full serial app-hosted suite | `xcodebuild … -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test` | **528 tests passed, 0 failures, 0 skips** |
| Date integration | `-only-testing:AudioMatorTests/TagLibDateMappingIntegrationTests` | 4 passed |
| Mapping contract | `-only-testing:AudioMatorTests/TagLibMappingContractIntegrationTests` | 13 passed |
| Existing TagLib integration | `-only-testing:AudioMatorTests/TagLibReadWriteIntegrationTests` | 35 passed |
| Dependency contract | `-only-testing:AudioMatorTests/TagLibUpgradeContractTests` | 5 passed |
| Conflict strategies | `-only-testing:AudioMatorTests/MetadataConflictStrategyTests` | 29 passed |
| Exchange profile | `-only-testing:AudioMatorTests/MetadataExchangeProfileTests` | 6 passed |
| Independent date state | `-only-testing:AudioMatorTests/IndependentDateIntentTests` | 5 passed |
| Renumber execution | `-only-testing:AudioMatorTests/TrackRenumberExecutionTests` | 6 passed |

No tests were skipped, marked expected-failure, or weakened to make the suite pass. Workflow tests that reach a documented package defect assert the safe failure and byte preservation explicitly; the dedicated package-contract canary for FLAC comments does the same. Live-network provider tests, interactive UI acceptance, signed/notarized distribution, and a macOS 15 runtime run were not executed. The TagLib bridge smoke script was not run (it crosses the package boundary).


## Supervising handoff preservation

The dsh wrap-up turn was interrupted after receiving the maintainer steer. See [the preserved outstanding-issue register](AUDIOMATOR_MAPPING_070_HANDOFF.md) for all six disclosures, evidence confidence, reproductions/investigation recipes, closure criteria, and A02/A08/A09 partial status. This link does not upgrade any acceptance result or constitute independent merge approval.


## Independent acceptance update — 2026-11-10

See [the independent acceptance and repairs](AUDIOMATOR_MAPPING_070_ACCEPTANCE_2026-11-10.md). The private-field seeding gap was narrowed by successful public structured-API fixtures. The original positive FLAC comment release gate has been restored and fails on 0.7.0; earlier green negative tests do not constitute release approval.


## Mapping conformance update

[The latest mapping audit](MAPPING_CONFORMANCE_2026-11-10.md) supersedes earlier companion-workaround guidance and completion claims. Purchase Date/RATE routes and unknown-advisory handling were corrected; positive package probes confirm a YEAR write can erase independent DATE. Overall conformance remains blocked.
