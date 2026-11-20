# Metadata Pipeline

This document describes how AudioMator reads metadata into application state, turns edits into writes, and interprets the result. It is the reference for changes to `Domain/MetadataEditing`, `Infrastructure/TagLib`, and the write extensions under `Features/Main/ViewModels`.

AudioMator pins published `TagLibAudioMetadata` **0.8.1** (revision `b8ed5475761cb50bacdd7dcd4f6e2f61142303d0`) through the normal Xcode project and committed `Package.resolved`; there is no local override in normal builds. The shared contract is **`AM-TLAM-MAPPING-2.2`** (see [Metadata Mapping Specification](METADATA_MAPPING_SPEC.md)); adoption evidence is recorded in [Published 0.8.1 Debug adoption](../Engineering/TAGLIB_081_DEBUG_ADOPTION_2026-11-17.md) and current restrictions in [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md).

## Boundary Summary

AudioMator does not parse or write container formats itself. It delegates all container work to the `TagLibAudioMetadata` Swift package and keeps only:

- application metadata semantics (fields, drafts, number text, artwork intent),
- format-capability preflight,
- conflict policy and file-identity validation,
- mutation scheduling, cancellation, reload, and presentation,
- raw metadata value-map editing and dump formatting.

The contract is declared in `AudioMator/Domain/MetadataEditing/AudioMetadataPipeline.swift`. It covers loading, conflict-snapshot reading, the opaque file version, raw dump/value-map reads, semantic writes, exact raw patches, and erase-all. Writes have a version-only form and a version+audio-content-identity form; the adapter also reports whether it needs transactional directory access. `TagLibAudioMetadataPipeline` implements all of it and is constructed only by the composition root. The protocol's default extension methods throw `featureUnsupported`/`MetadataAudioContentError.unavailable` for capabilities a fake does not provide, and `writeRawMetadataValueMap` computes an exact key-level delta over `writeRawMetadataPatch`.

## Package Interfaces Used

The app calls the following public package entry points. Their behavior is owned by the package; this list records the integration surface, not a reimplementation of its documentation.

| App call site | Package API |
| --- | --- |
| `loadAudioFile` | `TagLibMetadataManager.readSnapshot(from:includingAudioContent:)`, `numberingInventory(at:)`, then the app's `AudioFile` loader |
| Conflict baseline/read | `TagLibMetadataManager.readSnapshot(from:includingAudioContent:)`, `fileVersion(at:)` |
| Semantic write | `TagLibMetadataManager.applyMetadataPatch(_:to:expectedVersion:)` and its audio-content overload |
| Raw write | `TagLibMetadataManager.applyRawMetadataPatch(_:to:expectedVersion:)` and its audio-content overload |
| Erase | `TagLibMetadataManager.eraseAllMetadataWithVerification(from:expectedVersion:)` |
| Raw inspection | `rawMetadataResult(from:)`, `bestEffortRawMetadataText(from:)` |
| Capability discovery | `readableExtensions`, `writableExtensions`, `formatCapabilities`, `MetadataFieldRegistry` schemas |

Shared semantic types imported across the boundary include `MetadataFieldKey`, `MetadataFileVersion`, `MetadataSnapshot`, `MetadataAudioContentIdentity`, `MetadataAudioContentError`, `RawMetadataPatch`, and the numbering inventory types. This is the controlled dependency recorded in [ADR 0003](Decisions/0003-metadata-contract-and-taglib-adapter.md).

The Infrastructure adapter additionally uses `MetadataPatch`, `MetadataPatchValue`, `MetadataFieldRegistry`, `RawMetadataDump`, `StructuredArtwork`, `ExplicitAdvisory`, and `TagLibManagerError`. Those concrete types must not move into Domain.

## Loading

