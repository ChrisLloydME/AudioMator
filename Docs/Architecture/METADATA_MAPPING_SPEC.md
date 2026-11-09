# Metadata Mapping Specification

Contract ID: `AM-TLAM-MAPPING-2.2`. Decision date: 2026-11-09. Status: **accepted target design; not implemented**. This specification is the refactoring contract, not a claim about 0.6.0 behavior or current capabilities. Existing APIs and tests remain descriptive of the current implementation until explicitly migrated. A normal failing legacy test must not be hidden to claim conformance.

An identical copy is maintained as `Docs/Architecture/METADATA_MAPPING_SPEC.md` in AudioMator. The two copies are one shared contract, not independently editable policies. Any normative change must update both copies, increment the contract version, and state migration and test implications. The package owns native mapping/verification; AudioMator owns edit intent and presentation. Neither repository may silently override the other layer's semantics.

## 1. Sources, scope, and precedence

This document defines the package's metadata interoperability profile. The explicit per-format matrix and divergence decisions are normative. The [TagLib PropertyMap mapping](https://taglib.org/api/p_propertymapping.html), reviewed on 2026-11-09, supplies supplementary engine vocabulary and native mapping context. External application defaults and user-configurable mappings do not override this contract. Cross-tool testing is an interoperability oracle, not a second automatic mapping policy.

The current engine baseline is TagLib 2.3.1, upstream revision `54ae7d8ac45755e286a5c574280f48d5bef93aef`, distributed by package 0.6.0. The online table can describe newer behavior. It does not upgrade the engine or establish write support. In particular, newer documented mappings must be implemented or capability-gated before advertising them.

Resolve a mapping in this order:

1. Data-integrity and explicit divergence decisions in this specification.
2. The fixed native location declared in the target matrix for the exact field identity and tag family/version.
3. A supplementary TagLib mapping explicitly registered for a gap in the matrix, without colliding with another semantic field.
4. An explicitly registered conventional extension in the target matrix, or `unsupported`. Never invent a private field to claim support.

A canonical semantic key is a stable application/package identity; it does not force the engine's PropertyMap projection to have the same name. The adapter must translate from exact native identities where the interoperability profile and the engine PropertyMap dialect disagree. The selected engine is not an authority that can override the compatibility profile. No implementation may silently fall back to a different location after a verification failure.

Version 2.2 removes automatic Year/date projection and treats the fields independently by explicit maintainer decision. Version 2.1 supplemented the unimplemented 2.0 design with the complete MP4/MKV exclusive-field lists and explicit advisory semantics. Version 2.0 superseded the unimplemented 1.0 design. It changes native decisions for conductor, publisher and content group/work/grouping, and introduces a private-number-text retirement policy. It does not change executable code or the package pin. Generic semantic key names may remain TagLib-inspired for source stability; that is not TagLib-first precedence.

The reviewed online sources are references, not runtime dependencies. The explicit matrix and decisions here are the frozen target for the listed fields. Upstream changes need a contract revision. Fields outside the matrix remain preserved/read-only or explicit custom data until a reviewed entry is added. The complete source tables inform future expansion; they do not grant automatic write support or inject new fields into an existing contract.

This contract covers every current package field and every current AudioMator semantic edit, all 26 entries in the reviewed MP4-exclusive list, both MKV-exclusive entries, and generic raw/custom preservation. The exclusive tables overlap the core matrix; their row counts are not additional unique-field counts. New fields must declare a canonical key, value shape, aliases, native locations, version restrictions, preservation group, evidence and migration before becoming writable. No field is supported merely because the container can hold arbitrary bytes.

## 2. Registry and capability model

Each registry entry must contain: stable semantic ID; canonical PropertyMap key; display label; value type/cardinality; native read locations; one preferred write location per family/version; source-dialect names and any engine-PropertyMap translation; qualified alias locations; namespace/case rules; legal value constraints; shared-storage/conflict group; preservation/verification strategy; capability/evidence status; mapping contract version. Presentation aliases must not be stored in the native mapping list.

Capability results must distinguish `native`, `conventionalExtension`, `readOnly`, `unsupported`, and `ambiguous`. Separately report whether the exact operation can round-trip, whether it normalizes text, and whether its behavior is fixture-covered or only upstream-supported. Capability is per field, operation, tag version and concrete layout; extension-only lookup is advisory. Validate the actual source before staging.

The catalog has separate ID3v2.3 and ID3v2.4 columns; section 7 further constrains their codecs. `TXXX(K)` means a text frame whose description is exactly K; `F(K)` means the exact MP4 freeform name `----:com.apple.iTunes:K`. Explicit native atoms take precedence over extension fields. MP4 atom names and freeform namespace/description case are significant; PropertyMap lookup normalization must not destroy them.

For Vorbis Comment and APE, the explicit conventional names selected in this contract form the interoperability profile; preserve actual native field names when reading. Preserve the physical spelling of untouched fields. ASF and RIFF locations are listed explicitly below. Matroska is outside the seven-column core matrix; section 8.2 defines the two MKV-exclusive targets. Preserve/read other raw or structured content where supported, but add no typed write capability until its native targets and collections have a reviewed matrix and verified codec. Unknown or untested native layouts remain unsupported for semantic writes until verified. WAV/AIFF with ID3 must report which tag surface is authoritative and preserve other surfaces; never write ID3 and INFO in parallel merely because both exist.

## 3. Three distinct identities

- **Canonical semantic key**: used in snapshots, provider mapping, typed edits and serialization schemas, e.g. `DATE`, `LABEL`, `TRACKNUMBER`. These are semantic identities, not an assertion about the raw TagLib PropertyMap dialect.
- **Native identity**: frame/atom/attribute/key plus role, language, description, stream or Matroska target where applicable.
- **Presentation name**: localized UI label or namespaced import alias, e.g. `YEAR` or `PUBLISHER`.

Display aliases do not create new stored fields. Different canonical keys never become aliases just because their labels resemble each other. `ARTIST` and `ARTISTS`, `ENCODEDBY` and `ENCODING`, `DATE` and `RELEASEDATE`, `CONTENTGROUP`, `WORK` and `GROUPING`, and the two MusicBrainz track IDs are distinct.

Raw editing keeps native distinctions and exact ordered value arrays. A flattened display string is never an authoritative input for an unchanged semantic field. Do not split a value on commas, slashes or semicolons to infer multiple people, genres or identifiers.

## 4. Independent Year and date fields

**YEAR, DATE, RELEASEDATE and ORIGINALDATE are independent stored fields and independent edit intents.** Year is not derived from any date. No field is automatically filled, synchronized, reconciled, truncated, expanded, or cleared because another one changes. Different years are valid: YEAR=2004 and RELEASEDATE=2017-06-09 must both survive reads, edits, saves and reloads unchanged unless individually selected for editing. This maintainer decision supersedes the year-component/projection design in versions 1.0–2.1.

YEAR uses the declared YEAR location for the selected tag family: ID3v2.3 TYER, ID3v2.4 TDRC, MP4 ©day, Vorbis YEAR, APE YEAR, ASF WM/Year and RIFF ICRD. Some native slots can contain complete date text despite the Year label. Read and preserve the stored value as-is; never silently take its first four characters. Do not manufacture a separate DATE value from that text. New writes validate only the chosen field's actual target representation; validation must not compare its year with another field.

DATE is a separate explicit field. Under the declared ID3 compatibility dialect it is TDAT in v2.3 (legacy DDMM text) and TXXX(DATE) in v2.4; in MP4 the explicit extension is F(DATE), in Vorbis/APE it is DATE, and in ASF it is the explicit DATE text extension. RIFF INFO has no independent typed DATE target in this profile because ICRD is assigned to YEAR. The per-version shapes are different; the editor must show the exact source and permitted shape. It must not combine TYER+TDAT+TIME into a synthesized date or split a date back into those fields. This is a compatibility choice, not an assertion that every tool uses the same names.

RELEASEDATE is the independent **Release Date** field: ID3v2.4 TDRL, Vorbis/APE RELEASEDATE, MP4 F(RELEASEDATE). RELEASETIME is its explicit import/display alias. ORIGINALDATE is the independent original release date. Purchase date (purd) is also independent. Labels must not imply that one is a correction, duplicate, or automatically calculated form of another.

| Intent | Required result |
| --- | --- |
| YEAR=2004, RELEASEDATE=2017-06-09 | Preserve both; the differing years are valid |
| Change Year to 2005 | Change only YEAR; DATE, RELEASEDATE and ORIGINALDATE stay byte/value equivalent within the verification scope |
| Clear Year | Remove only the selected YEAR location and approved same-field aliases |
| Change or clear Date | Change or remove only DATE; Year is untouched |
| Change or clear Release Date | Change or remove only RELEASEDATE; Year and Date are untouched |
| Import different YEAR and DATE/RELEASEDATE values | Accept independently when each target can store its own value |
| One field absent | Leave it absent; no fallback from another field |
| Existing full date text in a Year slot | Preserve the full stored text; do not derive or update another field |
| Requested independent fields cannot coexist in a selected layout | Reject that operation before mutation; never merge or silently overwrite a sibling |

The registry must give each field a distinct native owner. If a legacy engine projection exposes the same physical slot under multiple names, use native provenance to avoid presenting it as two independently stored values. No shared-slot editing or automatic cross-field alias resolution is permitted. Preserve ambiguity and require an explicit native-field selection if identity cannot be established.

