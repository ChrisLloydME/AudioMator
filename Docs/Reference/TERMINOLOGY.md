# Terminology

Terms used throughout the AudioMator documentation and source.

| Term | Meaning |
| --- | --- |
| **Snapshot** | An immutable `AudioFile` value loaded from disk: tags, technical fields, artwork bytes, fingerprint, metadata version, and conflict baseline. |
| **Draft** | An editable `SingleFileEditModel` or `MultiFileEditModel` derived from one or more snapshots. A draft is not disk truth. |
| **Baseline** | The snapshot a draft was created from. Used to compute changed fields and detect conflicts. |
| **Fingerprint** | `AudioFileFingerprint`: normalized path, size, modification date, device, and inode. Not a content hash. |
| **Metadata version** | The package's opaque `MetadataFileVersion` used for optimistic write validation. |
| **Refresh-required** | A snapshot whose fingerprint or metadata version could not be recovered after a rename. Version-checked writes fail closed until a successful reload. |
| **Mutation** | Any operation that changes a file on disk: metadata write, raw patch, erase, track renumber, rename, or move. |
| **Reservation** | Exclusive access to one or more normalized file paths via `FileMutationCoordinator`. |
| **Conflict policy** | The Settings → Conflicts strategy controlling draft/disk merge behavior. |
| **Convergence** | A draft value that exactly equals the current disk value for an edited field, allowing a merge without overwriting. |
| **Semantic write** | A metadata write expressed as typed fields (title, artist, track number, artwork intent) rather than raw keys. |
| **Raw write** | A `RawMetadataPatch` of exact PropertyMap keys and value arrays. |
| **Preflight** | Capability checks performed before a write: extension writable and requested fields supported. |
| **PropertyMap** | TagLib's key → ordered value-list projection used by the raw editor and raw patches. |
| **Tag Inspector** | Read-only raw dump of TagLib properties, ID3v2 frames, legacy sections, and compatibility notes. |
| **Write plan** | A previewed set of per-file metadata changes produced by a converter or provider before applying. |
| **Provider** | An online metadata source: MusicBrainz, iTunes, or LRCLIB. |
| **Batch partial success** | Per-file commits where some targets succeed and others fail; there is no group rollback. |
| **Durability uncertain** | The package observed a commit but could not confirm directory durability. Treated as committed with a warning. |
| **Recovery item** | A rename failure record with original, intended, and observed file locations plus rollback errors. |
| **Current Session** | The non-persisted Quick Import file list. |
| **Watched folder** | A persisted, security-scoped folder whose contents are scanned and refreshed. |
| **MuseAmp ID** | Optional JSON comment payload with album/track IDs for MuseAmp compatibility. |

## Related Documents

- [Glossary is referenced from the documentation index](../README.md)
- [Architecture Overview](../Architecture/OVERVIEW.md)
- [State and Mutation Model](../Architecture/STATE_AND_MUTATION_MODEL.md)
- [Metadata Pipeline](../Architecture/METADATA_PIPELINE.md)