```mermaid
flowchart TD
    A[AudioFile(url,id)] --> B[capture fingerprint]
    B --> C[TagLib readSnapshot incl. audio content]
    C --> D[numberingInventory; verify same fileVersion]
    D --> E[copy basic tags + raw/structured baseline + fileVersion]
    E --> F{AVFoundation credits needed?}
    F -->|yes| G[load metadata items, read TEXT]
    F -->|no| H[credits = empty]
    G --> I[technical fallback if TagLib values missing]
    H --> I
    I --> J[duration, bitrate, sample rate, channels, format]
    J --> K[artwork bytes from snapshot]
    K --> L{fingerprint and fileVersion still equal?}
    L -->|yes| return AudioFile
    L -->|no| M[throw TagLibManagerError.fileChanged]
```

Key rules:

- The TagLib snapshot is the **editable-tag authority**. AVFoundation supplies display-only credits and technical fallbacks.
- Credits (`TEXT`) are read through AVFoundation only when the snapshot does not establish presence/absence: MP3/MP2/WAV/AIFF/AIF/TTA when an ID3 `TEXT` frame exists, and other formats whose ID3 frames are not exposed. MP4 and Ogg-family containers skip the credits read; unknown extensions fall back to the AVFoundation read.
- Technical values fall back to AVFoundation only when the TagLib value is non-positive or missing.
- Artwork bytes come from the snapshot's editable projection.
- The loader captures a fingerprint before the read and revalidates the fingerprint and the package file version after all awaits. A mismatch throws `fileChanged`; the adapter retries a **read** once, never a write.
- On success the loader is the only production route that constructs the write-authorizing observation (`AudioFile.Observation`): requested ID, lexical URL, nonoptional package version, conflict baseline, and the verified fingerprint, all from that one read. A display or rename/recovery projection carries no observation; metadata writes require a coherent observation plus a clear recovery decision.
- The snapshot also stores a `MetadataConflictBaseline` containing the raw value map, structured ID3/MP4/ASF/artwork/comment/lyrics projections, and optional package audio-content identity. `TagLibNumberingProjection` converts the package number inventory into displayed number/total/text.

### Reviewed writes and commit admission

Strict metadata workflows (`Domain/MetadataEditing/ReviewedMetadataWrite.swift`,
`AudioViewModel+ReviewedMetadataWrite.swift`, `MetadataFileMutationExecutor.swift`)
do not write from a live editor model:

- `ReviewedMetadataTarget` captures the logical file ID, operational URL,
  fingerprint and nonoptional package revision from one coherent observation.
  A display or recovery projection cannot produce a target.
- `ReviewedMetadataWrite` freezes a semantic payload, a raw patch or erase-all.
  `MetadataWriteProjection` is the adapter-owned, I/O-free summary of the exact
  field and number-component operations the same deterministic encoder will
  commit; missing capability information marks every requested field
  unsupported, and an empty request is a no-op that never reaches a writer.
- Plan-time eligibility rejects stale, recovery-blocked, unsupported or missing
  targets before any authorization prompt. Under the captured path reservation
  the owner revalidates membership, URL and recovery state, then registers a
  per-file `MetadataCommitPermit`.
- Cancellation synchronously revokes a pending permit. The detached worker
  verifies the captured fingerprint and admits the permit immediately before the
  synchronous package write; a revoked permit performs zero package calls. An
  admitted commit cannot be interrupted, so it reports its real outcome,
  warnings included, and is never retried. A cancelled queued write is reported
  as a cancelled outcome, not as a failure.
- Inspector and Raw Metadata Editor drafts use a distinct draft-aware route that
  keeps their conflict baseline, policy validation and audio-identity checks;
  the strict route passes the captured nonoptional revision to the package.
  The documented boundary is enforced by unit, execution and full-gate tests.
  After the final family migration the mixed optional-version entry point was
  removed: no production metadata write forwards an optional expected revision,
  and `ReviewedMetadataTarget` is the only write-authorization value.

### Missing, unsupported, and malformed metadata

