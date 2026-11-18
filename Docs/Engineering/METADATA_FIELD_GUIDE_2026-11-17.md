# Metadata Field Guide verification — 2026-11-17

> Dated evidence — current behavior is documented in the [user guide](../Product/METADATA_FIELD_GUIDE.md) and the [cross-layer mapping table](../Reference/METADATA_FIELD_MAPPING_TABLE.md). The 599/602-test app-hosted inventories below are historical; the latest automated gate is the [2026-11-18 cleanup acceptance](AUDIOMATOR_LEGACY_CLEANUP_ACCEPTANCE_2026-11-18.md). Several follow-ups claim only focused-test or build verification, and no interactive visual/accessibility acceptance is claimed.

Branch: `codex/review-inspector-date-field`. Tested implementation: `593bf2c`. The final gate began before this commit was recorded; production/test/script contents were identical to the committed implementation, with only documentation changed during the run. Subsequent changes record evidence only. Published package remains exact 0.8.1; no package source or metadata write path changed.

## Delivered

Help → Metadata Field Guide opens one native, resizable reference window. A searchable list covers 100 package fields and six read-only display values. Details explain purpose, common-field availability, independent dates and grouping identities. Native mapping details are collapsed initially and come directly from the installed registry. References open in the default browser only after selection; no guide fetch, file metadata access or draft mutation is performed. The complete reference table now includes purposes and per-row primary links.

Primary sources were reviewed through official ID3.org, Xiph.Org, Apple Developer, TagLib, MusicBrainz/Picard and AcoustID documentation. Explanations are paraphrases, not copied reference pages. Application-specific date/grouping/advisory semantics are distinguished from standard terminology. Undocumented opaque encodings are not promoted to supported codecs. See [user guide](../Product/METADATA_FIELD_GUIDE.md) and [cross-layer table](../Reference/METADATA_FIELD_MAPPING_TABLE.md).

## Verification

`bash scripts/validate-release.sh --tests-only` passed against the normal published dependency: 13 Python policies, 62 core tests and **599 serial app-hosted tests**, zero failures/skips/expected failures. Both named gates accepted exact source inventories with no missing/unexpected tests. Evidence: `.deriveddata-codex/Validation/20261117-141932-60975/` (`source.txt`, `core-gate.json`, `test-gate.json`, `AppTests.xcresult`, logs). All three new field-guide tests are mandatory critical identities: enum coverage/source completeness, reference/disclosure equality, and search/date/recording distinctions.

The preceding full run executed 598 tests and failed only the old fixed network-host inventory, which had not yet been updated for the new explicitly opened help links. The exact host inventory was updated; an additional equality test now requires all guide reference hosts to match the privacy disclosure. No assertion, skip policy or gate was weakened.

The initial sandboxed build was blocked by compiler/SwiftPM cache permissions. Rerunning with appropriate cache access passed the Debug build. The final full gate also compiled the current implementation. Relative documentation file links, table width/coverage and `git diff --check` passed. The extended table contains 106 data rows and 16 columns. Existing system shortcut-service/AppIntents diagnostics and the performance suite's existing SwiftUI State warning are not claimed resolved; no new Swift compilation warning was found.

No Release build, artifact/archive validation, package tests, manual app launch or interactive UI acceptance was performed. The maintainer should check Help menu discovery, window resizing, search focus/keyboard selection, VoiceOver and light/dark appearance. Automated acceptance does not establish those visual/accessibility outcomes or exhaustively validate every external reference site's future content.

## Metadata Editor naming follow-up

Implementation `3063e7f` shares the guide's AudioMator names and purposes with Metadata Editor. Suggestions show the friendly name above `PropertyMap key · purpose`; selection retains a separate mapping key. The Field column and Edit Field sheet use friendly labels with raw-key table tooltips. Custom names, qualified identities and distinct raw rows remain preserved. Friendly Date resolves independently from explicit uppercase DATE; an edit no longer redirects an existing raw alias to its registry-preferred key. A mixed Xiph/APE versus ID3/MP4 DATE row explicitly shows Year / Date.

