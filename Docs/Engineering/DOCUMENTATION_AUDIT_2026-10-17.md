# Documentation Audit — 2026-10-17

> Engineering record. This describes the audit and documentation rebuild performed
> on this date at the stated baseline. It is not current guidance.

## Baseline

- Branch: `docs/comprehensive-engineering-documentation`
- Parent commit: `e9deb6b`
- Audited app version: 2.7 (build 2697)
- Toolchain: Xcode 27.1 (27A9275), Apple Swift 6.4
- Dependency: `TagLibAudioMetadata` 0.5.3,
  `03473c9ae199026b806a5f75c387ca036e325284`

## Method

1. Read the app entry point, view model, domain contracts, mutation executor,
   conflict resolver, TagLib adapter, loader, file-system stores, provider
   clients, settings, and scripts.
2. Extracted build settings, entitlements, package pins, scheme configuration,
   CI workflow, and preference keys.
3. Inventoried both test targets, fixtures, network fakes, and performance tests.
4. Compared every existing document with the implementation.
5. Rebuilt the documentation set by audience and subject, archived superseded
   records, and removed duplicated wiki content.
6. Verified commands and corrected in-app disclosure text that contradicted the
   code.

## Verification Performed

| Command | Result |
| --- | --- |
| `swift test` | 61 tests passed, 0 failures |
| `bash scripts/codex-build.sh --force` | `** BUILD SUCCEEDED **` |
| `xcodebuild ... -only-testing:AudioMatorTests/TagLibReadWriteIntegrationTests test` | 33 tests passed, 0 failures |
| `xcodebuild ... -configuration Release ... CODE_SIGNING_ALLOWED=NO build` | `** BUILD SUCCEEDED **`; universal `x86_64 arm64` executable |
| `scripts/validate-macos-artifact.sh ... 15.0` | Passed; bundle and 2 Mach-O files accepted |

Not run:

- the complete 438-test app-hosted suite,
- the CI workflow,
- the TagLib bridge smoke tool (it builds from the external package checkout,
  which AudioMator Agents must not build from),
- any interactive UI or signed/notarized distribution check.

## Material Discrepancies Found

| Existing claim | Actual implementation |
| --- | --- |
| Docs said `TagLibAudioMetadata` 0.5.2 | Project and `Package.resolved` pin 0.5.3 |
| Wiki said CI runs on `macos-15` and covers only the core package | Workflow runs on `xcode-27`; it has a serial app-hosted test job and an unsigned Release build/validation job |
| Wiki architecture listed `Domain/UIState` | No such folder; UI state is under `Features/Main/State` |
| Wiki said six converter modes | Seven modes, including Copy or Cut Metadata Fields |
| README said Settings tabs General/Toolbar/Columns/About | Six tabs: General, Interface, Folders, Conflicts, Logs, About |
| README/config docs said build 2692 | Project build is 2697 |
| Docs described a "SwiftUI-first" mandate | `AGENTS.md` states no preferred UI framework; SwiftUI is used widely, with AppKit adapters |
| In-app acknowledgements claimed a vendored, trimmed TagLib source and bundled bridge | The app uses the external SwiftPM package; no TagLib source is vendored |
| In-app iTunes disclosure claimed track number, duration, artist ID, and catalog ID are sent | Only term/country/media/entity/limit/id/upc are request parameters |
| Privacy docs said MusicBrainz sends disc information | The Lucene builder emits no disc clause |
| Privacy docs implied all queries are metadata-derived | MusicBrainz, iTunes, and LRCLIB can use filename/parent-directory fallback |
| Disclosure listed `github.com` as an app request host | The app requests only `api.github.com`; it opens `github.com` in the browser |
| Docs implied a fixed three-host Apple artwork set | Apple-returned artwork URLs are followed; only some URLs are rewritten |
| Docs did not disclose embedded web content | Apple/MusicBrainz pages load in a default `WKWebView` without a host allow-list |
| Historical test docs claimed 38/404 tests and referenced non-ancestor commits | Current suite has 61 SwiftPM and 438 app-hosted test functions; historical commits share no ancestor with `main` |
| Release-readiness prose implied broader validation | No signing, notarization, packaging, upload, or release automation exists in the repository |
| Docs implied security-scoped bookmarks are fully verified | The `bookmarks.app-scope` entitlement is absent; cross-launch restoration is unverified |
| ADR 0003 described three shared package types | The Domain contract also uses `MetadataSnapshot`, so four semantic types cross the boundary |

The in-app acknowledgements and network disclosure strings were corrected because
they are user-facing documentation embedded in the app. No functional behavior was
changed.

## Resulting Documentation Structure

- Root: `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `AGENTS.md`, `LICENSE`.
- `Docs/README.md` — navigation, audiences, conventions.
- `Docs/Product` — overview, user guide, FAQ, troubleshooting.
- `Docs/Architecture` — overview, state/mutation, metadata pipeline, revision
  and reload, exchange, rename/renumber, online metadata, dependency rules, ADRs.
- `Docs/Development` — build, testing, debugging, release, documentation
  maintenance.
- `Docs/Reference` — project structure, configuration, dependency limitations.
- `Docs/Security` — security and data integrity.
- `Docs/Engineering` — dated performance records.
- `Docs/Engineering/HISTORY` — superseded progress logs, audits, and coverage maps.
- `Docs/wiki` — removed; content was consolidated into the structure above.

## Remaining Uncertainties

- External package internals were not audited.
- Full app-hosted suite and CI were not executed during the audit.
- Cross-launch bookmark restoration, WebKit subresource behavior, network-volume
  behavior, and malformed-file robustness are unverified.
- Signed/notarized distribution was not produced.
- The runtime-discovered format list was not enumerated; the README list is a
  point-in-time dependency statement.
- Some historical records reference removed paths; they are retained as evidence.

## Recommended Follow-Up

1. Verify cross-launch bookmark restoration on a signed sandboxed build.
2. Add a host allow-list for artwork downloads and embedded web pages.
3. Add AIFF/Opus fixtures and a positive container-normalization warning test.
4. Add malformed-file/fuzz coverage and an import size limit.
5. Add release automation for signing, notarization, packaging, and publishing,
   with CI artifact verification.
6. Keep `Docs/` synchronized with behavior using the update matrix.
