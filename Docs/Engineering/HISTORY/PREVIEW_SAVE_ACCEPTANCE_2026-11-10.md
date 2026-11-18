# Preview and editor save acceptance

Scope: AudioMator branch `codex/test-system-upgrade`, using published TagLibAudioMetadata 0.7.1 through the normal Xcode project. The maintainer specifically requested verification after provider preview and checkbox selection, plus Inspector and Metadata Editor. Network fetching is not the acceptance target.

## Previous coverage gap

The earlier `MetadataBoundaryMatrixTests` provider batch constructed write entries directly. It proved executor persistence, not that the actual workbench selected the right fields or captured the displayed preview. Existing snapshot tests checked plan immutability using fakes. The new `MetadataSaveJourneyTests` joins the real workbench store, captured plan, executor, mutation coordinator, adapter, disk reload and refreshed app models. Provider DTOs are deterministic offline samples. Recording credits use a stub transport with the actual browser cache and workbench; the metadata pipeline is never replaced by a recording fake.

## Required journeys

| Area | Automated evidence |
| --- | --- |
| iTunes | Explicit inventory decision for all 16 fields: 15 individually selected and saved on MP4/FLAC/generated AIFF, comparing unchecked fields with the baseline; absent remote barcode creates no write |
| MusicBrainz | All 27 fields have an inventory decision: 21 release fields individually selected and saved on the same three formats, plus six cached recording-credit fields; all available fields also save together |
| Captured preview | Later checkbox changes do not alter the original displayed plan that is applied |
| No selection / missing data | Empty selections and absent recording detail never clear existing metadata |
| Batch conflict | Both providers preserve an externally changed target byte-for-byte and continue the other valid target |
| Inspector | Real single and multi saves, independent dates, typed IDs, advisory and total clearing, invalid ID rejection preserving dirty draft, partial-batch retry without rewriting successful files |
| Metadata Editor | Real draft load, add/replace/delete, exact multivalue arrays, pending-target application, refreshed app model and retention of failed drafts after partial success |

Tests use only temporary fixture copies/generated audio. UI rendering/clicks/focus/window dismissal are not automated. View wiring still has its existing source-policy check, which cannot substitute for manual UI acceptance. No claim is made that arbitrary remote payloads or every field × container-version combination is covered.

## Known blocker

The independent MP4 Content Group regression remains a normal failing test, as recorded in [the test-system acceptance](TEST_SYSTEM_UPGRADE_2026-11-10.md). No skip, expected failure, package edit or raw-write workaround was introduced. Passing these journey tests cannot make that release blocker disappear.

## Verification results

The complete normal-project release gate ran 62 core tests successfully and 565 serial app-hosted tests with 564 passes and one failure, solely the previously exposed MP4 Content Group regression. Evidence: `.deriveddata-codex/Validation/20261110-183022-37990/`; the gate correctly stopped before Release/artifact phases.

After that run, test isolation annotations were tightened: the two new XCTest subclasses remain nonisolated while their app-facing tests/helpers are explicitly `@MainActor`. No concurrency warning suppression was added. The final focused run of both new suites executed 22 tests: the 12 preview/save journeys all passed, and only the same Content Group boundary case failed. Neither new suite emitted compiler warnings in that run. Older test files still emit existing XCTest initializer-isolation warnings; this is not a warning-free whole-suite claim. Log: `/tmp/audiomator-save-and-boundary-acceptance.log`. The preceding journey-only run also passed all 12 tests: `/tmp/audiomator-save-journeys-acceptance.log`.

`git diff --check` passed. No interactive UI testing, package edits, commits or publication occurred. The assertion is bounded: these real save journeys now have executable coverage; neither universal app correctness nor release readiness is established while the normal Content Group failure remains.
