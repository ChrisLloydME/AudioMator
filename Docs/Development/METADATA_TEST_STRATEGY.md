# Metadata test and release contract

Metadata correctness is established by explicit field and operation coverage, not the number of XCTest methods. The implementation entry point is `AudioMatorTests/Integration/TagLib/MetadataBoundaryMatrixTests.swift`; existing date, numbering, advisory, revision-conflict, raw-preservation and cancellation suites remain required.

## Required layers

| Layer | Required evidence | Failure policy |
| --- | --- | --- |
| Dedicated controls | Independently specified semantic key, sample, exact patch kind and explicit removal for every dedicated string control | A new string control without a manifest entry fails inventory equality |
| Exchange | Every writable `MetadataExchangeField` has an explicit case; real CSV planning, adapter save and reload | No entry, wrong identity, failed save or wrong reload fails |
| Container controls | Every editable catalog field has an explicit typed case; real MP4 persistence and removal, including present false | New editable keys fail inventory equality |
| Providers | Provider field inventories must be represented in exchange expectations; real iTunes and MusicBrainz two-file batch execution and refreshed application models | A recording fake alone cannot prove persistence |
| Inspector | Real single-file and multi-file save orchestration, bounded completion, disk reload and refreshed models | Missing task start, timeout or wrong disk/model values fail |
| Native storage | Explicit MP4 `plID`, `atID`, `cnID` expectations plus unrelated raw-array preservation | Semantic self-round-trip alone is insufficient |
| Rejection | Invalid IDs and range overflow reject with exact file-byte preservation; unchanged existing date, total and conflict safety suites remain required | No clamping, skipped field or partial per-file save |

Expectations are maintained in tests independently from the package registry. Registries and app enumerations may identify missing coverage, but must not generate the expected semantic identities or successful sample values. Fixture copies and generated temporary AIFF files are the only files mutated. No user audio, live service or interactive UI is used.

## Format scope

The dedicated-string lifecycle matrix exercises all 33 dedicated string fields on MP4 (set, replace, remove). The common matrix exercises seven fields (title, artist, album, comment and three Store IDs) on MP3, MP4, FLAC, Ogg Vorbis, AAC and WAV. Existing tests additionally cover numbering, dates and advisory across their declared formats. The generated-AIFF Store ID regression remains a required ordinary test.

This is not a claim of the full field × format × tag-version product. AIFF beyond Store IDs, Opus, provider field writes on formats outside the MP4/FLAC/AIFF journey matrix, container-field replacement beyond set/remove, audio-content preservation for the minimal MP4 fixture (its snapshot has no content identity), and independent external-decoder checks remain unverified. Required unsupported-format and ID3v2.3 safety cases in the existing suites must continue to reject before mutation. Package correctness remains an independent responsibility; native atom probes still use the package's decoder and are not external-tool conformance evidence.

## Release gate