Provider assignments are explicit per field: a provider's Release Date targets RELEASEDATE; an explicitly supplied Year targets YEAR; an explicitly supplied original release date targets ORIGINALDATE. A provider lacking Year leaves Year alone. Do not derive Year from a provider date or copy a date into multiple controls. A user-selected source profile can translate a source field name to its declared native equivalent, but it may not invent missing values.

The maintainer's purchased-iTunes example establishes the requirement to retain different Year/Release Date values. It does not establish which atoms that particular file contains; no such file was inspected for this decision. Migration must inspect real native identities rather than infer them from album chronology or where the album was purchased.

## 5. Read precedence, aliases, and preservation

Aliases are scoped by source dialect and container. The import label `DATE` is **not** a global synonym for canonical `DATE`: for ID3 it can mean a legacy day/month field or a custom TXXX field. The import label YEAR maps to semantic YEAR. A TagLib PropertyMap key named DATE may instead represent the native YEAR slot; translate that engine dialect using exact native provenance, never by treating semantic YEAR and DATE as interchangeable. Existing native aliases in the package registry are read-compatibility candidates, not universal aliases or write fan-out instructions.

When a preferred native location is absent, a documented same-meaning alias can supply the projection. When preferred and alias locations agree, present one semantic value but retain source provenance. When they disagree, expose ambiguity and preserve all originals. Do not choose a value by longest string, most complete date, newest-looking year, or arbitrary dictionary order.

An unrelated edit must preserve aliases, multi-values, roles, ordering and exact text, subject only to explicitly reported unavoidable container normalization. Editing an ambiguous semantic field requires an explicit resolution plan naming the locations to replace/remove. A typed clear removes the locations selected by that plan, not every key that resembles the label. Do not create duplicate aliases on save, and do not normalize the whole file just because one field changed.

An empty semantic value is not automatically a deletion. The patch model must distinguish unchanged, set, replace-values and remove. Untouched absent/present-empty distinctions survive raw operations. If a semantic API cannot represent an existing shape without loss, it must preserve it when untouched and reject or request explicit replacement when edited.

## 6. Numbers, text, identifiers, people and binary metadata

Track/disc/movement numbers and totals are independent semantic components with shared-storage groups. A number-only intent preserves the existing total; total-only preserves the number; component removal preserves its sibling; full-pair removal must be explicit. ID3 TRCK/TPOS/MVIN and MP4 trkn/disk require pair-aware serialization. Canonical TRACKTOTAL/DISCTOTAL are virtual components when native storage is a pair, not permission to write a duplicate custom total.

Retain formatted-number intent separately from numeric values. Capability validation covers bounds, number-only, total-only and component removal for each target; never cast overflow or substitute zero for an unrepresentable absence. Numeric readback equality with changed padding is a normalization warning, not automatically a commit failure. Non-numeric identifiers masquerading as numbers remain raw-only. Compare untouched sibling values and complete raw arrays after a typed pair edit.

### 6.1. Total Tracks and Total Discs storage

Total values are first-class semantic components, not private app fields. The names TRACKTOTAL, TOTALTRACKS, DISCTOTAL and TOTALDISCS are not themselves evidence of private data. Their meaning depends on container and source profile. In Vorbis/APE, ordinary explicit total keys are conventional metadata; in ID3/MP4, extra text totals can be redundant aliases of a native pair. Do not delete all fields with these names as a global cleanup.

| Tag surface | Preferred track storage | Preferred disc storage | Total-only representation |
| --- | --- | --- | --- |
| ID3v2.3 / v2.4 | TRCK as number/total | TPOS as number/total | /total, only through a verified native-text codec |
| MP4 | trkn first/second numeric components | disk first/second numeric components | Native first=0 sentinel, second=total; zero is absence, not displayed ordinal 0 |
| Vorbis Comment | TRACKNUMBER and TRACKTOTAL | DISCNUMBER and DISCTOTAL | Total key without a number key |
| APEv2 profile | TRACK and TRACKTOTAL | DISC and DISCTOTAL | Total key without a number key |
| ASF | WM/TrackNumber native text pair | WM/PartOfSet native text pair | Only after the exact /total codec has a passing fixture; otherwise reject |
| RIFF INFO alone | ITRK number only | No typed disc target | Unsupported; choose an existing supported ID3 surface explicitly or reject |

Read legacy TOTALTRACKS/TOTALDISCS aliases where same-meaning provenance is established. In Vorbis/APE, also inspect combined number/total text when separate totals are absent; contradictory combined and separate totals are ambiguous. An unchanged field preserves all native spellings and arrays. Editing a pair may consolidate recognized redundant aliases only through the explicit per-file plan. Canonicalization is not a side effect of loading or editing Title.

#### Legacy standalone number and total aliases

There are two distinct historical problems: standalone total aliases and private formatted-pair provenance. The former can be the only surviving copy of a total and must not be treated as mere padding. Current bridge code recognizes the following standalone MP4 descriptions for pair cleanup; historical ID3 paths also produced separate total frames. This inventory is source/history evidence, not proof that every file came from AudioMator.

| Native surface | Candidate identities | Target classification |
| --- | --- | --- |
| ID3 TXXX descriptions | TRACKTOTAL, TOTALTRACKS | Legacy standalone track total |
| ID3 TXXX descriptions | DISCTOTAL, TOTALDISCS | Legacy standalone disc total |
| MP4 com.apple.iTunes freeform descriptions | TRACKNUMBER, TRACK | Legacy standalone track number or combined text |
| MP4 com.apple.iTunes freeform descriptions | TRACKTOTAL, TOTALTRACKS | Legacy standalone track total |
| MP4 com.apple.iTunes freeform descriptions | DISCNUMBER, DISC | Legacy standalone disc number or combined text |
| MP4 com.apple.iTunes freeform descriptions | DISCTOTAL, TOTALDISCS | Legacy standalone disc total |
| Vorbis/APE text keys | TRACKTOTAL, TOTALTRACKS, DISCTOTAL, TOTALDISCS | Ordinary total metadata/aliases; not retired private fields |

Candidate matching inventories actual native spelling, namespace and arrays. Case-insensitive recognition may produce a candidate, but deletion always targets the exact inventoried identity. A lookalike in a different MP4 namespace or an unrelated ID3 frame is not part of the plan. Never delete a non-numeric custom value just because its description matches one of these names.

Resolve each component independently. If the native component exists and a valid alias agrees, mark it redundant. If the native component is absent and exactly one valid total is available (or several aliases agree), expose the recovered semantic total with **legacy source** provenance; retain the missing-native distinction and show that value in the Inspector, rather than silently displaying zero. This recovery projection does not itself authorize a write. For example TRCK=3 plus TXXX:TRACKTOTAL=12 displays number 3 and legacy total 12; its explicit normalization target is TRCK=3/12, not TRCK=3 with the total frame deleted.

If a native total and any valid alias disagree, expose all candidates and require a choice. If the only candidate is malformed, negative, overflowed or multi-valued, preserve it and mark recovery unresolved; do not parse-fail to zero. Native zero is an absent-component sentinel, not a positive total that wins over an orphan alias. Component absence, explicit removal and unresolved recovery are distinct states throughout drafts, exports and previews.

On the first approved edit/normalization of that pair, write the resolved number AND total into TRCK/TPOS or trkn/disk, then retire only the explicitly selected redundant aliases atomically. Number-only edits preserve a resolved legacy total; unresolved candidates block that pair edit until a full replacement or resolution is explicit. Removing Total must preview and remove approved alias-only copies so that they cannot resurrect on reload. A Title edit preserves all aliases without moving them. Track-only migration preserves the complete disc group, and vice versa.

Verification must independently inspect the native pair and every selected alias, not just a Basic projection that could still read its total from a leftover custom field. Failed staging/verification leaves the original bytes and orphan totals intact. No cleanup is allowed to discard the sole copy before native persistence has been verified.

| Intent from baseline number=3, total=12 | Required semantic result |
| --- | --- |
| Set number=5 | number=5, total=12 |
| Set total=15 | number=3, total=15 |
| Remove number | number absent, total=12; reject if the selected surface cannot express it |
| Remove total | number=3, total absent |
| Remove pair | both absent; remove selected native pair and explicitly resolved redundant aliases |
| Import number text 05 | number=5, total=12; padding handled by the selected format's codec |
| Import explicit replacement pair 05/15 | number=5, total=15 |
| Request exact padding in native-numeric MP4 | Either accept displayed normalization with a warning, or reject if exact-text mode was requested; never create a private field |

Absence is represented as optional components in the semantic model. Positive-value bounds are checked before staging; the API does not infer an absent value by integer parse failure. Existing non-numeric text stays raw and is preserved until explicitly replaced. A total smaller than the number is surfaced as unusual metadata, not silently corrected or swapped.

### 6.2. Private MP4 number-text inventory and retirement

The inspected 0.6.0 bridge declares these exact native identities in TLMetadataCore.inc. All are MP4 freeforms under the exact namespace `com.apple.iTunes`:

