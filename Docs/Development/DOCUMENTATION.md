# Documentation Maintenance

This document defines the ownership, scope, and maintenance rules for AudioMator's documentation. It applies to maintainers, contributors, and AI coding agents.

## Authority and Source of Truth

1. **The implementation is the source of truth.** Documentation is verified against source code, build settings, schemes, scripts, tests, and reproducible commands. Never change functional code merely to satisfy old documentation; investigate, then correct the document.
2. **Current-state documents describe today.** A statement in a current-state document is an implemented-behavior claim unless it is explicitly labeled as a limitation, proposal, or unverified item.
3. **Dated records are evidence, not contracts.** `Docs/Engineering/` and `Docs/Engineering/HISTORY/` preserve old measurements and investigations. Their claims, counts, paths, and commands may be stale.
4. **One fact, one home.** Link to the canonical document instead of copying its content. When two documents disagree, decide which one owns the fact, fix both, and remove the duplicate.
5. **Documentation is part of the change.** A behavior, build, test, privacy, dependency, or release change is incomplete until the affected documentation is updated in the same changeset.

## Document Classes

| Class | Location | Authority | Maintenance |
| --- | --- | --- | --- |
| Current guidance | `README.md`, `Docs/Product`, `Docs/Architecture`, `Docs/Development`, `Docs/Reference`, `Docs/Security` | Authoritative for current behavior | Update with code in the same change |
| Repository policy | `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE` | Authoritative for process and contribution rules | Update when process changes |
| Documentation system | `Docs/README.md`, this document | Authoritative for documentation structure and maintenance | Update when the documentation set changes |
| Legal and notices | `Docs/THIRD_PARTY_NOTICES.md`, `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md` | Authoritative for disclosures | Update with dependency, license, or network changes |
| Dated evidence | `Docs/Engineering/*.md` | Dated record of a measurement, acceptance, or repair | Add new records; do not rewrite results |
| Superseded archive | `Docs/Engineering/HISTORY/` | Traceability only; never current guidance | Preserve; do not add current guidance |

## Canonical Documents and Ownership

Every current-state document has one owner role and one scope. Do not create a second document covering the same scope.

