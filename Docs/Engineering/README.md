# Engineering Notes

This folder contains dated engineering evidence: performance measurements, investigations, and historical records. These documents are **not** current behavior contracts. They may describe superseded code, stale counts, or environment-specific numbers.

## Current Engineering Records

| Document | Date / baseline | Status |
| --- | --- | --- |
| [Published TagLibAudioMetadata 0.7.2 adoption](TAGLIB_072_ADOPTION_2026-11-11.md) | 2026-11-11, published 0.7.2 | Normal-project lock adopted; absent-Year/present-Date Comment/Lyrics regression blocks release |
| [Native mapping follow-up package acceptance](NATIVE_MAPPING_REPAIRS_2026-11-11.md) | 2026-11-11, local repair branch | Package gates and consumers pass; all 574 app tests pass with override |
| [MP4 Content Group package repair](MP4_CONTENT_GROUP_PACKAGE_REPAIR_2026-11-10.md) | 2026-11-10, local repair source | Complete 574-test app suite passes with package override; maintainer publication pending |
| [Inspector false unsaved-state repair](INSPECTOR_DIRTY_STATE_2026-11-10.md) | 2026-11-10, package 0.7.1 | Reproduced no-op/revert false positives; effective per-target dirty state and save filtering |
| [Preview and editor save acceptance](PREVIEW_SAVE_ACCEPTANCE_2026-11-10.md) | 2026-11-10, package 0.7.1 | Actual checkbox/preview plans through real persistence and editor draft recovery |
| [Test system upgrade](TEST_SYSTEM_UPGRADE_2026-11-10.md) | 2026-11-10, package 0.7.1 | Independent manifests, real workflow persistence, mutation sensitivity and exposed Content Group blocker |
| [Store identifier semantic-type repair](STORE_ID_MAPPING_REPAIR_2026-11-10.md) | 2026-11-10, package 0.7.1 | Dedicated Store ID patch typing and generated AIFF regression evidence |
| [Mapping 0.7.0 outstanding issues / interrupted-agent handoff](AUDIOMATOR_MAPPING_070_HANDOFF.md) | 2026-11-09, working-tree refactor | Six preserved issue IDs; A02/A08/A09 partial; steer received but final handoff interrupted |
| [AudioMator 0.7.0 / mapping 2.2 implementation](AUDIOMATOR_MAPPING_070_IMPLEMENTATION.md) | 2026-11-09, package 0.7.0 / revision `0f89fbe8` | Application adoption ledger, acceptance evidence, package limitations |
| [TagLib 0.6.0 integration](TAGLIB_060_INTEGRATION_2026-10-25.md) | 2026-10-25, baseline `78a66311` | Application migration and regression coverage; FLAC semantic comments remain an upstream merge blocker |
| [Reassessment remediation](REASSESSMENT_REMEDIATION_2026-10-18.md) | 2026-10-18, baseline `a60f3064` | Recovery/publication/cancellation repairs; unresolved reproduced audio-identity blocker |
| [Post-repair review](POST_REPAIR_REVIEW_2026-10-17.md) | 2026-10-17, base `78d5f5e3`, repair `02810a2b` | Independent finding matrix, additional fixes, fresh verification, and merge caveats |
| [Documentation Audit](DOCUMENTATION_AUDIT_2026-10-17.md) | 2026-10-17, parent `e9deb6b` | Audit findings, verification, and follow-ups |
| [Performance: Metadata I/O](PERFORMANCE_METADATA_IO.md) | 2026-10-11, revision `845296d` | Measurements and fixes; code may have changed since |
| [Performance: Middle-list selection](PERFORMANCE_MIDDLE_LIST_SELECTION.md) | 2026-10-08, revision `f376ad1` | Measurements and fixes; code may have changed since |

Use these records to understand why a design exists or to reproduce a measurement. Re-run the relevant tests before relying on any number.

Performance tests are documented in [Testing](../Development/TESTING.md#performance-tests). The current source is the authority for behavior.

## Historical Records

[Docs/Engineering/HISTORY](HISTORY/README.md) contains dated progress logs, audits, and superseded coverage maps. They are retained for traceability only.

- [Independent mapping acceptance — 2026-11-10](AUDIOMATOR_MAPPING_070_ACCEPTANCE_2026-11-10.md): application repairs, corrected private-field evidence, and the remaining FLAC release blocker.

- [Mapping conformance audit — 2026-11-10](MAPPING_CONFORMANCE_2026-11-10.md): current application routes and independent evidence that package 0.7.0 has not completed Mapping conformance.

- [0.7.1 joint Mapping acceptance](MAPPING_071_JOINT_ACCEPTANCE.md): current candidate evidence, repaired historical issues, explicit capability limits and maintainer publication handoff.
