# AudioMator Documentation

This directory is the authoritative documentation set for AudioMator. It is written and verified against the current source code, Xcode project, Swift package manifest, scripts, and tests — not against earlier documentation. The implementation is the source of truth; documentation that disagrees with it is a defect in the documentation.

## Start Here

| You want to… | Read |
| --- | --- |
| Understand what AudioMator does and does not do | [Product Overview](Product/OVERVIEW.md) |
| Use the app | [User Guide](Product/USER_GUIDE.md), [FAQ](Product/FAQ.md), [Troubleshooting](Product/TROUBLESHOOTING.md) |
| Understand a metadata field | [Metadata Field Guide](Product/METADATA_FIELD_GUIDE.md) |
| Build and run the project | [Build](Development/BUILD.md) |
| Run tests and judge coverage | [Testing](Development/TESTING.md), [Metadata test strategy](Development/METADATA_TEST_STRATEGY.md) |
| Understand the architecture | [Architecture Overview](Architecture/OVERVIEW.md) |
| Work on metadata reading/writing | [Metadata Pipeline](Architecture/METADATA_PIPELINE.md) |
| Work on the metadata mapping contract | [Mapping Specification](Architecture/METADATA_MAPPING_SPEC.md) (`AM-TLAM-MAPPING-2.2`, implemented by published package 0.8.1) |
| Look up UI, app, package, and native fields together | [Complete mapping table](Reference/METADATA_FIELD_MAPPING_TABLE.md) |
| Work on conflicts, reloads, or file revisions | [File Revision and Reload](Architecture/FILE_REVISION_AND_RELOAD.md), [State and Mutation Model](Architecture/STATE_AND_MUTATION_MODEL.md) |
| Work on filename/text/CSV workflows | [Metadata Exchange](Architecture/METADATA_EXCHANGE.md), [Rename and Renumbering](Architecture/RENAME_AND_RENUMBERING.md) |
| Work on online providers | [Online Metadata](Architecture/ONLINE_METADATA.md) |
| Review privacy or data-integrity risk | [Security and Data Integrity](Security/SECURITY_AND_DATA_INTEGRITY.md), [Acknowledgements and Privacy](ACKNOWLEDGEMENTS_AND_PRIVACY.md) |
| Review dependency acceptance evidence | [Engineering Notes](Engineering/README.md) — dated evidence, not current behavior |
| Prepare a release | [Release Engineering](Development/RELEASE.md) |
| Contribute code | [Contributing](../CONTRIBUTING.md), [Documentation Maintenance](Development/DOCUMENTATION.md) |
| Write a commit message | [Commit Messages](Development/COMMIT_MESSAGES.md) |
| Work as an AI coding agent | [AGENTS.md](../AGENTS.md) |

## Documentation Map

### Product

- [Product Overview](Product/OVERVIEW.md) — purpose, scope, features, platform, distribution, dependencies, limitations.
- [User Guide](Product/USER_GUIDE.md) — current workflows, menus, settings, and editing behavior.
- [FAQ](Product/FAQ.md) — common product and behavior questions.
- [Troubleshooting](Product/TROUBLESHOOTING.md) — user-visible failure modes and recovery steps.
- [Metadata Field Guide](Product/METADATA_FIELD_GUIDE.md) — the in-app field help content and field semantics.

### Architecture

- [Architecture Overview](Architecture/OVERVIEW.md) — layers, composition, runtime flows, concurrency, error propagation, extension points.
- [State and Mutation Model](Architecture/STATE_AND_MUTATION_MODEL.md) — state categories, file identity, mutation lifecycle, recovery semantics.
- [Metadata Pipeline](Architecture/METADATA_PIPELINE.md) — loading, editing, write preflight, conflict resolution, persistence, artwork, format behavior.
- [Metadata Mapping Specification](Architecture/METADATA_MAPPING_SPEC.md) — shared native-field interoperability contract, per-format target matrix, legacy migration, and conformance gates.
- [File Revision and Reload](Architecture/FILE_REVISION_AND_RELOAD.md) — revision guards, conflict policies, reload paths, detection limits.
- [Metadata Exchange](Architecture/METADATA_EXCHANGE.md) — filename, text, CSV, and field-transfer planning and write behavior.
- [Rename and Renumbering](Architecture/RENAME_AND_RENUMBERING.md) — rename templates, two-phase transactions, track renumbering.
- [Online Metadata](Architecture/ONLINE_METADATA.md) — MusicBrainz, iTunes, LRCLIB, release notes, update checks, network constraints.
- [Dependency Rules](Architecture/DEPENDENCY_RULES.md) — allowed dependency direction and enforced boundaries.
- [Architecture Decision Records](Architecture/Decisions/README.md) — accepted decisions and the process for new ones.