| Description | Scope | Historical meaning |
| --- | --- | --- |
| AUDIOMATOR_TRACKNUMBER_TEXT | Track pair | Legacy app-owned formatted text, e.g. 03/12 |
| AUDIOMATOR_DISCNUMBER_TEXT | Disc pair | Legacy app-owned formatted text, e.g. 01/02 |
| TAGLIBAUDIOMETADATA_TRACKNUMBER_TEXT | Track pair | Package-owned formatted text |
| TAGLIBAUDIOMETADATA_DISCNUMBER_TEXT | Disc pair | Package-owned formatted text |

Their fully qualified native name is `----:com.apple.iTunes:<description>`. The short uppercase names and uppercase fully qualified strings in the facade's hidden-key set are filter/lookup forms of these identities, not additional physical fields. Do not create missing unqualified copies or treat arbitrary similarly prefixed fields as ours.

Current source behavior: native trkn/disk set the numeric values; extraction also considers private text for formatted display. Numeric pair edits can migrate the touched AUDIOMATOR description to TAGLIBAUDIOMETADATA while retaining padding. Ordinary numeric edits on a standard-only file do not create that provenance. The standard raw-delta validator reserves these keys; structured MP4 atoms are needed to inventory them. These observations come from source inspection, not a new executed media round trip.

**Target decision: retire both namespaces.** No default writer creates either namespace, including explicit number-text APIs. Do not rename the app-owned fields into package-owned fields as a compatibility migration. MP4 totals are always stored in trkn/disk. Exact MP4 text padding is not portable metadata; render it through an app display preference or report normalization. This decision does not authorize adding sidecar files or another persistent private namespace.

Read the complete native pair and the complete private inventory before deciding which case applies. Strict private parsing permits only positive decimal components with leading zeros and an optional slash; missing components are distinct from zero. Enforce the target codec bounds and reject extra separators, arbitrary words, negative values or overflow as recovery candidates. Keep original bytes/text even when parsing fails. A string can be valid recovery text without being consistent formatting provenance.

| Observed state | Read and unrelated-save behavior | Explicit pair edit or cleanup behavior |
| --- | --- | --- |
| Native pair only | Native numbers; no private fields created | Update only native pair |
| Native pair plus numerically identical private text | Native numeric authority; optional legacy padding display; retain original atoms on unrelated saves | Preview padding normalization, then retire the touched pair's exact private atoms in the same transaction as the native write |
| Native pair and private text disagree, including a private-only total | Native numbers remain the normal projection; expose the alternate candidate and discrepancy; preserve all atoms | Require a resolution choosing native, private candidate, or an explicit replacement pair; show removals before commit |
| No native pair, one valid private candidate | Show a legacy-recovery candidate with provenance; do not quietly expose it as a verified native total or publish zero as if no candidate existed | Explicit Restore Numbers writes native pair and retires only the approved private atoms in one transaction |
| No native pair, multiple agreeing private candidates | One recovery candidate with all provenance; preserve originals | Same recovery action, enumerating every retired identity |
| Both private namespaces disagree, or private text is multi-valued/malformed/overflowed | Show ambiguity/diagnostic and preserve exact values | No automatic migration; explicit full replacement or exact cleanup preview required |
| Track changes, disc unchanged | Preserve disc pair and its private atoms exactly | Retire track provenance only; no cross-pair cleanup |
| User requests removal of all numbering | Preview native values, recovery-only values and exact private locations | Remove only the approved numbering identities atomically; verify their absence |

Private text may affect a legacy display projection only after strict numeric equivalence with all native components is established. It must never replace a native total, and the package-owned prefix must not automatically win over the app-owned prefix. Conflicting private text is diagnostic data, not a reason to overwrite verified native values during a Title save.

An ordinary pair edit may retire consistent, recognized provenance only when its preview explicitly includes that normalization. If no such preview has been acknowledged, leave the operation pending; elapsed time is not consent. Existing malformed or conflicting private atoms require a separate resolution plan. A complete replacement intent can supply that plan, but the discarded values still appear in the preview. Headless callers must supply an explicit cleanup/resolution policy rather than inheriting an app UI choice.

### 6.3. Cleanup API, raw visibility and verification

Provide a package-owned inventory plus a version-guarded pair normalization/recovery operation. These are future API requirements, not current method names. The plan records native before-values, private identities/types/value arrays, chosen after-pair, exact removals and normalization warnings. The app executes it inside FileMutationCoordinator; the package stages native writes and retirement together. A final version/audio guard failure preserves the original file, and a successful commit is never retried after a durability warning.

Do not implement cleanup through the current public raw delta API, which rejects reserved internal keys, or by replacing the whole MP4 atom collection. Extend the narrow package operation instead. Raw PropertyMap projection may remain filtered for compatibility, but Tag Inspector and the cleanup preview must expose this separate structured inventory. Whole-map replacement and erase-all must state their scope: omission of filtered private keys is not proof of removal. A dedicated exact removal needs structured readback of all four identities.

Conformance requires native values AND independent inventory checks: requested components round-trip in trkn/disk; approved legacy atoms are absent; untouched counterpart atoms/arrays are unchanged; unknown lookalike descriptions and namespaces survive; no replacement TAGLIBAUDIOMETADATA atom or duplicate total freeform is created. Test both namespaces independently and together, total-only pairs, stale candidates, absent native fields, malformed/multi-value private text, oversized values, zero/absent distinctions, case-sensitive near-matches, cancellation and version races. Existing tests expecting prefix renaming must be replaced only when the implementation changes, with explicit retirement assertions rather than deleted coverage.

The compatibility break in exact MP4 formatted-text persistence must be documented in the next package release and app adoption. Preserve read/recovery support for both old namespaces throughout the migration; do not remove the legacy reader simply because new writes no longer create private data. Unrelated saves must preserve old provenance until the user actually chooses migration.

### 6.4. Other value shapes

Use ordered arrays for multi-value text and people. A single-line Inspector replacement of a multi-value field is an explicit replacement, with a preview when values would be collapsed. No automatic trimming, Unicode normalization, case conversion or punctuation splitting on reads or unrelated saves. Validate new semantic values without silently changing them; any intentional formatting must be shown before commit.

`MUSICBRAINZ_TRACKID` identifies the recording; `MUSICBRAINZ_RELEASETRACKID` identifies the track on a release. ID3 recording ID uses the MusicBrainz-owned UFID, not a substitute TXXX on new writes. Labels, catalog numbers, barcodes, ISRCs and store IDs are strings or constrained native numeric values as declared by the registry; preserve leading zeros and reject out-of-range native values. Never infer equality between UPC/EAN variants or strip catalog punctuation. ID validation must not rewrite unrelated existing identifiers.

Role-qualified people need structured role/person pairs. Preserve description, language and role. TIPL and TMCL are shared native collections: editing one role must retain others. Do not union performer and musician-credit edits by flattening their text. ID3v2.3 IPLS must be treated as one shared group when representing both v2.4 collections; reject incompatible independent updates. `ARTISTS` remains a distinct canonical list when present, not an alias that can overwrite ARTIST.

Comments and lyrics preserve language/description and multiplicity. The simple Inspector edits only its explicitly selected/default entry; it does not delete every native comment or lyric. Artwork is a structured binary collection: native APIC/covr/FLAC picture or the engine's supported complex-property codec; do not store images as ordinary text. Replacement/removal scope must distinguish a selected/front image from all images and preserve unrelated picture entries unless remove-all was requested.

Advisory is the four-state enum specified in section 8.3: absent/unset, 0=not Explicit, 1=Explicit, 2=Clean. Use native MP4 rtng; conventional ITUNESADVISORY elsewhere is an extension with its own capability and uses the same four semantic states. Do not reduce it to Boolean or claim identical native representation across formats. Compilation, ratings, ReplayGain and iTunes numeric atoms likewise retain their own declared types. Ratings/popularity require an owner/profile, scale and optional play count; no universal unqualified RATING mapping is invented.

## 7. Versioned ID3 and custom fields

Default new ID3 tags to v2.4. Preserve an existing tag's major version during an ordinary edit; converting it is a separately previewed operation. Read-compatible frames do not establish write capability in another version. ID3v1 cannot express the full model and must not constrain the modern tag or be rewritten automatically on every save.

For v2.3 keep TYER (YEAR), TDAT (DATE) and TIME independent. TDAT is a legacy DDMM value, not a generated full date. An unsupported shape requires explicit conversion or rejection; do not combine, split, invent or truncate values. Tag-version conversion must preview each native-field move independently and reject a lossy or colliding conversion. ORIGINALDATE uses TORY when only year precision is representable; richer intent requires a supported extension/conversion explicitly selected by the user. Unsupported v2.4 native frames must not be smuggled into a v2.3 tag because a mapping table happens to list them. Use the engine's tested version conversion rules for all other frames; classify fallback text frames as extensions, never equivalent native support.

Custom fields use explicit namespaced intent: TXXX descriptions for ID3, F(description) for MP4, and named PropertyMap keys for formats with a verified codec. Raw/native mode may address exact locations. Custom intent may not impersonate a reserved canonical/native field to bypass preflight, override expected versions, or gain false verification success. Recognized collisions must be routed to the corresponding semantic or native structured editor.

Unknown native content is preserved without projecting it into a newly invented standard field. Binary frames, private structures, synchronized lyrics, chapters, ratings and unsupported collections require a tested structured codec or read-only treatment. Erase-all stays best effort with explicit verification scope; it is not a promise to erase every native structure.

