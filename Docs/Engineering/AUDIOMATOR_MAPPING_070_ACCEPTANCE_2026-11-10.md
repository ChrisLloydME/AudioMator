> Superseded candidate status: [0.7.1 joint acceptance](MAPPING_071_JOINT_ACCEPTANCE.md). Earlier 0.7.0 blocker findings remain historical evidence; do not read them as current candidate results.

# Independent mapping acceptance — 2026-11-10

Status: **NOT READY TO RELEASE**. Review target: the uncommitted AudioMator mapping adoption on `codex/metadata-mapping-spec`, based on `906bbbab`. This assessment reviews and repairs application code only. It does not authorize edits to the external package or establish signed distribution readiness.

## Findings and application repairs

| ID | Finding | Repair and evidence |
| --- | --- | --- |
| R1 | Number replacement used `Int(...)` directly; malformed non-empty input became nil, indistinguishable from intentional removal. | Reject non-empty malformed/overflow/zero/negative input. Only empty input means removal. `MappingAcceptanceRepairTests.testInvalidReplacementMustNotBecomeRemoval`. |
| R2 | Cleanup controls lived inside the valid-preview branch. Invalidating a preview hid the controls needed to repair it. Replacement text could also change without invalidating the captured plan. | Keep policy/group/replacement controls visible without a valid plan; keep the sheet open after planning failure. Invalidate the plan on policy, groups, number or total changes. Show planned native pair values separately from source inventory. Regression covers replacement draft invalidation. Interactive layout remains unverified. |
| R3 | CSV exporter emitted literal `<remove>` unquoted, so its own import could delete the field. Legacy imports also adopted the new destructive token syntax. Text exports had the same literal-token ambiguity. | Quote CSV literals, enable removal tokens only for v2, and implement reversible backslash escaping for v2 text literal tokens. Tests cover CSV export/import, legacy literal behavior, and repeated text escape round-trips. |
| R4 | MP4 date projections accepted any freeform namespace with a matching description. Foreign metadata could contaminate semantic date reads and conflict decisions. | Match the exact `com.apple.iTunes` namespace and description from the native key. Test excludes `org.example:DATE` while reading the canonical field. |
| R5 | Container-field atom names duplicated the package's native mapping table. | Read the declared MP4 target from the public registry, including read-only target fallback. The existing MP4 contract suite exercises these projections. |
| R6 | The original FLAC comment success contract was replaced with a test that considered a rejected write successful. | Restore `testFLACSemanticCommentSetReplaceAndClearContract` as a normal release gate, while retaining the separate byte-preserving failure test. The restored gate fails on package 0.7.0; a green negative test is not functional acceptance. |

## Private-field evidence correction

The previous ledger reported that public APIs could not seed private number fields and therefore A08/A09 could not cover them. That conclusion was too broad: custom-field writes and structured atom writes are different APIs.

`MappingAcceptanceRepairTests.testPrivatePairsCanBeSeededAndCleanedThroughCapturedAppPlan` uses the public structured writer on temporary M4A copies for **both** private prefixes. It seeds private-only `03/12`, disc `01/02`, and a foreign-namespace lookalike, then uses the real AudioMator pipeline's captured `.useLegacy` track-only plan. It verifies native `trkn=3/12`, exact track-private retirement, and unchanged disc/foreign private values. This test passed. It closes that specific seeding gap; it does not claim exhaustive malformed/multi-valued private-atom or interactive UI coverage.

## Verification

Stable `/Applications/Xcode.app`, macOS destination, `.deriveddata-codex`, serial tests (`-parallel-testing-enabled NO -maximum-parallel-testing-workers 1`), and `CODE_SIGNING_ALLOWED=NO`. Cache access required expanded filesystem permissions. No app was manually launched or interacted with.

