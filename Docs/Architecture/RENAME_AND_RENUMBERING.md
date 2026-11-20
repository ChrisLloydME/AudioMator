# Rename and Renumbering

This document covers two filesystem/metadata operations: renaming files from templates and rewriting track numbers from list order.

## Rename

### Planning

`makeFileRenamePlan(template:targetFiles:)` in `Domain/Rename/FileRenameTemplate.swift` renders each file's base name from the template, preserves the original extension, sanitizes unsafe characters, and produces a `FileRenamePlan` with per-row status.

Statuses include:

- `ready`,
- `unchanged`,
- `emptyName`,
- `nameTooLong`,
- `sourceUnavailable`,
- `duplicateTarget`,
- `existingFile`.

`FileRenameCollisionPolicy` handles duplicate destinations and existing files. If file A will move out of a name that file B wants, the plan allows the swap or cycle because all sources move in the same transaction. A destination occupied by a file that is not also moving is an existing-file conflict.

### Sanitization

`FileRenameSanitizer` replaces:

- `/` with `-`,
- `:` with `-`,
- NUL with `-`,
- other control characters with a space,

then trims surrounding whitespace. An empty result is rejected. Unicode scalars are otherwise preserved.

### Transaction and durable journal

`renameFiles(using:)` builds one immutable `PreparedRenameTransaction` under a single operation UUID, with deterministic per-index hidden stage names from `RenameStagingName`, then delegates the filesystem work to `RenameTransactionService` in `Infrastructure/FileSystem`. The view model keeps authorization, folder scopes, the multi-path reservation and presentation; the service owns durability and exclusive filesystem effects.

The transaction holds a stable `rename-journal.lock` file in `<Application Support>/AudioMator/RenameJournal/` with a non-blocking exclusive lock from preflight through terminal record publication, and again for an explicit restore. One versioned (v1) JSON manifest per operation UUID records the explicitly ordered entries with absolute original, temporary and intended URLs plus the captured source directory-entry identity evidence (device, inode, entry kind, size, modification and creation time, stable volume identity, and the exact symlink target where relevant). The record contains only recovery evidence: no metadata, drafts, tag values, session file IDs or security-scope bookmarks. Malformed, unsupported and orphaned records are retained for manual inspection and reported with sanitized diagnostics; recorded paths never appear in automatic logs.

The service executes in this order:

1. Preflight every entry without moving anything: source existence and entry identity, preview fingerprint, deterministic stage-name availability and the volume's exclusive-rename capability. A volume whose `URLResourceValues.volumeSupportsExclusiveRenaming` is not `true` is rejected before staging; there is no racy check-then-rename fallback.
2. Persist the `prepared` manifest atomically, flushing the file and its containing directory at the supported barrier. If preparation cannot be persisted safely, no file is moved.
3. Stage every source to its hidden same-directory name using `renameatx_np(..., RENAME_EXCL)` on held directory descriptors. The authorized lexical parent path must still identify the held directory immediately before each pass. Destination entry identity is verified after every stage move.
4. Finalize every temporary name to its intended name only after all sources are staged, again with `RENAME_EXCL` and post-move identity verification.
5. Flush the affected audio directories at the supported barrier, re-verify every intended entry, then rewrite the manifest as `committed` atomically and durably. The committed record is final state; the record is removed only after that record exists. Committed records left by a crash are shown for explicit acknowledgement and never moved automatically.
6. On a failure before the committed record, roll back finalized entries to their own temporary names and then staged entries to their originals in reverse order, verifying each reverse move. If rollback or restoration cannot be verified, stop moving, retain the prepared manifest as recovery evidence and report an unresolved outcome. A journal failure after any audio move is an unresolved outcome, not a clean failure.
7. Once staging begins the operation is not cancelled mid-move: cancellation before the first stage exits cleanly with no files moved and removes the record; after staging starts the app owns completion or rollback and reports the actual effects.

The transaction remains an app transaction over the database of record: app-owned operations are serialized by the path reservation, while other programs can still change the source name between verification and the rename syscall. Kernel destination exclusivity (`RENAME_EXCL`) does not bind the source inode inside the syscall; pre-move source identity revalidation, post-move destination verification and a retained prepared record are the available mitigations. A matching hidden-file prefix alone is never authority.

### Recovery reporting

`FileRenameRecoveryItem` records:

- the original URL,
- the intended URL,
- every observed final location,
- one verified location plus its directory-entry identity when exactly one candidate matched,
- rollback errors.

Rollback checks that a candidate at the destination still matches the expected file before moving it back. It never overwrites a file that appeared during rollback.

### After a rename

Successful moves are published in two reservation phases:

1. **Move and placeholder publication.** The transaction returns a receipt for every
   successful move containing the claimed file ID, the lexical old URL, the actual
   destination URL, and the directory-entry identity captured at the end of the move.
   While the source/destination reservation and directory access are still held, the
   app clears the old path keys and records the new ones as one mapping update (so
   swaps cannot transiently alias), rotates the affected quick-import URL tokens,
   advances the affected file-model generations, invalidates in-flight watched-folder
   scans, and publishes an authority-free display projection with a named pending
   recovery decision. No writer can start on a destination without observing that
   decision.
