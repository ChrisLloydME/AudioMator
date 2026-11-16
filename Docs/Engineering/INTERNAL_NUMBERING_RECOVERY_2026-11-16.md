# Internal numbering recovery — 2026-11-16

Application branch: `codex/internal-numbering-recovery`, based on `db2016b8`. The maintainer withdrew the 2.7 release and authorized a separate package branch (`codex/automatic-numbering-recovery`) and local override verification. No publication is performed.

## Adjudication and product contract

The former cleanup dialog implemented an old explicit-preview policy, rather than a necessary end-user operation. It exposed technical storage choices and was outside the common-field Inspector product boundary. Published 0.8.0 also supplied usable recovery inventory that the application ignored: a private-only `03/12` displayed as empty. After normal number edits, retained private data could conflict and block later clearing. This was an intentional old contract; the new product contract requires deterministic internal resolution and one atomic semantic save, not a raw workaround or two writes.

The Inspector action/sheet, choice enum, published session state and application plan/Apply protocol wrappers are removed. Normal loading uses validated inventory: canonical component first, then unambiguous recovery, never an arbitrary first candidate. Reading and unrelated saves preserve data. The package candidate supplies atomic retirement only for explicitly edited groups; conflicting missing siblings ask for an ordinary number/total value. Application errors omit private identities and Native/Legacy instructions. Existing direct package normalization tests remain as headless API tests; obsolete UI-session tests are replaced by absence-of-storage-controls/state regressions.

## Verification scope

Focused application recovery/mapping tests passed with the local candidate. Package tests independently verify native bytes/audio, both groups/namespaces, set/remove/text/mixed saves, one staging operation, conflict/opaque/stale/invalid safety. Final Debug-only gates are recorded below. Release builds/tests are skipped by request; no interactive app launch is performed. The committed published pin remains 0.8.0 until the repaired package is published and adopted; local override acceptance does not establish that published 0.8.0 implements the new behavior.

An adapter inspection also found discarded returned `MetadataWriteResult.commitStatus`: the old interpreter accepted only warning arrays. It now accepts the complete package result and preserves both warnings and committed/durability-uncertain status for semantic/raw/erase/number-text writes. The existing post-commit exception handling remains. A direct result-contract regression verifies returned uncertain and durable results with warnings; a typed return prevents future `.warnings`-only forwarding.

## Final Debug verification and publication boundary

Final tested application code: `3d291490`; package product code: `e5cc42a` (unchanged in standalone accepted package revision `e9fb7da`). The local candidate gate passed all 13 policies, 62 required core tests and 593 required serial app-hosted tests with accepted exact source inventories and no failures/skips/expected failures. The six real recovery/save/ambiguity/stale-read regressions and returned commit-status contract passed. Evidence: `.deriveddata-codex/Validation/20261116-175556-60307/`. The earlier joint `af64d670` run passed 592 tests before the additional returned-status regression; it is not substituted for the final run.

The package independently accepted its full strict Debug gate: 181 XCTest (two existing opt-in skips), 280 Swift Testing / 52 suites, 75/75 scenarios and 16 compiled/activated/killed calibration faults. Focused ASan/TSan passed. This closes the behavior in a package-owned regression without depending on AudioMator. See the package record `docs/records/remediation/REM-2026-11-16-automatic-numbering.md` in that separate repository.

No Release build, archive, signing, notarization, tag, push, publication or interactive UI launch was performed. The committed normal-project pin remains published 0.8.0, which does not supply the amended cleanup behavior. Keep the withdrawn 2.7 release on hold: first publish the repaired package, update the exact app pin/revision/disclosures and dependency contract, then rerun the normal-project acceptance lane. Local candidate acceptance is not permission to ship with the old pin. The implementation/test/configuration is unchanged after the tested application revision; this final update only records evidence and the publication constraint.