- Missing tags become empty strings, zero numbers, or `nil` artwork/advisory.
- Malformed or unreadable sources throw; import reports a per-file failure and keeps successfully loaded siblings.
- Container-native structures that TagLib does not project into PropertyMap are not surfaced in the raw editor; the raw metadata dump and field guide can still show them.
- Legacy ID3v1 values are preserved in the raw dump and explained with compatibility notes; the modern TagLib property value is treated as authoritative.

## Representation

The editable snapshot fields are defined in `Domain/AudioFiles/AudioFile.swift`. The draft (`SingleFileEditModel`) mirrors them and adds artwork intent.

### Number fields

Track and disc data is represented by:

- numeric `track`, `trackTotal`, `disc`, `discTotal`,
- display text `trackNumberText`, `discNumberText`,
- derived field text used by the inspector.

`AudioTagNumberText` and `AudioTagNumberPair` implement parsing and write-expectation checks. Track and disc are component intents: a number edit submits only the changed number component, a total edit submits only the changed total, and a cleared component is an explicit removal. The untouched sibling is never rewritten or removed. Individual track/disc components preserve a positive total when the number is cleared (the package serializes the pair); whole-pair clearing removes both components. MP4 uses native `trkn`/`disk`; ID3 uses combined `TRCK`/`TPOS` text; Xiph/APE use separate keys. The package may normalize displayed text padding (for example MP4 `07` to `7`); verification compares numeric values, so a text-representation difference is not by itself a failed write. The app does not add an app-side number-text warning-normalization layer.

The package's `numberingInventory` states (`native`, `recoveredLegacy`, `ambiguous`) are projected by `TagLibNumberingProjection`: a canonical value wins, an unambiguous recovered value is displayable, an ambiguous candidate is never guessed (the projected component becomes zero rather than an arbitrary first candidate), and unresolved/malformed text is preserved for correction rather than parsed to zero. Reading never migrates or rewrites a file. `MetadataEditPayload.numberPairValidationMessage` rejects non-numeric edited number text and out-of-range totals. The low-level raw editor remains the explicit exception.

### Year and release date

`year`, `date`, `releaseDate` and `originalReleaseDate` are four independent fields with separate drafts, dirty tracking, clear actions, merged-selection state and conflict groups:

| App semantic identity | Package typed field |
| --- | --- |
| `year` | `.year` (complete stored YEAR text; the legacy `.date` YEAR-slot alias is never submitted) |
| `date` | `.standaloneDate` |
| `releaseDate` | `.releaseDate` |
| `originalReleaseDate` | `.originalReleaseDate` |

No value is inferred, synchronized, completed or truncated; `2004-07-15` remains complete YEAR text.

**Independent-date behavior.** No companion date writes are synthesized. Conflict comparison for the four date identities uses exact native frames/atoms through `TagLibDateNativeProjection` rather than the legacy PropertyMap `DATE` projection, which can alias YEAR and DATE. Existing ID3v2.3 separate date fields are treated as unverified for export, file transfer and filename extraction: those routes reject separate date fields for ID3v2.3 tags instead of inferring native values. Direct user-entered date text (typed, pasted, CSV/text-imported, or filename-extracted) passes through without AudioMator date-format checks, date-specific rewriting, or time-zone inference; format-capability preflight and clear semantics still apply, and writer rejections identify the affected file and field while retaining the draft for correction. When the user applies a choice from the native macOS date/time picker (`MetadataDatePickerEligibilityResolver` + `MetadataDateTimeCodec`), the generated string follows the destination tag's format and precision, including UTC conversion. The picker resolves the full local clock time before checking whether the destination can represent it at the selected precision. It does not truncate a converted instant to fit. Explicitly turning off seconds changes the requested precision and drops seconds when the instant would otherwise be inexact at minute precision. Inspector eligibility uses the semantic target. Metadata Editor eligibility requires an established mapping for the exact raw write key, since the semantic registry alone does not establish the destination of a PropertyMap write. APEv2 raw `DATE` is ineligible because it can address the native `YEAR` item.

### Content advisory

`ContentAdvisory` has three values (`notExplicit`, `explicit`, `clean`) and the draft may be unset. The adapter maps unset to `.unspecified` only when the advisory changed; unchanged advisory is never submitted. Raw non-advisory values are preserved by the package.

