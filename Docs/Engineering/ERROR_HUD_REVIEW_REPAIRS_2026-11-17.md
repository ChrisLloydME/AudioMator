# Error and HUD review repairs — 2026-11-17

Status: implementation and syntax-only verification. No localization resources changed. No app launch, app-hosted run, full validation, or temporary-folder authorization was attempted for this repair.

## Review disposition

The third-party review was checked against the current implementation, not accepted solely on priority labels.

| Review items | Disposition |
| --- | --- |
| 1 | Updated the MusicBrainz descriptions and both provider timeout assertions. |
| 2 | Confirmed data-integrity defect. Validate both components, including malformed totals and integer bounds, before mutation. Added Inspector-payload regressions for track and disc edits, valid removal, and unrelated text-number preservation. |
| 3, 9 | Removed HUD log navigation per maintainer request. Preserve full model details, render a bounded preview, and show an independent omission notice rather than silently clipping a footer. Batch summaries state the omitted issue count. |
| 4 | Artwork preparation has its own title and presenter; it does not create a save-failure entry. |
| 5 | Save and clear failure sentences name the actual operation. |
| 6 | Per-file unsuccessful/cancelled accounting and the existing result enum are retained by design. Presentation recognizes only the pipeline’s own exact cancellation messages, shows cancellation as a warning, and keeps the cancellation count out of save-failure counts. Empty lyric results are warnings. Aggregate log severity now follows HUD severity; individual issue reasons remain available. |
| 7 | Background checks still preserve drafts by design. Reread errors are now surfaced with deduplication; fully failed manual reloads are failures. Read failures do not belong in Save Logs. |
| 8 | Confirmed race from source inspection. A presentation generation guards asynchronous dismissal completion so it cannot hide a newer HUD. No interactive reproduction is claimed. |
| 10–18 | Fixed field labels, shared post-commit context, record status, import-count instructions, update-alert composition, generic date validation wording, rename recovery sentences, directory status grammar/accuracy and CSV count grammar. |
| 19 | Status summaries retain the original title and show a count; no lowercasing or grammatical noun-phrase synthesis. |
| 20, 21 | Metadata read-error lists disclose omitted files; recording detail failure text is preserved. |
| 22 | Artwork cancellation has separate non-error state; existing results remain usable after a download cancellation. |
| 23 | Diagnostic detail remains available by design, after a friendly summary. It is not reclassified as the cause of a failed save, or discarded. |
| 24 | HUD model owns summary/details and supports explicit content for filenames containing newlines. Legacy subtitle callers remain supported. Removed the dead verb helper and shared post-commit warning construction. A wider migration of every historical subtitle caller is unnecessary for this repair. |
| 25 | Nonactivating, noninteractive, timed notification behavior and centered SF Symbols are retained by design. Persistent/interactive error panels and cross-Space behavior would be a separate UX change. |

## Verification boundary

Updated existing expectations and added ErrorPresentationRepairTests for number-total rejection, explicit removal, unchanged text numbering, HUD content/omission, cancellation accounting and operation-specific clear wording. Those app-hosted tests were not executed. A Swift frontend syntax parse and diff-whitespace inspection were used; they do not establish compilation, runtime layout, test success or accessibility acceptance. The maintainer explicitly declined full validation and temporary-folder access. No external TagLib checkout was accessed or modified.

## Follow-up review (N1–N9)

| Item | Disposition |
| --- | --- |
| N1 | Corrected cancellation-state, rename-recovery, and mixed-result severity assertions. Partial success remains a warning in both HUD and aggregate log. |
| N2 | Deduplication now includes file ID and URL, resets after manual as well as automatic completion, and clears with selection/draft-baseline replacement. A stale in-flight refresh cannot publish failures for a different selection. |
| N3 | Single clear and lyrics route through the common cancellation-aware presenter. Renumber cancellation has its own collection and neutral metric, separate from failed files. Rename has a typed cancellation flag, catches CancellationError explicitly, preserves other diagnostics, and avoids the failure alert when cancelled. Legacy unsuccessful per-file accounting remains for metadata batches. |
| N4 | No HUD log link or expansion control is added: this is an explicit maintainer choice, not a defect to reverse. The preview now keeps complete detail groups within a larger budget; omitted groups disclose their headings and count. The actual three-warning fixture retains both messages for the second file and its additional-file count. Oversized single groups have an explicit remaining-character count. |
| N5 | Single warning APIs now require fileName and warnings separately. Reload, quick-import and rename-failure presenters supply explicit content. Compatibility splitting remains only for historical callers that own their first summary line. Added a warning test with a newline in the filename. |
| N6–N9 | Added field-specific range errors and negative/overflow coverage, removed redundant filename prefixes from fingerprint errors, separated rename cancellation from unexpected errors, removed duplicate all-failed summary clauses, clarified count punctuation, removed tooltip double spacing, and made the shared readback warning mention closing Metadata Editor when applicable. |

Follow-up verification remains syntax-only plus source and whitespace inspection. The new tests were not run and no build-for-testing result is claimed for these follow-up edits. Files marked untracked remain deliverable working-tree files; no commit or staging of unrelated work was authorized or performed.

## Third follow-up (H1–H8)

- **H1, fixed:** the oversized-single-group fallback now applies both the 14-line and 1,000-character limits. Notices include at most three headings of 40 characters each, followed by the remaining group count; the view also bounds notice lines. Added short-line and 500-omitted-group regression cases. Full original details remain in the model. No log link or interactive HUD was added.
- **H2, fixed:** only a real selected-ID change clears the dedup state through the selection property's observer. Rebuilding/cancelling Inspector drafts and publishing same-selection write readback no longer rearm the warning. Completed refreshes continue to update dedup state. Added a same-selection edit/cancel/readback regression.
- **H3, fixed:** integer syntax is recognized separately from machine-integer parsing, so enormous decimal values reach field-specific range validation rather than the nonnumeric-text message. Range tests now assert the wording as well as the field name.
- **H4, fixed:** shared recovery instructions refer to closing an open metadata tool and make the unsaved-edit confirmation conditional; no Inspector workflow is assumed.
- **H5, retained and documented:** a single cancelled-before-write operation is not a failed save and does not enter Save Logs. Batch records retain unprocessed files to account for every requested target. This is an intentional difference in logging scope, not an inconsistent severity.
- **H6–H7, compatibility retained:** exact owned cancellation messages, legacy subtitle fallback, and unused filename associated values have no confirmed faulty current caller. A typed-result/API migration is deferred rather than mixed into these repairs.
- **H8, fixed:** removed the omitted-file message's trailing space and use “folders” consistently in directory status.

Verification for this follow-up: Swift frontend syntax parse and diff-whitespace check only. Regression tests were added but not executed. No build, app-hosted run, localization resource change, app launch, or temporary-folder authorization is claimed.
