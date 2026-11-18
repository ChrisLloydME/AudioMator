# Historical engineering archive

Everything in this folder is a dated record. **None of it is current guidance.** Claims, counts, file paths, dependency versions, commit IDs, CI behavior and test results may be stale or describe code that no longer exists. These records are retained for traceability only.

Use the current documentation instead:

- [Engineering evidence index](../README.md) — the current dated records that are still kept in the parent folder.
- [Documentation index](../../README.md) — Product, Architecture, Development, Reference and Security.
- [Testing](../../Development/TESTING.md), [Build](../../Development/BUILD.md), [Architecture overview](../../Architecture/OVERVIEW.md), [Metadata pipeline](../../Architecture/METADATA_PIPELINE.md), [Dependency limitations](../../Reference/DEPENDENCY_LIMITATIONS.md).

## Standing warnings

- **Never current guidance.** Do not copy a claim, count, command or path from this folder into current documentation without re-verifying it against source and reproducible commands.
- **Stale claims and counts.** Test counts, file sizes, dependencies, dates and commit IDs were true only for the stated snapshot; re-count and re-run before quoting.
- **Stale links and paths.** Many records were written while living in another folder. Targets may have been moved, renamed or deleted (including retired campaign plans and hand-off prompts), so some relative links may no longer resolve. Broken links inside an archive record are known and are not current documentation defects; do not rewrite dated results just to make a link resolve.
- **Snapshot-only commits.** Some records reference commits or tags that exist as Git objects but share no ancestor with the current `main`; only the snapshot content can be inspected.
- Do not add new current-state documentation to this folder.

## Records

All 36 records currently in this folder are listed below. The 26 newest were moved here from the `Docs/Engineering/` root during the 2026-11-18 documentation overhaul; the 10 older records were already archived here (originally from the repository root, `Tests/`, `Docs/` or `Docs/Engineering/`).

### Package adoption and release readiness

| Date | Record | What it records |
| --- | --- | --- |
| 2026-10-25 | [TAGLIB_060_INTEGRATION_2026-10-25.md](TAGLIB_060_INTEGRATION_2026-10-25.md) | Migration to TagLibAudioMetadata 0.6.0 from baseline `78a66311`; the FLAC semantic-comment blocker it describes was fixed in later releases. |
| 2026-11-11 | [TAGLIB_072_ADOPTION_2026-11-11.md](TAGLIB_072_ADOPTION_2026-11-11.md) | Published 0.7.2 adoption; the absent-Year/present-Date MP4 Comment/Lyrics failure remains a required regression on later releases. |
| 2026-11-12 | [TAGLIB_073_RELEASE_READINESS_2026-11-12.md](TAGLIB_073_RELEASE_READINESS_2026-11-12.md) | Published 0.7.3 release-candidate acceptance: 13 policy, 62 core and 579 serial app tests, unsigned Release build and Archive; superseded for later pins. |
| 2026-11-16 | [TAGLIB_080_RELEASE_READINESS_2026-11-16.md](TAGLIB_080_RELEASE_READINESS_2026-11-16.md) | Published 0.8.0 acceptance: 580 serial app tests, unsigned Release build and Archive; superseded by the 0.8.1 Debug adoption. |

### Mapping contract adoption and conformance