### Artwork

`ArtworkEditAction` is `unchanged`, `replace(PendingArtwork)`, or `remove`. Replacement carries bytes and a MIME type; the adapter converts it into a `MetadataArtworkPatch` with one `StructuredArtwork` entry, or `.removeAll`.

Artwork selection, photo-library import and clipboard PNG/TIFF import normalize with ImageIO on the concurrent executor, then publish the draft on the main actor. `ArtworkImageNormalizer` bounds input at 50 MiB, 4096 px output dimension, and 4096×4096 source pixels. Post-rename reloads also use a detached worker. Visible-file rebuilding publishes the recovered list once.

Every asynchronous artwork handoff — online lookup/download and the Finder, photo-library and clipboard single and batch imports — captures the Inspector destination before its first suspension: the F3 draft session ID, the independent artwork command generation, the ordered captured target IDs and the source context. Data is staged only through the guarded commit, which revalidates the same draft session/command generation, the full ordered target set, source membership, artwork write support and recovery state immediately before the draft mutation. A stale destination is rejected with a localized message; the commit never creates or steals a draft, never substitutes the current selection, and never stages a surviving subset. The online lookup's search and per-candidate download fault channels live in the lookup sheet, so a failed download leaves the result grid and selected candidate available for retry or alternate selection without creating or altering a draft. Nothing reaches disk until the separate Inspector Save, which still uses the normal reviewed-write route, conflict checks, and per-field format preflight.

## Write Preflight

Every production semantic write is planned before any authorization prompt and
runs through either the strict reviewed route or the draft-aware
Inspector/Raw Editor route. The removed mixed helper (`persistMetadataEdit`) and
its optional expected-version/expected-fingerprint forwarding no longer exist in
production source.

1. capture a failable `ReviewedMetadataTarget` from the reviewed observation
   (missing fingerprint or package version, or a recovery block, means the file
   is not writable),
2. build `MetadataEditPayload` compared to the reviewed baseline snapshot,
3. obtain the adapter-owned `MetadataWriteProjection` from the same deterministic
   encoder the commit uses; malformed number/date text and unsupported fields are
   rejected here, and a no-op projection never reaches a writer,
4. look up `AudioFormatSupport.writableMetadataFields(for:)`. Missing capability
   information marks every requested field unsupported (fail closed); an unknown
   format is never treated as permission to write,
5. revalidate current membership, URL, recovery state and the captured tokens
   under the path reservation before the package writer runs.

The draft-aware route keeps the Inspector/Raw Editor conflict baseline, conflict
policy and audio-continuity validation; the strict route passes the captured
nonoptional package revision and never selects a merge policy or substitutes a
newer version. The raw editor keeps its documented low-level exception from
semantic field preflight, but it still requires a reviewed target and a captured
nonoptional revision; there is no unversioned fallback.

## Payload Construction

`MetadataEditPayload` carries all editable values, the changed-field set, advisory and number-text change flags, typed container-exclusive field intents, and artwork intent.

`MetadataPipelineSupport.metadataPatch(from:)` then:

- includes only fields in `changedFields`,
- trims text; empty text becomes `.remove`,
- submits only changed number components as `.integer`, or `.remove` when cleared; it never sends combined number text and never touches an unchanged sibling,
- encodes requested non-empty fields whose registry accepts only integers as `.integer`; an empty edit remains `.remove`,
- passes typed `containerFields` through unchanged,
- includes advisory only when it changed,
- includes artwork only when changed.

An unchanged revision with an empty patch performs no write but rechecks the file version.

### Store identifier encoding

The dedicated Inspector/provider/exchange models retain Album, Artist and Catalog Store IDs as display strings. At the shared semantic patch boundary, requested non-empty fields whose registry accepts only integers are encoded as `.integer`; an empty edit remains `.remove`. Text identifiers such as MusicBrainz IDs, barcode and catalog number are not converted. Invalid or overflowing numeric IDs remain validation failures: no clamping, truncation, field dropping or partial per-file save is allowed. Untouched fields are filtered before conversion.