2. **Bounded full readback.** After the union reservation is released, each
   destination is reacquired under the coordinator and read in full with a 60-second
   deadline (at most the existing four concurrent metadata reads). The destination
   entry identity is checked before the read and again before the result is accepted.
   Only a successful, same-entry full read produces a new coherent observation and
   clears that move's pending decision. A failed or timed-out read, or a replaced
   entry, keeps the display projection read-only and directs the user to Reload from
   Disk; no lightweight fingerprint/version probe can restore write authority. When
   Reload from Disk decodes a different valid file at a non-journal recovery path,
   the move/unresolved decision remains blocked and AudioMator presents an explicit
   **Accept Replacement** confirmation (`PendingReplacementFileReview`); accepting
   re-reads the file under reservation, verifies that its device/inode still matches
   the reviewed replacement, and clears matching-path move/unresolved decisions via
   `.explicitReplacementAcceptance` without ever clearing `.journalPending`.

The coordinator serializes app-owned operations only. An external program can change
the destination between the move and the readback; the before/after entry-identity
checks and the loader's own post-await fingerprint/version guard are the protections
against publishing a different entry. It is an app transaction, not a filesystem-wide
lock.

### Restart recovery

Startup restores authorized folders, loads journal manifests read-only, installs path-keyed mutation blocks even when no session file IDs are loaded, then classifies in the background. Nothing is moved, removed or cleared automatically. A single startup warning directs the user to **Settings > Folders > Rename Recovery**, which lists prepared, committed, unreadable and busy records with per-entry observed roles and folder availability.

- **Restore Original Names** is offered only for a prepared record whose entries classify unambiguously; a prepared record whose recorded folder is currently unavailable exposes an explicit **Authorize & Restore…** action that requests access to the missing folder before re-classifying under the journal lock. Restore re-checks scope, takes the journal lock and union reservation, re-classifies under the lock, validates the complete reverse set before the first move, and then restores with `RENAME_EXCL`: each verified final location first moves back to its own unoccupied temporary name, then stages are restored to originals. Case-only names, swaps and cycles are matched by entry identity, not by name. An occupied name stops the restore with nothing overwritten at that step; the record is retained and a later retry is idempotent, recognizing entries already back at their originals.
- **Remove Record** is offered for a verified committed record (or a prepared record that proves no files moved). It removes only the saved record after fresh verification under the lock; files are not moved. An uncertain committed record can be acknowledged for inspection but never authorizes moving files.
- **Busy** means another AudioMator instance in the same bundle container holds the journal lock. Read-only classification still installs blocks; a user-requested retry is required. The lock is advisory between processes that honor the journal; other programs remain external writers.

Missing folder access is reported as unavailable and a restore prompts for the exact recorded folders before the journal lock is taken. While a record blocks a path, metadata writes and rename planning for that path fail closed until restore or acknowledgement. Hidden staging files created by older app versions have no journal record and remain manual recovery work; no broad filesystem search or prefix-based adoption runs.

Journal-path durability and pre-upgrade manual recovery remain separate concerns: release evidence distinguishes process-termination recovery from power-loss durability, and the app never claims a stronger durability barrier than the host filesystem supports.

### Constraints

- Existing destination files are not overwritten: staging and finalization use exclusive renames and stop on an occupied name.
- All sources are preflighted before any move, but an external change after preflight can still fail after earlier sources have moved, so verified rollback may be required.
- A rename is not a group commit: failure triggers rollback, and an incomplete rollback or restore keeps a prepared journal record for explicit recovery.
- Only volumes that report exclusive-rename support participate; other volumes are rejected before staging with a specific error.
- The transaction cannot overlap app-owned metadata writes to any source, destination, staging or symlink-target path (reservations compose the symlink-resolved comparison key and the directory-entry location key).
- A file with an unresolved recovery decision or a journal-blocked path cannot be renamed or written until a coherent reload or the verified recovery flow clears it; the planner only accepts a coherent observation fingerprint, never a fresh stat probe.
- Process-termination recovery is exercised by real killed-process probes for the documented crash gates (prepared/staged, partially finalized, committed-marker, and restore-boundary gates); the remediation acceptance record names the covered gates. Power-loss durability depends on the barriers actually supported by the host filesystem and is not claimed beyond them.

## Track Renumbering

### Inputs

`TrackRenumberOptions`:

- direction: ascending or descending,
- start number: a required positive integer from `1` to `9_999`, default `1`.

There is no zero-padding option. The preview and execution submit the stored numeric value; text formatting such as `07` is not a supported input intent. A blank, malformed, zero, negative, signed, fractional, overflowed, or Unicode-lookalike start number is an explicit invalid state that disables Apply and causes zero writes; the value is never clamped or replaced by a fallback.

### Plan and target order

`makeTrackRenumberPlan(...)` builds one `TrackRenumberPlan` from the ordered files and the current selection. Each ordered row carries a reasoned disposition (ready, unchanged, rejected, or skipped), the reviewed write target, the assigned numeric value and a frozen track-only `MetadataEditPayload` derived from the same reviewed snapshot. Preview, eligibility, counts and Apply all consume that same plan; Apply never recomputes the sequence from the current collection.

