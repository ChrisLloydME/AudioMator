# Metadata Pipeline

This document describes how AudioMator reads metadata into application state,
turns edits into writes, and interprets the result. It is the reference for
changes to `Domain/MetadataEditing`, `Infrastructure/TagLib`, and the write
extensions under `Features/Main/ViewModels`.

## Boundary Summary

AudioMator does not parse or write container formats itself. It delegates all
container work to the `TagLibAudioMetadata` Swift package and keeps only:

- application metadata semantics (fields, drafts, number text, artwork intent),
- format-capability preflight,
- conflict policy and file-identity validation,
- mutation scheduling, cancellation, reload, and presentation,
- raw PropertyMap editing and dump formatting.

The contract is declared in
`AudioMator/Domain/MetadataEditing/AudioMetadataPipeline.swift`.

```swift
protocol AudioMetadataPipeline: Sendable {
    func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile
    func conflictSnapshot(for url: URL) throws -> MetadataSnapshot
    func metadataFileVersion(at url: URL) throws -> MetadataFileVersion
    func rawMetadataDumpText(for url: URL) -> String?
    func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap
    func writeMetadata(_ edit: MetadataEditPayload, to url: URL,
                       expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult
    func writeRawMetadataPatch(_ patch: RawMetadataPatch, to url: URL,
                               expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult
    func eraseAllMetadata(at url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult
    func writeTrackNumberText(_ trackNumberText: String, discNumberText: String?,
                              to url: URL, verifyAfterWrite: Bool,
                              expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult
}
```

The concrete adapter is
`Infrastructure/TagLib/TagLibAudioMetadataPipeline.swift`. Only the composition
root constructs it in production.

## Package Interfaces Used

The app calls the following public package entry points. Their behavior is owned
by the package; this list records the integration surface, not a reimplementation
of its documentation.

| App call site | Package API |
| --- | --- |
| `loadAudioFile` | `TagLibMetadataManager.readSnapshot(from:)`, `AudioFile(...)` adapter |
| Conflict baseline/read | `TagLibMetadataManager.readSnapshot`, `fileVersion` |
| Semantic write | `TagLibMetadataManager.applyMetadataPatch(_:to:expectedVersion:)` |
| Raw write | `TagLibMetadataManager.applyRawMetadataPatch(_:to:expectedVersion:)` |
| Erase | `TagLibMetadataManager.eraseAllMetadataWithVerification(from:expectedVersion:)` |
| Number text | `TagLibMetadataManager.writeTrackNumberText(...)` |
| Raw inspection | `rawMetadataResult(from:)`, `bestEffortRawMetadataText(from:)`, `readMetadataResult(from:)` |
| Capability discovery | `readableExtensions`, `writableExtensions`, `formatCapabilities` |

Shared semantic types imported into Domain: `MetadataFieldKey`,
`MetadataFileVersion`, `RawMetadataPatch`, `MetadataPatch`,
`MetadataPatchValue`, `MetadataSnapshot`, `MetadataFieldRegistry`,
`RawMetadataDump`, `StructuredArtwork`, `ExplicitAdvisory`,
`MetadataNumberTextPatch`, and `TagLibManagerError`. This is the controlled
dependency recorded in [ADR 0003](Decisions/0003-metadata-contract-and-taglib-adapter.md).

## Loading

```mermaid
flowchart TD
    A[AudioFile(url,id)] --> B[capture fingerprint]
    B --> C[TagLib readSnapshot]
    C --> D[copy basic tags + raw/structured baseline + fileVersion]
    D --> E{AVFoundation credits needed?}
    E -->|yes| F[load metadata items, read TEXT]
    E -->|no| G[credits = empty]
    F --> H[technical fallback if TagLib values missing]
    G --> H
    H --> I[duration, bitrate, sample rate, channels, format]
    I --> J[artwork bytes from snapshot]
    J --> K{fingerprint and fileVersion still equal?}
    K -->|yes| L[return AudioFile]
    K -->|no| M[throw TagLibManagerError.fileChanged]
```

Key rules:

- The TagLib snapshot is the **editable-tag authority**. AVFoundation supplies
  display-only credits and technical fallbacks.
- Credits (`TEXT`) are read through AVFoundation only for formats where the
  snapshot does not establish presence/absence: MP3/MP2/WAV/AIFF/AIF/TTA when an
  ID3 `TEXT` frame exists, and formats whose ID3 frames are not exposed. MP4 and
  Ogg-family containers skip the credits read.
