# Reliability Remediation Evidence

This file records the evidence used for the reliability remediation requested on
2026-06-21. It intentionally contains no user media paths, metadata values,
credentials, or signing material.

## Baseline captured before task edits

- Current branch: `main`
- Initial `HEAD`: `2c05c39f0ef211740a0be5580949c2ce2d6d9681`
- Initial upstream state: `main...origin/main [ahead 1]`
- Initial worktree: clean (no tracked or untracked task edits)
- Pre-existing commit ahead of upstream: `2c05c39 Defer Review & Apply track menu construction`
- Required compatibility tag: `V2.4.1B26516`
- Tag commit: `67ce047f7915dbccc5c1b5a5b8fa2be0574d640c`
- Tag commit date: `2026-06-01 16:18:28 +0800`
- Tag project version: `MARKETING_VERSION = 2.4.1`,
  `CURRENT_PROJECT_VERSION = 26516`
- Initial current project version: `2.4.2 (26517)`; the remediation does not
  change version or build settings.

The initial repository state was recorded with:

```sh
git status --short --branch
git rev-parse HEAD
git rev-parse V2.4.1B26516^{commit}
git show -s --format='%H%n%ci%n%s%n%D' V2.4.1B26516
git log --oneline --decorate V2.4.1B26516..HEAD
git diff --name-status V2.4.1B26516..HEAD
```

The authoritative repository-provided validation surfaces found before edits
were:

```sh
swift test
bash scripts/build-taglib-bridge-smoke.sh
bash scripts/codex-build.sh --force
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex-macos CODE_SIGNING_ALLOWED=NO test
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .deriveddata-codex-macos CODE_SIGNING_ALLOWED=NO archive \
  -archivePath /tmp/AudioMator.xcarchive
```

The shared `AudioMator` scheme includes `AudioMatorTests` and is configured for
Release Archive. The smoke script resolves the checked-out TagLib bridge from
`.deriveddata-codex` (or an explicit `TAGLIB_BRIDGE_ROOT`) and builds a local
smoke executable without accessing user media.

## Finding disposition and regression evidence

The baseline tag contains the same unsafe behaviors: independent detached
metadata mutation helpers, `try?` rename rollback, workbench actions that read
`store.plan` again, uncancellable quick import, the full metadata dump, track
renumbering with `verifyAfterWrite: false`, and one monitor per discovered
directory. This was verified with `git show` and `git grep` against
`V2.4.1B26516`; none of the post-baseline implementations was assumed correct.

| Risk | Disposition | Evidence and regression coverage |
| --- | --- | --- |
| High: file mutations were not uniformly serialized | Confirmed and fixed | A shared actor now atomically reserves normalized source/destination file URL keys for metadata write, raw read-modify-write, erase, track renumber, and rename. The old implementation allowed two overlapping mutations; `FileMutationSerializationTests` now proves URL aliases serialize and that write, erase, and renumber share one reservation. |
| High: rename rollback failures were discarded | Confirmed and fixed | Baseline rollback used `try?`. The transaction now records every rollback error, re-probes original/temp/destination paths, returns structured recovery items, and keeps a persistent failure alert open with the complete manual recovery list. `FileRenameTransactionTests` injects both staging and finalization rollback failures; the old seam produced no recovery item. |
| Medium: displayed online tagging plan differed from the applied plan | Confirmed and fixed | Both workbench buttons now pass the plan value captured by that render. Generated write entries also carry the loaded file fingerprint, which is checked inside the file mutation reservation immediately before writing. `OnlineMetadataPlanSnapshotTests` covers both stores, source-level apply routing, captured values/fingerprints, and rejection after an external file change. |
| Medium: quick import merged batches after Clear | Confirmed and fixed | A deterministic delayed pipeline reproduced a late batch after Clear in the old implementation. Tasks are now tracked and cancelled, every batch checks a generation token, and security-scoped URLs remain retained until the underlying task exits. `QuickImportCancellationTests` locks the behavior. |
| Medium: Release path logged complete sensitive metadata | Confirmed and fixed | The baseline contained an unconditional `print` of metadata values. The logger and its call are removed. `SensitiveLoggingPolicyTests`, source scans, and a scan of the archived Release binary verify that the logger and its field labels are absent. |
| Medium: track renumber skipped verification and optimistically updated the model | Confirmed and fixed | The old path passed `verifyAfterWrite: false`, discarded warnings, and wrote the requested padded text into memory. It now verifies, reloads from disk while retaining the file reservation, propagates warnings, and updates the model only from readback. `TrackRenumberExecutionTests` proves the disk value wins over the requested display value. |
| Low: directory monitor descriptors were unbounded and open failure was silent | Structural risk confirmed; bounded hardening applied | Resource exhaustion was not forced on the host. Code evidence proved one descriptor per directory and silent `open` failure, so no FSEvents rewrite was attempted. A deterministic plan caps monitors at 128 per watched folder, always retains the root monitor, and publishes omitted/open-failure counts in the sidebar. `DirectoryMonitoringPlanTests` verifies the bound and observable degraded state. |
| Low: reliability tests and CI were missing | Confirmed and fixed | Seven focused test files cover the requested flows; existing lazy-rendering and workbench tests remain collected. `.github/workflows/core-logic.yml` runs `swift test` on `macos-15` with read-only contents permission, no secrets, and a 15-minute limit. Full Xcode/TagLib/Archive validation remains the local authority because the workflow intentionally covers only the dependency-light core package. |

