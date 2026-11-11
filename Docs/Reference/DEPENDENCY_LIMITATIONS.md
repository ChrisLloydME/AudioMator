> Current dependency: published **0.7.2**, revision `5e6f604b0e9df244f4b69608261407d2ab758788`. [Current adoption and blocker](../Engineering/TAGLIB_072_ADOPTION_2026-11-11.md). The 0.7.0/0.7.1 evidence below is historical. Normal builds use the published pin; the unreleased repair candidate uses explicit local override validation described below.


# Dependency Limitations

AudioMator depends on the external `TagLibAudioMetadata` package for container metadata behavior. This page records constraints that are observable from the app side and that affect product behavior. It is not a substitute for the package's own issue tracker.

Baseline: `TagLibAudioMetadata` **0.7.0**, revision `0f89fbe83c8fb029a9b6d640d57e397686986930`, mapping contract `AM-TLAM-MAPPING-2.2`. Reproductions use temporary copies of the committed fixtures and the public `applyMetadataPatch`, `numberingInventory`/`planNumberNormalization` and `writeTrackNumberText` APIs. The released package source was read during the 2026-11-10 mapping audit; it was not modified.

## Published 0.7.2 — current blocker

On MP4 with absent YEAR and present standalone DATE, writing only Comment or Lyrics fails verification with `Unedited native date field year changed during the patch.` The original file bytes remain unchanged. `MappingPackageConformanceTests` contains deterministic public-package and app-adapter regressions; the release gate must remain red until the package repair passes them. AudioMator does not synthesize companion dates or substitute raw writes. See [A072-01](../Engineering/TAGLIB_072_ADOPTION_2026-11-11.md#a072-01--p1--mp4-commentlyrics-writes-reject-when-year-is-absent-and-standalone-date-is-present).

Previous Content Group/Grouping/Work, Store ID and independent-date controls pass in the initial normal-project run against 0.7.2. ID3v2.3 independent-date writes, typed MP4 RATE and assigning new unknown advisory codes remain explicitly unavailable; those are capability restrictions, not claims of new regressions.

## 0.7.0 Integration Status

The dependency resolves, builds, and declares independent YEAR/DATE/RELEASEDATE/ORIGINALDATE identities, but native-write conformance remains incomplete and typed number/container fields. The application implements the registry-driven intent path, independent date drafting, typed number components, advisory states, MP4-exclusive typed fields, versioned exchange profiles, and an explicit number-cleanup preview/Apply. Several package verification defects remain; AudioMator rejects affected writes before mutation instead of synthesizing cross-field date companions, and does not route unsupported semantic writes through raw patches. See the [0.7.0 implementation ledger](../Engineering/AUDIOMATOR_MAPPING_070_IMPLEMENTATION.md) and the historical [0.6.0 record](../Engineering/TAGLIB_060_INTEGRATION_2026-10-25.md).

## 0.7.0 Observed Package Limitations

### FLAC semantic comments

Copy `AudioMatorTests/Fixtures/Audio/testAudioFile.flac` and call:

```swift
try TagLibMetadataManager.applyMetadataPatch(
    MetadataPatch(fields: [.comment: .text("Probe Comment")]), to: url
)
```

Observed: `verificationFailed(["Patched native comment collection differs after save."])`; original bytes remain unchanged. This is unchanged from 0.6.0. The raw `COMMENT` path works but is not used to bypass the semantic defect. Package-owner tests should cover set, replace, clear, multiple languages/descriptions and exact byte preservation on failure.

### ID3v2.3 DATE and RELEASEDATE

A valid ID3v2.3 tag containing `TYER=2004` and `TDAT=0304` reads through TagLib as a merged `TDRC=2004-04-03`; the package reports `year = "2004-04-03"` and `standaloneDate = ""`. Writing `.standaloneDate` (`0304`, `0403`, or a full date) fails with:

```text
verificationFailed(["Patched semantic field standaloneDate differs after save.",
                    "Patched field standaloneDate differs after save."])
```

`.releaseDate` (TDRL extension) similarly fails verification on a v2.3 tag. The original bytes remain unchanged. AudioMator therefore does not claim ID3v2.3 independent DATE/RELEASEDATE support; YEAR remains writable. Package-owner tests should read actual TYER/TDAT without flattening them into TDRC and verify TDAT/TDRL set/clear independently.

### YEAR/DATE PropertyMap alias verification

TagLib projects both YEAR and the independent DATE into the legacy PropertyMap `DATE` key on ID3/MP4. On a file without a YEAR value:

```swift
try TagLibMetadataManager.applyMetadataPatch(
    MetadataPatch(fields: [.standaloneDate: .text("2008-03-04")]), to: url
)
```

fails with `verificationFailed(["Unedited PropertyMap field DATE changed during the patch."])`. Removing DATE on ID3-backed tags fails the same way. The former `TagLibDateCompanion` workaround has been removed because repeating an unedited sibling is not independent write intent. AudioMator now sends only requested date fields and surfaces the dependency failure; it does not substitute a companion or raw write. Package-owner fix: verify native YEAR/DATE slots instead of the legacy PropertyMap projection.

### Xiph YEAR write drops DATE

Set `.year = 2004` and `.standaloneDate = 2008-03-04` on FLAC or Ogg, then write only `.year = 2005`. Observed: the native `DATE` key disappears while `YEAR` becomes `2005`. The same companion (repeating the exact DATE value in the YEAR patch) preserves it. Package-owner tests should assert unrelated YEAR writes preserve DATE on Vorbis Comment.

### ID3 MusicBrainz recording-ID removal

```swift
try TagLibMetadataManager.applyMetadataPatch(
    MetadataPatch(fields: [.musicBrainzTrackID: .remove]), to: mp3URL
)
```

Observed: `operationFailedWithUnderlying(... "Each ID3v2 frame ID must be exactly four uppercase ASCII letters or digits")`. Other typed removals succeed. Package-owner tests should cover UFID removal and byte preservation.

### Formatted ID3 number text with a zero total

`MetadataNumberTextPatch(trackNumberText: "7/0")` is rejected as `ambiguousNumberRecovery(field: "track", identities: [])` on ID3-backed formats. Typed `.track`/`.trackTotal` component edits and number-only removals work. AudioMator uses the typed path and does not parse or repair the text. Package-owner tests should distinguish “total 0/absent” from contradictory candidates.

### MP4 formatted text padding

`writeTrackNumberText("07/12", ...)` now reads back `7/12` on MP4 without a normalization warning. AudioMator reports the displayed normalized pair and does not create private text atoms.

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


## Independent mapping audit — 2026-11-10

See [the current mapping audit](../Engineering/MAPPING_CONFORMANCE_2026-11-10.md). In a direct 0.7.0 package probe, editing FLAC YEAR alone removes the independently stored DATE. This disproves complete mapping conformance. The application no longer uses `TagLibDateCompanion`; it rejects this unsafe operation before mutation. Earlier companion descriptions and green-suite evidence describe the superseded workaround, not current behavior. MP4 Date-only editing without that workaround passed a direct probe.

Unknown advisory codes are preserved during unrelated saves and same-file exchange round trips. Assigning one to a different value/file is explicitly unsupported by the current typed package API and is rejected in preview and execution; it is never converted to unset.

## Post-0.7.2 state-coverage candidate

The normal remote 0.7.2 pin still has the independently reproduced absent-Year/present-Date MP4 Comment/Lyrics defect. `codex/metadata-state-coverage-repairs` is an unreleased package candidate; app tests use the explicit ignored local workspace. The candidate repairs native projection replay and low-level date ownership, array preservation, Artist/ARTISTS and ASF validation/custom-field paths. [Current acceptance](../Engineering/METADATA_STATE_COVERAGE_2026-11-11.md) records actual tests and does not certify the unchanged published tag. No application companion-date or raw-write workaround is installed.
