# Historical Engineering Records

Everything in this folder is a dated record. **None of it is current guidance.**
Claims, counts, file paths, commit IDs, CI behavior, and test results may be stale
or describe code that no longer exists.

Use the current documentation instead:

- [Testing](../../Development/TESTING.md)
- [Build](../../Development/BUILD.md)
- [Architecture](../../Architecture/OVERVIEW.md)
- [Metadata Pipeline](../../Architecture/METADATA_PIPELINE.md)
- [Dependency Limitations](../../Reference/DEPENDENCY_LIMITATIONS.md)

## Records

| File | Original location | What it records |
| --- | --- | --- |
| [MAINTENANCE_PROGRESS.md](MAINTENANCE_PROGRESS.md) | Repository root | Multi-pass maintenance log through 2026-09-22 |
| [AUDIOMATOR_ARCHITECTURE_OPTIMIZATION_PROGRESS.md](AUDIOMATOR_ARCHITECTURE_OPTIMIZATION_PROGRESS.md) | `Docs/Engineering` | Architecture optimization batches and commits |
| [AUDIOMATOR_SYSTEM_AUDIT.md](AUDIOMATOR_SYSTEM_AUDIT.md) | `Docs/Engineering` | System audit, issue matrix, selected batches |
| [ONLINE_METADATA_RESPONSIVENESS_PROGRESS.md](ONLINE_METADATA_RESPONSIVENESS_PROGRESS.md) | `Docs/Engineering` | Online metadata responsiveness investigation and batches |
| [RELEASE_READINESS_2026-07-25.md](RELEASE_READINESS_2026-07-25.md) | `Docs/Engineering` | Release-readiness snapshot; no signing/notarization/upload performed |
| [ENGINEERING_HEALTH_STATUS.md](ENGINEERING_HEALTH_STATUS.md) | `Tests` | Historical health snapshot for a baseline/head that is not an ancestor of current `main` |
| [FULL_FUNCTION_COVERAGE_MAP.md](FULL_FUNCTION_COVERAGE_MAP.md) | `Tests` | Coverage map from an earlier pass; counts and attributions may be stale |
| [RELIABILITY_REMEDIATION_EVIDENCE.md](RELIABILITY_REMEDIATION_EVIDENCE.md) | `Tests` | 2026-06 remediation evidence; CI/toolchain claims are stale |
| [FAST_TEST_GAPS.md](FAST_TEST_GAPS.md) | `Tests` | Fast-test scope and gaps at an earlier point; some statements are superseded |
| [METADATA_FIELD_TRANSFER_VERIFICATION_2026-10-11.md](METADATA_FIELD_TRANSFER_VERIFICATION_2026-10-11.md) | `Docs` | Field-transfer dependency observations; current summary is [Dependency Limitations](../../Reference/DEPENDENCY_LIMITATIONS.md) |

## Notes on Validity

- Links inside these records may point to locations that were removed or renamed
  during documentation reorganization. Broken internal links in a historical record
  do not indicate current documentation.
- Some records reference commits or tags that exist as Git objects but share no
  ancestor with the current `main`. Chronological comparison is not possible; only
  the snapshot content can be inspected.
- Test counts and file sizes in these records are stale. Re-count before quoting.
- CI descriptions in older records may name `macos-15`, alternate derived-data
  paths, or a core-only workflow. The current workflow is documented in
  [Testing](../../Development/TESTING.md#ci).
- Do not copy a historical claim into current documentation without re-verifying
  it against source and reproducible commands.

Do not add new current-state documentation to this folder.
