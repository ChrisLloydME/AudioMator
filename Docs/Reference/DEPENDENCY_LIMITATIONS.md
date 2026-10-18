# Dependency Limitations

AudioMator depends on the external `TagLibAudioMetadata` package for container metadata behavior. This page records constraints that are observable from the app side and that affect product behavior. It is not a substitute for the package's own issue tracker.

Baseline: `TagLibAudioMetadata` 0.5.3, revision `03473c9ae199026b806a5f75c387ca036e325284`. Reproductions use temporary copies of the committed fixtures and the public `applyMetadataPatch` / `writeTrackNumberText` APIs. The package source was not audited or modified.

## Current AudioMator Workarounds

1. **Total-only number pairs are blocked before writing.** If an operation would leave a positive track/disc total with a zero or blank number, AudioMator rejects the write at the shared `persistMetadataEdit` boundary as well as in the field-transfer planner. This covers the inspector, provider plans, CSV/text imports, and filename metadata. This is a safety guard, not support for total-only pairs.
2. **Disc-only text patches avoid resubmitting an untouched track pair.** The adapter respects independent optional track/disc number-text edits.
3. **A stale expected version is never cleared to force a write.**

These guards should be removed or revisited when the dependency supports the behavior below.

## Observed Failure: Total-Only Number Pairs

Reproduction:

1. Seed track text `07/12` and disc text `02/03`.
2. Cut `Track Number` to another field while retaining `Total Tracks = 12`.
3. The payload holds track `0`, total `12`.

Observed:

- The current number-text serialization produces an empty string, which clears both components in MP3, M4A, and FLAC.
- AAC rejects it with a verification error.
- Public patches expressing the total as `/12`, `0/12`, or structured `.track: .remove` plus `.trackTotal: .integer(12)` also fail MP3 verification: expected total `12`, read back `0`.
- Original files remain intact on these errors.

Expected: a blank/zero number and a positive total round-trip independently for both track and disc pairs, with unrelated fields preserved and rollback on unsupported representations.

AudioMator status: blocked at planning/execution for user operations; the underlying API remains untrusted for this shape.

## Observed Failure: MP3 Disc-Only Patches Alter an Untouched Track Representation

Reproduction:

1. Seed track text `07/12` and disc text `02/03`.
2. Copy `Track Number` to `Disc Number`, or write any changed disc pair without changing the track pair.

Observed: the package rejects the transaction with `Unedited PropertyMap field TRACKNUMBER changed during the patch.` Original bytes remain unchanged. Seven combinations occur in the fixture matrix. The equivalent failure occurs with an untouched `7/0` track when cutting disc to comment.

Expected: the disc patch succeeds while preserving the untouched padded track representation.

## Observed Failure: AAC Number-Only Patches Do Not Clear the Existing Total

Reproduction:

1. Seed `07/12` and `02/03` in ADTS.
2. Cut `Total Tracks` to `Track Number` or another numeric field.

Observed: the number text has no slash/total, the package expects total `0`, but retains the old total `12` and rejects the transaction. Disc total has the equivalent failure retaining `3`. Six combinations occur; original bytes remain unchanged.

Expected: the patch's total-clearing intent agrees with its validator and round-trips. The package should fix the writer or clarify the API contract for number-only and explicit-zero totals.

## Observed Failure: Multi-Artwork Role Replacement

An attempted FLAC fixture setup through the public `applyMetadataPatch` API failed with `verificationFailed(["Patched artwork differs after save."])` when replacing artwork with two `StructuredArtwork` entries using identical JPEG payloads, picture type codes 3 and 4, and a description of `"Before"` on the second entry.

This occurs before AudioMator's conflict resolver runs. The cause is not established; it may be an undocumented required role representation or a package round-trip/verification issue.

AudioMator status:

- standard single-cover integration tests pass,
- multi-cover write support is **not claimed**,
- no workaround was introduced.

Expected package behavior: accepted artwork input round-trips under documented normalization, or validation fails before mutation with a clear unsupported-role diagnosis.

## Package Behaviors AudioMator Relies On

These are assumptions, not guarantees:

- `readSnapshot` and `fileVersion` describe a coherent revision.
- `applyMetadataPatch` verifies its own write and enforces the expected version.
- `applyRawMetadataPatch` preserves unrelated keys and value arrays.
- `eraseAllMetadataWithVerification` is best effort across tag surfaces.
- `writeTrackNumberText` can express independent track/disc text intent.
- Format capability data accurately reflects writable fields and artwork.
- A post-commit durability failure is reported distinctly from a failed commit.

If any assumption is false, the app may report a failure after a commit or claim a capability the container does not support. Report such cases with a minimal reproduction.

## Reporting Package Defects

Provide the package maintainer with:

1. The public API and exact arguments.
2. Input file format and a minimal temporary fixture.
3. Expected and observed readback (numeric values, text, raw keys, artwork).
4. Whether the original file bytes changed.
5. The AudioMator commit and package revision.
6. A proposed package test.

Do not modify the package checkout from the AudioMator repository. Keep any AudioMator-side mitigation narrow and documented here.

## Related Documents

- [Metadata Pipeline](../Architecture/METADATA_PIPELINE.md)
- [File Revision and Reload](../Architecture/FILE_REVISION_AND_RELOAD.md)
- [Testing](../Development/TESTING.md)

## Non-Numeric Number Text (0.5.3)

A controlled FLAC probe through the concrete semantic adapter rejects `A1/13` with `TagLibMetadataExtractor` code 245: number-text components must be unsigned decimal values at most 2147483647. Thus `A1/12`, `A1` plus an edited total, and `B2` plus an edited disc total are not supported semantic number-text edits. The app now distinguishes this limitation from a missing number, refuses before mutation, and directs the user to Metadata Editor. Unrelated title edits preserve the raw non-numeric text and totals. Regression tests exercise all three shapes and compare complete raw maps and bytes on rejection. The package owner should document the accepted grammar or add non-numeric number-text round trips; AudioMator does not bypass the package with a speculative semantic-to-raw mapping.