## Conflict Resolution

`MetadataConflictResolver.writeMetadata` runs inside the file mutation reservation and consumes one observation, so the conflict baseline, fingerprint, and package version always share provenance. The equal-version fast path is safe for that reason; a changed revision still requires verified audio identity before rebasing:

1. Validate that the path, device, and inode still match the expected snapshot.
2. Read the current package file version.
3. If unchanged, write the original patch with the original expected version.
4. If changed:
   - read a fresh verified snapshot including audio identity,
   - require equal, non-nil baseline/current audio identities; otherwise require explicit reload,
   - stop for `requireReload`,
   - compare edited semantic groups against the baseline and current snapshot,
   - for `preferDiskChanges`, drop conflicting groups and record the discarded fields,
   - for `mergeNonConflicting`, stop if any edited group changed on disk and did not converge exactly,
   - for `preferUserChanges`, keep the draft values,
   - write against the fresh snapshot's version and the original audio identity.

Field groups follow actual native storage:

- track + track total,
- disc + disc total,
- performer + musician credits,
- YEAR, DATE, RELEASE DATE and ORIGINAL RELEASE DATE are each an independent group,
- artwork is compared as a whole.

A group is considered converged only when the exact single property value matches; the basic tag projection alone is not trusted, and date identities and container-exclusive fields never auto-converge.

Raw writes use the same policy but operate on exact key-level deltas. Only the edited semantic groups (or the edited custom key) are replaced; unrelated keys, arrays, and external additions are preserved.

See [File Revision and Reload](FILE_REVISION_AND_RELOAD.md) for the full policy matrix and detection limits.

## Persistence and Verification

The package owns:

- container-specific encoding (ID3v2, MP4, Xiph/PropertyMap, ASF, WAV, and others it reports),
- atomic commit behavior,
- post-write verification,
- the opaque expected-version guard,
- durability reporting.

AudioMator interprets the returned `warnings` and commit status:

- normal warnings are surfaced in the HUD and save issue log,
- `TagLibManagerError.committedButDurabilityUncertain` is converted to `AudioMetadataCommitStatus.durabilityUncertain` and reported as committed,
- `TagLibManagerError.fileChanged` is surfaced as a revision conflict,
- package numbering ambiguity (`MetadataPatchValidationError.ambiguousNumberRecovery`) becomes a field-specific "enter the value you want to save" failure,
- any other error becomes a failure message.

The typed semantic write path is the only numbering write route: number and total components are patched through `applyMetadataPatch` and the package owns encoding, verification and warning text. Package warnings are surfaced as returned; the app does not rewrite or filter number-text warnings.

## Reload

After a successful write, `MetadataFileMutationExecutor` reloads the file through the pipeline with a 60-second timeout while still holding the path reservation.

- Success: `MetadataFileMutationSuccess` carries the new snapshot.
- Failure/timeout: carries the write result plus `reloadErrorDescription`; the app reports "saved but could not refresh".
- Cancellation: only observed before the write starts; a started commit always yields the real result.

The late reload result is discarded if its refresh generation is stale. See [State and Mutation Model](STATE_AND_MUTATION_MODEL.md).

## Raw Metadata Editing

`RawMetadataValueMap` is `[String: [String]]` keyed by uppercase property key. A value list is ordered data: duplicates, an empty element, and a line break embedded inside one element are distinct and preserved.

