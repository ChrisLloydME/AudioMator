# Engineering Notes

This folder contains dated engineering evidence: package adoption and release acceptance, performance measurements, investigations, and historical records. These documents are **not** current behavior contracts. They may describe superseded code, stale counts, or environment-specific numbers.

The current-state documentation lives in `Docs/Product`, `Docs/Architecture`, `Docs/Development`, `Docs/Reference`, and `Docs/Security`. When a current claim needs evidence, link to the relevant record here and re-verify the claim against source before copying it into current guidance.

## Current Release Evidence

| Document | Date / baseline | Status |
| --- | --- | --- |
| [Published TagLibAudioMetadata 0.7.3 release readiness](TAGLIB_073_RELEASE_READINESS_2026-11-12.md) | 2026-11-12, published 0.7.3, revision `7ca1b75326388a5902815f70145b600299944ae0` | **Current.** Normal-project gate passed: 13 policy tests, 62 core tests, 579 serial app tests, unsigned Release build, artifact checks, and unsigned Archive; interactive UI acceptance and manual distribution remain maintainer work. |

## Application and Package Records

These records document earlier package adoption, candidate validation, and application repairs. Superseded records remain for traceability; their failures are not current capability claims.

| Document | Date / baseline | Status |
| --- | --- | --- |
| [Published TagLibAudioMetadata 0.7.2 adoption](TAGLIB_072_ADOPTION_2026-11-11.md) | 2026-11-11, published 0.7.2 | Superseded by 0.7.3 acceptance; records the absent-Year/present-Date MP4 Comment/Lyrics failure. |
| [Native mapping follow-up package acceptance](NATIVE_MAPPING_REPAIRS_2026-11-11.md) | 2026-11-11, local repair branch | Historical local-candidate evidence; superseded by the published 0.7.3 gate. |
| [Metadata state coverage and complete gate evidence](METADATA_STATE_COVERAGE_2026-11-11.md) | 2026-11-11, published 0.7.2 plus local candidate | Historical candidate evidence for the sparse-state matrices; superseded by the published 0.7.3 gate. |
| [MP4 Content Group package repair](MP4_CONTENT_GROUP_PACKAGE_REPAIR_2026-11-10.md) | 2026-11-10, local repair source based on 0.7.1 | Historical local-candidate evidence; the repair is included in later published releases. |
| [Inspector false unsaved-state repair](INSPECTOR_DIRTY_STATE_2026-11-10.md) | 2026-11-10, package 0.7.1 | Historical application repair evidence; behavior is covered by current tests. |
| [Preview and editor save acceptance](PREVIEW_SAVE_ACCEPTANCE_2026-11-10.md) | 2026-11-10, package 0.7.1 | Historical acceptance evidence for workbench and editor save journeys. |
| [Test system upgrade](TEST_SYSTEM_UPGRADE_2026-11-10.md) | 2026-11-10, package 0.7.1 | Historical test-system design evidence and the then-open Content Group blocker. |
| [Store identifier semantic-type repair](STORE_ID_MAPPING_REPAIR_2026-11-10.md) | 2026-11-10, package 0.7.1 | Historical application adapter repair evidence. |
| [0.7.1 joint Mapping acceptance](MAPPING_071_JOINT_ACCEPTANCE.md) | 2026-11-10, local 0.7.1 candidate | Superseded by the published 0.7.1 dependency and later 0.7.3 acceptance. |
| [Mapping conformance audit — 2026-11-10](MAPPING_CONFORMANCE_2026-11-10.md) | 2026-11-10, package 0.7.0 | Superseded package audit; its blockers describe 0.7.0 behavior. |
| [Independent mapping acceptance — 2026-11-10](AUDIOMATOR_MAPPING_070_ACCEPTANCE_2026-11-10.md) | 2026-11-10, package 0.7.0 | Superseded candidate acceptance; retained as historical evidence. |
| [AudioMator 0.7.0 / mapping 2.2 implementation](AUDIOMATOR_MAPPING_070_IMPLEMENTATION.md) | 2026-11-09, package 0.7.0 / revision `0f89fbe8` | Superseded application adoption ledger; mapping contract 2.2 is implemented by 0.7.3. |
| [Mapping 0.7.0 outstanding issues / interrupted-agent handoff](AUDIOMATOR_MAPPING_070_HANDOFF.md) | 2026-11-09, working-tree refactor | Superseded handoff record; preserved outstanding-issue IDs and evidence confidence. |
| [TagLib 0.6.0 integration](TAGLIB_060_INTEGRATION_2026-10-25.md) | 2026-10-25, baseline `78a66311` | Historical migration record; the FLAC semantic-comment blocker it describes is fixed in later releases. |

## Reliability, Performance, and Audit Records

| Document | Date / baseline | Status |
| --- | --- | --- |
| [Documentation audit — 2026-11-12](DOCUMENTATION_AUDIT_2026-11-12.md) | 2026-11-12, commit `21f5940c` | Current documentation refresh record: current-state corrections, index reorganization, and archive moves. No functional changes. |
| [Reassessment remediation](REASSESSMENT_REMEDIATION_2026-10-18.md) | 2026-10-18, baseline `a60f3064` | Historical recovery/publication/cancellation repairs and reproduced audio-identity findings. |
| [Post-repair review](POST_REPAIR_REVIEW_2026-10-17.md) | 2026-10-17, base `78d5f5e3`, repair `02810a2b` | Historical independent finding matrix, additional fixes, and merge caveats. |
| [Documentation audit — 2026-10-17](DOCUMENTATION_AUDIT_2026-10-17.md) | 2026-10-17, parent `e9deb6b` | Historical documentation audit findings and follow-ups. |
| [Performance: Metadata I/O](PERFORMANCE_METADATA_IO.md) | 2026-10-11, revision `845296d` | Historical measurements and fixes; code has changed since. |
| [Performance: Middle-list selection](PERFORMANCE_MIDDLE_LIST_SELECTION.md) | 2026-10-08, revision `f376ad1` | Historical measurements and fixes; code has changed since. |

Use these records to understand why a design exists or to reproduce a measurement. Re-run the relevant tests before relying on any number.

Performance tests are documented in [Testing](../Development/TESTING.md#performance-tests). The current source is the authority for behavior.

## Historical Archive

[Docs/Engineering/HISTORY](HISTORY/README.md) contains dated progress logs, audits, superseded coverage maps, and retired task prompts. They are retained for traceability only.

- [Metadata mapping 0.7.0 agent prompt](HISTORY/AUDIOMATOR_MAPPING_070_AGENT_PROMPT.md) — retired repository-scoped task prompt for the completed 0.7.0 adoption.

Do not move current guidance into the archive, and do not copy historical claims out of it without re-verifying them.