The Debug build and normal-project `bash scripts/validate-release.sh --tests-only` passed: 13 policy tests, 62 core tests and **602 app-hosted tests**, no failures/skips/expected failures, exact inventories accepted. Evidence: `.deriveddata-codex/Validation/20261117-145354-72366/`. The three additional critical regressions cover suggestion names/descriptions, row labels and distinct raw identities, and store-level DATE/YEAR/alias preservation. The run began on the uncommitted implementation; code/test/script content matches `3063e7f`, committed during the run. Existing localization work was retained outside these commits. No Release build or interactive UI validation was performed.

## Settings and Inspector naming follow-up

Settings Interface controls and single/batch Inspector previously shared `InspectorMetadataField.displayName` with each other, but maintained those names separately from the new guide/editor source. They now delegate to the shared AudioMator naming functions. Batch-edit field labels, read-only technical titles and Interface list-column labels use those same functions. Filename remains a file property. Track/Disc list headers become Track Number/Disc Number; raw preference IDs, defaults, visibility, ordering, value formatting and writes remain unchanged.

Focused serial Debug verification passed **13 tests** across InspectorFieldConfigurationTests, MetadataFieldGuideTests and MetadataEditorDraftRowsTests, with zero failures. Evidence: `.deriveddata-codex/Logs/Test/Test-AudioMator-2026.11.17_15-03-12-+0800.xcresult`; command output `.tmp/shared-field-labels-final-tests.log`. The first final compile identified a missing explicit TagLibAudioMetadata type import in MiddleListColumn; that import was added before the successful rerun. `git diff --check` passed. No full-suite rerun, Release build or manual UI launch is claimed for this naming-only follow-up. Existing localization changes remain outside the commit.

## Guide layout follow-up

The field list now measures all localized labels using the system body font and reserves 64 points for row insets/scrollbar, with a minimum preferred width of 320 points. The wider default window retains room for details. User resizing is retained and labels wrap when narrowed. The storage section no longer uses DisclosureGroup: a persistent native GroupBox/Grid presents format headings, padded rows, dividers, native locations and availability. Rows grow with their content in the existing document scroll view; no nested fixed-height table scrollbar is introduced.

Serial Debug compilation and the three MetadataFieldGuideTests passed with zero failures. Evidence: `.deriveddata-codex/Logs/Test/Test-AudioMator-2026.11.17_15-18-00-+0800.xcresult`; log `.tmp/field-guide-layout-tests.log`. `git diff --check` passed. No full-suite or Release run, or interactive visual acceptance, is claimed. Existing localization edits remain uncommitted. Implementation references: Apple's [sidebar guidance](https://developer.apple.com/design/human-interface-guidelines/sidebars) and [native Grid documentation](https://developer.apple.com/documentation/swiftui/grid).

## Remove usage section

Removed the entire “Using This Field” section at the maintainer's request. The detail view now contains purpose, the always-visible storage table where applicable, and references. `bash scripts/codex-build.sh` passed the Debug build; `git diff --check` passed. Build output: `.tmp/field-guide-remove-usage-build.log`. No tests, Release build or interactive app launch was performed for this view-only deletion.

## Simplify suggestion subtitles

On `fix-native-field-suggestions`, the maintainer chose to remove mapping names from the Add Field dropdown rather than add destination-specific native mapping subtitles. Suggestions now show only the shared AudioMator name and purpose. No native-format inference was retained, and write keys, aliases, row identity and the field-guide mapping table remain unchanged. Serial Debug compilation and all four MetadataEditorDraftRowsTests passed. Evidence: `.deriveddata-codex/Logs/Test/Test-AudioMator-2026.11.17_15-42-44-+0800.xcresult`; log `.tmp/suggestion-purpose-only-tests.log`. `git diff --check` passed. No Release build, full-suite run, manual UI launch or push was performed.
