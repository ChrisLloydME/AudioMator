# Testing

AudioMator has two test targets and no UI automation suite. This document
describes what exists, what it validates, and what remains unverified.

Counts and paths below were verified by source inspection at the audited commit.
They change; re-count before quoting them in a release.

## Test Targets

| Target | Kind | Root | Framework | Test functions |
| --- | --- | --- | --- | --- |
| `AudioMatorCoreLogicTests` | SwiftPM test target | `Tests/AudioMatorCoreLogicTests` | XCTest | 61 |
| `AudioMatorTests` | App-hosted Xcode unit-test bundle | `AudioMatorTests` | XCTest | 438 |

- There is no Swift Testing (`import Testing`, `@Test`) usage.
- There are 60 `XCTestCase` classes; no custom base class.
- The only shared helper is `AudioMatorTests/TestSupport/AudioFileTestFactory.swift`;
  other fakes are private to their files.
- The scheme includes one testable, `skipped = "NO"`, `parallelizable = "NO"`,
  with an auto-created test plan. No `.xctestplan` file exists.
- There are no skipped, disabled, or expected-failure tests, and no
  environment-variable gating.

## Commands

Fast core logic:

```bash
swift test
swift test --filter AudioMatorCoreLogicTests
```

App-hosted suite:

```bash
xcodebuild \
  -project AudioMator.xcodeproj \
  -scheme AudioMator \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  test
```

Focused app-hosted run:

```bash
xcodebuild ... \
  -only-testing:AudioMatorTests/TagLibReadWriteIntegrationTests \
  test
```

Always keep the serial flags for Agent-driven runs. The test bundle is app-hosted
and each parallel runner launches another app instance.

