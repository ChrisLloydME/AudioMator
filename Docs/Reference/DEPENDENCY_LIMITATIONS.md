# Dependency Limitations

AudioMator pins published **TagLibAudioMetadata 0.7.3**, revision `7ca1b75326388a5902815f70145b600299944ae0`, through the normal Xcode project and committed remote lock. The mapping contract is `AM-TLAM-MAPPING-2.2`. [Current adoption evidence](../Engineering/TAGLIB_073_RELEASE_READINESS_2026-11-12.md) records validation against that tag; the older local workspace is an optional candidate tool.

## Published repair boundary

Version 0.7.3 includes the native-owner and sparse-state repairs that were tested using the local candidate. The absent-Year/present-Date MP4 Comment/Lyrics reproduction remains a mandatory, ordinary regression test. No application companion-date or raw-write workaround is installed. Field-selection intent, Inspector/Editor state and expected-version safety remain app responsibilities; native codec behavior remains package-owned.

The [0.7.2 failing adoption](../Engineering/TAGLIB_072_ADOPTION_2026-11-11.md), [local state-coverage acceptance](../Engineering/METADATA_STATE_COVERAGE_2026-11-11.md), [0.7.0 ledger](../Engineering/AUDIOMATOR_MAPPING_070_IMPLEMENTATION.md) and [0.6.0 integration](../Engineering/TAGLIB_060_INTEGRATION_2026-10-25.md) are historical evidence. Their superseded failures are not current capability claims. Current regressions must pass the published-tag gate; a package release note alone is insufficient acceptance.

## Explicit capability restrictions

- Existing ID3v2.3 independent-date edits remain read-only unless the package supplies verified writable evidence for the concrete layout. The app preflights actual-file evidence; an extension-level capability does not authorize an unsafe write.
- MP4 RATE is read-only for typed writes. Native media-kind integer codes are preserved; the app does not invent label/code bindings.
- MKV registrations do not establish a supported native codec.
- Number formatting can normalize in containers such as MP4. Numeric pair values are authoritative, and AudioMator does not manufacture private text atoms.
- Fixture coverage is finite. Passing MP3/MP4/FLAC/AAC/Vorbis/WAV integration and generated AIFF Store ID/provider cases does not certify every codec, tag version or native structure. See [Testing](../Development/TESTING.md#known-coverage-gaps).

## Audio Continuity

Loading opts into `audioContentIdentity`. Automatic rebases require equal, non-nil baseline and current tokens and commit with both the baseline token and exact current version. WAV, AIFF/AIFF-C and native FLAC have package support; unsupported or ambiguous layouts require explicit reload after a version change. An unchanged exact version may still save normally. Two absent tokens never establish continuity. The package hashes encoded audio with bounded memory; this adds streaming I/O proportional to audio size.

## Historical Multi-Artwork Role Replacement Probe (0.5.3)

Under 0.5.3, an attempted FLAC fixture setup through the public `applyMetadataPatch` API failed with `verificationFailed(["Patched artwork differs after save."])` when replacing artwork with two `StructuredArtwork` entries using identical JPEG payloads, picture type codes 3 and 4, and a description of `"Before"` on the second entry.

That probe was not rerun against 0.7.0 and does not establish a current package defect. It occurred before AudioMator's conflict resolver ran. The cause is not established; it may be an undocumented required role representation or a package round-trip/verification issue.

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
- Typed `.track`/`.trackTotal`/`.disc`/`.discTotal` patches preserve the untouched sibling and reject unsupported layouts.
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

## Non-Numeric Number Text (0.7.0)

The semantic adapter rejects non-numeric track/disc number text. The accepted semantic components are unsigned decimal values at most 2147483647; an empty number can accompany a positive total. Thus `A1/12`, `A1` plus an edited total, and `B2` plus an edited disc total are not supported semantic number-text edits. The app now distinguishes this limitation from a missing number, refuses before mutation, and directs the user to Metadata Editor. Unrelated title edits preserve the raw non-numeric text and totals. Regression tests exercise all three shapes and compare complete raw maps and bytes on rejection. The package owner should document the accepted grammar or add non-numeric number-text round trips; AudioMator does not bypass the package with a speculative semantic-to-raw mapping.

## Audio Identity Limits

`MetadataFileVersion` remains an opaque revision token. AudioMator adopts the 0.7.0 audio-content continuity contract described above. Package support is limited by format and layout, so automatic rebases are unavailable whenever either snapshot lacks a token. Whole-file hashes include metadata and are not used as a fallback. The same-inode WAV replacement regression now passes for both typed and raw writes under all conflict policies.


## Historical mapping audits

The [2026-11-10 audit](../Engineering/MAPPING_CONFORMANCE_2026-11-10.md) reproduced failures on 0.7.0. Those reports describe superseded behavior. The published 0.7.3 acceptance exercises the retained independent-date regressions through the real app adapter, with no `TagLibDateCompanion` or raw-write substitution.

## Unknown advisory codes

Unknown advisory codes are preserved during unrelated saves and same-file exchange round trips. Assigning one to a different value/file is explicitly unsupported by the current typed package API and is rejected in preview and execution; it is never converted to unset.