| Date | Record | What it records |
| --- | --- | --- |
| 2026-11-09 | [AUDIOMATOR_MAPPING_070_IMPLEMENTATION.md](AUDIOMATOR_MAPPING_070_IMPLEMENTATION.md) | AudioMator 0.7.0 / mapping contract 2.2 implementation ledger on `codex/metadata-mapping-spec`; superseded application adoption record. |
| 2026-11-09 | [AUDIOMATOR_MAPPING_070_HANDOFF.md](AUDIOMATOR_MAPPING_070_HANDOFF.md) | Interrupted-agent hand-off for the uncommitted 0.7.0 mapping adoption; preserves outstanding-issue IDs and evidence confidence. |
| 2026-11-10 | [AUDIOMATOR_MAPPING_070_ACCEPTANCE_2026-11-10.md](AUDIOMATOR_MAPPING_070_ACCEPTANCE_2026-11-10.md) | Independent 0.7.0 mapping acceptance marked not ready to release; superseded by the published 0.7.3 acceptance. |
| 2026-11-10 | [MAPPING_CONFORMANCE_2026-11-10.md](MAPPING_CONFORMANCE_2026-11-10.md) | Application mapping refactor and released-0.7.0 conformance audit; its blockers describe superseded 0.7.0 behavior. |
| 2026-11-10 | [MAPPING_071_JOINT_ACCEPTANCE.md](MAPPING_071_JOINT_ACCEPTANCE.md) | Local 0.7.1 candidate joint mapping acceptance; superseded by the published dependency and later acceptance. |
| 2026-11-10 | [MP4_CONTENT_GROUP_PACKAGE_REPAIR_2026-11-10.md](MP4_CONTENT_GROUP_PACKAGE_REPAIR_2026-11-10.md) | Local package repair acceptance for MP4 Content Group based on 0.7.1; the repair is included in later published releases. |
| 2026-11-11 | [NATIVE_MAPPING_REPAIRS_2026-11-11.md](NATIVE_MAPPING_REPAIRS_2026-11-11.md) | Native mapping follow-up package acceptance on a local candidate; superseded by published 0.7.3 evidence. |
| 2026-11-11 | [METADATA_STATE_COVERAGE_2026-11-11.md](METADATA_STATE_COVERAGE_2026-11-11.md) | Local-candidate sparse-state matrix evidence; the matrices remain required tests on later published dependencies. |

### Application feature, test-system and repair evidence

| Date | Record | What it records |
| --- | --- | --- |
| 2026-10-11 | [METADATA_FIELD_TRANSFER_VERIFICATION_2026-10-11.md](METADATA_FIELD_TRANSFER_VERIFICATION_2026-10-11.md) | Field-transfer planner/save/reload verification across committed fixtures and known dependency rejections (130 related tests at that date). |
| 2026-11-10 | [TEST_SYSTEM_UPGRADE_2026-11-10.md](TEST_SYSTEM_UPGRADE_2026-11-10.md) | Unified local/CI validation script and test-system redesign evidence, plus the then-open Content Group blocker. |
| 2026-11-10 | [PREVIEW_SAVE_ACCEPTANCE_2026-11-10.md](PREVIEW_SAVE_ACCEPTANCE_2026-11-10.md) | Provider preview/checkbox selection plus Inspector and Metadata Editor save acceptance on published 0.7.1. |
| 2026-11-10 | [INSPECTOR_DIRTY_STATE_2026-11-10.md](INSPECTOR_DIRTY_STATE_2026-11-10.md) | Inspector false unsaved-state repair evidence on published 0.7.1, including real save and reload checks. |
| 2026-11-10 | [STORE_ID_MAPPING_REPAIR_2026-11-10.md](STORE_ID_MAPPING_REPAIR_2026-11-10.md) | Adapter repair for iTunes store-ID integer semantic types rejected as text on 0.7.1. |

### Local package candidate validation

| Date | Record | What it records |
| --- | --- | --- |
| 2026-11-12 | [TAGLIB_API_PERFORMANCE_CANDIDATE_2026-11-12.md](TAGLIB_API_PERFORMANCE_CANDIDATE_2026-11-12.md) | Unreleased package API/performance candidate migration and local-candidate verification based on 0.7.3. |
| 2026-11-14 | [TAGLIB_DIAGNOSTIC_CANDIDATE_2026-11-14.md](TAGLIB_DIAGNOSTIC_CANDIDATE_2026-11-14.md) | Diagnostic-native-owner-repairs candidate evaluation: literal YEAR/TDAT date contract with the published pin still at 0.7.3. |
| 2026-11-14 | [TAGLIB_REVIEW_REPAIR_2026-11-14.md](TAGLIB_REVIEW_REPAIR_2026-11-14.md) | Local-candidate acceptance after advisory-review repairs for final-state erase verification and unknown advisory-code preservation. |

### Performance investigations

