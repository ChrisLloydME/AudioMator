# Internal numbering recovery — 2026-11-16

Application branch: `codex/internal-numbering-recovery`, based on `db2016b8`. The maintainer withdrew the 2.7 release and authorized a separate package branch (`codex/automatic-numbering-recovery`) and local override verification. No publication is performed.

## Adjudication and product contract

The former cleanup dialog implemented an old explicit-preview policy, rather than a necessary end-user operation. It exposed technical storage choices and was outside the common-field Inspector product boundary. Published 0.8.0 also supplied usable recovery inventory that the application ignored: a private-only `03/12` displayed as empty. After normal number edits, retained private data could conflict and block later clearing. This was an intentional old contract; the new product contract requires deterministic internal resolution and one atomic semantic save, not a raw workaround or two writes.

The Inspector action/sheet, choice enum, published session state and application plan/Apply protocol wrappers are removed. Normal loading uses validated inventory: canonical component first, then unambiguous recovery, never an arbitrary first candidate. Reading and unrelated saves preserve data. The package candidate supplies atomic retirement only for explicitly edited groups; conflicting missing siblings ask for an ordinary number/total value. Application errors omit private identities and Native/Legacy instructions. Existing direct package normalization tests remain as headless API tests; obsolete UI-session tests are replaced by absence-of-storage-controls/state regressions.

## Verification scope

Focused application recovery/mapping tests passed with the local candidate. Package tests independently verify native bytes/audio, both groups/namespaces, set/remove/text/mixed saves, one staging operation, conflict/opaque/stale/invalid safety. Final Debug-only gates are recorded below. Release builds/tests are skipped by request; no interactive app launch is performed. The committed published pin remains 0.8.0 until the repaired package is published and adopted; local override acceptance does not establish that published 0.8.0 implements the new behavior.
