# AudioMator Documentation

This directory is the authoritative documentation set for AudioMator. It is written and reviewed against the current source, Xcode project, Swift package manifest, scripts, and tests — not against earlier documentation.

## Start Here

| You want to… | Read |
| --- | --- |
| Understand what AudioMator does and what it does not do | [Product Overview](Product/OVERVIEW.md) |
| Use the app | [User Guide](Product/USER_GUIDE.md), [FAQ](Product/FAQ.md), [Troubleshooting](Product/TROUBLESHOOTING.md) |
| Build and run the project | [Build](Development/BUILD.md) |
| Run tests and judge coverage | [Testing](Development/TESTING.md) |
| Understand the architecture | [Architecture Overview](Architecture/OVERVIEW.md) |
| Work on metadata reading/writing | [Metadata Pipeline](Architecture/METADATA_PIPELINE.md) |
| Work on conflicts, reloads, or file revisions | [File Revision and Reload](Architecture/FILE_REVISION_AND_RELOAD.md) |
| Work on filename/text/CSV workflows | [Metadata Exchange](Architecture/METADATA_EXCHANGE.md), [Rename and Renumbering](Architecture/RENAME_AND_RENUMBERING.md) |
| Work on online providers | [Online Metadata](Architecture/ONLINE_METADATA.md) |
| Review privacy or data-integrity risk | [Security and Data Integrity](Security/SECURITY_AND_DATA_INTEGRITY.md) |
| Prepare a release | [Release Engineering](Development/RELEASE.md) |
| Contribute code | [Contributing](../CONTRIBUTING.md), [Documentation Maintenance](Development/DOCUMENTATION.md) |
| Work as an AI coding agent | [AGENTS.md](../AGENTS.md) |

## Documentation Map

### Product

- [Product Overview](Product/OVERVIEW.md) — purpose, scope, features, platforms, distribution, dependencies, limitations.
- [User Guide](Product/USER_GUIDE.md) — current workflows and settings.
- [FAQ](Product/FAQ.md) — common product and behavior questions.
- [Troubleshooting](Product/TROUBLESHOOTING.md) — user-visible failure modes and diagnostic steps.

### Architecture

- [Architecture Overview](Architecture/OVERVIEW.md) — layers, composition, runtime flows, concurrency, error propagation, extension points.
- [State and Mutation Model](Architecture/STATE_AND_MUTATION_MODEL.md) — state categories, file identity, mutation lifecycle, recovery semantics.
- [Metadata Pipeline](Architecture/METADATA_PIPELINE.md) — loading, editing, write preflight, conflict resolution, persistence, artwork, format behavior.
- [File Revision and Reload](Architecture/FILE_REVISION_AND_RELOAD.md) — revision guards, conflict policies, reload paths, detection limits.
- [Metadata Exchange](Architecture/METADATA_EXCHANGE.md) — filename, text, CSV, field-transfer planning and write behavior.
- [Rename and Renumbering](Architecture/RENAME_AND_RENUMBERING.md) — rename templates, two-phase transactions, track renumbering.
- [Online Metadata](Architecture/ONLINE_METADATA.md) — MusicBrainz, iTunes, LRCLIB, release notes, update checks, network constraints.
- [Dependency Rules](Architecture/DEPENDENCY_RULES.md) — allowed dependency direction and enforced boundaries.
- [Architecture Decision Records](Architecture/Decisions/README.md) — accepted decisions and the process for new ones.

### Development

- [Build](Development/BUILD.md) — toolchain, configurations, commands, common build failures.
- [Testing](Development/TESTING.md) — targets, suites, Fixtures, coverage gaps, manual verification boundaries.
- [Debugging](Development/DEBUGGING.md) — build logs, bridge smoke tool, performance probes, diagnostics.
- [Release Engineering](Development/RELEASE.md) — versioning, current release process, what is and is not automated.
- [Documentation Maintenance](Development/DOCUMENTATION.md) — ownership, update matrix, style, and verification rules.

### Reference

- [Project Structure](Reference/PROJECT_STRUCTURE.md) — repository layout and module inventory.
- [Configuration](Reference/CONFIGURATION.md) — build settings, bundle identifiers, entitlements, preference keys, persisted data.
- [Terminology](Reference/TERMINOLOGY.md) — project-specific terms used across the docs and source.
- [Dependency Limitations](Reference/DEPENDENCY_LIMITATIONS.md) — known TagLibAudioMetadata behavior that constrains AudioMator.

### Security and Operations

- [Security and Data Integrity](Security/SECURITY_AND_DATA_INTEGRITY.md) — sandboxing, file access, local data, network disclosure, failure modes, and vulnerability reporting.
- [Third-Party Notices](THIRD_PARTY_NOTICES.md) and [Acknowledgements and Privacy](ACKNOWLEDGEMENTS_AND_PRIVACY.md).

### Engineering Records

- [Engineering Notes](Engineering/README.md) — performance measurements and historical engineering records. These are evidence, not current contracts.
- [History](Engineering/HISTORY/README.md) — dated progress logs and audits.

## Documentation Conventions

Every document states current behavior unless it is explicitly marked otherwise.

- **Current-state documents** describe what the code does today and should be updated with the code.
- **Engineering records** preserve dated measurements, investigations, and decisions. They may describe superseded behavior and are never the authority for current behavior.
- **Proposals and known gaps** are labeled as such. They are not features.
- Behavior that could not be verified is described as unverified or omitted.

When a document and the implementation disagree, investigate first, then change the document. Do not change functional code merely to match stale documentation.

## Maintaining This Documentation

See [Documentation Maintenance](Development/DOCUMENTATION.md) for the update matrix. In short: a change to user-visible behavior, build configuration, dependencies, privacy, testing, or release process must update the corresponding document in the same pull request.

Historical documents remain under `Engineering/HISTORY/` and are not linked as current guidance.
