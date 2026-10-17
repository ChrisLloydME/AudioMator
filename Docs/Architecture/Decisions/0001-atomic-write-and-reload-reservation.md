# ADR 0001: Metadata write and reload share one path reservation

- Status: Accepted
- Date: 2026-07-25
- Amended: 2026-09-16

## Context

`FileMutationCoordinator` already provided atomic reservations for normalized
paths. Track renumbering performed fingerprint validation, write, and reload in one
reservation, but the inspector, raw metadata, erase, and LRCLIB paths released the
reservation after the write and then reloaded separately. A rename or another write
could therefore occur between persistence and refresh.

## Decision

Create an explicit metadata file mutation use case that performs, inside one path
reservation:

- cancellation checks,
- expected-fingerprint validation,
- the concrete write closure, and
- the persisted-snapshot reload.

It returns a structured result distinguishing write failure, write success with
reload success, and write success with a reload warning. `AudioViewModel` applies
snapshots, synchronizes drafts, and maps presentation only on the main actor.

A synchronous TagLib write cannot be reliably stopped once it has started by Swift
Task cancellation. The write therefore has no UI deadline; callers wait for the
real commit result. A deadline applies only to the reload after a successful
commit. A reload timeout returns write success with a reload warning and releases
the reservation so later mutations can proceed.

## Alternatives

- **Add a second reservation around reload only:** rejected. An interleaving window
  remains between the two reservations, so the reload cannot be proven to belong to
  the write.
- **Reserve every file in a batch at once:** rejected. It unnecessarily blocks
  unrelated files and widens the impact of cancellation and long batches. Per-file
  atomic write/reload already provides consistency.
- **Let each feature keep its own helper:** rejected. The existing inconsistency
  came from multiple orchestration paths.

## Consequences

- In normal completion, rename and same-path metadata mutations cannot occur
  between write and reload. After the reload deadline the reservation is released
  and a late reload result is discarded.
- A reload failure does not roll back a successful write; the result states that
  disk changed but the UI snapshot was not refreshed.
- The use case needs app-hosted fake-pipeline tests; extractable result semantics
  belong in fast tests.
- Multi-file batches still allow partial success and report per file.

## Verification

- A continuation-controlled test proves a second mutation cannot enter during a
  normal reload; another proves a reload timeout returns persisted success and
  releases the reservation.
- A blocked-write test proves a synchronous write that exceeds the reload deadline
  still waits for its real result and is not reported as a failure that later
  commits.
- Injected reload failure preserves write warnings and marks the result as not
  refreshed.
- Cancellation while waiting for the reservation proves the write closure does not
  run.
- App-hosted mutation tests, SwiftPM core tests, and the macOS build pass.
