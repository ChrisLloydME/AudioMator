# Metadata state coverage — 2026-11-11

App branch: `codex/metadata-state-coverage-tests`, retaining the uncommitted 0.7.2 adoption changes. Package candidate branch: `codex/metadata-state-coverage-repairs`, based on published 0.7.2. The normal app project/lock remains pinned to the real remote 0.7.2 revision `5e6f604b0e9df244f4b69608261407d2ab758788`. No package publication, app release, commit, tag or push is part of this work.

## Failure mechanism and scope

The published package could route MP4 Comment/Lyrics through a whole PropertyMap projection that recreated a missing native Year from independent Date. Old matrices used fixed scalar sibling states; a CSV test's dictionary order sometimes exposed the missing-Year/present-Date state. The package now reproduces that defect independently, plus related ID3/Xiph low-level, ASF verification/custom-field and unchanged-array write-surface gaps. The original app/package deterministic regressions remain normal tests.

The app has no new metadata workaround. Candidate compilation and testing use the explicitly generated ignored local workspace. The package owns native codec and transaction repairs; the app owns field intent, selection, displayed plans, dirty state and refreshed models.

## Added app coverage

| Required evidence | Cases/operations |
| --- | ---: |
| 33 dedicated string controls × 16 date masks × set/replace/clear | 1584 |
| All 16 iTunes and 27 MusicBrainz field selections × 16 date masks | 688 |
| Captured iTunes/MusicBrainz plans, Inspector, Metadata Editor, CSV × 16 date masks | 80 |
| Complete app-hosted XCTest inventory | 579 declarations |
| Complete Foundation-only core inventory | 62 declarations |
| Gate policy | 13 Python tests |

Every test writes temporary fixture copies or generated AIFF. The iTunes missing-barcode case explicitly asserts no entry and byte-identical no-op behavior. MusicBrainz recording credits come from the offline client through the actual browser cache. Unchecked provider fields and all unaffected dates are compared after real disk reload. Inspector/Editor saves must become clean; false dirty-state and failure recovery suites remain required. CSV's ordinary per-field loop is deterministic and starts with a fresh fixture per field.

## Acceptance gate

`bash scripts/validate-release.sh --local-package /absolute/path/TagLibAudioMetadata` runs the same full app/core/build gate with an explicit local candidate. No test filters are accepted. `xcresult` named Test Case identities must equal the full source inventory; critical identities and the minimum reviewed count cannot disappear. Runner status and summary/named results must agree. Skips, expected failures, duplicate/missing/foreign-target cases, malformed JSON and incomplete results fail closed. Separate core named execution evidence is also checked.

The package has its own Debug/Release gates, independent native byte readers and state/writer matrices. A green app test run cannot replace those gates. The app keeps source identity, logs, test tree, summary and machine-readable acceptance in `.deriveddata-codex/Validation`.

## Final validation

The final unified gate passed using the local candidate:

```bash
bash scripts/validate-release.sh --local-package /absolute/path/TagLibAudioMetadata
```

Evidence root: `.deriveddata-codex/Validation/20261111-215259-91974/`.

| Phase | Result | Evidence |
| --- | --- | --- |
| Gate policy | 13 Python tests passed | `policy.log` |
| Core | 62 tests passed; exact source/execution identities accepted | `core.log`, `core-gate.json` |
| Full serial Debug app suite | 579 passed, zero failures/skips/expected failures; exact inventory accepted | `app.log`, `AppTests.xcresult`, `test-summary.json`, `test-tree.json`, `test-gate.json` |
| Unsigned Release generic macOS build | passed | `release.log` |
| macOS artifact validation | passed | `artifact.log` |
| Candidate source record | package base SHA, branch/dirty status, diff and untracked hashes captured | `source.txt` |

A prior real 576-test failing result is rejected by the current parser: it has failures and omits all three new state declarations. A complete current result is accepted. Unit policy tests additionally exercise both app and core log/result tampering. No failure was converted to an expected failure and no app test is skipped.

The app's production source did not change after this acceptance. Subsequent package-only test hardening independently verifies each matrix seed's native before-state; its final gate evidence belongs to that repository. The package's Debug/Release results are 158 XCTest (156 pass and the two original optional skips) plus 179 Swift Testing declarations in 41 suites, accepted; both independent consumers pass. Publication and normal-project adoption remain separate from this local integration acceptance.

## Limits

No interactive AudioMator launch, UI automation, live provider network, signing, notarization or publication was performed. Tests drive real stores/view models and disk writes, not mouse/keyboard interactions. Fixture and operating-system coverage remains finite; see [Testing](../Development/TESTING.md#known-coverage-gaps). Local candidate success must not be described as published 0.7.2 success. The maintainer publishes the repaired package before the next normal remote dependency adoption.