Performance tests are part of the same scheme and run in CI. See
[Performance tests](#performance-tests).

## SwiftPM Fast Target

`Package.swift` compiles exactly 30 Foundation-only production files:

- Core: numeric conversion, tag-number text, format-support core, async deadline,
  path semantics, fuzzy similarity.
- Domain: metadata model core, fingerprint, file collection, mutation directory
  plan, conflict policy, text edit pipeline, mutation coordinator, CSV and
  template syntax, MuseAmp IDs, rename plan/template/sanitizer, filename
  extraction, track renumber.
- Infrastructure pure cores: iTunes artwork/provider, LRCLIB models/ranker/request
  builder, MusicBrainz provider core/Lucene builder/request scheduling, online
  selection core.

It intentionally excludes:

- all UI, AppKit, SwiftUI, Combine, and platform code,
- TagLib adapters and `AudioFile` loading,
- network clients and services,
- app models (`AudioFile`, edit models, pipeline contract, conflict baseline),
- the app metadata exchange planner, template models, and filename plan builders.

A file in this target must stay Foundation-only and deterministic. It may use a
temporary directory for path-semantics tests, but it must not contact the network,
invoke TagLib, or depend on app-hosted types.

## App-Hosted Suite Map

| Directory | Files | Tests | Validates |
| --- | ---: | ---: | --- |
| `Application/MetadataEditing` | 10 | 116 | pipeline contract, batch summaries, reload workflow, revision conflicts, view-model orchestration, conflict strategies, editor store, text pipeline, renumber execution |
| `Application/MetadataExchange` | 3 | 57 | fixture parsing, planner import/export/matching/limits, field transfer |
| `Application/Rename` | 4 | 19 | template parsing, transaction rollback, filename extraction, refresh safety |
| `Application/WatchedFolders` | 3 | 17 | directory-monitor plan/cap, bookmark persistence/corruption, security-scope balancing |
| `Concurrency` | 3 | 23 | reservation ordering/cancellation/starvation, quick-import cancellation, 200-track presentation stress |
| `Integration/Network` | 5 | 39 | mocked HTTP faults, LRCLIB, artwork timeout/cancel, page traversal, search restart |
| `Integration/TagLib` | 1 | 33 | real TagLib reads/writes on temporary fixture copies |
| `Performance` | 3 + fixture | 20 | batch concurrency, publication bounds, IO stages, online workbench work bounds |
| `Unit/Core` | 15 | 67 | tag numbers, formatters, fuzzy matching, MuseAmp, provider helpers, version/update, disclosure registry, issue log, markdown |
| `Unit/Presentation` | 7 | 34 | artwork preview cache, editor rows, status text, list selection, comparison builders, folder selection |
| Root | 2 | 13 | source-policy checks for write-plan routing and sensitive logging |

Notable coverage:

- Real TagLib writes use temporary copies of the six committed audio fixtures.
- Conflict-strategy tests drive the real adapter on a temporary FLAC copy.
- Network tests never open a socket: they use `URLProtocol` fakes or injected
  protocol clients.
- Presentation tests include `NSHostingView` traversal of online metadata pages
  with a 2-second layout budget.

## Fixtures

Committed fixtures live in `AudioMatorTests/Fixtures` and are copied to temporary
directories before any write:

- Audio: `testAudioFile.mp3`, `.m4a`, `.flac`, `.aac`, `.ogg`, `.wav`.
- Artwork: `testCover.jpg`.
- Metadata exchange: ten `aurora-*.flac` files (byte-identical copies of the FLAC
  fixture) plus pipe/tab/comma/semicolon text fixtures and an expected-output
  file.

There are no committed AIFF or Opus fixtures. Artwork write/clear coverage is
limited to MP3, M4A, and FLAC.

## Network Tests

There are no live-network tests and no environment gating.

- `MockURLProtocol` (LRCLIB), `ProviderFaultURLProtocol`, and
  `UpdateMockURLProtocol` intercept requests in ephemeral sessions.
- Other tests inject non-cooperative or traversal client fakes.
- Production request timeouts are asserted to be 15 seconds where applicable.
- Provider stores are tested for cancellation, restart races, timeout clearing,
  and bounded fan-out.

What this does **not** prove: live service availability, remote rate limits, API
drift, Apple-provided artwork hosts, or WebKit subresource behavior.

## Performance Tests

- No `XCTMetric` and no `measure {}` API.
- Timing uses `ContinuousClock`/`Duration`; the online workbench reports warm
  medians as attachments.
- Most wall-clock numbers are informational. Hard assertions mostly check work
  bounds: four concurrent batch writes, publication counts below a fraction of
  file count, virtualized rows ≤ 40, recording fan-out ≤ 1, menu deferral.
- One traversal test asserts a 2-second layout budget.
- All performance tests run unconditionally in CI and in the scheme.

They are regression sensors for algorithmic blowups, not benchmarks for a
specific Mac or volume.

## CI

Only one workflow exists: `.github/workflows/core-logic.yml` (`Validation`).

- Triggers: pull requests and pushes to `main`.
- Runner label: `xcode-27`; `DEVELOPER_DIR` points at
  `/Applications/Xcode_27.0.app/Contents/Developer`.
- `swift-test`: 15-minute timeout, runs `swift test`.
- `xcode-test`: 45-minute timeout, runs the app-hosted suite serially with
  signing disabled, then builds an unsigned Release artifact and validates it
  with `scripts/validate-macos-artifact.sh`.

The `xcode-27` runner provision and the `Xcode_27.0.app` path are external to the
repository and were not verified. There is no test sharding, artifact upload, or
signing secret.

## Known Coverage Gaps

1. **No AIFF/Opus fixtures.** Those formats are not integration-tested even
   though they are readable/writable in the dependency.
2. **Artwork writes only for MP3/M4A/FLAC.** Other artwork-capable formats are
   untested.
3. **No live-network coverage.** Provider integration is mocked.
4. **No UI automation.** Full SwiftUI/AppKit interaction, file panels,
   drag-and-drop, accessibility, and visual behavior are manual.
5. **Watched-folder OS integration is simulated.** Tests use temporary
   directories and isolated `UserDefaults` suites; real sandbox bookmark grants,
   file providers, and volume notifications are not exercised.
6. **Full `AudioViewModel` watched-folder scanning and long-running batch UI**
   are only partially covered by synthesized orchestration tests.
7. **Positive container-normalization warning coverage is missing.** Current
   fixtures assert the warning is absent; no test forces the normalized-warning
   branch.
8. **No archived-binary security scan.** `validate-macos-artifact.sh` checks
   minimum OS and Mach-O platform only. Historical claims about scanning a
   release binary are not backed by a committed script.
9. **Source-policy tests depend on repository layout.** Tests read files via
   `#filePath`; moving those files breaks the tests.
10. **Historical test documents are stale.** Dated counts (38 or 404 tests) do not
    describe the current suite. They are archived under
    `Docs/Engineering/HISTORY/`.

## Manual Verification Boundary

Automated tests and builds are the Agent verification boundary. Interactive
acceptance remains the maintainer's responsibility. When manual verification is
required, use temporary fixture copies and check:

- import, single and batch edit, save, reload,
- rename and renumber previews and failure reporting,
- text/CSV import and export,
- online metadata apply and cancellation,
- watched-folder restore and degraded status,
- settings persistence and conflict policies.

Do not run destructive smoke tests against a real music library.

## Recommended Additions (Not Implemented)

These are proposals, not current coverage:

1. Add redistributable AIFF and Opus fixtures to the integration matrix.
2. Add a fixture that forces the container-normalization warning and assert it is
   emitted.
3. Replace source-text policy tests with behavioral tests where practical, or
   assert paths through a small manifest.
4. Add a live-network opt-in test target that is skipped by default; never run it
   in CI.
5. Add a UI test host with stable accessibility identifiers for selection, save,
   and window flows.
6. Add real bookmark/security-scope integration tests on a signed sandboxed
   build.

## Verification Status of This Audit

Executed on 2026-10-17 with Xcode 27.1:

- `swift test`: 61 tests passed.
- `xcodebuild ... -only-testing:AudioMatorTests/TagLibReadWriteIntegrationTests test`:
  33 tests passed.
- `bash scripts/codex-build.sh --force`: build succeeded.

Not executed: the complete 438-test app-hosted suite, CI itself, and the TagLib
bridge smoke tool (the latter builds against the external package checkout, which
AudioMator Agents must not build from).

## Related Documents

- [Build](BUILD.md)
- [Debugging](DEBUGGING.md)
- [Release Engineering](RELEASE.md)