## 8. Field catalog

The catalog below enumerates every `MetadataFieldKey` in 0.6.0 plus five explicitly planned additions: standaloneDate, contentGroup, artists, replayGainTrackPeak and replayGainAlbumPeak. The existing date case is a legacy migration handle for the YEAR slot and must receive an explicit new year identity; it must not be silently reinterpreted as standalone DATE. These are target mappings, deliberately differing from the current generated field-schema documentation. Existing Swift case names are migration handles, not immutable semantic labels. The columns are complete preferred target locations for ID3v2.3, ID3v2.4, MP4, Vorbis Comment, APEv2, ASF and RIFF INFO. `—` means no typed target in this revision, never automatic custom fallback. `PAIR(K)` addresses one component in the native combined field; YEAR and DATE use independent versioned native fields from section 4; there is no combined year/date codec. `EXT(K)` is an explicitly registered text extension. In the Xiph/APE columns a bare name is a text key. Artwork names denote structured collections, not text.

All entries are target registrations with runtime capability initially unproven for changed paths. A location alone does not establish cardinality support; multi-values, roles, bounds, lossless deletion and partial pairs must pass section 12. The package currently accepts at most Int32.max for track/disc components; target MP4 pair components are limited to 1...65535, with zero only as the native absent-component sentinel. ID3/Xiph/APE positive components are bounded by Int32.max in the typed API. ASF/RIFF must declare and test the concrete codec's bounds before activation. Totals are never encoded as invented ordinal zero or private text. An all-absent pair removes the native field.

Native numeric store identifiers require lossless parsing and the exact atom codec bounds; do not route them through floating point. If the engine cannot represent the requested native type/cardinality, report unsupported. Structured artwork, comments, lyrics and role entries retain collection-level identity even where the matrix shows a single container key.