- Technical values fall back to AVFoundation only when the TagLib value is
  non-positive or missing.
- Artwork bytes come from the snapshot's editable projection.
- The loader captures a fingerprint before the read and revalidates the
  fingerprint and the package file version after all awaits. A mismatch throws
  `fileChanged`; the adapter retries a **read** once, never a write.
- The snapshot also stores a `MetadataConflictBaseline` containing the raw value
  map and structured ID3/MP4/ASF/artwork/comment/lyrics projections.

### Missing, unsupported, and malformed metadata

- Missing tags become empty strings, zero numbers, or `nil` artwork/advisory.
- Malformed or unreadable sources throw; import reports a per-file failure and
  keeps successfully loaded siblings.
- Container-native structures that TagLib does not project into PropertyMap are
  not surfaced in the raw editor; Tag Inspector may still show them.
- Legacy ID3v1 values are preserved in the raw dump and explained with
  compatibility notes; the modern TagLib property value is treated as
  authoritative.

## Representation

The editable snapshot fields are defined in `Domain/AudioFiles/AudioFile.swift`.
The draft (`SingleFileEditModel`) mirrors them and adds artwork intent.

### Number fields

Track and disc data is represented by:

- numeric `track`, `trackTotal`, `disc`, `discTotal`,
- display text `trackNumberText`, `discNumberText`,
- derived field text used by the inspector.

`AudioTagNumberText` and `AudioTagNumberPair` implement parsing and
write-expectation checks. A blank numeric field clears the value; text may retain
padding such as `02/09`. When writing, the adapter sends separate number and
total fields plus optional number text.

### Year and release date

`year` maps to the package's `date` field, while `releaseDate` maps to its
release-date field. They remain separate edit intents. Containers that share one
slot can reject an independent year edit; the app does not merge them silently.

### Content advisory

`ContentAdvisory` has three values (`notExplicit`, `explicit`, `clean`) and the
draft may be unset. The adapter maps unset to `.unspecified` only when the
advisory changed. Raw non-advisory values are preserved by the package.

### Artwork

`ArtworkEditAction` is `unchanged`, `replace(PendingArtwork)`, or `remove`.
Replacement carries bytes and a MIME type. The adapter converts this into a
`MetadataArtworkPatch` with one `StructuredArtwork` entry, or `.removeAll`.

## Write Preflight

Before any semantic write, `persistMetadataEdit`:

1. refuses if the snapshot is marked refresh-required,
2. checks `isTagWriteSupportedExtension` against the runtime writable extensions,
3. builds `MetadataEditPayload` compared to the baseline snapshot,
4. expands the requested fields with advisory and number-text companions,
5. looks up `AudioFormatSupport.writableMetadataFields(for:)`,
6. refuses the write if any requested field is unsupported, naming the fields.

`nil` capability information means the format is not known to the app's snapshot;
the write is left to the package's own validation. This is a deliberate
fail-open for unknown capability data, offset by package verification and error
reporting.

## Payload Construction

`MetadataEditPayload` carries all editable values, the changed-field set,
advisory/number-text change flags, and artwork intent.

`MetadataPipelineSupport.metadataPatch(from:)` then:

- includes only fields in `changedFields`,
- trims text; empty text becomes `.remove`,
- builds separate track/disc number text, falling back to `"number/total"` only
  when no explicit text was supplied,
- includes advisory only when it changed,
- includes artwork only when changed,
- includes number text only when the corresponding text flag changed.

An unchanged revision with an empty patch performs no write but rechecks the
file version.

## Conflict Resolution

`MetadataConflictResolver.writeMetadata` runs inside the file mutation
reservation:

1. Validate that the path, device, and inode still match the expected snapshot.
2. Read the current package file version.
3. If unchanged, write the original patch with the original expected version.
4. If changed:
   - read a fresh verified snapshot,
   - stop for `requireReload`,
   - compare edited semantic groups against the baseline and current snapshot,
   - for `preferDiskChanges`, drop conflicting groups and record the discarded
     fields,
   - for `mergeNonConflicting`, stop if any edited group changed on disk and did
     not converge exactly,
   - for `preferUserChanges`, keep the draft values,
   - write against the fresh snapshot's version.

Field groups are conservative:

- track + track total,
- disc + disc total,
- year + release date,
- performer + musician credits,
- all artwork as one group.

