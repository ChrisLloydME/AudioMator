# Test system upgrade acceptance

Branch: `codex/test-system-upgrade`. Scope: AudioMator only, published TagLibAudioMetadata 0.7.1 through the normal project; no package source was entered or modified. No user audio or interactive app session was used.

## Changes

Added independent manifests for 33 dedicated string controls, 35 writable exchange fields and 18 generic container controls. Reflection/enumeration equality detects missing manifest entries. Tests assert exact single-field semantic patches and removals, exercise all dedicated strings through MP4 set/replace/remove, and run seven common fields through six committed audio formats. Existing generated AIFF Store ID tests remain required.

CSV planning now has real adapter and disk-reload coverage for every writable exchange field. Representative real iTunes/MusicBrainz two-file provider batches and Inspector single/multi-file saves verify both persistence and refreshed app models. Native MP4 Store ID atoms and unrelated raw-array preservation have independent literal expectations. Existing revision-conflict, date, total, advisory, cancellation, unsupported-capability and failure-atomicity suites remain active. Successful mock-provider workflow samples now use decimal Store IDs.

The unified local/CI release script runs core, serial app-hosted, Release and artifact phases and keeps evidence under `.deriveddata-codex/Validation`. CI uploads that evidence on failure. Failed tests stop release acceptance. Coverage and remaining gaps are specified in [the test strategy](../Development/METADATA_TEST_STRATEGY.md); this record does not establish universal format conformance.

## Sensitivity experiment

Temporarily removed only the dedicated text-to-integer conversion loop from `TagLibAudioMetadataPipeline.swift` and ran `MetadataBoundaryMatrixTests/testEveryDedicatedStringHasIndependentPatchAndRemovalContract`. All three Store ID assertions failed because `.text` differed from independently expected `.integer`. The experiment verified an actual failing test, not just a source scan. A `finally` block restored the exact original source bytes; the final full suite ran after restoration. Probe log: `/tmp/audiomator-mutation-probe.log`.

## Exposed release blocker: MP4 Content Group

Affected API: `TagLibAudioMetadataPipeline.writeMetadata` calling the package semantic patch/verification path for `.contentGroup`.

Observed by `testAllDedicatedStringsPersistReplaceAndRemoveOnMP4`: setting only Content Group on the MP4 fixture fails with `verificationFailed(["Unedited PropertyMap field GROUPING changed during the patch."])`. The test confirms rejected writes preserve all original file bytes. This is a suspected package verification/alias issue; the observation does not establish loss of native grouping data.

Expected: a valid Content Group edit writes its native `©grp` target, preserves independent Grouping and Work, verifies and reloads successfully.

Minimal application reproduction using a temporary MP4 fixture copy:

```swift
let pipeline = TagLibAudioMetadataPipeline()
let file = try await pipeline.loadAudioFile(at: temporaryMP4, id: UUID())
var edit = SingleFileEditModel(from: file)
edit.contentGroup = "First contentGroup"
_ = try pipeline.writeMetadata(MetadataEditPayload(edit, comparedTo: file),
                               to: temporaryMP4,
                               expectedVersion: file.metadataFileVersion)
```

Package owner regression: single-field `.contentGroup` set/replace/remove, with independent Grouping and Work both absent and present; inspect native atoms and PropertyMap aliases, avoid treating an alias changed by the requested field as an unrelated edit, and verify rollback bytes on genuine rejection. Do not fix this by submitting a companion Grouping edit or bypassing semantic verification.

The failure remains a normal blocking assertion, not a skip or expected failure. Release must remain blocked pending package repair and a fresh complete gate.

## Test-development corrections

Advisory CSV canonical output is `1`, not the display label `Explicit`; HD Video has Boolean shape. These expectations were corrected against the current contract. The minimal MP4 fixture produces no audio-content identity even when requested, so no preservation claim is made from two nil identities; raw-array preservation remains asserted. Broad audio-payload preservation and external decoder comparison remain explicit coverage gaps.

## Final local evidence

`bash scripts/validate-release.sh` on restored application source: 62 core tests passed; the complete serial app-hosted suite executed 553 tests, 552 passed and one failed. The only final failure is the MP4 Content Group regression above. The gate exited nonzero and did not run its Release or artifact phases. Final logs and result bundle: `.deriveddata-codex/Validation/20261110-181707-37144/`; launcher log: `/tmp/audiomator-test-upgrade-final.log`. `bash -n scripts/validate-release.sh` and `git diff --check` passed. CI upload execution itself was not exercised locally. No changes were committed or published.