Unsupported, refresh-required, duplicate-identity and stale targets are classified before numbering and do not consume numbers. A target that already has the desired number is an unchanged numbered row: it keeps its slot and performs no disk write. A later write failure keeps its slot so following rows keep their reviewed assignments.

The UI supplies the current list order and selection:

- with no selection, every file in list order,
- with a selection, only selected files, preserving list order.

### Write behavior

Before writing, Track Renumber pre-authorizes only currently eligible executable rows (`prePromptDirectoryAccessURLs`) so stale, removed, or recovery-blocked rows never trigger a folder prompt. For each ready row, in order:

1. Revalidate the captured reviewed target against current membership, path identity and recovery state.
2. Submit the frozen track-number component intent through the reviewed executor with the captured nonoptional metadata revision. The existing total, the complete disc group and unrelated fields are carried as untouched values and are not removed.
3. Reload the snapshot from disk and report success, warnings, or failure per file.

Renumbering is serial and uses the same reviewed-write reservation, commit permit and bounded readback as other metadata writes and erase. It does not modify disc numbers.

### Results

`TrackRenumberResult` reports total targets, succeeded, unchanged, skipped unsupported, skipped duplicates, failed, any start validation message, per-file failures, and per-file warnings. The UI displays the summary; there is no group rollback.

### Constraints

- Track totals are preflighted and preserved; renumbering never clears a total.
- The operation writes a typed number component, not a formatting-only text patch and not a full semantic replacement. Disc numbers and their totals are preserved.
- Ambiguous or invalid legacy number candidates make the package reject the write; renumbering reports the failure and does not pick a candidate.
- Renumbering never performs private-atom cleanup; typed component patches leave legacy aliases and unrelated keys untouched.
- Containers may normalize number representation. Verification compares numeric component values; a text-only difference is not by itself a failed write. Package warnings are surfaced as returned. An unchanged numeric value performs no write, so padded original raw text is preserved when its numeric value already matches.
- Unsupported formats are skipped rather than force-written.

## Tests

- Filename template parsing, sanitization, collisions, and extraction: `FileRenameTemplateTests`, `FilenameMetadataTemplateTests`, `AudioMatorCoreLogicTests`.
- Independent filename tokens: `year` keeps complete stored YEAR text; `date`, `releaseDate` and `originalReleaseDate` edit only their own field. Extraction applies only the explicitly targeted field.
- Journal-service transaction ordering, identity gates and rollback: `FileRenameTransactionTests`, `RenameTransactionServiceTests`.
- Durable journal format, store, lock and corruption retention: `RenameJournalManifestTests`, `RenameJournalStoreTests`.
- Exclusive-move native probes (occupied destination, case-only, held directory descriptor): `RenameFileSystemProbeTests`.
- Startup bootstrap, path blocks, busy classification, acknowledgement and missing-folder classification: `RenameJournalRecoveryTests`.
- Post-rename refresh safety: `RenameRefreshSafetyTests`.
- Renumber start policy, plan rows and dispositions: `TrackRenumberTests` (plus the Foundation-only start policy in `AudioMatorCoreLogicTests`).
- Renumber strict execution, verification, cancellation and disk readback: `TrackRenumberExecutionTests`.
- Real FLAC/MP3/M4A renumber round trips: `TrackRenumberRoundTripTests`.

Interactive preview UI is not covered by automated UI tests.

## Recovery Publication Ordering

Incomplete rollback reconciles each recovery item by file ID. A single verified location is rebound through the same two-phase receipt/readback path; an unknown, ambiguous, or replaced location disables writes. Recording a recovery decision also discards queued reloads, advances the file's publication generation, and invalidates in-flight watched-folder scans and old-URL import tokens so older observations cannot undo that safety state. Recovery decisions are named reasons (pending move readback, unresolved recovery location, journal pending) and are cleared only by their matching transition; automatic activation, watched-folder reads, and quick reimport clear none. A `.journalPending(operationID)` decision is attached as soon as an observation is accepted at a recorded path, so a queued writer is rechecked inside its reservation. It is cleared only by a verified restore or explicit acknowledgement of that operation; an ordinary reload does not clear it.

Renumbering treats a committed-but-durability-uncertain outcome as a successful write with a warning, matching other metadata writers. It reports the directory-sync detail and advises against retrying the committed save.

## Renumber Eligibility and Cancellation

Only format-capable targets with a verified loaded revision participate in number assignment. Refresh-required targets are reported as failures before directory-access prompting and do not consume numbers. A runtime write failure may still leave a gap; renumbering does not retry or roll back committed files. Cancellation stops before the next target. The current commit and readback finish under their mutation reservation, and the result retains committed successes and records every unprocessed target as cancelled.

## Related Documents

- [Metadata Exchange](METADATA_EXCHANGE.md)
- [State and Mutation Model](STATE_AND_MUTATION_MODEL.md)
- [File Revision and Reload](FILE_REVISION_AND_RELOAD.md)
