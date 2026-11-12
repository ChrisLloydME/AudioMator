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

The dedicated-string lifecycle matrix exercises all 33 dedicated string fields on MP4 (set, replace, remove). The common matrix exercises seven fields (title, artist, album, comment and three Store IDs) on MP3, MP4, FLAC, Ogg Vorbis, AAC and WAV. Existing tests additionally cover numbering, dates and advisory across their declared formats. The generated AIFF Store ID regression remains mandatory.

This is not a claim of the full field × format × tag-version product. AIFF beyond Store IDs, Opus, provider field writes on formats outside the MP4/FLAC/AIFF journey matrix, container-field replacement beyond set/remove, audio-content preservation for the minimal MP4 fixture (its snapshot has no content identity), and independent external-decoder checks remain unverified. Required unsupported-format and ID3v2.3 safety cases in the existing suites must continue to reject before mutation. Package correctness remains an independent responsibility; native atom probes still use the package's decoder and are not external-tool conformance evidence.

## Release gate

Run `bash scripts/validate-release.sh` with stable Xcode at `/Applications/Xcode.app`. The script runs core tests, all serial app-hosted tests, rejects skipped app tests, builds unsigned Release and audits the macOS artifact. All Xcode outputs use `.deriveddata-codex`. Each run keeps logs and an `.xcresult` under `.deriveddata-codex/Validation`; successful test execution also produces a machine-readable summary. A failed phase stops release validation. No filter, expected failure or skip is allowed to hide a reproduced mapping defect.

CI invokes the same gate and uploads its evidence even on failure. Uploads contain test evidence, not a distributable release. Maintainer UI acceptance, signing, notarization and publication remain separate.

A red regression that reproduces a dependency bug blocks release. Report the API, observed/expected behavior, minimal app reproduction and proposed package regression; do not patch a sibling checkout or silently substitute raw writes.

## Preview-to-save journeys

`MetadataSaveJourneyTests` starts at actual workbench stores and `MetadataEditorStore`, not manually constructed provider write entries. The provider transport is offline; metadata planning, field selection, mutation coordinator, adapter writes, verification and disk reloads are real. Tests run on MP4/FLAC copies and generated AIFF files.

- Every iTunes field has a declared decision: 15 fields are individually checked, saved and compared after reload; absent remote barcode must produce no write. Every unchecked provider field is compared with the original file.
- All 27 MusicBrainz fields are represented: 21 release fields individually checked and saved, plus six recording-credit fields supplied through an offline client and cached by the real browser store. Inventory equality fails if the provider adds an unclassified field. Unchecked fields remain unchanged.
- All available fields selected together must persist together. Literal assertions additionally verify Album/Artist/Catalog Store IDs, independently from provider comparison helpers.
- Captured displayed plans retain their original checked selection after later checkbox changes. No checked fields and missing recording values must not clear metadata. Both providers reject an externally changed target while continuing the valid file in a batch.
- Metadata Editor uses the actual loaded draft maps and pending targets: additions, replacement, exact multivalue arrays, deletion, disk/model refresh, and partial-success removal with failed drafts retained.
- Inspector single and batch orchestration covers genuine saves, independent dates, typed IDs, explicit clears, advisory removal, total-only removal preserving its number, invalid-input draft retention and partial-batch retry without rewriting already successful files.

These automated journeys stop at view models/stores and persisted file state. They do not synthesize mouse clicks or verify SwiftUI checkbox rendering, focus, windows or dismissal. Maintainer UI acceptance is still required. The existing workbench view-routing check verifies that the view passes the displayed plan, but a source-policy assertion is not an interactive UI test. The Content Group regression remains a normal required test and passes with published 0.7.2. The older [local package repair](../Engineering/MP4_CONTENT_GROUP_PACKAGE_REPAIR_2026-11-10.md) remains historical evidence. The [absent-Year/present-Date Comment/Lyrics regression](../Engineering/TAGLIB_072_ADOPTION_2026-11-11.md) blocked 0.7.2; both deterministic tests remain mandatory for the published 0.7.3 gate and must pass without companion writes or raw fallbacks.

## State and API coverage

Native package correctness must be reproducible without importing AudioMator. The package repair branch independently checks native byte owners, absent/present date combinations and public write surfaces; application tests do not serve as its only oracle. App acceptance adds 1,584 dedicated-field lifecycle operations, 688 provider field/date cases and 80 Inspector/Metadata Editor/CSV/workbench journeys across all 16 date masks. Checked fields must persist after disk reload; unchecked fields and independent dates must remain unchanged. No Year companion patch or raw fallback is allowed to make a semantic save pass.

The release gate verifies every named core and app XCTest against the source inventory, plus frozen critical identities and minimum reviewed counts. A successful aggregate count cannot compensate for a missing journey. Parser/policy tests exercise incomplete and tampered evidence. Use the explicit `--local-package` option for candidate integration and the no-argument gate for the published dependency; never label one as the other. [Current acceptance evidence](../Engineering/METADATA_STATE_COVERAGE_2026-11-11.md) supersedes earlier candidate counts without changing historical records.

This is finite coverage, not a complete media × encoding × OS × UI-state product. The package's independent native probes, the application's model/store journeys and maintainer interactive acceptance establish different facts. Remaining platform/fixture limits listed in Testing remain in force.
