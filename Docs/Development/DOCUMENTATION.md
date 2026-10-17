# Documentation Maintenance

This document defines how AudioMator's documentation is organized, how it stays
accurate, and what to update with each kind of change.

## Principles

1. **The implementation is the source of truth.** Documentation is verified
   against source, build settings, scripts, and reproducible commands.
2. **Current-state documents describe today.** Historical material is clearly
   separated and never linked as current guidance.
3. **One fact, one home.** Link to the canonical document instead of copying its
   content.
4. **Label uncertainty.** State "unverified", "not implemented", or "proposal"
   when that is true.
5. **Do not document intentions as features.** A TODO, disabled path, or plan is
   not current behavior.

## Document Classes

| Class | Location | Authority | Maintenance |
| --- | --- | --- | --- |
| Current guidance | `README.md`, `Docs/Product`, `Docs/Architecture`, `Docs/Development`, `Docs/Reference`, `Docs/Security` | Authoritative for current behavior | Update with code |
| Policies | `CONTRIBUTING.md`, `SECURITY.md`, `AGENTS.md` | Authoritative for process | Update when process changes |
| Legal/notices | `Docs/THIRD_PARTY_NOTICES.md`, `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md` | Authoritative for disclosures | Update with dependency/network changes |
| Engineering records | `Docs/Engineering/*.md` | Dated evidence, not current contracts | Add new records; do not silently rewrite history |
| Historical logs | `Docs/Engineering/HISTORY` | Dated, superseded | Preserve; add a banner if context changes |

When a historical record's claim is needed for current work, re-verify it and
move the verified fact into a current-state document.

## Update Matrix

| Change | Update |
| --- | --- |
| User-visible behavior, workflow, settings | `README.md` if headline-worthy, `Docs/Product/USER_GUIDE.md`, `FAQ.md`, `Troubleshooting.md` as applicable |
| Metadata write/read behavior, conflicts, formats | `Docs/Architecture/METADATA_PIPELINE.md`, `Docs/Architecture/FILE_REVISION_AND_RELOAD.md`, `Docs/Reference/DEPENDENCY_LIMITATIONS.md` |
| Rename, conversion, renumber | `Docs/Architecture/METADATA_EXCHANGE.md`, `RENAME_AND_RENUMBERING.md`, `USER_GUIDE.md` |
| Network provider, endpoint, data sent, timeout | `Docs/Architecture/ONLINE_METADATA.md`, `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md`, `NetworkServiceDisclosure.swift`, privacy sheet text |
| Entitlement, sandbox, file access, logging | `Docs/Security/SECURITY_AND_DATA_INTEGRITY.md`, `Docs/Reference/CONFIGURATION.md` |
| Build setting, toolchain, package version | `Docs/Development/BUILD.md`, `Docs/Reference/CONFIGURATION.md`, `Docs/THIRD_PARTY_NOTICES.md` |
| Test target, suite, fixture, CI | `Docs/Development/TESTING.md` |
| Release process, signing, versioning | `Docs/Development/RELEASE.md` |
| Architecture boundary or decision | `Docs/Architecture/OVERVIEW.md`, `DEPENDENCY_RULES.md`, and a new ADR |
| Repository layout | `Docs/Reference/PROJECT_STRUCTURE.md`, `README.md` |
| Contribution or review process | `CONTRIBUTING.md`, `AGENTS.md`, this file |

If behavior changes and the documentation is not updated in the same change, the
change is incomplete.

## Writing Style

- Use English. The current documentation set is English-only; historical
  documents may contain other languages and are preserved as-is.
- Use project terminology: Inspector, Metadata Editor, Tag Inspector,
  Filename & Metadata, Current Session, Watched Folders, conflict strategy,
  snapshot, draft, mutation reservation, refresh-required.
- State the platform: macOS 15.0+, App Sandbox.
- Prefer concrete file paths and type names over vague references.
- Explain *why* only when the reason is established by code, tests, an ADR, or a
  verifiable constraint.
- Do not include secrets, personal paths, or real user media metadata.
- Use Mermaid for diagrams; keep them aligned with the current code.

## Verification

Before committing documentation:

1. Re-read the implementation for every factual claim.
2. Check links and anchors relative to the file that contains them.
3. Run documented commands where practical and record the result.
4. Remove or qualify claims that could not be verified.
5. Check for contradictions with existing current-state documents.
6. Confirm historical documents are not presented as current guidance.

There is no automated link checker. Treat broken links as defects.

## ADR Process

Architecture Decision Records live in `Docs/Architecture/Decisions`.

- Number them sequentially.
- Include status, date, context, decision, alternatives, consequences, and
  verification.
- Record decisions that constrain future work or explain a non-obvious boundary.
- Do not fabricate historical decisions. A new ADR records a decision made now.
- Superseding an ADR: add a new ADR and update the old one's status to
  `Superseded by ADR-XXXX`.

See [the ADR index](../Architecture/Decisions/README.md).

## Engineering Records and History

- `Docs/Engineering/` holds dated performance measurements and investigation
  records. They may contain numbers that are stale; each must state its date and
  baseline.
- `Docs/Engineering/HISTORY/` holds superseded progress logs and audits. They are
  retained for traceability and are not maintained.
- Do not copy current guidance out of a historical record without re-verifying it.

## AI Coding Agents

`AGENTS.md` is the entry point for agents. It must remain short and point to this
documentation set. Agents must:

- verify implementation details before changing code or docs,
- treat existing docs and tests as unverified evidence until checked,
- update the documents listed in the matrix above,
- not modify the external `TagLibAudioMetadata` checkout,
- not claim verification they did not perform.

## Review Checklist for Documentation Pull Requests

- [ ] Every changed fact is supported by code/config/test evidence.
- [ ] Current behavior, limitations, and proposals are clearly separated.
- [ ] Links resolve.
- [ ] No duplicate source of truth was introduced.
- [ ] Historical records are labeled and not used as current guidance.
- [ ] Commands were run or explicitly marked unverified.
- [ ] Privacy/third-party docs updated if network or dependencies changed.
- [ ] `AGENTS.md` remains concise and consistent with the docs.

## Related Documents

- [Documentation index](../README.md)
- [Contributing](../../CONTRIBUTING.md)
- [AGENTS.md](../../AGENTS.md)