| Date | Record | What it records |
| --- | --- | --- |
| 2026-10-08 | [PERFORMANCE_MIDDLE_LIST_SELECTION.md](PERFORMANCE_MIDDLE_LIST_SELECTION.md) | Middle-list selection instrumentation, diagnosis and fixes at revision `f376ad1`. |
| 2026-10-11 | [PERFORMANCE_METADATA_IO.md](PERFORMANCE_METADATA_IO.md) | Metadata and main-list performance investigation at revision `845296d`, including batch-save/selection follow-ups. |
| 2026-11-12 | [WRITE_CONCURRENCY_2026-11-12.md](WRITE_CONCURRENCY_2026-11-12.md) | Bounded guarded-write measurements at 1/2/4/8 workers across six formats; the machine-readable data table remains at [WRITE_CONCURRENCY_2026-11-12.json](WRITE_CONCURRENCY_2026-11-12.json) in the archive. |

### Audits, reviews and remediation

| Date | Record | What it records |
| --- | --- | --- |
| 2026-06-21 | [RELIABILITY_REMEDIATION_EVIDENCE.md](RELIABILITY_REMEDIATION_EVIDENCE.md) | Reliability remediation evidence for the 2026-06-21 pass; CI scope, platform findings and paths are stale. |
| 2026-07-25 | [AUDIOMATOR_SYSTEM_AUDIT.md](AUDIOMATOR_SYSTEM_AUDIT.md) | System audit, issue matrix and selected maintenance batches (Chinese); source counts and platform model are stale. |
| 2026-10-17 | [DOCUMENTATION_AUDIT_2026-10-17.md](DOCUMENTATION_AUDIT_2026-10-17.md) | Documentation audit findings and follow-ups at parent `e9deb6b`. |
| 2026-10-17 | [POST_REPAIR_REVIEW_2026-10-17.md](POST_REPAIR_REVIEW_2026-10-17.md) | Independent post-repair review: finding matrix, additional fixes and merge caveats at base `78d5f5e3` / repair `02810a2b`. |
| 2026-10-18 | [REASSESSMENT_REMEDIATION_2026-10-18.md](REASSESSMENT_REMEDIATION_2026-10-18.md) | Independent reassessment and remediation at `a60f3064`, including recovery/publication/cancellation repairs and audio-identity findings. |
| 2026-11-12 | [DOCUMENTATION_AUDIT_2026-11-12.md](DOCUMENTATION_AUDIT_2026-11-12.md) | Documentation refresh at `21f5940c`: current-state corrections, index reorganization and archive moves. |

### Historical progress logs, coverage and release snapshots

| Date | Record | What it records |
| --- | --- | --- |
| Undated (earlier pass) | [ENGINEERING_HEALTH_STATUS.md](ENGINEERING_HEALTH_STATUS.md) | Engineering-health snapshot for baseline `V2.4.1B26516` (`67ce047`) and audited head `668c6aa`, which share no ancestor with current `main`. |
| Undated (earlier pass) | [FULL_FUNCTION_COVERAGE_MAP.md](FULL_FUNCTION_COVERAGE_MAP.md) | Earlier automated coverage map for main app behavior areas; counts and attributions are stale. |
| Undated (earlier pass) | [FAST_TEST_GAPS.md](FAST_TEST_GAPS.md) | Fast SwiftPM test scope and gaps at an earlier point; several statements are explicitly superseded. |
| 2026-07-25 | [AUDIOMATOR_ARCHITECTURE_OPTIMIZATION_PROGRESS.md](AUDIOMATOR_ARCHITECTURE_OPTIMIZATION_PROGRESS.md) | Architecture optimization batches and commits (Chinese); platform and architecture statements describe the period, not the macOS-only app. |
| 2026-07-25 | [RELEASE_READINESS_2026-07-25.md](RELEASE_READINESS_2026-07-25.md) | Release-readiness snapshot; no signing, notarization or upload was performed. |
| 2026-07-25/26 | [ONLINE_METADATA_RESPONSIVENESS_PROGRESS.md](ONLINE_METADATA_RESPONSIVENESS_PROGRESS.md) | Online metadata responsiveness investigation and batches; runtime measurements, test counts and iPadOS references are period evidence. |
| Through 2026-09-22 | [MAINTENANCE_PROGRESS.md](MAINTENANCE_PROGRESS.md) | Multi-pass metadata architecture maintenance log, last updated 2026-09-22. |