### Development

- [Build](Development/BUILD.md) — toolchain, configurations, commands, common build failures, release validation.
- [Testing](Development/TESTING.md) — targets, suites, fixtures, CI, coverage gaps, manual verification boundaries.
- [Metadata Test Strategy](Development/METADATA_TEST_STRATEGY.md) — independent field manifests, real persistence coverage, explicit gaps and release gates.
- [Debugging](Development/DEBUGGING.md) — build logs, diagnostics, performance probes, maintainer-only helpers.
- [Commit Messages](Development/COMMIT_MESSAGES.md) — typed subject, scope, merge and revert conventions, body rules, and the advisory checker.
- [Release Engineering](Development/RELEASE.md) — versioning, current release process, what is and is not automated.
- [Documentation Maintenance](Development/DOCUMENTATION.md) — document ownership, update matrix, agent requirements, labels, and verification.

### Reference

- [Project Structure](Reference/PROJECT_STRUCTURE.md) — repository layout, module inventory, test and script inventory.
- [Configuration](Reference/CONFIGURATION.md) — build settings, bundle identifiers, entitlements, preference keys, persisted data, CI.
- [Terminology](Reference/TERMINOLOGY.md) — project-specific terms used across the docs and source.
- [Dependency Limitations](Reference/DEPENDENCY_LIMITATIONS.md) — verified `TagLibAudioMetadata` behavior and constraints that shape AudioMator.
- [Metadata Field Mapping Table](Reference/METADATA_FIELD_MAPPING_TABLE.md) — UI labels, AudioMator properties, package identities, and native mappings in one cross-reference.

### Security and Legal

- [Security and Data Integrity](Security/SECURITY_AND_DATA_INTEGRITY.md) — sandboxing, file access, local data, network disclosure, failure modes, vulnerability reporting.
- [Third-Party Notices](THIRD_PARTY_NOTICES.md) — bundled software licenses and service obligations.
- [Acknowledgements and Privacy](ACKNOWLEDGEMENTS_AND_PRIVACY.md) — user-facing privacy, network, and attribution disclosure.

### Engineering Evidence

- [Engineering Notes](Engineering/README.md) — dated measurements, package adoption records, cleanup evidence, and release evidence. These are evidence, not current contracts.
- [Published TagLibAudioMetadata 0.8.1 Debug adoption](Engineering/TAGLIB_081_DEBUG_ADOPTION_2026-11-17.md) — exact published-package Debug adoption evidence.
- [Accumulated-code cleanup acceptance](Engineering/AUDIOMATOR_LEGACY_CLEANUP_ACCEPTANCE_2026-11-18.md) and [cleanup ledger](Engineering/AUDIOMATOR_LEGACY_CLEANUP_LEDGER_2026-11-18.md) — automated gate evidence and whole-application cleanup audit.
- [History](Engineering/HISTORY/README.md) — superseded release, mapping, performance, audit, and maintenance records retained for traceability.

## Documentation Conventions

Every document states current behavior unless it is explicitly labeled otherwise.

- **Current-state documents** describe what the code does today and are updated with the code. They live in `Docs/Product`, `Docs/Architecture`, `Docs/Development`, `Docs/Reference`, and `Docs/Security`.
- **Engineering records** preserve dated measurements, investigations, and release evidence. They may describe superseded behavior and are never the authority for current behavior.
- **Historical records** under `Docs/Engineering/HISTORY/` are retained for traceability only. Do not use them as current guidance.
- **Known limitations, proposals, and unverified behavior** are labeled as such. See [Labels for Uncertainty](Development/DOCUMENTATION.md#labels-for-uncertainty).

When a document and the implementation disagree, investigate first, then correct the document. Do not change functional code merely to match stale documentation.

## Maintaining This Documentation

Documentation is part of every change. See [Documentation Maintenance](Development/DOCUMENTATION.md) for the canonical document map, ownership, update matrix, and requirements. In short:

- identify the documents affected by a change and update them in the same changeset;
- verify claims against the implementation rather than copying existing text;
- remove descriptions invalidated by architecture, API, feature, or behavior changes;
- prefer extending an existing canonical document over adding an overlapping one;
- run `python3 scripts/check-doc-links.py` before completing the change.

Do not add current guidance under `Docs/Engineering` or `Docs/Engineering/HISTORY/`; those folders hold dated evidence.
