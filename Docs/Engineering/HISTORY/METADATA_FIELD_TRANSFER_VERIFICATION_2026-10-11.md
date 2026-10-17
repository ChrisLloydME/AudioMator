# Metadata field transfer verification

The automated checks exercise the planner, batch execution, patch serialization, transactional save, and reload. Fixtures cover MP3, M4A, FLAC, AAC/ADTS, OGG, and WAV. These checks do not establish interactive UI acceptance.

Validation on 2026-10-11: 130 related regression tests and one additional focused number-cut test passed; the macOS build passed. Known dependency rejections below are tested as failures that preserve the original file, not successful transfers.

## AudioMator safeguards

- The preview uses the shared writer's trimmed destination value. A source containing only whitespace is skipped for both Copy and Cut, preserving its destination.
- A write that would leave a positive track/disc total with a zero or blank number is rejected in both planning and execution. This is a temporary AudioMator workaround for the external dependency issue below, not support for saving total-only pairs.
- Copy and Cut operate on each file's own values. Source clearing and destination writing use one patch. Failure does not clear the loaded source, and the batch continues to the next file.
- Unsupported fields and stale file versions reject a patch without changing the original file's bytes. Preview fingerprints remain enforced at execution.

## External TagLibAudioMetadata defects

No dependency checkout or package source was modified. The public API under test is `TagLibMetadataManager.applyMetadataPatch(_:to:expectedVersion:)`, called through `TagLibAudioMetadataPipeline.writeMetadata`. Reproductions use writable copies of the committed `testAudioFile.*` fixtures.

### Total-only number pairs

1. Seed `MetadataNumberTextPatch(trackNumberText: "07/12", discNumberText: "02/03")`.
2. Cut Track Number to Comment while retaining Total Tracks = 12.
3. The edit payload correctly holds track = 0, total = 12. AudioMator's existing number-text serialization produces an empty string, which clears both components in MP3, M4A, and FLAC. AAC rejects it with a verification error instead.
4. Public patches expressing the retained total as `/12`, `0/12`, or structured `.track: .remove` plus `.trackTotal: .integer(12)` also fail verification on MP3: expected trackTotal = 12, read back 0. The originals remain intact on these errors.

Expected: a blank/zero number and a positive total round-trip independently, including Disc Number/Total Discs. The dependency agent should test and fix both number-text and structured patches for total-only pairs across all six formats, including preservation of unrelated fields and rollback on unsupported representations. After that fix, remove the temporary transfer safety guard and restore successful cut-and-reload coverage for these cases.

### MP3 disc-only patches alter an untouched track representation

Seed track text `07/12`, disc text `02/03`. Copy Track Number to Disc Number, or write any changed disc pair without changing the track pair. The dependency rejects the transaction with `Unedited PropertyMap field TRACKNUMBER changed during the patch.` The original bytes remain unchanged. Seven such combinations occur in the fixture matrix. Expected: the disc patch succeeds while preserving the untouched padded track representation. The equivalent failure also occurs with an untouched `7/0` track when cutting Disc Number to Comment. The dependency agent should add ID3 preservation tests around disc-only number-text patches for padded and explicit zero-total representations.

### AAC number-only patches do not clear the existing total

Seed `07/12` and `02/03` in ADTS. Cut Total Tracks to Track Number (or another numeric field). The resulting track number text has no slash/total. The dependency expects total = 0 but retains the old total = 12 and rejects the transaction. Disc Total has the equivalent failure retaining 3. Six combinations occur in the fixture matrix; their original bytes remain unchanged. Expected: the supplied number-text patch's total-clearing intent agrees with its validator and round-trips. The dependency agent should add ADTS clear-total tests with both number-only and explicit-zero total representations, fixing the writer or clarifying the API contract.

`testFieldTransferNumberCombinationsRoundTripOrFailWithoutChangingFile` currently checks successful numeric round trips for the other combinations and asserts the specific known failures plus byte-for-byte rollback. If a dependency update fixes them, the test intentionally requests updating these notes and acceptance checks.
