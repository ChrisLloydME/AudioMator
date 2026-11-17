# Metadata Field Guide verification — 2026-11-17

Branch: `codex/review-inspector-date-field`. Tested implementation: `593bf2c`. The final gate began before this commit was recorded; production/test/script contents were identical to the committed implementation, with only documentation changed during the run. Subsequent changes record evidence only. Published package remains exact 0.8.1; no package source or metadata write path changed.

## Delivered

Help → Metadata Field Guide opens one native, resizable reference window. A searchable list covers 100 package fields and six read-only display values. Details explain purpose, common-field availability, independent dates and grouping identities. Native mapping details are collapsed initially and come directly from the installed registry. References open in the default browser only after selection; no guide fetch, file metadata access or draft mutation is performed. The complete reference table now includes purposes and per-row primary links.

Primary sources were reviewed through official ID3.org, Xiph.Org, Apple Developer, TagLib, MusicBrainz/Picard and AcoustID documentation. Explanations are paraphrases, not copied reference pages. Application-specific date/grouping/advisory semantics are distinguished from standard terminology. Undocumented opaque encodings are not promoted to supported codecs. See [user guide](../Product/METADATA_FIELD_GUIDE.md) and [cross-layer table](../Reference/METADATA_FIELD_MAPPING_TABLE.md).

## Verification

`bash scripts/validate-release.sh --tests-only` passed against the normal published dependency: 13 Python policies, 62 core tests and **599 serial app-hosted tests**, zero failures/skips/expected failures. Both named gates accepted exact source inventories with no missing/unexpected tests. Evidence: `.deriveddata-codex/Validation/20261117-141932-60975/` (`source.txt`, `core-gate.json`, `test-gate.json`, `AppTests.xcresult`, logs). All three new field-guide tests are mandatory critical identities: enum coverage/source completeness, reference/disclosure equality, and search/date/recording distinctions.

The preceding full run executed 598 tests and failed only the old fixed network-host inventory, which had not yet been updated for the new explicitly opened help links. The exact host inventory was updated; an additional equality test now requires all guide reference hosts to match the privacy disclosure. No assertion, skip policy or gate was weakened.

The initial sandboxed build was blocked by compiler/SwiftPM cache permissions. Rerunning with appropriate cache access passed the Debug build. The final full gate also compiled the current implementation. Relative documentation file links, table width/coverage and `git diff --check` passed. The extended table contains 106 data rows and 16 columns. Existing system shortcut-service/AppIntents diagnostics and the performance suite's existing SwiftUI State warning are not claimed resolved; no new Swift compilation warning was found.

No Release build, artifact/archive validation, package tests, manual app launch or interactive UI acceptance was performed. The maintainer should check Help menu discovery, window resizing, search focus/keyboard selection, VoiceOver and light/dark appearance. Automated acceptance does not establish those visual/accessibility outcomes or exhaustively validate every external reference site's future content.
