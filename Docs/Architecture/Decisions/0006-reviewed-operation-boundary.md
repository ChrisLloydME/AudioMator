# ADR 0006: Reviewed metadata writes and commit admission

- Status: Accepted
- Date: 2026-11-19

## Context

The audited write path had one mixed entry point with several optional
arguments. A plan could be authorized from a mutable model re-resolved at
Apply time, the expected package revision could silently default to the model
loaded at that moment, missing capability information failed open, and there
was no admission gate between the final MainActor eligibility check and the
synchronous package writer. Cancellation was reported as a generic failure by
matching a localized message. The audit findings AM-03, AM-05, AM-06, AM-08,
AM-12, AM-18 and AM-19 all depend on this boundary.

The pinned dependency's writer performs a synchronous compare-and-commit with
the expected package revision. A commit that has started cannot be interrupted;
only its real outcome can be reported. The app-owned path reservation serializes
app mutations but does not stop an external process from changing the file
between the final check and the commit.

## Decision

1. **Write authority is an observation.** `AudioFile.Observation` is created only
   by a validated full read (requested ID, lexical URL, nonoptional package
   version, conflict baseline, verified fingerprint) and is replaced or cleared
   by later observations and recovery projections. Display, move and recovery
   projections always carry no observation. `withUpdatedURL`-style composition
   of new tokens with retained metadata is not part of the type.
2. **A reviewed write freezes target and intent.** `ReviewedMetadataTarget`
   carries the logical ID, operational URL, fingerprint and nonoptional package
   version captured from one coherent observation. `ReviewedMetadataWrite`
   freezes either a semantic payload, a raw patch or erase-all. A frozen adapter
   projection records the executable field operations, component operations and
   rejection state, so previews and the commit use the same deterministic
   encoder. Preview and draft state never rebuild the payload from the live
   editor at Apply time.
3. **Precommit eligibility and admission are separate.** The MainActor owner
   classifies an unready target before any authorization prompt, revalidates
   membership, URL identity and recovery state after queueing under the captured
   path reservation, and registers a per-file `MetadataCommitPermit` before the
   detached worker starts. Cancellation synchronously revokes the pending permit.
   Immediately before the synchronous writer the worker verifies the captured
   fingerprint and `admit()`s; a revoked permit returns a precommit rejection
   with zero package calls. The permit critical section contains no file or actor
   work.
4. **Outcomes stay explicit.** A cancelled queued write is a `.cancelled`
   outcome, not a localized failure string. An admitted commit reports its real
   result, including durability and reload warnings. Cancellation never
   relabels a committed outcome and an admitted commit is never retried.
5. **Publication is by stable identity.** Accepted reloads publish to the
   authoritative source collections by file ID, not only the visible sidebar
   projection, and completion stays tied to the operation and draft generation
   that began it. Stale generations discard their UI publication while still
   reporting real disk outcomes to the operation summary.
6. **Draft-aware routes are distinct.** Inspector and Raw Metadata Editor drafts
   keep their documented conflict-aware baseline and policy validation. The
   strict reviewed route passes the captured nonoptional revision to the package;
   it does not select a merge policy or substitute a newer version.

## Alternatives

- Keeping the mixed optional-version entry point and adding checks: rejected
  because the authority decision remains implicit and a caller can still fall
  back to the model loaded at Apply.
- A MainActor-only final guard without a cross-thread admission gate: rejected
  because the detached writer can outlive membership, protection or recovery
  changes.
- A global write broker: rejected; ownership stays per workflow and per file with
  the existing coordinator and executor.
- Treating cancellation as a message-matching failure: rejected because batch
  accounting cannot distinguish a cancelled unstarted target from a real error.
- Continuing to write with a nil revision: rejected for reviewed routes. A load
  without a package version cannot authorize a reviewed write; such a file stays
  readable and must be reviewed again after a coherent read.

## Consequences

- A file that failed a full read after a move, or that has no package revision,
  cannot be written through a reviewed route. Users see reload guidance instead
  of a silently substituted revision.
- The app cannot promise that cancellation stops an admitted commit; it promises
  accurate reporting of committed and warning outcomes and zero unstarted work.
- The package remains the only owner of container I/O, atomic commit and revision
  comparison. The app verifies fingerprint identity and observable outcomes but
  does not claim to prove the package's rollback behavior by itself.
- Inspector, Raw Metadata Editor, LRCLIB, MuseAmp and erase routes must migrate
  to the reviewed or draft-aware routes before the optional forwarding path is
  removed; until then the legacy route is an explicitly labeled migration
  boundary, not an authorization fallback.
- Test doubles must implement the adapter-owned projection when a plan-time
  projector is required; fabricated package revisions are not acceptable, so
  tests mint real tokens from disposable fixture copies.

## Verification

- `MetadataWriteProjectionTests`, `MetadataCommitPermitTests`,
  `ReviewedMetadataWriteExecutionTests`: projection determinism/no-op/fail-closed
  capability, permit first-transition and cancellation, strict route captured
  revision and changed-disk rejection.
- `FileObservationConstructionPolicyTests` and the rename/reload suites:
  only the validated loader constructs observations; failed readback, replacement
  and late observations stay non-writable.
- `ProviderTaggingCancellationTests`, `FileMutationSerializationTests`,
  `MetadataBoundaryMatrixTests`, `MetadataSaveJourneyTests`: structural
  cancellation accounting, admission ordering, strict provider writes and
  real-adapter readback.
- Full named gate evidence: `.deriveddata-codex/Validation/` runs on the
  integrated candidate.