| Existing/new case | Semantic key; shape | ID3v2.3 | ID3v2.4 | MP4 | Vorbis Comment | APEv2 | ASF | RIFF INFO |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `title` | `TITLE`; text | `TIT2` | `TIT2` | `©nam` | `TITLE` | `TITLE` | `Title` | `INAM` |
| `artist` | `ARTIST`; text[] | `TPE1` | `TPE1` | `©ART` | `ARTIST` | `ARTIST` | `Author` | `IART` |
| `album` | `ALBUM`; text | `TALB` | `TALB` | `©alb` | `ALBUM` | `ALBUM` | `WM/AlbumTitle` | `IPRD` |
| `albumArtist` | `ALBUMARTIST`; text[] | `TPE2` | `TPE2` | `aART` | `ALBUMARTIST` | `ALBUM ARTIST` | `WM/AlbumArtist` | `—` |
| `date` | `YEAR`; stored text, target year identity | `TYER` | `TDRC` | `©day` | `YEAR` | `YEAR` | `WM/Year` | `ICRD` |
| `standaloneDate (new)` | `DATE`; native-version-specific text | `TDAT (DDMM)` | `TXXX(DATE)` | `EXT(F(DATE))` | `DATE` | `DATE` | `EXT(DATE)` | `—` |
| `releaseDate` | `RELEASEDATE`; date | `EXTFRAME(TDRL)` | `TDRL` | `EXT(F(RELEASEDATE))` | `RELEASEDATE` | `RELEASEDATE` | `—` | `—` |
| `originalReleaseDate` | `ORIGINALDATE`; date | `TORY (year only)` | `TDOR` | `EXT(F(ORIGINALDATE))` | `ORIGINALDATE` | `ORIGINALDATE` | `WM/OriginalReleaseYear` | `—` |
| `track` | `TRACKNUMBER`; integer component | `PAIR(TRCK)` | `PAIR(TRCK)` | `PAIR(trkn)` | `TRACKNUMBER` | `TRACK` | `PAIR(WM/TrackNumber)` | `ITRK` |
| `trackTotal` | `TRACKTOTAL`; integer component | `PAIR(TRCK)` | `PAIR(TRCK)` | `PAIR(trkn)` | `TRACKTOTAL` | `TRACKTOTAL` | `PAIR(WM/TrackNumber)` | `—` |
| `disc` | `DISCNUMBER`; integer component | `PAIR(TPOS)` | `PAIR(TPOS)` | `PAIR(disk)` | `DISCNUMBER` | `DISC` | `PAIR(WM/PartOfSet)` | `—` |
| `discTotal` | `DISCTOTAL`; integer component | `PAIR(TPOS)` | `PAIR(TPOS)` | `PAIR(disk)` | `DISCTOTAL` | `DISCTOTAL` | `PAIR(WM/PartOfSet)` | `—` |
| `artwork` | `PICTURE (complex)`; picture[] | `APIC` | `APIC` | `covr` | `PICTURE (structured)` | `COVER ART (structured)` | `WM/Picture (structured)` | `—` |
| `lyrics` | `LYRICS`; qualified text[] | `USLT(entry identity)` | `USLT(entry identity)` | `©lyr` | `LYRICS` | `LYRICS` | `WM/Lyrics` | `—` |
| `comment` | `COMMENT`; qualified text[] | `COMM(entry identity)` | `COMM(entry identity)` | `©cmt` | `COMMENT` | `COMMENT` | `Description` | `ICMT` |
| `genre` | `GENRE`; text[] | `TCON` | `TCON` | `©gen` | `GENRE` | `GENRE` | `WM/Genre` | `IGNR` |
| `composer` | `COMPOSER`; text[] | `TCOM` | `TCOM` | `©wrt` | `COMPOSER` | `COMPOSER` | `WM/Composer` | `IMUS` |
| `conductor` | `CONDUCTOR`; text[] | `TPE3` | `TPE3` | `©con` | `CONDUCTOR` | `CONDUCTOR` | `WM/Conductor` | `—` |
| `remixer` | `REMIXER`; text[] | `TPE4` | `TPE4` | `EXT(F(REMIXER))` | `REMIXER` | `MIXARTIST` | `WM/ModifiedBy` | `—` |
| `performer` | `PERFORMER`; role/person[] | `IPLS (shared roles)` | `TMCL role entries` | `EXT(F(PERFORMER))` | `PERFORMER` | `PERFORMER` | `—` | `—` |
| `producer` | `PRODUCER`; text[] | `TXXX(PRODUCER)` | `TXXX(PRODUCER)` | `EXT(F(PRODUCER))` | `PRODUCER` | `PRODUCER` | `WM/Producer` | `—` |
| `engineer` | `ENGINEER`; text[] | `TXXX(ENGINEER)` | `TXXX(ENGINEER)` | `EXT(F(ENGINEER))` | `ENGINEER` | `ENGINEER` | `—` | `—` |
| `lyricist` | `LYRICIST`; text[] | `TEXT` | `TEXT` | `EXT(F(LYRICIST))` | `LYRICIST` | `LYRICIST` | `WM/Writer` | `—` |
| `involvedPeople` | `INVOLVEDPEOPLE`; role/person[] | `IPLS (shared roles)` | `TIPL` | `EXT(F(INVOLVEDPEOPLE))` | `INVOLVEDPEOPLE` | `INVOLVEDPEOPLE` | `—` | `—` |
| `musicianCredits` | `MUSICIANCREDITS`; role/person[] | `IPLS (shared roles)` | `TMCL` | `EXT(F(MUSICIANCREDITS))` | `MUSICIANCREDITS` | `MUSICIANCREDITS` | `—` | `—` |
| `publisher` | `LABEL`; text | `TPUB` | `TPUB` | `©pub` | `LABEL` | `LABEL` | `WM/Publisher` | `—` |
| `copyright` | `COPYRIGHT`; text | `TCOP` | `TCOP` | `cprt` | `COPYRIGHT` | `COPYRIGHT` | `Copyright` | `ICOP` |
| `encodedBy` | `ENCODEDBY`; text | `TENC` | `TENC` | `©enc` | `ENCODEDBY` | `ENCODEDBY` | `WM/EncodedBy` | `—` |
| `encoderSettings` | `ENCODING`; text | `TSSE` | `TSSE` | `©too` | `ENCODING` | `ENCODING` | `WM/EncodingSettings` | `—` |
| `isrc` | `ISRC`; text | `TSRC` | `TSRC` | `EXT(F(ISRC))` | `ISRC` | `ISRC` | `WM/ISRC` | `—` |
| `barcode` | `BARCODE`; text | `TXXX(BARCODE)` | `TXXX(BARCODE)` | `EXT(F(BARCODE))` | `BARCODE` | `BARCODE` | `WM/Barcode` | `—` |
| `catalogNumber` | `CATALOGNUMBER`; text | `TXXX(CATALOGNUMBER)` | `TXXX(CATALOGNUMBER)` | `EXT(F(CATALOGNUMBER))` | `CATALOGNUMBER` | `CATALOGNUMBER` | `WM/CatalogNo` | `—` |
| `asin` | `ASIN`; text | `TXXX(ASIN)` | `TXXX(ASIN)` | `EXT(F(ASIN))` | `ASIN` | `ASIN` | `—` | `—` |
| `releaseType` | `RELEASETYPE`; text[] | `TXXX(MusicBrainz Album Type)` | `TXXX(MusicBrainz Album Type)` | `EXT(F(MusicBrainz Album Type))` | `RELEASETYPE` | `MUSICBRAINZ_ALBUMTYPE` | `MusicBrainz/Album Type` | `—` |
| `releaseStatus` | `RELEASESTATUS`; text | `TXXX(MusicBrainz Album Status)` | `TXXX(MusicBrainz Album Status)` | `EXT(F(MusicBrainz Album Status))` | `RELEASESTATUS` | `MUSICBRAINZ_ALBUMSTATUS` | `MusicBrainz/Album Status` | `—` |
| `releaseCountry` | `RELEASECOUNTRY`; text | `TXXX(MusicBrainz Album Release Country)` | `TXXX(MusicBrainz Album Release Country)` | `EXT(F(MusicBrainz Album Release Country))` | `RELEASECOUNTRY` | `RELEASECOUNTRY` | `MusicBrainz/Album Release Country` | `—` |
| `mediaType` | `MEDIA`; text | `TMED` | `TMED` | `EXT(F(MEDIA))` | `MEDIA` | `MEDIA` | `WM/Media` | `—` |
| `work` | `WORK`; text | `TXXX(WORK)` | `TXXX(WORK)` | `©wrk` | `WORK` | `WORK` | `—` | `—` |
| `movement` | `MOVEMENTNAME`; text | `EXTFRAME(MVNM)` | `EXTFRAME(MVNM)` | `©mvn` | `MOVEMENTNAME` | `MOVEMENTNAME` | `—` | `—` |
| `movementNumber` | `MOVEMENTNUMBER`; integer component | `PAIR(EXTFRAME(MVIN))` | `PAIR(EXTFRAME(MVIN))` | `©mvi` | `MOVEMENTNUMBER` | `MOVEMENTNUMBER` | `—` | `—` |
| `movementCount` | `MOVEMENTCOUNT`; integer component | `PAIR(EXTFRAME(MVIN))` | `PAIR(EXTFRAME(MVIN))` | `©mvc` | `MOVEMENTCOUNT` | `MOVEMENTCOUNT` | `—` | `—` |
| `discSubtitle` | `DISCSUBTITLE`; text | `TXXX(DISCSUBTITLE)` | `TSST` | `EXT(F(DISCSUBTITLE))` | `DISCSUBTITLE` | `DISCSUBTITLE` | `WM/SetSubTitle` | `—` |
| `subtitle` | `SUBTITLE`; text | `TIT3` | `TIT3` | `EXT(F(SUBTITLE))` | `SUBTITLE` | `SUBTITLE` | `WM/SubTitle` | `—` |
| `grouping` | `GROUPING`; text[] | `EXTFRAME(GRP1)` | `EXTFRAME(GRP1)` | `EXT(F(GROUPING))` | `GROUPING` | `GROUPING` | `—` | `—` |
| `mood` | `MOOD`; text[] | `TXXX(MOOD)` | `TMOO` | `EXT(F(MOOD))` | `MOOD` | `MOOD` | `WM/Mood` | `—` |
| `language` | `LANGUAGE`; text[] | `TLAN` | `TLAN` | `EXT(F(LANGUAGE))` | `LANGUAGE` | `LANGUAGE` | `WM/Language` | `ILNG` |
| `musicalKey` | `INITIALKEY`; text | `TKEY` | `TKEY` | `EXT(F(INITIALKEY))` | `INITIALKEY` | `INITIALKEY` | `WM/InitialKey` | `—` |
| `bpm` | `BPM`; integer | `TBPM` | `TBPM` | `tmpo` | `BPM` | `BPM` | `WM/BeatsPerMinute` | `—` |
| `compilation` | `COMPILATION`; boolean | `EXTFRAME(TCMP)` | `EXTFRAME(TCMP)` | `cpil` | `COMPILATION` | `COMPILATION` | `—` | `—` |
| `explicitContent` | `ITUNESADVISORY`; advisory enum | `TXXX(ITUNESADVISORY)` | `TXXX(ITUNESADVISORY)` | `rtng` | `ITUNESADVISORY` | `ITUNESADVISORY` | `—` | `—` |
| `sortTitle` | `TITLESORT`; text | `EXTFRAME(TSOT)` | `TSOT` | `sonm` | `TITLESORT` | `TITLESORT` | `WM/TitleSortOrder` | `—` |
| `sortArtist` | `ARTISTSORT`; text | `EXTFRAME(TSOP)` | `TSOP` | `soar` | `ARTISTSORT` | `ARTISTSORT` | `WM/ArtistSortOrder` | `—` |
| `sortAlbum` | `ALBUMSORT`; text | `EXTFRAME(TSOA)` | `TSOA` | `soal` | `ALBUMSORT` | `ALBUMSORT` | `WM/AlbumSortOrder` | `—` |
| `sortAlbumArtist` | `ALBUMARTISTSORT`; text | `EXTFRAME(TSO2)` | `EXTFRAME(TSO2)` | `soaa` | `ALBUMARTISTSORT` | `ALBUMARTISTSORT` | `WM/AlbumArtistSortOrder` | `—` |
| `sortComposer` | `COMPOSERSORT`; text | `EXTFRAME(TSOC)` | `EXTFRAME(TSOC)` | `soco` | `COMPOSERSORT` | `COMPOSERSORT` | `—` | `—` |
| `musicBrainzArtistID` | `MUSICBRAINZ_ARTISTID`; identifier[] | `TXXX(MusicBrainz Artist Id)` | `TXXX(MusicBrainz Artist Id)` | `EXT(F(MusicBrainz Artist Id))` | `MUSICBRAINZ_ARTISTID` | `MUSICBRAINZ_ARTISTID` | `MusicBrainz/Artist Id` | `—` |
| `musicBrainzAlbumID` | `MUSICBRAINZ_ALBUMID`; identifier | `TXXX(MusicBrainz Album Id)` | `TXXX(MusicBrainz Album Id)` | `EXT(F(MusicBrainz Album Id))` | `MUSICBRAINZ_ALBUMID` | `MUSICBRAINZ_ALBUMID` | `MusicBrainz/Album Id` | `—` |
| `musicBrainzAlbumArtistID` | `MUSICBRAINZ_ALBUMARTISTID`; identifier[] | `TXXX(MusicBrainz Album Artist Id)` | `TXXX(MusicBrainz Album Artist Id)` | `EXT(F(MusicBrainz Album Artist Id))` | `MUSICBRAINZ_ALBUMARTISTID` | `MUSICBRAINZ_ALBUMARTISTID` | `MusicBrainz/Album Artist Id` | `—` |
| `musicBrainzTrackID` | `MUSICBRAINZ_TRACKID`; identifier | `UFID(http://musicbrainz.org)` | `UFID(http://musicbrainz.org)` | `EXT(F(MusicBrainz Track Id))` | `MUSICBRAINZ_TRACKID` | `MUSICBRAINZ_TRACKID` | `MusicBrainz/Track Id` | `—` |
| `musicBrainzReleaseGroupID` | `MUSICBRAINZ_RELEASEGROUPID`; identifier | `TXXX(MusicBrainz Release Group Id)` | `TXXX(MusicBrainz Release Group Id)` | `EXT(F(MusicBrainz Release Group Id))` | `MUSICBRAINZ_RELEASEGROUPID` | `MUSICBRAINZ_RELEASEGROUPID` | `MusicBrainz/Release Group Id` | `—` |
| `musicBrainzReleaseTrackID` | `MUSICBRAINZ_RELEASETRACKID`; identifier | `TXXX(MusicBrainz Release Track Id)` | `TXXX(MusicBrainz Release Track Id)` | `EXT(F(MusicBrainz Release Track Id))` | `MUSICBRAINZ_RELEASETRACKID` | `MUSICBRAINZ_RELEASETRACKID` | `MusicBrainz/Release Track Id` | `—` |
| `musicBrainzWorkID` | `MUSICBRAINZ_WORKID`; identifier[] | `TXXX(MusicBrainz Work Id)` | `TXXX(MusicBrainz Work Id)` | `EXT(F(MusicBrainz Work Id))` | `MUSICBRAINZ_WORKID` | `MUSICBRAINZ_WORKID` | `MusicBrainz/Work Id` | `—` |
| `acoustID` | `ACOUSTID_ID`; text | `TXXX(Acoustid Id)` | `TXXX(Acoustid Id)` | `EXT(F(Acoustid Id))` | `ACOUSTID_ID` | `ACOUSTID_ID` | `Acoustid/Id` | `—` |
| `acoustIDFingerprint` | `ACOUSTID_FINGERPRINT`; text | `TXXX(Acoustid Fingerprint)` | `TXXX(Acoustid Fingerprint)` | `EXT(F(Acoustid Fingerprint))` | `ACOUSTID_FINGERPRINT` | `ACOUSTID_FINGERPRINT` | `Acoustid/Fingerprint` | `—` |
| `musicIPPUID` | `MUSICIP_PUID`; text | `TXXX(MusicIP PUID)` | `TXXX(MusicIP PUID)` | `EXT(F(MusicIP PUID))` | `MUSICIP_PUID` | `MUSICIP_PUID` | `MusicIP/PUID` | `—` |
| `replayGainTrackGain` | `REPLAYGAIN_TRACK_GAIN`; gain text with unit | `TXXX(REPLAYGAIN_TRACK_GAIN)` | `TXXX(REPLAYGAIN_TRACK_GAIN)` | `EXT(F(REPLAYGAIN_TRACK_GAIN))` | `REPLAYGAIN_TRACK_GAIN` | `REPLAYGAIN_TRACK_GAIN` | `—` | `—` |
| `replayGainAlbumGain` | `REPLAYGAIN_ALBUM_GAIN`; gain text with unit | `TXXX(REPLAYGAIN_ALBUM_GAIN)` | `TXXX(REPLAYGAIN_ALBUM_GAIN)` | `EXT(F(REPLAYGAIN_ALBUM_GAIN))` | `REPLAYGAIN_ALBUM_GAIN` | `REPLAYGAIN_ALBUM_GAIN` | `—` | `—` |
| `itunesAlbumID` | `ITUNESALBUMID`; native unsigned ID | `TXXX(ITUNESALBUMID)` | `TXXX(ITUNESALBUMID)` | `plID` | `ITUNESALBUMID` | `ITUNESALBUMID` | `—` | `—` |
| `itunesArtistID` | `ITUNESARTISTID`; native unsigned ID | `TXXX(ITUNESARTISTID)` | `TXXX(ITUNESARTISTID)` | `atID` | `ITUNESARTISTID` | `ITUNESARTISTID` | `—` | `—` |
| `itunesCatalogID` | `ITUNESCATALOGID`; native unsigned ID | `TXXX(ITUNESCATALOGID)` | `TXXX(ITUNESCATALOGID)` | `cnID` | `ITUNESCATALOGID` | `ITUNESCATALOGID` | `—` | `—` |
| `itunesGenreID` | `ITUNESGENREID`; native unsigned ID | `TXXX(ITUNESGENREID)` | `TXXX(ITUNESGENREID)` | `geID` | `ITUNESGENREID` | `ITUNESGENREID` | `—` | `—` |
| `itunesMediaType` | `ITUNESMEDIATYPE`; native enum | `TXXX(ITUNESMEDIATYPE)` | `TXXX(ITUNESMEDIATYPE)` | `stik` | `ITUNESMEDIATYPE` | `ITUNESMEDIATYPE` | `—` | `—` |
| `itunesPurchaseDate` | `ITUNESPURCHASEDATE`; date/time | `TXXX(ITUNESPURCHASEDATE)` | `TXXX(ITUNESPURCHASEDATE)` | `purd` | `ITUNESPURCHASEDATE` | `ITUNESPURCHASEDATE` | `—` | `—` |
| `itunesNorm` | `ITUNNORM`; opaque text | `TXXX(iTunNORM)` | `TXXX(iTunNORM)` | `EXT(F(iTunNORM))` | `ITUNNORM` | `ITUNNORM` | `—` | `—` |
| `itunesSMPB` | `ITUNSMPB`; opaque text | `TXXX(iTunSMPB)` | `TXXX(iTunSMPB)` | `EXT(F(iTunSMPB))` | `ITUNSMPB` | `ITUNSMPB` | `—` | `—` |
| `originalAlbum` | `ORIGINALALBUM`; text | `TOAL` | `TOAL` | `EXT(F(ORIGINALALBUM))` | `ORIGINALALBUM` | `ORIGINALALBUM` | `WM/OriginalAlbumTitle` | `—` |
| `originalArtist` | `ORIGINALARTIST`; text[] | `TOPE` | `TOPE` | `EXT(F(ORIGINALARTIST))` | `ORIGINALARTIST` | `ORIGINALARTIST` | `WM/OriginalArtist` | `—` |
| `artistType` | `MUSICBRAINZ_ARTISTTYPE`; text | `TXXX(MusicBrainz Artist Type)` | `TXXX(MusicBrainz Artist Type)` | `EXT(F(MusicBrainz Artist Type))` | `MUSICBRAINZ_ARTISTTYPE` | `MUSICBRAINZ_ARTISTTYPE` | `—` | `—` |
| `trackerName` | `TRACKERNAME`; text | `—` | `—` | `—` | `—` | `—` | `—` | `—` |
| `custom` | `<explicit key>`; raw text[] / structured | `TXXX(<description>)` | `TXXX(<description>)` | `EXT(F(<description>))` | `<explicit key>` | `<explicit key>` | `—` | `—` |
| `contentGroup (new)` | `CONTENTGROUP`; text | `TIT1` | `TIT1` | `©grp` | `CONTENTGROUP` | `CONTENTGROUP` | `WM/ContentGroupDescription` | `—` |
| `artists (new)` | `ARTISTS`; text[] | `TXXX(ARTISTS)` | `TXXX(ARTISTS)` | `EXT(F(ARTISTS))` | `ARTISTS` | `ARTISTS` | `WM/ARTISTS` | `—` |
| `replayGainTrackPeak (new)` | `REPLAYGAIN_TRACK_PEAK`; peak decimal | `TXXX(REPLAYGAIN_TRACK_PEAK)` | `TXXX(REPLAYGAIN_TRACK_PEAK)` | `EXT(F(REPLAYGAIN_TRACK_PEAK))` | `REPLAYGAIN_TRACK_PEAK` | `REPLAYGAIN_TRACK_PEAK` | `—` | `—` |
| `replayGainAlbumPeak (new)` | `REPLAYGAIN_ALBUM_PEAK`; peak decimal | `TXXX(REPLAYGAIN_ALBUM_PEAK)` | `TXXX(REPLAYGAIN_ALBUM_PEAK)` | `EXT(F(REPLAYGAIN_ALBUM_PEAK))` | `REPLAYGAIN_ALBUM_PEAK` | `REPLAYGAIN_ALBUM_PEAK` | `—` | `—` |

