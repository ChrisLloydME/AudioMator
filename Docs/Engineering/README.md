# Engineering evidence

This folder holds the remaining, still-relevant dated engineering evidence: dependency and release acceptance, the accumulated-code cleanup audit, and feature/investigation verification. These records are **evidence, not authority** — each one describes a specific date, baseline and environment, and may be partly superseded even while its main claim still holds. Current behavior is documented in the current-state documentation set; never copy a claim from here into current guidance without re-verifying it against the implementation.

- Current documentation: [Documentation index](../README.md) — Product, Architecture, Development, Reference and Security.
- Superseded records: [HISTORY archive](HISTORY/README.md).
- Related current pages: [Testing](../Development/TESTING.md), [Build](../Development/BUILD.md), [Metadata Pipeline](../Architecture/METADATA_PIPELINE.md), [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md).

## Release and dependency acceptance

| Record | Date / baseline | Claim it supports | Status |
| --- | --- | --- | --- |
| [Accumulated-code cleanup automated acceptance](AUDIOMATOR_LEGACY_CLEANUP_ACCEPTANCE_2026-11-18.md) | 2026-11-18 · branch `codex/audiomator-legacy-cleanup-20261117` · baseline `origin/main` `f36c2a2e` · final tested revision `19e1ac23` | Latest full automated gate: 13 policy, 62 core and 629/629 serial app-hosted tests, zero failures/skips/expected failures, unsigned Release build plus artifact validation, `EXIT:0`, against the unchanged published 0.8.1 pin | Current automated gate evidence. Interactive UI acceptance, signing, notarization and distribution are explicitly unexecuted; the retained-protection register in the ledger remains in force. |
| [Published TagLibAudioMetadata 0.8.1 Debug adoption](TAGLIB_081_DEBUG_ADOPTION_2026-11-17.md) | 2026-11-17 · branch `codex/adopt-taglib-081` based on `main` `a0230a00` · tested source `6a94d745` | Exact published 0.8.1 pin (revision `b8ed5475…`) resolved through the normal Xcode project; Debug-only 13/62/596 gate, no local override, unchanged license and TagLib binary | Evidence for the unchanged dependency pin (still 0.8.1). Its 596-test app inventory is superseded as an inventory by the 2026-11-18 cleanup acceptance; Release/Archive were excluded. |
| [Accumulated-code cleanup ledger](AUDIOMATOR_LEGACY_CLEANUP_LEDGER_2026-11-18.md) | 2026-11-18 · same branch and baseline · code-complete revision `28fe62a6` | Whole-application audit of 314 tracked files across seven area audits, candidate/decision ledger, retained user-data compatibility register, investigate register and deferred candidates | Current audit record for the cleanup campaign. Documentation-only follow-up commits do not change its findings; it claims automated scope only, not interactive or distribution acceptance. |

## Application investigations and feature evidence

| Record | Date / baseline | Claim it supports | Status |
| --- | --- | --- | --- |
| [Internal numbering recovery](INTERNAL_NUMBERING_RECOVERY_2026-11-16.md) | 2026-11-16 · branch `codex/internal-numbering-recovery` based on `db2016b8` · final tested app `3d291490`, local package candidate `e9fb7da` | Investigation and local-candidate evidence for automatic edited-group numbering recovery, atomic edited-pair retirement and preservation of returned commit status; 13/62/593 local-candidate gate, later follow-up 596 | Retained for the recovery and dirty-state investigation. Its publication constraint (published 0.8.0) was superseded by the 0.8.1 adoption above; its app-test counts are historical. |
| [Inspector common-field visibility](INSPECTOR_FIELD_VISIBILITY_2026-11-16.md) | 2026-11-16 · branch `codex/restore-inspector-field-design` · tested implementation `86e156fb` | Curated Inspector common-field visibility, 17-field defaults, optional independent date/grouping rows, persisted-choice preservation and hidden-draft single/batch save journeys; 13/62/586 gate | Behavior evidence for the current Inspector contract. The 586-test inventory is historical; Release checks completed before a skip instruction, and no interactive UI acceptance is claimed. |
| [Metadata Field Guide verification](METADATA_FIELD_GUIDE_2026-11-17.md) | 2026-11-17 · branch `codex/review-inspector-date-field` · implementation `593bf2c` with later naming/layout follow-ups | Native Help → Metadata Field Guide content, official-source explanations, shared field naming across guide/editor/Settings/Inspector, storage/layout changes and purpose-only suggestions; full gates 13/62/599 then 13/62/602 | Feature evidence for the current guide and shared naming behavior. Counts are historical; several follow-ups were focused-test or build-only, and no interactive visual/accessibility acceptance is claimed. |
| [Error and HUD review repairs](ERROR_HUD_REVIEW_REPAIRS_2026-11-17.md) | 2026-11-17 · no branch or commit baseline recorded | Review dispositions and implementation changes for HUD content/omission, cancellation accounting, operation-specific wording and track/disc component validation | Implementation evidence only: verification was syntax-only, the added app-hosted tests were not executed, and no build or app-hosted acceptance is claimed. |

## Archive

Superseded release, mapping, performance, audit and progress records now live in the [HISTORY archive](HISTORY/README.md). They are retained for traceability only; their claims, counts, paths and relative links may be stale, and broken links inside the archive are not current documentation defects. The campaign plan and agent hand-off prompt for the 2026-11-18 cleanup were removed from the repository after completion; the acceptance and ledger records above preserve their results.

The machine-readable data table for the archived write-concurrency record moved with it: [WRITE_CONCURRENCY_2026-11-12.json](HISTORY/WRITE_CONCURRENCY_2026-11-12.json).

## Using these records

- Treat each record as evidence for its stated date, baseline and environment only; re-run the relevant tests or inspect source before relying on a number.
- Current behavior is owned by [Docs/Product](../Product/), [Docs/Architecture](../Architecture/), [Docs/Development](../Development/), [Docs/Reference](../Reference/) and [Docs/Security](../Security/).
- Do not add current guidance here, do not rewrite dated results, and do not copy a dated claim into current documentation without re-verifying it.