- Foundation-only core tests: **62 passed**, zero failures.
- Serial full app-hosted suite after application repairs: **534 passed**, zero failures, before restoring the additional positive FLAC release gate. This is not a claim that the final release suite is green.
- Restored positive FLAC gate: **1 executed, 1 failed**, with `verificationFailed(["Patched native comment collection differs after save."])`. The separate unchanged-byte rejection regression passes.
- Unsigned universal Release build: **BUILD SUCCEEDED**. `validate-macos-artifact.sh` passed for the app and embedded framework at macOS 15.0. Signing/notarization and interactive acceptance were not performed.
- Logs: `/tmp/audiomator-final-core.log`, `/tmp/audiomator-final-tests.log`, `/tmp/audiomator-release-comment-gate.log`, `/tmp/audiomator-acceptance-release.log`, `/tmp/audiomator-acceptance-artifact.log`. These local files are not committed artifacts.

## External release blocker and minimal reproduction

Affected released API: `TagLibMetadataManager.applyMetadataPatch(_:to:)`, semantic `.comment` on FLAC in TagLibAudioMetadata 0.7.0. The AudioMator adapter uses this typed path; no raw fallback is permitted.

Reproduction: copy the committed FLAC fixture to a temporary file, submit `MetadataPatch(fields: [.comment: .text("Probe Comment")])`, then read comment back. Expected: set, replacement, and removal persist. Observed: the first set throws the verification error above. Existing safety coverage verifies rejected writes preserve file bytes. Run `TagLibUpgradeContractTests/testFLACSemanticCommentSetReplaceAndClearContract` for the positive release contract and `testFLACSemanticCommentWriteFailsSafelyWithUnchangedBytes` for atomic failure evidence.

The package owner needs a regression for FLAC comment set/replace/remove, a verified native comment codec/planner correction, and a new published version. AudioMator must then adopt that exact release and rerun the positive contract and complete serial suite. Do not remove verification, bypass the typed path, or mark the failing positive gate expected/ignored to publish.

The previously disclosed ID3v2.3 date limitation and date-companion workaround also remain package follow-up items in the [handoff register](AUDIOMATOR_MAPPING_070_HANDOFF.md); this review does not independently certify or close them. The existing companion workaround remains narrow and labeled in source.

Current `AGENTS.md` restricts work to AudioMator and prohibits entering/patching the external package without explicit task-specific permission. No package checkout or resolved source was inspected or modified in this review. Publication remains blocked pending package ownership action/authorization and successful revalidation. Signing, notarization, minimum-OS runtime and interactive UI acceptance remain separate maintainer release steps.

## Additional normative conformance review

A subsequent source-level review found additional unfinished requirements. These are not covered by the earlier green suite and have not yet been repaired or separately runtime-tested. The application-side repair list above is not exhaustive conformance approval.

- **Independent write intent:** `TagLibDateCompanion.augmenting` adds an unrequested legacy YEAR write/removal when editing DATE, and adds a DATE write when editing YEAR. Keeping an equal value is not the same as leaving native storage untouched. This workaround conflicts with the contract's prohibition on automatic cross-field alias resolution and must be eliminated by correcting the underlying package behavior, with exact unchanged-sibling/native-provenance tests.
- **MP4-exclusive completeness:** `itunesPurchaseDate` is classified `.dedicated` in `ContainerMetadataFieldCatalog`, but repository search finds no dedicated application property/editor/patch route. It is excluded from generic read/edit lists. A classification-count test does not prove a usable field route.
- **Read-only presentation:** the Inspector loops only over `editableKeys`; RATE is `.readOnly` and therefore never reaches the read-only display branch within that loop. Registration alone does not meet the requested readable/read-only presentation.
- **Unknown advisory exchange:** export carries `advisoryRawValue`, but import validation accepts only recognized 0/1/2/label values, and application uses `ContentAdvisory.fromMetadataText`. Unknown code export therefore does not establish lossless import/reapplication. The full export/import/preview/apply contract remains unfinished.

The correct overall assessment is **partial implementation, not complete mapping conformance**, independently of the FLAC comment blocker. Further application work and positive end-to-end regressions are required before a release decision.


## Mapping conformance update

[The latest mapping audit](MAPPING_CONFORMANCE_2026-11-10.md) supersedes earlier companion-workaround guidance and completion claims. Purchase Date/RATE routes and unknown-advisory handling were corrected; positive package probes confirm a YEAR write can erase independent DATE. Overall conformance remains blocked.