Catalog coverage: 79 existing enum cases plus five planned additions (84 rows). New cases are target schema additions, not current APIs. Every cell has a chosen location or an explicit unsupported result. `EXT(F(K))` explicitly registers a conventional freeform; it does not classify K as a native atom. `EXTFRAME(K)` registers a product-compatible nonstandard/other-version ID3 frame and requires its own capability and tests. The source field definitions come from the local 0.6.0 registry, with the reviewed 2.2 design overrides.

ASF/RIFF unsupported cells deliberately narrow the initial target; no supported current read is removed, and untouched values remain preserved. For example RIFF INFO Track Number uses ITRK in this profile; it has no typed Total Tracks/Total Discs target here. A WAV file with usable ID3 can use TRCK/TPOS through that explicitly selected surface. Never add a private RIFF field to compensate. Tracker Name has no portable target in these seven tag surfaces; module-header codecs retain their separately declared format-specific capabilities, not invented TRACKERNAME text tags. Existing XM/module title/comment/tracker-name operations must preserve their native fixed-width constraints and receive format-specific tests if changed.

Sections 8.1 and 8.2 additionally enumerate the complete MP4-exclusive and MKV-exclusive lists selected for this contract, including fields with no current Swift case. These are target registrations, not currently implemented APIs. Podcast/URL fields outside the explicit tables remain preserved or explicit custom/structured data pending a reviewed entry. Completeness here means explicit decisions for the declared package/app scope and both exclusive-field lists, not a claim to implement every field supported by another product.

### 8.1. Complete MP4-exclusive list

This table defines all 26 MP4-exclusive entries in this profile. Entries already present in the core matrix reference the same semantic field, never a duplicate. The field name is also the semantic registry key unless a translation is shown. Each listed native atom is the sole preferred MP4 write location; do not create a matching freeform as a fallback. Value shape, validation and independent native verification are required before advertising engine support.

| Field name | MP4 atom | Semantic shape / target rule |
| --- | --- | --- |
| DIRECTOR | ©dir | Ordered people values; preserve native cardinality |
| ITUNESACCOUNT | apID | Account text; user-supplied, never fetched or logged automatically |
| ITUNESADVISORY | rtng | Four states; section 8.3 |
| ITUNESALBUMID | plID | Lossless store ID; existing itunesAlbumID |
| ITUNESARTISTID | atID | Lossless store ID; existing itunesArtistID |
| ITUNESCATALOGID | cnID | Lossless catalog ID; existing itunesCatalogID |
| ITUNESCOMPOSERID | cmID | Lossless composer ID; separate from artist ID |
| ITUNESCOUNTRYID | sfID | Numeric storefront ID; separate from RELEASECOUNTRY |
| ITUNESGAPLESS | pgap | Write 1 or remove; preserve existing 0 on unrelated edits |
| ITUNESGENREID | geID | Numeric store genre ID; separate from GENRE |
| ITUNESHDVIDEO | hdvd | Absent, 0, or 1; zero is a present false value |
| ITUNESMEDIATYPE | stik | Native media-kind enum; separate from textual MEDIA |
| ITUNESOWNER | ownr | Semantic OWNER; owner text |
| ITUNESPURCHASEDATE | purd | Purchase timestamp; independent of DATE/RELEASEDATE |
| RATE | rate | Native rating value/type; no assumed POPM scale conversion |
| SHOWMOVEMENT | shwm | Semantic SHOWWORKMOVEMENT; absent/false/true |
| STOREDESCRIPTION | sdes | Store-description text; separate from COMMENT/LYRICS |
| TOTALDISCS | disk | DISCTOTAL component; section 6.1, no duplicate atom |
| TOTALTRACKS | trkn | TRACKTOTAL component; section 6.1, no private total field |
| TVEPISODE | tves | Nonnegative episode integer; distinct from TVEPISODEID |
| TVEPISODEID | tven | Episode identifier text; preserve leading zeros |
| TVNETWORK | tvnn | Network text |
| TVSEASON | tvsn | Nonnegative season integer; preserve season 0 |
| TVSHOW | tvsh | Show title text |
| TVSHOWSORT | sosn | Semantic SHOWSORT; show sorting text |
| WORK | ©wrk | Existing WORK; independent of CONTENTGROUP/GROUPING |

