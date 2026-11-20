# ADR 0007: Durable rename journal and restart recovery

- Status: Accepted
- Date: 2026-11-19

## Context

A rename batch moves every source to a hidden same-directory staging name before
finalizing it to the intended name. Before this decision the mapping between an
operation's original, temporary and intended names existed only in memory
(`executeFileRenameTransaction` in `AudioViewModel+FileRename.swift`). The audit
finding AM-04 terminated the process after the first stage move and found only a
hidden `.audiomator-rename-<UUID>` file: no record identified its original or
intended name, startup had no staging reconciliation, and normal enumeration skips
hidden files. In-process rollback could recover only while the process survived.
F1 added verified move receipts, reservation-phase publication and bounded
readback, but no durable record existed, so process termination after any writable
stage still stranded files.

Rename also legitimately needs cycles, swaps and case-only renames, so a simpler
"move directly, never stage" rule cannot replace the two-phase transaction.

## Decision

Use a durable, versioned rename journal and an exclusive-move filesystem service.

- `RenameTransactionService` (`AudioMator/Infrastructure/FileSystem`) owns durable
  effects. `AudioViewModel` keeps authorization, folder scopes, the multi-path
  reservation and presentation.
- One JSON manifest per operation UUID lives in
  `<Application Support>/AudioMator/RenameJournal/` inside the sandbox container.
  It records explicitly ordered entries with absolute original, temporary and
  intended URLs plus captured source directory-entry identity evidence (device,
  inode, kind, size, modification/creation times, stable volume identity, and the
  exact symlink target when applicable). It contains no metadata, drafts, tag
  values, session file IDs or scope bookmarks.
- A stable `rename-journal.lock` file in the same directory is locked with a
  non-blocking exclusive `flock` from preflight through terminal record
  publication, and again for an explicit restore. The lock file is never renamed
  or removed. A second AudioMator instance in the same bundle container reports
  recovery as busy and retries on request.
- The prepared manifest is written atomically and flushed before the first file
  move. All sources are staged with same-directory
  `renameatx_np(..., RENAME_EXCL)` on held directory descriptors, then finalized
  only after every source is staged. Every stage, final, rollback and reverse
  restore move is followed by destination entry-identity verification. Volumes
  whose `URLResourceValues.volumeSupportsExclusiveRenaming` is not true are
  rejected before staging; there is no racy check-then-rename fallback.
- The record becomes `committed` atomically only after every intended identity
  verifies and the affected audio directories are flushed at the supported
  barrier. A committed record is final state. The record is removed after that
  durable marker, or after a verified complete rollback/restoration. Committed or
  uncertain records left by termination are never restored automatically; they are
  offered for explicit acknowledgement only.
- Startup loads manifests read-only after authorized folders are restored and
  before scans or mutations can publish. It installs path-keyed mutation blocks
  even when no session file IDs are loaded, then classifies in the background.
  Automatic startup moves no files, removes no records and clears no decisions. A
  warning directs the user to **Settings > Folders > Rename Recovery**, which lists
  the read-only classification and offers explicit, identity-checked,
  no-overwrite **Restore Original Names** for prepared records and **Remove
  Record** for verified committed/no-move records.
- A path-keyed journal block rejects metadata writes and rename planning until the
  recorded operation is restored or acknowledged. An accepted observation at a
  recorded path also receives a named `.journalPending(operationID)` recovery
  decision, cleared only by `verifiedJournalLocation(operationID)` after a verified
  restore or acknowledgement.
- Reservations compose two identities per lexical path: the symlink-resolved
  comparison key and the directory-entry location key (parent resolved, basename
  folded with the parent volume's case semantics). Rename reservations also include
  the deterministic staging URLs.
- Process-termination recovery is exercised by real killed-process probes for the
  documented crash gates (prepared/staged, partially finalized, committed-marker and
  restore-boundary gates); the remediation acceptance record names the covered gates.
  Power-loss durability is limited to the barriers the host filesystem actually
  supports and is reported honestly. Hidden staging files created by app versions
  before this decision have no manifest and remain manual recovery; a matching
  name prefix is never authority.

## Alternatives

- **Keep in-memory rollback only.** Rejected: process termination cannot run
  rollback, and the audit reproduced stranded hidden files.
- **Scan for `.audiomator-rename-*` files at startup and infer the mapping.**
  Rejected: a prefix conveys no original/intended names or entry identity, and a
  broad library scan or stale-file adoption is unsafe.
- **Check availability then `rename(2)`.** Rejected: the check/rename window can
  overwrite an external occupant. Exclusive renames are the product contract;
  unsupported volumes fail closed before staging.
- **Per-operation lock files.** Rejected: ownership must be provable across
  processes with one stable inode; a single stable lock in the journal directory is
  simpler and cannot move with a manifest.
- **Forward-complete a prepared record after all final moves.** Rejected for now:
  without a durable committed marker the app cannot claim the new names are final.
  A prepared record offers explicit restore instead.
- **Copy-and-delete fallback for exclusive-move-unsupported volumes.** Rejected:
  cross-volume copy semantics change identity evidence and can leave partial copies;
  rename is rejected with a specific error instead.
- **Automatically repair startup state.** Rejected: automatic destructive repair is
  outside the acceptance invariant; classification and explicit user actions are
  the contract.

## Consequences

- Interrupted renames can be found, explained and restored after process death on
  volumes that support exclusive renames; no broad filesystem search is required.
- Rename is unavailable on volumes that cannot provide exclusive renames. This is
  an intended fail-closed product behavior and must be documented for users.
- The journal is local user data under Application Support and records file paths;
  automatic diagnostics stay sanitized and the record never enters the save issue
  log. Users with backups may include the journal directory.
- Records remain until restore, acknowledgement or verified completion. Committed
  records left by termination require explicit acknowledgement; prepared records
  require explicit restore (or acknowledgement when they prove no file moved).
- Cross-process protection is advisory and limited to AudioMator instances that
  honor the journal. Other programs remain external writers; source-name and
  destination races outside the exclusive syscall are documented limits.
- A malicious or externally modified journal is treated as untrusted input:
  validation rejects malformed or unsupported records and retains them for
  inspection rather than acting on them.

## Verification

- Journal format/store: `RenameJournalManifestTests`, `RenameJournalStoreTests`
  (round trip, unsupported/malformed/orphan retention, duplicate protection, stable
  lock inode, non-blocking contention).
- Exclusive moves: `RenameFileSystemProbeTests` (native `RENAME_EXCL` no-overwrite,
  case-only after staging, held-directory identity, directory barrier).
- Transaction service: `RenameTransactionServiceTests` (prepared-before-stage,
  identity gates, rollback, committed marker, classify/restore, idempotent retry,
  busy, occupied destinations).
- App wiring: `FileRenameTransactionTests` (faulted stage/final/rollback and
  replacement controls), `RenameJournalRecoveryTests` (startup bootstrap without
  moves, path blocks, shared writer guard, busy, acknowledgement, unavailable
  folder), `RenameRefreshSafetyTests`, `FileMutationSerializationTests`.
- Native APFS probe evidence recorded for the campaign: exclusive renames reject an
  occupied destination without changing either file, staged case-only renames
  succeed, directory `fsync` succeeds, and same-process second lock attempts report
  contention.
