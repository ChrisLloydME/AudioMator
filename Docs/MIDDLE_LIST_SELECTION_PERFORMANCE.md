# Middle-list selection performance diagnosis

Date: 2026-10-08. Baseline: `f376ad1`; last tagged release: `V2.6B2691`.

## Findings

- `340cbdf` replaced loaded `NSImage` objects with immutable artwork bytes and
  a computed main-actor image projection. `01704b5` made the same change for
  pending and shared multi-file artwork. Inspector body evaluation then created
  images repeatedly, including for the Clear Artwork button's availability.
  Rendering a new image incurred decoding of the full embedded cover on the
  main thread. The tagged release retained the loaded image instead.
- `a2be178` correctly replaced sampled artwork fingerprints with exact byte
  equality. Extending or revisiting a multi-selection repeated comparisons
  between the same immutable file snapshots, multiplying work for large covers.
- Existing list work amplified these regressions: selection and draft changes
  reevaluated sorting/manual ordering, every row's metadata fingerprint, full-list
  selection normalization, and selection-index scanning. Those list scans were
  already present in the tagged release; they are additional costs rather than
  the newly introduced image regression.

## Changes

- The Main feature owns a serial background ImageIO thumbnail decoder and an
  eight-entry preview cache. Thumbnails are bounded to 440 pixels for the
  220-point inspector cover. Changing selection clears the previous preview and
  cancels queued work; stale completions cannot update the current cover.
- Immutable file snapshots and pending artwork have independent revision tokens.
  Copies preserve their tokens; a reload/transformation or new replacement gets
  a new token. Preview cache lookups do not hash image bytes.
- A bounded cache memoizes exact artwork equality for pairs of immutable
  snapshots. The first comparison still examines the complete bytes; revisiting
  the pair reuses that result. Reloaded snapshots cannot use an older result.
- List ordering is cached until the visible collection, sort, or manual order
  changes. Selection-only updates skip row snapshot scans entirely. Row refresh
  decisions use snapshot tokens, and selection synchronization uses an ID/index
  lookup. Single-file inspector lookup and selection validation also use an
  ID/file lookup rebuilt when the collection changes.
- Table reloads suppress native selection callbacks before restoring selection
  by file ID, including after sorting, column changes, or file removal. Rejected
  unsaved-draft discard still restores the previous native selection.
- Full artwork payloads, exact multi-file equality, metadata write intent, and
  container write behavior are preserved. No dependency checkout was changed.

## Non-interactive measurement

A deterministic synthetic 2400 × 2400 PNG (20,129,323 bytes), rendered into a
220 × 220 CGContext, was used for 40 iterations in a standalone scratch Swift
program. It compared the old `NSImage(data:)`/render path with the production
preview cache and thumbnail decoder. It did not launch AudioMator or inspect UI.

| Operation | Time |
| --- | ---: |
| Old repeated image creation and rendering | 85.693 ms/iteration |
| New first thumbnail, including background completion | 87.990 ms elapsed |
| New cached reselection and rendering | 0.027 ms/iteration |

These are local image-path measurements, not whole-app selection latency. Cold
decode work still exists, but runs off the main actor; cached reselection avoids
it. Initial exact comparison of a previously unseen artwork pair also remains.

## Verification

- Incremental unsigned macOS build: successful.
- Focused serial app-hosted selection/artwork tests: 13 passed. They exercise
  cache reuse and invalidation, delayed/stale decode completion, bounded preview
  dimensions, exact multi-file equality, draft preservation, same-ID file reload,
  rejected selection changes, sorting, manual order, columns, and removal.
- Fast SwiftPM core tests: 57 passed, no failures.
- An initial broader inspector run was interrupted in the unrelated existing
  provider-cancellation test; validation uses the focused selection tests above.
- Interactive UI acceptance remains with the maintainer, per `AGENTS.md`.
