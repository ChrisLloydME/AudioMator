# Bounded write concurrency — 2026-11-12

Branch: `codex/package-api-performance-integration`. Package candidate: `codex/api-mapping-performance`, production `bbf64c3`. Normal published dependency resolution remains 0.7.3; validation uses the explicit ignored local workspace.

## Findings and decision

The existing Inspector path already uses four independent file transactions. MusicBrainz, iTunes, filename-to-metadata and CSV/text import plans were sequential. Raising Inspector's limit cannot accelerate those other paths.

The expanded real-pipeline benchmark uses 48 files across MP3/M4A/FLAC/AAC/Vorbis/WAV with ordinary and 64-custom-key metadata-heavy fixtures. It measures three counterbalanced samples at 1/2/4/8 workers, including version/conflict protection, actual durable writes and reload. Custom arrays are checked after stopping the timer. [All eight measured profiles](WRITE_CONCURRENCY_2026-11-12.json) are committed.

| Dataset | 1 worker | 2 workers | 4 workers | 8 workers |
| --- | ---: | ---: | ---: | ---: |
| Ordinary | 710 ms | 513 ms | 343 ms | 316 ms |
| Metadata-heavy | 1,482 ms | 910 ms | 770 ms | 745 ms |

Eight versus four improves these local medians only about 8% and 3%; sample ranges overlap for ordinary metadata. Keep the four-file default and apply it consistently to the four formerly sequential captured-plan paths. Do not infer a universal device/storage recommendation or a measured provider speedup from this executor-level experiment. No TagLib lock, filesystem flush, conflict/version or semantic preservation check is removed.

## Implementation and cancellation contract

`executeBoundedMetadataPlan` reuses `MetadataBatchExecutor` and the existing per-file `persistMetadataEdit`/`FileMutationCoordinator` path. It captures the supplied entry values and file baselines, caps active work at four, updates progress by completions and stores outcomes by original plan index. Summary ordering remains stable when completions arrive out of order. Every previous field/fingerprint preflight remains in its original workflow.

Cancellation stops work that has not entered the operation. Already started commits finish and report their real outcome. At most four may be in flight; this replaces the sequential assumption that only one could have started. The real-file cancellation regressions now use seven targets, hold all four reloads, verify exactly four committed outcomes and three unchanged files, then verify complete untouched raw maps and ordered issue accounting. In queued cancellation, all targets are reserved so no write can start; cancellation must leave every file unchanged. Serial raw-map and renumber cases retain their original expectations.

## Verification

The concurrency profile passed before production plan scheduling changed: `.deriveddata-codex/Validation/WriteConcurrencyProfile.xcresult`. Source paths newly changed by this campaign require their focused and complete gate evidence below; benchmark success alone is not functional acceptance.

Focused acceptance passed: 33 real integration/boundary/provider tests, then all five strengthened cancellation/ordering tests. Evidence: `.deriveddata-codex/Validation/BoundedPlanWrites.xcresult` and `BoundedPlanOrdering.xcresult`. All five cancellation/ordering identities are mandatory in the full named-evidence gate; deleting them from source cannot silently reduce coverage. Full acceptance pending. No manual app launch or UI acceptance was performed. No dependency version bump, publication or release was created.
