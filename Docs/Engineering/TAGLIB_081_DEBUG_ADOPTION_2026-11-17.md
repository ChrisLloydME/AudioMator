# Published TagLibAudioMetadata 0.8.1 Debug adoption — 2026-11-17

> Dated evidence — current behavior is documented in [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md) and the [Metadata Mapping Specification](../Architecture/METADATA_MAPPING_SPEC.md). This remains the Debug-adoption evidence for the unchanged published 0.8.1 pin; the 596-test app-hosted inventory below is historical and the later [2026-11-18 cleanup acceptance](AUDIOMATOR_LEGACY_CLEANUP_ACCEPTANCE_2026-11-18.md) records the current 629-test gate. Release, Archive and interactive UI were excluded.

Branch: `codex/adopt-taglib-081`, based on main `a0230a00`.

The normal Xcode project pins exact published `0.8.1`, revision `b8ed5475761cb50bacdd7dcd4f6e2f61142303d0`. Xcode generated the remote lock; no local workspace override is used. The package checkout is not modified. This adopts automatic edited-group numbering recovery and retirement after the earlier [local candidate](INTERNAL_NUMBERING_RECOVERY_2026-11-16.md).

The published MIT license matches the bundled text byte-for-byte. The TagLib 2.3.1 revision 2 binary URL and checksum remain unchanged (`d7a36b2492266a17fcd97bd776cd841d9fc85275270bc0c3cb9621395b3178c7`). Runtime acknowledgements, current notices and the literal dependency contract identify 0.8.1.

## Verification scope

Final tested source: `6a94d745f251f8d01c1f947994b01b1435591445`, with a clean tracked worktree. Subsequent changes only record documentation evidence.

`bash scripts/validate-release.sh --tests-only` completed successfully against the normal project:

| Check | Result |
| --- | --- |
| Python gate policies | 13 passed |
| Foundation core tests | 62 passed; exact named gate accepted |
| Serial Debug app-hosted tests | 596 passed; zero failures, skips or expected failures |
| App source-to-result identity | Accepted; 596 expected/executed, no missing or unexpected tests |
| Changed Markdown relative file links / whitespace | Passed |

Evidence: `.deriveddata-codex/Validation/20261117-134510-57258/` (`source.txt`, `core-gate.json`, `test-gate.json`, `AppTests.xcresult`, `app.log`). The source evidence records the remote 0.8.1 lock, not a local override.

The nine automatic-numbering regressions passed, including reconstructed historical layouts, read-only import, canonical authority, single/batch migration and clear, clean Inspector lifecycle, retained real drafts, ambiguity and stale revisions. Full save journeys also passed MusicBrainz/iTunes selected-field writes and unchecked-field preservation, Metadata Editor arrays/failed drafts, Inspector independent dates/totals/clears, and unchanged-save behavior. No new functional integration failure was reproduced; no application metadata workaround was added.

The test result includes a SwiftUI runtime warning in the existing `OnlineMetadataWorkbenchPerformanceTests` about accessing `State<Bool>` before installation on a View. Xcode also emits the AppIntents extraction warning because the target has no AppIntents dependency and system shortcut-service connection diagnostics. These are not test failures or evidence of a new package defect; this run is not claimed warning-free.

 Release builds, artifacts, archives, signing, notarization, publication and interactive application launch are excluded by request. Debug automation does not establish distribution acceptance or visual UI acceptance.