| Document | Scope it owns | Update when |
| --- | --- | --- |
| [README.md](../../README.md) | Product pitch, headline features, requirements, quick-start build commands, dependency and license summary, documentation entry point | Headline features, requirements, build commands, dependencies, or distribution approach change |
| [Docs/README.md](../README.md) | Documentation index, document classes, navigation | Any document is added, moved, renamed, or removed |
| [Product Overview](../Product/OVERVIEW.md) | Purpose, scope, feature set, platform, distribution, high-level dependencies and limitations | Product scope or headline behavior changes |
| [User Guide](../Product/USER_GUIDE.md) | Current user workflows, menus, settings, and field editing behavior | User-visible behavior or workflow changes |
| [FAQ](../Product/FAQ.md) | Recurring product and behavior questions that the other documents do not own | A recurring user question appears or an answer changes |
| [Troubleshooting](../Product/TROUBLESHOOTING.md) | User-visible failure modes and recovery steps | Error presentation, recovery guidance, or diagnostics change |
| [Metadata Field Guide](../Product/METADATA_FIELD_GUIDE.md) | In-app field help: field meaning, accepted values, storage behavior | Field help content or field semantics change |
| [Architecture Overview](../Architecture/OVERVIEW.md) | Layers, composition, runtime flows, concurrency model, error propagation, extension points | Architecture boundary or composition changes |
| [Metadata Pipeline](../Architecture/METADATA_PIPELINE.md) | Metadata load, edit, write preflight, verification, conflict handling, artwork, per-format behavior | Metadata semantics or pipeline behavior changes |
| [Metadata Mapping Specification](../Architecture/METADATA_MAPPING_SPEC.md) | Shared native-field interoperability contract and per-format mapping matrix | The mapping contract, package integration, or accepted native mappings change |
| [State and Mutation Model](../Architecture/STATE_AND_MUTATION_MODEL.md) | State categories, file identity, mutation lifecycle, recovery semantics | State ownership or mutation lifecycle changes |
| [File Revision and Reload](../Architecture/FILE_REVISION_AND_RELOAD.md) | Revision guards, conflict policies, reload paths, detection limits | Conflict, revision, or reload behavior changes |
| [Metadata Exchange](../Architecture/METADATA_EXCHANGE.md) | Filename, text, CSV, field-transfer planning and write behavior | Exchange modes, templates, profiles, or limits change |
| [Rename and Renumbering](../Architecture/RENAME_AND_RENUMBERING.md) | Rename templates and transactions, track renumbering | Rename or renumber rules change |
| [Online Metadata](../Architecture/ONLINE_METADATA.md) | MusicBrainz, iTunes, LRCLIB, release notes, update checks, network constraints | A provider, endpoint, request payload, or constraint changes |
| [Dependency Rules](../Architecture/DEPENDENCY_RULES.md) | Allowed module dependency direction and enforced boundaries | A layer boundary or exception changes |
| [Architecture Decisions](../Architecture/Decisions/README.md) | Accepted decisions and the ADR process | A decision is made, amended, or superseded |
| [Build](../Development/BUILD.md) | Toolchain, configurations, build commands, derived-data rules, common build failures | Build settings, commands, or toolchain policy change |
| [Testing](../Development/TESTING.md) | Test targets, suites, fixtures, commands, CI, known coverage gaps, manual-only verification | Tests, fixtures, CI, or coverage status change |
| [Metadata Test Strategy](../Development/METADATA_TEST_STRATEGY.md) | Required metadata coverage, independent field manifests, release gates | Required coverage or acceptance gates change |
| [Debugging](../Development/DEBUGGING.md) | Build logs, diagnostics, performance probes, maintainer-only tools | Diagnostic tooling or log locations change |
| [Release Engineering](../Development/RELEASE.md) | Versioning, signing, notarization, distribution, dependency updates | Release process or artifact handling changes |
| [Commit Messages](../Development/COMMIT_MESSAGES.md) | Commit subject/body conventions, merge and revert rules, advisory checker | Commit convention or checker changes |
| [Documentation Maintenance](DOCUMENTATION.md) | This document: document map, ownership, update matrix, requirements, verification | A document is added, moved, removed, or the process changes |
| [Project Structure](../Reference/PROJECT_STRUCTURE.md) | Repository layout, module inventory, test/script inventory | Files, folders, targets, or scripts are added, moved, or removed |
| [Configuration](../Reference/CONFIGURATION.md) | Build settings, bundle identifiers, entitlements, preference keys, persisted data, CI | Configuration or persistence changes |
| [Terminology](../Reference/TERMINOLOGY.md) | Project-specific terms used by docs and source | A term is introduced or its meaning changes |
| [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md) | Verified dependency behavior and constraints that shape AudioMator | Dependency behavior, version, or verified constraint changes |
| [Metadata Field Mapping Table](../Reference/METADATA_FIELD_MAPPING_TABLE.md) | One-table cross-reference of UI labels, AudioMator properties, package identities, and native mappings | Fields, labels, or mappings change |
| [Security and Data Integrity](../Security/SECURITY_AND_DATA_INTEGRITY.md) | Sandbox, file access, local data, network disclosure, failure modes, vulnerability reporting | Security, sandbox, persistence, or network behavior changes |
| [Third-Party Notices](../THIRD_PARTY_NOTICES.md) | Bundled software licenses and service obligations | A dependency, license, or bundled resource changes |
| [Acknowledgements and Privacy](../ACKNOWLEDGEMENTS_AND_PRIVACY.md) | User-facing privacy, network, and attribution disclosure | Network behavior, data handling, or attribution changes |
| [Engineering Notes](../Engineering/README.md) | Index of current dated evidence | An evidence record is added or archived |
| [Historical Records](../Engineering/HISTORY/README.md) | Index of superseded dated records | A record is archived |

`AGENTS.md` and `CONTRIBUTING.md` summarize process rules and must stay consistent with this document; this document owns the detailed documentation requirements.

## Update Matrix

