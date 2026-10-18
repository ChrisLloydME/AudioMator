# Engineering Notes

This folder contains dated engineering evidence: performance measurements, investigations, and historical records. These documents are **not** current behavior contracts. They may describe superseded code, stale counts, or environment-specific numbers.

## Current Engineering Records

| Document | Date / baseline | Status |
| --- | --- | --- |
| [Reassessment remediation](REASSESSMENT_REMEDIATION_2026-10-18.md) | 2026-10-18, baseline `a60f3064` | Recovery/publication/cancellation repairs; unresolved reproduced audio-identity blocker |
| [Post-repair review](POST_REPAIR_REVIEW_2026-10-17.md) | 2026-10-17, base `78d5f5e3`, repair `02810a2b` | Independent finding matrix, additional fixes, fresh verification, and merge caveats |
| [Documentation Audit](DOCUMENTATION_AUDIT_2026-10-17.md) | 2026-10-17, parent `e9deb6b` | Audit findings, verification, and follow-ups |
| [Performance: Metadata I/O](PERFORMANCE_METADATA_IO.md) | 2026-10-11, revision `845296d` | Measurements and fixes; code may have changed since |
| [Performance: Middle-list selection](PERFORMANCE_MIDDLE_LIST_SELECTION.md) | 2026-10-08, revision `f376ad1` | Measurements and fixes; code may have changed since |

Use these records to understand why a design exists or to reproduce a measurement. Re-run the relevant tests before relying on any number.

Performance tests are documented in [Testing](../Development/TESTING.md#performance-tests). The current source is the authority for behavior.

## Historical Records

[Docs/Engineering/HISTORY](HISTORY/README.md) contains dated progress logs, audits, and superseded coverage maps. They are retained for traceability only.