Run `bash scripts/validate-release.sh` with stable Xcode at `/Applications/Xcode.app`. The gate checks documentation links, runs policy tests, and verifies the complete core and serial app-hosted test inventories. The standard lane uses the committed package lock. The gate then builds unsigned Release from clean build products and checks the bundle identifier, universal app and TagLib binaries, macOS Mach-O platform and deployment versions, and five non-empty license files. A failed phase stops validation. Evidence under `.deriveddata-codex/Validation/` includes logs, the `.xcresult`, and machine-readable test results. See [Testing](TESTING.md#release-gate-evidence) for the exact execution requirements.

CI invokes the same gate and uploads its evidence even on failure. Uploads contain test evidence, not a distributable release. Maintainer UI acceptance, signing, notarization and publication remain separate.

A red regression that reproduces a dependency bug blocks release. Report the API, observed/expected behavior, minimal app reproduction and proposed package regression; do not patch a sibling checkout or silently substitute raw writes.

## Preview-to-save journeys

Real-write tests can declare fixture directories through the [XCTest folder-access setup](TESTING.md#test-targets) while exercising the normal mutation pipeline under App Sandbox.
The exact raw-array test requires a per-file write issue and unchanged bytes when the edit is rejected, so early folder-access failure cannot satisfy its rejection assertion.

`MetadataSaveJourneyTests` starts at actual workbench stores and `MetadataEditorStore`, not manually constructed provider write entries. The provider transport is offline; metadata planning, field selection, mutation coordinator, adapter writes, verification and disk reloads are real. Tests run on MP4/FLAC copies and generated AIFF files.

- Every iTunes field has a declared decision: 15 fields are individually checked, saved and compared after reload; absent remote barcode must produce no write. Every unchecked provider field is compared with the original file.
- All 27 MusicBrainz fields are represented: 21 release fields individually checked and saved, plus six recording-credit fields supplied through an offline client and cached by the real browser store. Inventory equality fails if the provider adds an unclassified field. Unchecked fields remain unchanged.
- All available fields selected together must persist together. Literal assertions verify Album, Artist and Catalog Store IDs independently from provider comparison helpers. The iTunes batch test uses Album and Catalog IDs above the 32-bit range and verifies disk readback from FLAC and M4A.
- Captured displayed plans retain their original checked selection after later checkbox changes. No checked fields and missing recording values must not clear metadata. Both providers reject an externally changed target while continuing the valid file in a batch.
- Metadata Editor uses the actual loaded draft maps and pending targets: additions, replacement, exact multivalue arrays, deletion, disk/model refresh, and partial-success removal with failed drafts retained. E2 covers per-element utility preview/apply over captured arrays (whole-value, prefix/suffix, case/trim, empty/duplicate/multiline elements, missing keys, reordering), stale-preview rejection, no-op entry confirmations with zero writes, captured per-file/key Done changes, and real FLAC readback of a multiline element beside unrelated keys.
- The named Date Add Field journey puts a picker-generated date in the initial value slot and verifies the exact FLAC `DATE` array and preserved Year after reviewed Apply.
- Inspector single and batch orchestration covers genuine saves, independent dates, typed IDs, explicit clears, advisory removal, total-only removal preserving its number, invalid-input draft retention and partial-batch retry without rewriting already successful files.

These automated journeys stop at view models/stores and persisted file state. They do not synthesize mouse clicks or verify SwiftUI checkbox rendering, focus, windows or dismissal. Maintainer UI acceptance is still required. The existing workbench view-routing check verifies that the view passes the displayed plan, but a source-policy assertion is not an interactive UI test. The Content Group regression remains a required test for the published pin. The older [local package repair](../Engineering/HISTORY/MP4_CONTENT_GROUP_PACKAGE_REPAIR_2026-11-10.md) remains historical evidence. The [absent-Year/present-Date Comment/Lyrics regression](../Engineering/HISTORY/TAGLIB_072_ADOPTION_2026-11-11.md) blocked 0.7.2; both deterministic tests remain mandatory and are frozen critical identities in `scripts/check-test-evidence.py`, and must pass without companion writes or raw fallbacks.

## State and API coverage

Native package correctness must be reproducible without importing AudioMator. The published package's own tests and native probes independently check byte owners, absent/present date combinations and public write surfaces; application tests are not its only oracle. Source-verified on 2026-11-18, app acceptance asserts 1,584 dedicated-field lifecycle operations, 688 provider field/date cases and 80 Inspector/Metadata Editor/CSV/workbench journeys across all 16 date masks in `MetadataBoundaryMatrixTests` and `MetadataSaveJourneyTests`. Checked fields must persist after disk reload; unchecked fields and independent dates must remain unchanged. No Year companion patch or raw fallback is allowed to make a semantic save pass.

The release gate verifies every named core and app XCTest against the source inventory, plus frozen critical identities and minimum reviewed counts. A successful aggregate count cannot compensate for a missing journey. Parser/policy tests exercise incomplete and tampered evidence. Use the explicit `--local-package` option for candidate integration and the no-argument gate for the published dependency; never label one as the other. [Published 0.8.1 Debug adoption](../Engineering/TAGLIB_081_DEBUG_ADOPTION_2026-11-17.md) records acceptance for an earlier published pin.

This is finite coverage, not a complete media × encoding × OS × UI-state product. The package's independent native probes, the application's model/store journeys and maintainer interactive acceptance establish different facts. Remaining platform/fixture limits listed in Testing remain in force.
