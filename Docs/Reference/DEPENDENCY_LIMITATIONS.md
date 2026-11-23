# Dependency Limitations

AudioMator pins published **TagLibAudioMetadata 0.8.2**, revision `6b03cb97d96f2f7c25080b7145e4bf3340a9f868`, through the normal Xcode project and committed remote lock. The mapping contract is `AM-TLAM-MAPPING-2.2`. The ignored local workspace is used only for explicit candidate validation. Historical records under [Docs/Engineering/HISTORY](../Engineering/HISTORY/README.md) describe superseded versions and are not current capability claims.

## Current Published Boundary

The current 0.8.2 pin supplies automatic edited-group numbering recovery and retirement. `MappingPackageConformanceTests` exercises the MP4 absent-Year/present-Date regression for Comment and Lyrics through the public package boundary and the app adapter. AudioMator owns field-selection intent, Inspector and Editor state, and expected-version safety. The package owns native codec behavior.

## Explicit Capability Restrictions

- Existing ID3v2.3 independent-date edits remain read-only unless the package supplies verified writable evidence for the concrete layout. `TagLibDateMappingIntegrationTests` asserts that ID3v2.3 DATE writes remain safely read-only. The app preflights actual-file evidence; an extension-level capability does not authorize an unsafe write.
- The Metadata Editor preserves the raw key it writes. ID3v2.4 raw `DATE` displays as Year and stays text-only. For the named Date suggestion, verified Vorbis Comment and WavPack targets use raw `DATE`. Other targets use the text-only `STANDALONEDATE` key, separate from the Inspector's semantic Date slot. See the [Metadata Field Guide](../Product/METADATA_FIELD_GUIDE.md#shared-field-names-in-metadata-editor).
- MP4 RATE is read-only for typed writes. Native media-kind integer codes are preserved; the app does not invent label/code bindings.
- Matroska registrations do not establish a supported native codec; the field guide labels them as planned mappings, and the app does not advertise Matroska as writable.
- Number formatting can normalize in containers such as MP4. Numeric pair values are authoritative, and AudioMator does not manufacture private text atoms.
- Fixture coverage is finite. Passing MP3/MP4/FLAC/AAC/Vorbis/WAV integration and generated AIFF Store ID/provider cases does not certify every codec, tag version or native structure. See [Testing](../Development/TESTING.md#known-coverage-gaps).

## Audio Continuity

Loading opts into the package's optional `audioContentIdentity`. Automatic conflict rebases require equal, non-nil baseline and current tokens and commit with both the baseline token and exact current version. An unchanged exact version may still save normally; two absent tokens never establish continuity. The token is package-owned and opaque to the app; its derivation, cost and layout coverage are package responsibilities.

Reviewed write authorization requires a nonoptional `MetadataFileVersion`; a
load that cannot supply one produces no writable target. The app no longer has
any nil-revision write path: the removed mixed helper and its optional expected
version forwarding are gone. Such a file stays readable and must be reviewed
again after a coherent reread.

`MetadataFileVersion` remains an opaque revision token. Package support is limited by format and layout, so automatic rebases are unavailable whenever either snapshot lacks a token. Whole-file hashes are not used as a fallback. Current app integration coverage includes the same-inode content-replacement regression; it does not prove continuity for every container. WAV, AIFF/AIFF-C and native FLAC have been reported for the current pin, but the app treats continuity as optional and format-dependent rather than assumed.

## Number Text and Normalization

The semantic adapter rejects non-numeric track/disc number text. The accepted semantic components are unsigned decimal values at most 2147483647; an empty number can accompany a positive total. Thus `A1/12`, `A1` plus an edited total, and `B2` plus an edited disc total are not supported semantic number-text edits. The app distinguishes this limitation from a missing number, refuses before mutation with a clear message, and directs the user to Metadata Editor. Unrelated title edits preserve the raw non-numeric text and totals.

Individual components preserve a positive total when the number is cleared, serialized as `/total`; whole-pair clearing still removes both components. The package owner should document the accepted grammar or add non-numeric number-text round trips. AudioMator does not bypass the package with a speculative semantic-to-raw mapping.

## Raw Value Arrays

`RawMetadataValueMap` is `[String: [String]]`; the app treats each list as ordered data and preserves duplicates, empty elements and line breaks embedded inside one element. The published package exposes no per-key raw capability API, so a raw patch is accepted by the deterministic projection and the container then either round-trips the exact array or fails its own post-write verification. AudioMator reports that failure and does not retry with a semantic or different raw write. Blank, duplicate and multiline element acceptance is format- and container-dependent; fixture coverage is limited to the committed MP3/M4A/FLAC files (see [Testing](../Development/TESTING.md#fixtures)). The app preserves an existing empty array but does not emit `valuesToSet[key] = []` from normal editing; changing it requires an explicit value or the Delete Field command.

## Artwork

The Inspector writes a single cover. The M4A fixture verifies that unrelated semantic and raw edits preserve an existing JPEG/PNG cover pair. The test seeds both covers using the package API, and broader multi-cover layouts and role editing remain outside this coverage.

A 0.5.3-era probe attempted to set two `StructuredArtwork` entries with identical JPEG payloads, picture type codes 3 and 4, and a description of `"Before"` on the second entry through the public `applyMetadataPatch` API. It failed with `verificationFailed(["Patched artwork differs after save."])`. That probe is a dated historical observation, is not part of current acceptance evidence, and does not establish a current package defect. Expected package behavior: accepted artwork input round-trips under documented normalization, or validation fails before mutation with a clear unsupported-role diagnosis.

## Unknown Advisory Codes

Unknown advisory codes are preserved during unrelated saves and same-file exchange round trips. Assigning one to a different value or file is explicitly unsupported by the current typed package API and is rejected in preview and execution; it is never converted to unset. Exchange profile v2 exports the exact native code and accepts a native integer code from 0 through 255 on import.

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

## Historical Audits

The [2026-11-10 audit](../Engineering/HISTORY/MAPPING_CONFORMANCE_2026-11-10.md) reproduced failures on 0.7.0. Those reports describe superseded behavior. The current published-tag acceptance exercises the retained independent-date regressions through the real app adapter, with no `TagLibDateCompanion` or raw-write substitution. The [0.7.2 adoption record](../Engineering/HISTORY/TAGLIB_072_ADOPTION_2026-11-11.md) documents the MP4 absent-Year/present-Date failure that later releases fixed.

## Related Documents

- [Metadata Pipeline](../Architecture/METADATA_PIPELINE.md)
- [Mapping Specification](../Architecture/METADATA_MAPPING_SPEC.md)
- [Complete Metadata Field Mapping Table](METADATA_FIELD_MAPPING_TABLE.md)
- [File Revision and Reload](../Architecture/FILE_REVISION_AND_RELOAD.md)
- [Testing](../Development/TESTING.md)
- [Published 0.8.1 Debug adoption](../Engineering/TAGLIB_081_DEBUG_ADOPTION_2026-11-17.md)