| Change | Update |
| --- | --- |
| User-visible behavior, workflow, settings, menus | `README.md` if headline-worthy; `Docs/Product/USER_GUIDE.md`; `FAQ.md` and `Troubleshooting.md` when relevant |
| Metadata read/write behavior, conflicts, formats | `Docs/Architecture/METADATA_PIPELINE.md`, `FILE_REVISION_AND_RELOAD.md`, `Docs/Reference/DEPENDENCY_LIMITATIONS.md`, `Docs/Reference/METADATA_FIELD_MAPPING_TABLE.md` |
| Metadata field meaning, labels, or help text | `Docs/Product/METADATA_FIELD_GUIDE.md`, `Docs/Reference/METADATA_FIELD_MAPPING_TABLE.md`, `Docs/Reference/TERMINOLOGY.md` |
| Mapping contract or package integration | `Docs/Architecture/METADATA_MAPPING_SPEC.md`, `Docs/Reference/METADATA_FIELD_MAPPING_TABLE.md`, `Docs/Reference/DEPENDENCY_LIMITATIONS.md`, new evidence record, `Docs/Engineering/README.md` |
| Rename, conversion, renumber | `Docs/Architecture/METADATA_EXCHANGE.md`, `RENAME_AND_RENUMBERING.md`, `USER_GUIDE.md` |
| Network provider, endpoint, payload, timeout | `Docs/Architecture/ONLINE_METADATA.md`, `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md`, `NetworkServiceDisclosure.swift`, in-app privacy text |
| Entitlement, sandbox, file access, local persistence | `Docs/Security/SECURITY_AND_DATA_INTEGRITY.md`, `Docs/Reference/CONFIGURATION.md` |
| Build setting, toolchain, package version | `Docs/Development/BUILD.md`, `Docs/Reference/CONFIGURATION.md`, `Docs/THIRD_PARTY_NOTICES.md`, `README.md` requirements |
| Test target, suite, fixture, CI, coverage | `Docs/Development/TESTING.md`, `Docs/Development/METADATA_TEST_STRATEGY.md` |
| Release process, signing, versioning, distribution | `Docs/Development/RELEASE.md`, `README.md` distribution section |
| Architecture boundary or decision | `Docs/Architecture/OVERVIEW.md`, `DEPENDENCY_RULES.md`, and a new ADR |
| Repository layout, target, or script inventory | `Docs/Reference/PROJECT_STRUCTURE.md`, `README.md`, `AGENTS.md` |
| Contribution, review, or agent process | `AGENTS.md`, `CONTRIBUTING.md`, this document |
| Commit message convention | `Docs/Development/COMMIT_MESSAGES.md`, `AGENTS.md`, `CONTRIBUTING.md` |
| License, attribution, bundled license text | `Docs/THIRD_PARTY_NOTICES.md`, `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md`, `AudioMator/Core/Legal/LicenseDisclosure.swift`, `AudioMator/Resources/Licenses`, in-app Acknowledgements |
| Documentation structure or ownership | `Docs/README.md`, this document |

If a change affects a fact owned by a document that is not listed, add the row here and update the document in the same changeset.

## Requirements for Agents and Contributors

These requirements apply throughout implementation, refactoring, bug fixing, and feature development. They are not deferred to a separate documentation cleanup task.

1. **Identify affected documentation before changing code.** Read this document's canonical ownership table and update matrix; inspect every document that owns the behavior you are touching, including documents that link to it.
2. **Update documentation within the same changeset.** Include documentation edits with the implementation so the repository is never left in a known-inconsistent state.
3. **Remove or revise invalidated descriptions.** Architectural changes, API changes, feature changes, and behavioral changes invalidate old text. Delete superseded descriptions, abandoned plans, and obsolete workflow references instead of layering new text on top.
4. **Verify every documentation claim against the implementation.** Use source inspection, build settings, public interfaces, scripts, and reproducible commands. Do not copy a claim from an existing document, a comment, a test name, or a commit message without checking it.
5. **Label uncertainty.** Distinguish implemented behavior from proposals, assumptions, and unverified behavior. Use the labels below.
6. **Prefer maintaining existing canonical documents.** Extend or correct the canonical document rather than creating a new overlapping one. A new document requires a scope that no existing document owns and registration in `Docs/README.md` and the ownership table above.
7. **Include documentation consistency in final verification.** Before reporting completion, run the verification steps below and include the documentation result in the report. A docs pass is not optional cleanup.

