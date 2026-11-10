# Inspector false unsaved-state repair

Scope: AudioMator, branch `codex/test-system-upgrade`, normal-project dependency 0.7.1. No package source, user audio or interactive UI was used.

## Reproduced defects

Before production changes, `InspectorDirtyStateTests` executed six tests and produced 27 failed assertions. Batch state used `modifiedTextFields` / explicit action flags as the unsaved predicate: re-entering the current value, reverting a shared value, choosing an existing advisory or removing already absent artwork could request discard confirmation despite no effective file change. The sidebar-discard routing test reproduced an unwanted confirmation rather than merely asserting an internal flag.

Single-file split Track/Disc setters also rebuilt raw text when given the unchanged displayed component: `07 / 12` became `07/12`. The raw-string dirty comparison treated this invisible representation change as an edit. These are observed production-state defects, not just incorrect test assertions. Existing tests covered actual changes/cancel/save but omitted no-op setter delivery and change-then-revert transitions.

## Repair

Batch dirty state and batch-save target filtering now compare the effective per-target draft against its captured source baseline after excluding completed intent. The intent sets remain intact so mixed-value blank input still explicitly clears files and partial batch completion still prevents retries of already committed intent. No expected fingerprint/version or conflict check is removed.

Split-component setters leave raw representations untouched when the incoming displayed value is unchanged. Dirty comparison checks displayed number/total components and numeric values, so restoring a component removes dirty state even if joining the pair normalized separator spacing; changing visible zero-padding remains an edit. The raw editor remains separate.

Empty container text means removal: removing an already absent field is clean, while present Boolean false and integer zero remain real values. Explicitly clearing an unknown advisory must remain dirty and must remove the stored code, so applying that batch action now carries the existing `clearsUnknownAdvisory` intent.

## Regression evidence

`InspectorDirtyStateTests` covers every shared batch text control, revert-to-original sidebar routing, advisory/artwork no-ops, explicit mixed-value clear, unchanged split number bindings, visible number undo/padding, absent-container removal with false/zero preservation, clean reload rebasing and dirty reload draft retention.

Two real-file `MetadataSaveJourneyTests` supplement this state coverage: no-op/reverted batch edits do not enqueue writes or change bytes/versions; a genuine subsequent save and activation reload become clean; explicit batch clearing of unknown MP4 advisory codes remains a real write and reloads clean. Existing partial-save/conflict/retry suites remain mandatory.

Before-fix log: `/tmp/audiomator-inspector-dirty-before.log`. The initial affected-suite run after repair executed 92 tests with zero failures: `/tmp/audiomator-inspector-dirty-after.log`. Final verification results follow below. No tests were skipped, weakened or marked expected failure.

## Final verification

The complete release-gate test run executed 62 core tests with zero failures and 574 app-hosted tests with one failure, solely the existing MP4 Content Group blocker. Evidence: `.deriveddata-codex/Validation/20261110-184043-38867/`. After the final displayed-component undo comparison was tightened, the affected suites (dirty-state, save journeys, conflicts, Inspector/editor workflow, main-flow performance and file reload) executed 104 tests with zero failures: `/tmp/audiomator-inspector-dirty-acceptance.log`.

The separately requested unsigned universal Release build succeeded (`/tmp/audiomator-inspector-dirty-release.log`); the artifact audit passed for bundle minimum macOS 15.0 and both Mach-O files (`/tmp/audiomator-inspector-dirty-artifact.log`). The normal release gate remains red because of Content Group; successful compilation and these targeted tests do not waive that blocker. `git diff --check` passed. No interactive UI acceptance, commits or publication occurred.