- Loading uses `rawMetadataValueMap`, which preserves value order. A missing key is represented only by absence; it is not the same as an existing empty array, and neither is the same as one blank element.
- Metadata Editor presents shared AudioMator field names and purposes; raw keys remain the row IDs and write identities. Selected suggestion keys are kept separately from their visible labels. Uppercase raw aliases are not canonicalised as a side effect of editing. See [field guide](../Product/METADATA_FIELD_GUIDE.md#shared-field-names-in-metadata-editor).
- The field editor works on an ordered element list. Its commit path accepts an array and never derives element boundaries by splitting text; an existing raw key keeps its exact identity. An empty list is never a key deletion: the last element cannot be removed from the list and key removal is the separate Delete Field command. A mixed selection requires an explicit replacement list.
- A text-utility preview captures per-file/key before/after arrays for the current presentation, target set and draft generation. `TextEditPipeline` transforms each element independently; Apply stages exactly the captured after-arrays and never inserts a missing key. A preview whose generation, targets, session or before-values changed is rejected with no mutation.
- Done captures the per-file/key before/after arrays for pending targets at apply start. The reviewed raw route requires a coherent reviewed target and captured conflict baseline and fails closed otherwise; it freezes the exact patch from the captured original map (never the current disk) and never writes an unchanged target. Unrelated keys and value arrays are preserved by the package's exact raw patch. See [ADR 0006](Decisions/0006-reviewed-operation-boundary.md).
- A container may reject a blank, duplicate or multiline element. The raw editor keeps its low-level exception from semantic field preflight, so there is no per-key capability preflight; the pipeline reports the failure and the app does not retry with a different write.

## Erase All Metadata

Erase is exposed only as a destructive batch operation with an unchanged-revision requirement. It calls `eraseAllMetadataWithVerification`. Success is best effort by container: supported tag surfaces differ, and the app reports warnings rather than claiming every native structure was removed.

## Format-Specific Behavior

The app does not maintain a per-format write table. It consumes the package's capability snapshot and must be tested per format for behavior that matters. Known cross-format differences documented by AudioMator include:

- ID3, MP4 and Xiph layouts can hold the four date identities independently; ID3v2.3 TDAT and TDRL remain package limitations documented in [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md).
- MP4 YEAR uses the `©day` atom; independent DATE/RELEASE DATE/ORIGINAL RELEASE DATE use freeform extensions.
- MP4 track/disc use `trkn`/`disk`; containers may normalize combined text.
- Multi-artwork roles are not uniformly writable; AudioMator writes a single selected cover.
- Some number-only or total-clearing operations can fail safely without changing the file; see [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md).

## Error Contracts

| Error | Meaning | App behavior |
| --- | --- | --- |
| `TagLibManagerError.fileChanged` | Source read revision mismatch or expected-version mismatch | Fail closed; report reload/conflict; never retry a commit with a cleared version |
| `TagLibManagerError.committedButDurabilityUncertain` | Commit observed, directory durability not confirmed | Report success with warning; do not encourage retry |
| Package verification error | Write completed but readback differed | Failure or warning depending on surface; file may already be changed |
| Cocoa file errors | Permission, missing file, access denied | Failure; ask for folder access when applicable |
| Cancellation | Task cancelled before irreversible work | Report cancelled; no write |

## Number Text Validation

Changed number text is validated centrally before semantic writes through `MetadataEditPayload.numberPairValidationMessage`: non-numeric edited Track/Disc Number text is rejected with an explanation, and edited totals must be a whole number from 0 to 2147483647 or cleared. A total without a number is a valid component intent. Existing non-numeric raw values remain untouched during unrelated edits. See [dependency limitations](../Reference/DEPENDENCY_LIMITATIONS.md).

## Known Gaps and Unverified Areas

- The package's internal representation and verification logic were not audited in this repository; the app documents the interface it consumes.
- Positive coverage for a package-emitted text-normalization warning remains limited; the app no longer renders a normalization warning itself.
- Multi-artwork write behavior is not claimed; only single-cover replacement is exercised.
- Network-volume and file-provider durability characteristics are not measured.

## Related Documents

- [Architecture Overview](OVERVIEW.md)
- [Metadata Mapping Specification](METADATA_MAPPING_SPEC.md)
- [State and Mutation Model](STATE_AND_MUTATION_MODEL.md)
- [File Revision and Reload](FILE_REVISION_AND_RELOAD.md)
- [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md)