A group is considered converged only when the exact single property value
matches; the basic tag projection alone is not trusted.

Raw writes use the same policy but operate on exact key-level deltas. Only the
edited semantic groups (or the edited custom key) are replaced; unrelated keys,
arrays, and external additions are preserved.

See [File Revision and Reload](FILE_REVISION_AND_RELOAD.md) for the full policy
matrix and detection limits.

## Persistence and Verification

The package owns:

- container-specific encoding (ID3v2, MP4, Xiph/PropertyMap, ASF, WAV, and
  others it reports),
- atomic commit behavior,
- post-write verification,
- the opaque expected-version guard,
- durability reporting.

AudioMator interprets the returned `warnings` and commit status:

- normal warnings are surfaced in the HUD and save issue log,
- `TagLibManagerError.committedButDurabilityUncertain` is converted to
  `AudioMetadataCommitStatus.durabilityUncertain` and reported as committed,
- `TagLibManagerError.fileChanged` is surfaced as a revision conflict,
- any other error becomes a failure message.

Number-text warnings receive app-side normalization: if the numeric number/total
readback matches the expected text, the warning becomes "formatting was
normalized by the container" or is dropped when the container added a total the
user did not request.

## Reload

After a successful write, `MetadataFileMutationExecutor` reloads the file through
the pipeline with a 60-second timeout while still holding the path reservation.

- Success: `MetadataFileMutationSuccess` carries the new snapshot.
- Failure/timeout: carries the write result plus `reloadErrorDescription`; the
  app reports "saved but could not refresh".
- Cancellation: only observed before the write starts; a started commit always
  yields the real result.

The late reload result is discarded if its generation is stale. See
[State and Mutation Model](STATE_AND_MUTATION_MODEL.md).

## Raw Metadata Editing

`RawMetadataValueMap` is `[String: [String]]` keyed by uppercase property key.

- Loading uses `rawMetadataResult` and preserves value order.
- Saving computes an exact delta from the original map:
  - set keys whose values changed,
  - remove keys absent from the draft,
  - leave all other keys untouched.
- The raw editor deliberately bypasses semantic field preflight because it is a
  low-level tool; it still uses the shared reservation, expected version, and
  conflict policy when a baseline is available.
- If no conflict baseline exists, the older strict path uses the expected version
  without rebasing.

## Erase All Metadata

Erase is exposed only as a destructive batch operation with an unchanged-revision
requirement. It calls `eraseAllMetadataWithVerification`. Success is best effort
by container: supported tag surfaces differ, and the app reports warnings rather
than claiming every native structure was removed.

## Format-Specific Behavior

The app does not maintain a per-format write table. It consumes the package's
capability snapshot and must be tested per format for behavior that matters.
Known cross-format differences documented by AudioMator include:

- ID3 and Xiph formats can hold year and release date independently.
- MP4 has one standard date slot.
- MP4 track/disc use `trkn`/`disk`; containers may normalize combined text.
- Multi-artwork roles are not uniformly writable; AudioMator writes a single
  selected cover.
- Some number-only or total-clearing operations can fail safely without changing
  the file; see
  [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md).

## Error Contracts

| Error | Meaning | App behavior |
| --- | --- | --- |
| `TagLibManagerError.fileChanged` | Source read revision mismatch or expected-version mismatch | Fail closed; report reload/conflict; never retry a commit with a cleared version |
| `TagLibManagerError.committedButDurabilityUncertain` | Commit observed, directory durability not confirmed | Report success with warning; do not encourage retry |
| Package verification error | Write completed but readback differed | Failure or warning depending on surface; file may already be changed |
| Cocoa file errors | Permission, missing file, access denied | Failure; ask for folder access when applicable |
| Cancellation | Task cancelled before irreversible work | Report cancelled; no write |

## Known Gaps and Unverified Areas

- The package's internal representation and verification logic were not audited
  in this repository; the app documents the interface it consumes.
- Positive coverage that the container-normalization warning is emitted is
  limited. Existing integration tests assert absence for current fixtures.
- Multi-artwork write behavior is not claimed; only single-cover replacement is
  exercised.
- Network-volume and file-provider durability characteristics are not measured.

## Related Documents

- [Architecture Overview](OVERVIEW.md)
- [State and Mutation Model](STATE_AND_MUTATION_MODEL.md)
- [File Revision and Reload](FILE_REVISION_AND_RELOAD.md)
- [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md)