## Labels for Uncertainty

Use explicit labels when a statement is not an implemented-behavior claim:

- **Implemented** — verified against the current source and reproducible commands. This is the default for current-state documents and normally needs no label.
- **Known limitation** — a real constraint of the current implementation. Name the affected format, provider, or workflow.
- **Proposal** — a design idea that is not implemented. Never describe it in the present tense as available behavior.
- **Unverified** — plausible but not checked against the implementation or environment.
- **Dated evidence** — historical record under `Docs/Engineering/`. Not current guidance.

## Adding, Consolidating, and Removing Documents

- Add a document only when a current-state topic has no owner. Register it in `Docs/README.md` and this document's ownership table, and state its scope.
- Consolidate overlapping documents into the canonical owner; delete the redundant file and update inbound links.
- Remove documents that no longer serve a meaningful purpose: completed campaign plans and agent handoff prompts, superseded implementation descriptions, abandoned proposals, and obsolete workflow guides.
- Preserve meaningful dated evidence by archiving it under `Docs/Engineering/HISTORY/` and indexing it in that folder's README. Do not archive mere duplication.
- Never leave a stub document behind after a move or merge. Update every link, including `Docs/README.md`, `AGENTS.md`, `CONTRIBUTING.md`, and `README.md`.
- Do not rewrite the results of a dated record. Add a "Dated evidence" banner or a successor link instead.

## Engineering Records and History

- `Docs/Engineering/` holds only records that still support current release, dependency, or behavior evidence. Each record states its date and baseline.
- Superseded records move to `Docs/Engineering/HISTORY/`. The archive index there lists them and warns that their claims, paths, commands, and links may be stale.
- Do not add current guidance to the archive, and do not copy a record's claim into current documentation without re-verifying it against the implementation.
- Current facts belong in current-state documents; link the evidence record as support rather than duplicating its narrative.

## Verification

Before completing a documentation change:

1. Re-read the implementation for every factual claim you wrote or kept.
2. Run `python3 scripts/check-doc-links.py` and fix every reported problem. Use `--all` when you changed the archive or its index; stale archive links are tolerated only inside historical records.
3. Check cross-references, anchors, terminology, file paths, type names, setting names, and command examples against the current repository.
4. Confirm that implemented behavior, known limitations, and proposals are clearly separated.
5. Confirm that no document duplicates a fact owned elsewhere and that `Docs/README.md` still describes the actual structure.
6. Confirm that dated records are labeled as evidence and are not presented as current guidance.
7. Run documented commands where practical, or mark them unverified. Never claim a command was run when it was not.
8. Confirm the documentation changed in the same changeset as the implementation.

## Review Checklist for Documentation Pull Requests

- [ ] Every changed fact is supported by code, configuration, script, or reproducible-command evidence.
- [ ] Current behavior, known limitations, proposals, and unverified items are clearly separated.
- [ ] Links and anchors resolve; `python3 scripts/check-doc-links.py` passes.
- [ ] No duplicate source of truth was introduced; canonical documents were extended instead.
- [ ] Obsolete, superseded, and abandoned-plan material was removed rather than retained.
- [ ] `Docs/README.md` and the ownership table match the actual document set.
- [ ] Historical records are labeled and not used as current guidance.
- [ ] Commands were run or explicitly marked unverified.
- [ ] Privacy and third-party disclosures match current network and dependency behavior.
- [ ] Bundled license resources and in-app Acknowledgements entries match the legal documents.
- [ ] `AGENTS.md` and `CONTRIBUTING.md` remain concise and consistent with this document.

## ADR Process

Architecture Decision Records live in `Docs/Architecture/Decisions`.

- Number them sequentially.
- Include status, date, context, decision, alternatives, consequences, and verification.
- Record decisions that constrain future work or explain a non-obvious boundary.
- Do not fabricate historical decisions. A new ADR records a decision made now.
- Superseding an ADR: add a new ADR and update the old one's status to `Superseded by ADR-XXXX`.

See [the ADR index](../Architecture/Decisions/README.md).

## Related Documents

- [Documentation index](../README.md)
- [Contributing](../../CONTRIBUTING.md)
- [Agent guide](../../AGENTS.md)
