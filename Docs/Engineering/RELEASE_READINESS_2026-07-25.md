# AudioMator Release Readiness — 2026-07-25

## Verdict

Source, tests, generic platform builds, and disposable-fixture metadata operations are ready for the separately authorized signing/notarization/upload process. This audit did not push, tag, sign a release artifact, notarize, upload, or publish.

## Reviewed scope

- Starting point: `f1378c1` (`Pin TagLibAudioMetadata dependency to 0.4.3`), clean `main` aligned with `origin/main` when the audit began.
- Final implementation/tooling checkpoint: `c40dd32`.
- Remote verification during the final gate: `origin/main` = `a9634dabf04061bb8d59e3f87c198e82d1db657f`; local commits after that remote point remain intentionally unpushed.
- Latest verified remote release tag: `V2.4.2B26521` = `a28822bac79c20e8618799cd097f1fe1a8ca1923`.
- Configured app release line: `MARKETING_VERSION = 2.5`, `CURRENT_PROJECT_VERSION = 2672`.

## Architecture result

- Metadata writes now reserve the normalized file path across fingerprint validation, write, and reload, with an explicit persisted-but-reload-failed result.
- `AudioViewModel` is the single selection/draft owner; the `SharedState` selection mirror was removed.
- UI-only state lives under `Features/Main/State`.
- Metadata pipeline contract/payload stay in Domain; TagLib, AVFoundation, and platform image loading live in `Infrastructure/TagLib`.
- Metadata Exchange is split by schema, syntax, typed field mapping, and planning/matching responsibilities. Production syntax parsing is part of the fast test target.
- Provider semantics remain provider-specific; no unjustified common framework was introduced.

## Verification evidence

All commands used the repository-local `.deriveddata-codex` when applicable.

| Gate | Result |
| --- | --- |
| `swift test --filter AudioMatorCoreLogicTests` | PASS — 47 tests, 0 failures |
| `bash scripts/codex-build.sh --force` | PASS — universal macOS Debug build |
| Full macOS app-hosted `xcodebuild ... -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test` | PASS — 264 tests, 0 failures |
| Generic macOS build, signing disabled | PASS |
| Generic iOS build with Xcode 27 beta, signing disabled, no simulator | PASS, no orientation/launch warnings |
| Focused TagLib integration suite after warning cleanup | PASS |
| `bash -n scripts/build-taglib-bridge-smoke.sh` | PASS |
| `git diff --check` at each checkpoint | PASS |

The active Xcode 26.6 installation does not contain the required iOS 26.5 SDK. The generic iOS gate therefore used `/Applications/Xcode-beta.app` (Xcode 27) with an iOS 27 SDK; no simulator was booted.

## Disposable fixture smoke

`scripts/build-taglib-bridge-smoke.sh` was repaired to support the pinned package's binary `TagLib.xcframework` while retaining the older source-layout path. The tool was built and run only against copies in `/private/tmp`.

- Imported/read and raw-inspected FLAC, M4A, MP3, OGG, and WAV copies.
- Wrote title/artist/album/composer/genre/comment/year/release date plus `02/09` track and `1/1` disc intent across all five copies.
- Reloaded every written file and verified the values and numeric totals. Container-normalized display text varied as expected while numeric values round-tripped.
- Renamed a written FLAC copy to `02 – 烟雾测试.flac` and reloaded it successfully with metadata intact.
- A missing-source write failed closed with a nonzero exit and a readable error.
- Deleted the temporary directory after verification; repository fixtures were untouched.

## Operational notes

- `.github/workflows/core-logic.yml` runs the SwiftPM core suite on pull requests and `main`; the full Xcode matrix remains a documented local release gate because it requires current Apple SDKs and app-hosted execution.
- The build tool reports that AppIntents metadata extraction is skipped because the target has no AppIntents dependency. This is informational and matches the product.
- Remaining architectural opportunities are non-blocking: `AudioViewModel` is still a broad application orchestrator; several observation-oriented Domain models still import Combine; full Metadata Exchange planning remains app-hosted because it consumes localized `AudioFile` snapshots and fingerprints.
- External release actions still require explicit authority and credentials: push, tag, archive signing, notarization, upload, and publication.
