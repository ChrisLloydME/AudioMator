> Historical record. Superseded by [published 0.7.3 acceptance](TAGLIB_073_RELEASE_READINESS_2026-11-12.md). The 0.7.0 blocker findings below remain dated evidence; do not read them as current capability claims.

# Application mapping refactor and released-package conformance audit

Date: 2026-11-10. Application base: `906bbbab` plus the uncommitted mapping implementation and independent repairs. Package inspected read-only: released `0.7.0`, revision `0f89fbe83c8fb029a9b6d640d57e397686986930`, clean local checkout at that revision. No package sources/caches were changed and no release was created.

Overall result: **application mapping routes improved; end-to-end conformance remains blocked by package 0.7.0**. Neither repository receives a complete-conformance approval.

## Application changes in this pass

- Removed `TagLibDateCompanion`: a Year edit produces only YEAR intent and a Date edit only DATE intent. No automatic `.date` legacy-alias write, sibling set/removal, derivation, or synchronization is introduced.
- Kept the four independent semantic fields and their separate drafts. The package's legacy `.date` spelling is not used for new semantic writes.
- Added a narrow, explicit 0.7.0 safety gate before executing Year-only Xiph/APE writes when independent DATE data exists. The Inspector also gates this case. Affected files are not modified; this restriction is not presented as successful date support. Remove the gate only after a released package repair passes the positive probes.
- Purchase Date is now an editable/readable generic container field using the package registry's `purd` target. It is no longer classified as a nonexistent dedicated control.
- RATE is included in the visible/read-only field list but excluded from edit intents. The native location is obtained from the registry, not a copied atom table.
- Unknown advisory codes can be parsed, exported, and reimported on the original file without becoming unset or a known Boolean/state. The current public typed API has no unknown-code assignment operation: a changed/new unknown assignment is rejected visibly in preview and again at execution, without partial saves or a raw fallback.
- Added actual Purchase Date write/reload and unknown-advisory preservation tests, not merely registry-count assertions.

Earlier application repairs (private cleanup input validation/state, source/target preview, CSV literal removal protection, legacy/v2 syntax separation, text escapes, and namespace-aware native reads) remain in place; see [the earlier acceptance report](AUDIOMATOR_MAPPING_070_ACCEPTANCE_2026-11-10.md).

## Package findings

### P1: YEAR writes delete independent Xiph DATE

`MappingPackageConformanceTests.testPackageYearMustPreserveIndependentXiphDate` bypasses the app adapter and submits public typed package patches to a temporary FLAC copy:

1. Write `.year = "2004"` and `.standaloneDate = "2008-03-04"` together.
2. Write only `.year = "2005"`.
3. Read the independent Date.

Expected: `2008-03-04`. Actual: empty string. This is native data loss in a successful package operation, not a display-label issue or an unsupported app control.

Source audit: `MetadataNativePlanning.swift` takes all `schema.propertyMapKeys` as native removals on the Xiph/APE path. YEAR still carries the historical DATE alias, while `MetadataMappingCatalog.swift` declares native YEAR and DATE as independent slots. The write planner therefore contradicts the native registry. The preservation verifier in `MetadataSnapshotPatch.swift` also exempts declared property aliases from unchanged-key checking, masking that deletion. Registering distinct targets was insufficient.

Repair requirements for the package owner: resolve cleanup against the actual native family and canonical semantic owner; never remove a different semantic field's native target merely because it is an engine alias. Verify untouched date identities and native cardinality/provenance separately from PropertyMap alias projections. Add independent set/remove tests for each of the four dates, including absent siblings, malformed/multi-valued siblings, and Xiph/APE fixtures. Joint four-field round trips alone cannot establish independence.

### FLAC comment native verification is still broken

The restored `TagLibUpgradeContractTests.testFLACSemanticCommentSetReplaceAndClearContract` fails with `verificationFailed(["Patched native comment collection differs after save."])`. The separate negative regression confirms unchanged bytes after rejection. Do not treat rejection as successful Mapping support or replace this positive gate with an expected failure.

### MP4 independent DATE probe passed

`testPackageMP4DateMustNotRequireYearCompanion` writes YEAR and then DATE in separate public package calls and verifies both values. It passed without the former application companion. The restriction must not be generalized to every format merely because one family is defective.

### Other scope and API limits

- ID3v2.3 TDAT/TDRL codec behavior remains disclosed in the existing handoff. This pass does not certify it as repaired; target registration does not prove that TagLib preserves that layout.
- `MetadataPatch.explicitAdvisory` accepts the known `ExplicitAdvisory` enum; `.explicitContent` has no normal field patch kinds. Existing unknown-code preservation is supported, but arbitrary unknown-code assignment has no typed API. App previews now state this limitation instead of dropping or recoding the value.
- Registry/capability declarations, native planning, bridge codecs, reads, and verification are separate layers. A complete-looking table and passing earlier package tests do not establish that they agree. The confirmed YEAR counterexample is sufficient to reject complete package-conformance claims; other untested rows remain unverified.

## Latest verification

Stable `/Applications/Xcode.app`, `.deriveddata-codex`, serial Debug app-hosted tests, unsigned test host (`CODE_SIGNING_ALLOWED=NO`), expanded cache access.

- Core: **62 passed**, zero failures.
- Full app-hosted suite: **541 executed, 536 passed, 5 failed**, no tests skipped. All nine `MappingAcceptanceRepairTests` passed, including actual Purchase Date write/reload and unknown advisory preservation.
- Package conformance probes: MP4 independent Date and app pre-mutation Xiph rejection passed; the positive package Xiph independence assertion failed.
- Other failures: positive four-date cross-format integration, Date/custom-array/artwork preservation and independent-Date conflict integration are blocked by the Xiph safety gate; the positive FLAC comment contract fails in the package. None were hidden or weakened.
- Logs: `/tmp/audiomator-mapping-core.log` and `/tmp/audiomator-mapping-final.log`.
- Release was not rebuilt in this pass; earlier Release evidence predates these latest mapping changes and is not current release approval.

No app UI was manually launched/interacted with. Interactive acceptance, signing, notarization, minimum-OS runtime and a release decision remain outside these test results. The application cannot receive full functional acceptance until the dependency passes the required independent-field operations. A package repair, followed by exact-pin adoption and rerunning the positive gates, is required.
