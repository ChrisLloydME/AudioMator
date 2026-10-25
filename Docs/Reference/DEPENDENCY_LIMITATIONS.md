# Dependency Limitations

AudioMator depends on the external `TagLibAudioMetadata` package for container metadata behavior. This page records constraints that are observable from the app side and that affect product behavior. It is not a substitute for the package's own issue tracker.

Baseline: `TagLibAudioMetadata` 0.6.0, revision `c135fe0a3c52ba76054731e2afe3e56b83f6d40e`. Reproductions use temporary copies of the committed fixtures and the public `applyMetadataPatch` / `writeTrackNumberText` APIs. The package source was not audited or modified.

## 0.6.0 Integration Status

The dependency resolves and builds, but this branch is not ready to merge or distribute: semantic FLAC comment writes still fail verification. The application does not bypass semantic writes through raw patches. See the [upgrade record](../Engineering/TAGLIB_060_INTEGRATION_2026-10-25.md).

## Number-Pair Contract

Total-only track and disc pairs use number-text patches (`"/12"`, `"/3"`). AudioMator preserves the remaining component when an individual number field is cleared. Clearing a complete pair clears both components. Non-numeric semantic number text remains unsupported and is rejected before mutation; unchanged raw text does not block unrelated edits.

The 0.5.3 guards rejecting total-only pairs have been removed. The adapter now serializes them explicitly instead of clearing the pair. It also appends a retained model total to number-only imported text: 0.6.0 semantic `MetadataNumberTextPatch` treats omitted totals as zero, unlike legacy `writeTrackNumberText`. The integration matrix also requires MP3 disc-only edits, AAC total clearing, and AAC combined text to succeed. Structured component removal is not a substitute for the number-text representation: some containers reject it with `unsupportedPartialPairRemoval`.

## Observed Failure: FLAC Semantic Comments

On 0.6.0, copy `AudioMatorTests/Fixtures/Audio/testAudioFile.flac` to a temporary writable file and call:

```swift
try TagLibMetadataManager.applyMetadataPatch(
    MetadataPatch(fields: [.comment: .text("Probe Comment")]), to: url
)
```

Observed: `verificationFailed(["Patched native comment collection differs after save."])`; original bytes remain unchanged. The raw `COMMENT` path works, but is not used to bypass this defect. Package-owner tests should cover set, replace, clear, existing native comments, and multiple values with exact readback and byte preservation on failure. The package's internal cause has not been investigated from this repository.

## Audio Continuity

Loading opts into `audioContentIdentity`. Automatic rebases require equal, non-nil baseline and current tokens and commit with both the baseline token and exact current version. WAV, AIFF/AIFF-C and native FLAC have package support; unsupported or ambiguous layouts require explicit reload after a version change. An unchanged exact version may still save normally. Two absent tokens never establish continuity. The package hashes encoded audio with bounded memory; this adds streaming I/O proportional to audio size.

## Historical Multi-Artwork Role Replacement Probe (0.5.3)

Under 0.5.3, an attempted FLAC fixture setup through the public `applyMetadataPatch` API failed with `verificationFailed(["Patched artwork differs after save."])` when replacing artwork with two `StructuredArtwork` entries using identical JPEG payloads, picture type codes 3 and 4, and a description of `"Before"` on the second entry.

That probe was not rerun against 0.6.0 and does not establish a current package defect. It occurred before AudioMator's conflict resolver ran. The cause is not established; it may be an undocumented required role representation or a package round-trip/verification issue.

AudioMator status:

- standard single-cover integration tests pass,
- multi-cover write support is **not claimed**,
- no workaround was introduced.

Expected package behavior: accepted artwork input round-trips under documented normalization, or validation fails before mutation with a clear unsupported-role diagnosis.

## Package Behaviors AudioMator Relies On

These package contracts still require fixture validation:

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

## Non-Numeric Number Text (0.6.0)

The 0.6.0 concrete semantic adapter still rejects non-numeric number-text edits. The accepted semantic components are unsigned decimal values at most 2147483647; an empty number can accompany a positive total. Thus `A1/12`, `A1` plus an edited total, and `B2` plus an edited disc total are not supported semantic number-text edits. The app now distinguishes this limitation from a missing number, refuses before mutation, and directs the user to Metadata Editor. Unrelated title edits preserve the raw non-numeric text and totals. Regression tests exercise all three shapes and compare complete raw maps and bytes on rejection. The package owner should document the accepted grammar or add non-numeric number-text round trips; AudioMator does not bypass the package with a speculative semantic-to-raw mapping.

## Audio Identity Limits

`MetadataFileVersion` remains an opaque revision token. AudioMator now separately adopts the 0.6.0 audio-content continuity contract described above. Package support is limited by format and layout, so automatic rebases are unavailable whenever either snapshot lacks a token. Whole-file hashes include metadata and are not used as a fallback. The same-inode WAV replacement regression now passes for both typed and raw writes under all conflict policies.