### Pre-fix distinguishing evidence

The focused tests were introduced before their corresponding behavior change
or were run through an injectable seam against the old behavior. The following
failures distinguished the old and new paths:

- file mutation serialization: old maximum concurrency was `2`; fixed is `1`;
- rename rollback: a hidden temporary or destination file remained while the
  old result contained no recovery item;
- displayed plan routing: the old views called `applyTags()` and then read
  `store.plan.writeEntries`; the fixed source-policy test requires the displayed
  plan parameter;
- quick import: the delayed old task repopulated the list after Clear;
- sensitive logging: the old source-policy test found
  `logMetadataWrite` and its unconditional marker;
- track renumber: the old pipeline received `verifyAfterWrite == false`, the UI
  model showed the requested `07`, and its warning was lost.

The directory exhaustion condition was not made to consume host resources.
Only bounded policy, status reporting, and deterministic tests were added for
that finding.

## Final validation

Completed on 2026-06-25 with no user media, credentials, or signing identity:

```sh
swift test
# 38 tests, 0 failures

bash scripts/build-taglib-bridge-smoke.sh
cp AudioMatorTests/Fixtures/Audio/testAudioFile.m4a \
  /private/tmp/AudioMator-taglib-smoke-019ee806.m4a
.tmp/taglib_bridge_smoke write-roundtrip \
  /private/tmp/AudioMator-taglib-smoke-019ee806.m4a
# build and generated-fixture round trip succeeded; the generated smoke
# executable and /private/tmp fixture were deleted after validation.

bash scripts/codex-build.sh --force
# BUILD SUCCEEDED

xcodebuild -quiet -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex-macos CODE_SIGNING_ALLOWED=NO test
# all shared-scheme tests passed; output lists every new test suite

git diff --check
# passed

xcodebuild -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .deriveddata-codex-macos CODE_SIGNING_ALLOWED=NO archive \
  -archivePath /private/tmp/AudioMator-codex-20260625-archive.xcarchive
# ARCHIVE SUCCEEDED
```

Archive inspection:

- path: `/private/tmp/AudioMator-codex-20260625-archive.xcarchive`;
- product: `AudioMator.app`;
- version: `2.4.2 (26517)`;
- executable architectures: `arm64` and `x86_64`;
- size: 92 MB;
- signing identity: absent, as expected for `CODE_SIGNING_ALLOWED=NO`;
- Release executable scan found none of the removed sensitive logger markers;
- production-source scan found none of the removed logger markers or provider
  identifiers.

The only build attempted beyond the required macOS surfaces was a generic iOS
compile. It is blocked by the repository's pre-existing unconditional
`import AppKit` in `MetadataFilenameTemplateEditors.swift`; that file is not
modified by this remediation. No unrelated cross-platform refactor was made.

### Remaining operational limits

- Directory monitoring intentionally becomes observable but partial after 128
  directories; the root remains monitored and a full rescan still refreshes the
  model. A future FSEvents migration can remove this limit but is outside this
  evidence-supported repair.
- The new hosted workflow has not run remotely in this local task. It is
  intentionally limited to `swift test`; the passing local TagLib, Xcode test,
  and Release Archive commands above remain authoritative.