Native integer atoms require exact width, signedness and lossless readback from the selected codec before activation. Preserve IDs as lossless values throughout serialization; never pass them through floating point. For tves/tvsn the planned codec is an unsigned 32-bit integer; validate range before staging. For rtng/pgap/hdvd/stik/shwm the semantic constraints above restrict values even when the underlying codec can hold more. An unknown existing enum or a differently typed RATE is preserved as unknown native data until explicitly replaced; do not coerce it to zero.

The ITUNESMEDIATYPE vocabulary includes Normal, Audiobook, Bookmark, Music Video, Movie, TV Show, Booklet, Ringtone, Podcast and iTunes U. Registry entries must explicitly bind each supported label to a verified native code; this specification does not invent numeric codes from list order. Retain unknown codes in snapshots. Display and edit the store enum independently of the container's physical media description.

All 26 fields need set/replace/remove/unrelated-save tests, raw native readback and failure-byte preservation before write capability is advertised. This includes the fields absent from the current enum. Account, owner and purchase fields must not trigger any account/network discovery; existing privacy/logging boundaries apply. MP4 RATE has no default cross-format rating conversion; a future conversion needs a named scale/profile and explicit intent.

### 8.2. Complete MKV-exclusive list

The two MKV-exclusive fields in this profile are distinct Matroska target registrations:

| Field name | Native SimpleTag name | TargetTypeValue | Value shape |
| --- | --- | --- | --- |
| TVEPISODE | PART_NUMBER | 50 | Nonnegative episode integer |
| TVSEASON | PART_NUMBER | 60 | Nonnegative season integer |

The semantic keys match the MP4 fields, but the native identity includes TargetTypeValue and any applicable TrackUID/EditionUID/ChapterUID/AttachmentUID, language/default flag and nested tag path. The two PART_NUMBER fields must not overwrite each other. Preserve other target levels, languages, unknown tags and video-track metadata; do not flatten all PART_NUMBER values into TRACKNUMBER or DISCNUMBER. A TVSEASON=0 is a real value, not an absent tag.

These two mappings are now part of the accepted design; Matroska implementation remains pending and must not be enabled merely because these rows exist. Before adding capability, inspect actual MKV/MKA layouts, declare the exact container/target support, test independent episode/season edits and removal, and use an independent native inspector. MKA album/track numbering and MKV episode/season numbering are separate source profiles. No generic TargetTypeValue=30 fallback is allowed for these fields.

### 8.3. ITUNESADVISORY four-state contract

The maintainer's requested semantic interpretation is normative:

| Semantic state | UI meaning | MP4 native representation | Semantic operation |
| --- | --- | --- | --- |
| unset | Not set / 未设置 | rtng absent | remove |
| notExplicit | Not Explicit / 不 Explicit | rtng present, integer 0 | set 0 |
| explicit | Explicit | rtng present, integer 1 | set 1 |
| clean | Clean | rtng present, integer 2 | set 2 |

Blank means absent, not numeric zero. Choosing blank in the Inspector or an explicit blank/remove import cell emits removal; an omitted import column is unchanged. The CSV profile must define blank/removal syntax without conflating an omitted value, literal "0" and a Boolean false. A single typed advisory field accepts only these four states; 3, 4 or arbitrary strings are not writable through this semantic profile.

Read current native 0/1/2 without collapsing states. Unknown or historic values, including a legacy value 4, must be retained with raw value and provenance as an unsupported/legacy state, rather than silently recoded as Clean or unset. An unrelated save preserves them. An explicit replacement or migration to one of the four states requires a preview and native verification. Do not alias this state to compilation, podcast, rating or the Boolean isExplicit convenience projection.

On non-MP4 targets with the declared ITUNESADVISORY text extension, write literal "0", "1" or "2", or remove the field for unset; no default empty string. Verify exact present-zero versus absent behavior. Conflicting rtng and advisory freeform aliases require explicit resolution; clearing the semantic field must remove only the approved native/alias locations so a stale extension cannot resurrect its value.

Required regression cases: absent→0→1→2→absent, exact round-trip of each state, Title-only preservation of present zero and absent values, omitted/blank/literal-zero CSV cases, mixed-selection presentation, unknown-value preservation and explicit replacement, and version/verification failure leaving original bytes unchanged. These are implementation gates, not tests run by this documentation change.

## 9. Explicit divergence decisions

| Area | Target decision |
| --- | --- |
| Year and dates | Independent YEAR (declared native locations), DATE, RELEASEDATE and ORIGINALDATE. No projection, fallback, synchronization or year-equality check |
| Publisher / label | Semantic LABEL, display/import name PUBLISHER; TPUB / MP4 ©pub. F(LABEL) remains a legacy read location, not a parallel write target |
| Conductor | TPE3 / MP4 ©con; F(CONDUCTOR) is a read-compatible legacy extension |
| Content group | New semantic CONTENTGROUP: TIT1 / ©grp. It is not classical WORK or modern GROUPING |
| Grouping | GRP1 / explicit F(GROUPING) extension. Never claim ©grp belongs simultaneously to CONTENTGROUP and GROUPING |
| Work | ©wrk for MP4; explicit TXXX(WORK) extension for ID3. Do not inherit TagLib WORK→TIT1 when CONTENTGROUP owns TIT1 |
| Encoder fields | ENCODEDBY uses TENC / ©enc. Semantic ENCODING is encoder settings, TSSE / ©too; distinct from ENCODEDBY |
| Media | Semantic MEDIA is textual physical media, not the ITUNESMEDIATYPE/stik store enum |
| Release metadata | The explicitly declared qualified MusicBrainz locations apply; semantic keys RELEASETYPE/RELEASESTATUS/RELEASECOUNTRY remain stable |
| MP4 atom case | Use exact native ©ART for Artist, not a literal lowercase variant from a prose/table rendering. Documentation typos are not storage decisions |
| Store fields | Native plID/atID/cnID/geID/stik/purd and exact iTunNORM/iTunSMPB descriptions; no generic ITUNES-field fan-out |
| MusicBrainz IDs | Recording ID uses UFID(http://musicbrainz.org); release-track ID is independent. Do not silently overwrite contradictory aliases |
| ID3 version | Some compatibility profiles use extension frames under v2.3. Native-standard compatibility wins: version-invalid frames require a declared extension codec or explicit conversion; no silent nonconforming write |
| Number text | Four historical private MP4 descriptions are legacy formatting provenance, not a total-storage solution; section 6 defines retirement |
| Remaining gaps | Use the explicit matrix, including its unsupported cells. Do not reinstate TagLib precedence through a generic fallback |

The adapter must distinguish semantic and engine keys. For example TagLib may project TIT1 as WORK and ©grp as GROUPING; this contract exposes both as CONTENTGROUP. Resolve them from native identity without rewriting the raw map or reading the same slot into two semantic fields. Likewise ©pub may project as a generic PUBLISHER key while the semantic model uses LABEL. Round-trip verification must inspect the chosen native slot, not compare a misleading engine alias.

No bundled compatibility presets are authorized by this version beyond this one default profile. A future optional preset needs its own versioned mapping, preview and tests; changing a UI label cannot switch the file's storage policy.

### Import and display name translation

This is an import/export name dialect, not an alternative native writer. Matching canonical names pass through unchanged. Apply these non-identical names only in the explicitly declared compatibility import profile; unknown names remain explicit custom fields or are reported, never guessed. Native Vorbis/APE keys must first be interpreted using their tag-family rules, not this UI-name table.

| Field name | Canonical key or operation |
| --- | --- |
| YEAR | YEAR, independent stored value; preserve complete native text |
| RELEASETIME | RELEASEDATE |
| ORIGYEAR | ORIGINALDATE, with supplied precision retained |
| PUBLISHER | LABEL |
| TRACK | TRACKNUMBER / TRACKTOTAL, parsed as an explicit pair |
| TOTALTRACKS / TOTALDISCS | TRACKTOTAL / DISCTOTAL |
| MEDIATYPE | MEDIA |
| ENCODERSETTINGS | ENCODING |
| CONTENTGROUP | CONTENTGROUP; new field, not WORK or GROUPING |
| MIXARTIST | REMIXER |
| SETSUBTITLE | DISCSUBTITLE |
| MOVEMENT / MOVEMENTTOTAL | MOVEMENTNUMBER / MOVEMENTCOUNT |
| ORIGALBUM / ORIGARTIST | ORIGINALALBUM / ORIGINALARTIST |
| ORIGFILENAME / ORIGLYRICIST | ORIGINALFILENAME / ORIGINALLYRICIST |
| FILEOWNER | OWNER |
| NETRADIOSTATION / NETRADIOOWNER | RADIOSTATION / RADIOSTATIONOWNER |
| MUSICBRAINZ_ALBUMRELEASECOUNTRY | RELEASECOUNTRY |
| MUSICBRAINZ_ALBUMSTATUS / MUSICBRAINZ_ALBUMTYPE | RELEASESTATUS / RELEASETYPE |
| ENCODEDBY / GROUPING / WORK / MUSICBRAINZ_TRACKID | Same semantic identity; not ENCODING / CONTENTGROUP / MUSICBRAINZ_RELEASETRACKID |
| DATE / TIME | Independent native-version-specific fields; no automatic combination with YEAR |

Fields outside the selected profile retain their native identities and require explicit registry entries before typed exposure. For example POPULARIMETER and RATING WMP are owner/scale-qualified rating profiles, not aliases to one scalar RATING. This version does not promise semantic writing of unregistered fields.

## 10. AudioMator integration contract

The Inspector treats **Year**, **Date**, **Release Date** and **Original Release Date** as independent fields with separate drafts, dirty flags, set/remove intents and capabilities. Target app names are `year`, `date`, `releaseDate` and `originalReleaseDate`. Do not derive Year, rename Release Date to imply an additional/corrective value, or introduce year-component editing. Native-version-specific Date shapes must be explained by the field's own editor. Expose distinct `contentGroup`, `grouping` and `work` when supported. Unsupported operations must be disabled/explained before Save, with final all-fields preflight for stale capabilities and mixed selections.

Preserve `AudioViewModel` as selection owner. Single edit, multi-edit, CSV/text import, filename extraction, field transfer, MusicBrainz, iTunes and raw editor must converge on the same intent planner and package registry. Every preview lists unsupported fields, precision loss, alias resolution and destructive changes. A per-file semantic operation is all-or-nothing; never silently save only its supported subset. Existing batch partial-success reporting remains per file.

| Current app property or surface | Target intent |
| --- | --- |
| year | Independent YEAR set/remove; retain its exact native text and provenance |
| releaseDate | Independent RELEASEDATE set/remove; retain exact native provenance; never update Year |
| planned date | Independent DATE set/remove, distinct from the legacy package case named date |
| title, artist, album, albumArtist, composer, genre, comment | Corresponding catalog semantic ID, with exact baseline arrays/entry identity retained |
| track/trackTotal/disc/discTotal and number text | Component intents with pair group and independent text intent |
| publisher, mediaType | LABEL, MEDIA respectively |
| isrc, barcode, catalogNumber, copyright, language | ISRC, BARCODE, CATALOGNUMBER, COPYRIGHT, LANGUAGE |
| lyricist, remixer, producer, engineer | Corresponding people/role-aware catalog entry |
| itunesAlbumID/ArtistID/CatalogID | Corresponding distinct store identifiers and native types |
| musicBrainzAlbumID/TrackID/ReleaseGroupID | Release / recording / release-group IDs respectively; TrackID must not receive release-track IDs |
| releaseType/releaseCountry | RELEASETYPE / RELEASECOUNTRY |
| contentAdvisory, artworkEditAction | Enum intent / explicit binary collection intent |
| credits | Display-only until a precise role/field edit is defined; never serialize an AVFoundation display string as authoritative metadata |
| Provider release date | RELEASEDATE only; no derived YEAR or DATE |
| Filename year token | Stored YEAR value; extraction edits YEAR only, without date inference |
| Filename/date and CSV exports | Carry canonical field identity and full precision; version the exchange schema |

CSV headers must declare a schema/profile version. YEAR, DATE, RELEASEDATE and ORIGINALDATE are independent stored columns. Preserve differences between them; do not reject a row merely because its dates have different years. Omitted columns are unchanged, and explicit removal affects only the selected field. Unversioned old AudioMator headers retain their legacy schema and native provenance until explicitly remapped; never recalculate their values from another column. Namespaced compatibility and TagLib profiles must translate source names/native identities explicitly; in particular TagLib DATE can name the native YEAR slot. Export independently stored values without deriving, completing or synchronizing them.

The app never writes containers directly, falls back to an unverified raw write, or calls a legacy Basic writer to bypass an unsupported typed patch. All mutations stay inside FileMutationCoordinator and the existing version/audio-identity guards. Package capability and mapping revisions must be checked when adopting the refactored package. Do not implement the package fix by pointing the released app at an unversioned local checkout.

## 11. Migration and rollout

1. Preserve the current pin and current-state documentation until an independently versioned package release implements this contract. Add target conformance tests alongside legacy tests with explicit intent; update obsolete assertions only when implementation changes. Inventory both standalone total aliases and formatted-pair private atoms; neither may be bulk-deleted or migrated during scanning.
2. Refactor the package registry, full-fidelity snapshot and patch planner together. Separate semantic keys from the engine PropertyMap dialect. Migrate old grouping/work projections using exact native provenance; never reinterpret old scalar drafts by property name. Publish the mapping contract version separately from the package version. Keep deprecated Basic projections source-compatible where feasible, but document any semantic change and provide explicit new date operations. Do not silently reinterpret a public enum on a patch release.
3. Release the package normally, then upgrade AudioMator's exact pin, disclosures and adapter. Update Inspector, provider application, CSV/filename schemas, conflicts and reload together. No user file migration runs on import, launch, scan or reload.
4. Existing native values remain authoritative. A file has no reliable marker proving which AudioMator version wrote a date. Never infer provenance from extension, timestamps or matching year prefixes. For legacy MP4 ©day, read its complete native value as YEAR under this profile; do not derive DATE or additionally create F(RELEASEDATE). Preserve an existing F(RELEASEDATE) independently. For FLAC/ID3, preserve independent DATE/RELEASEDATE and expose both.
5. Old in-memory or persisted drafts/previews must carry their original schema and baseline. Rebuild/preview them under the new contract or require explicit reload; never replay them against a new mapping silently. User-selected migration previews show source location, destination, before/after, removals, normalization and unresolved collisions. Default is preserve, not canonicalize.
6. Group conflicts by actual touched native storage, not by a permanent rule that all dates conflict. YEAR, DATE, RELEASEDATE and ORIGINALDATE are independent groups. A legacy alias conflict is handled through an explicit native selection, never by binding independent drafts to one slot. Pair components, role collections and alias-resolution plans likewise retain exact version guards. No retry, expected-version clearing or similar-file substitution is allowed.

## 12. Required conformance and release gates

The following are requirements for the later implementation, **not tests executed by this documentation change**:

- Enumerate every public field and every app edit property; fail registry coverage if one lacks a mapping, explicit unsupported reason or declared display-only status. Test native atom spelling/case, freeform namespace/description and source-dialect aliases.
- For each advertised field/family/version, test set, replace, remove, absent no-op, unrelated-edit preservation and unsupported rejection with original-byte preservation. Use an independent native inspector where possible, not only the same projection that wrote the field.
- Date matrix: YEAR=2004 with RELEASEDATE=2017-06-09, different independent DATE values, per-field set/remove/absence, complete native text preservation, MP4 YEAR and independent DATE/RELEASEDATE, ID3 TYER/TDAT independence, differing-year imports, absent-provider-Year preservation, and exact unchanged sibling values. No year-component synchronization tests belong to this contract.
- Test ID3v2.3 and v2.4 independently, including version preservation/conversion, independent legacy TYER/TDAT/TIME, UFID, role collections and full-date no-loss behavior. Add AIFF/Opus fixtures before claiming their conformance.
- Test totals and component clearing across all writable advertised fixtures; padded text, native numeric bounds and total-only layout limits must have explicit outcomes.
- Test every declared multi-value and shared-storage group with duplicate/empty/whitespace values, unknown siblings, multiple languages/roles, artwork entries and explicit normalization warnings. Establish comments/lyrics correctness before relying on them as a migration gate.
- Cross-tool fixtures must establish equivalent mappings for YEAR, independent DATE and release date, label, encoder fields, work/grouping and MusicBrainz IDs. Do not claim live compatibility with other editors without that observed validation; source-table agreement alone is insufficient.
- All AudioMator routes must produce the same semantic plan for equivalent intent. Test previews, mixed-format preflight, CSV profile/version handling, provider dates, conflicts, atomic rejection and post-commit reload. Preserve transaction, audio identity and durability semantics.
- A new package release and app adoption must document implemented contract version, per-format evidence, intentional gaps, migration behavior and exact commands/results. No support claim may be inferred from this specification alone.

## 13. Current implementation gaps

At the inspected package 0.6.0 revision, `.date` is labeled Recording Date and rejected for typed MP4 writes; `.releaseDate` maps to ©day; Basic year is a four-character projection. AudioMator maps Year directly to `.date` and can discard the rest of DATE when that field is edited. Its current Inspector allows unsupported MP4 Year intent. These are known differences from the target, not reasons to amend the target back to current behavior.

Other migration targets include ARTIST/ARTISTS separation, CONTENTGROUP/WORK/GROUPING placement, conductor and label native slots, encoder-field separation, canonical media/release mappings, native iTunes atoms and MusicBrainz UFID. Current private-number-text migration creates package-prefixed replacement atoms; target 2.2 instead retires both namespaces under section 6. Current generated schema tables describe existing code; do not regenerate them from this target document before changing code. The earlier Year round-trip tests establish only their asserted current behavior, not complete date-preserving conformance.
