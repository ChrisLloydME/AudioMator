# Project Structure

This document maps the repository to responsibilities. See [Build](../Development/BUILD.md) for build commands and [Dependency Rules](../Architecture/DEPENDENCY_RULES.md) for allowed imports.

## Top Level

```text
AudioMator/
├── AudioMator.xcodeproj/          Xcode project, shared scheme, package pin
├── AudioMator/                    App source (Xcode file-system synchronized root)
│   ├── App/                       Entry point, commands, notifications, delegates
│   ├── Core/                      UI-independent support
│   ├── Domain/                    Models and business rules
│   ├── Features/                  Native UI, view models, feature stores
│   ├── Infrastructure/            Concrete integrations and adapters
│   ├── Resources/Licenses/        Bundled AGPL, LGPL, MPL, MIT and Boost texts
│   ├── Assets.xcassets/
│   ├── AppIcon.icon/
│   ├── Localizable.xcstrings
│   └── InfoPlist.xcstrings
├── AudioMatorTests/               App-hosted XCTest bundle and fixtures
├── Config/                        Info.plist and entitlements (outside the synchronized root)
├── Docs/                          Documentation set, including Docs/Images
├── Tests/AudioMatorCoreLogicTests SwiftPM Foundation-only fast tests
├── scripts/                       Build, validation, evidence and bridge smoke helpers
├── .github/workflows/             Validation CI workflow
├── Package.swift                  SwiftPM fast-test manifest
├── README.md, CONTRIBUTING.md, SECURITY.md, AGENTS.md, LICENSE
```

## `AudioMator/App`

Application entry, lifecycle, commands, and notifications.

- `AudioMatorApp.swift` — `@main`, composition root, scenes (`WindowGroup`, Settings, Metadata Field Guide, Online Metadata, Filename & Metadata, Metadata Editor), commands.
- `AppDelegate.swift` — first-launch 900×600 window sizing and terminate-on-last-window.
- `AudioMatorTestHost.swift` — isolated preferences and startup behavior when running as the test host.
- `AppNotifications.swift` — cross-window notification names.
- `Commands/` — app info, edit/toolbar commands, view layout commands.

Add composition or platform lifecycle code here, not feature logic.

## `AudioMator/Core`

Shared, mostly UI-independent support.

| Folder | Responsibility |
| --- | --- |
| `Audio/` | Tag-number parsing/text, numeric conversion, format-support core, independent date text parsing and validation |
| `Artwork/` | Artwork image validation and PNG normalization |
| `Concurrency/` | `withAsyncTimeout` deadline wrapper |
| `FileSystem/` | Normalized path semantics |
| `Legal/` | License catalog and bundled license-text loader |
| `Localization/` | `L10n` helper and window-title table |
| `Network/` | GitHub request headers, network-service disclosure |
| `Platform/` | macOS application/window/security-scope adapters |
| `Text/` | Fuzzy string similarity |

`Core` files compiled by the SwiftPM target must remain Foundation-only.

## `AudioMator/Domain`

Business rules and value models that do not own UI or concrete file transactions.

| Folder | Responsibility |
| --- | --- |
| `AudioFiles/` | `AudioFile`, fingerprint, edit models, metadata model core, container field identities |
| `FileSources/` | Source modes, bookmark records, mutation directory access plan |
| `MetadataEditing/` | Pipeline contract, conflict policy/baseline, text pipeline, mutation coordinator |
| `MetadataExchange/` | Converter modes/fields, exchange profile, template syntax, CSV, import/export planning, field transfer |
| `MuseAmp/` | Deterministic MuseAmp ID generation |
| `Rename/` | Filename templates, extraction, rename plan, collision policy |
| `TrackRenumber/` | Renumber start policy, shared plan/row dispositions, result models |

There is no `Domain/UIState` folder. UI state lives under `Features/Main/State`.

## `AudioMator/Features`

Feature-owned views, view models, and presentation models.

| Folder | Responsibility |
| --- | --- |
| `Main/` | Main window, sidebar, middle list, Inspector, artwork lookup, track renumber sheet, `AudioViewModel` and write extensions, batch executor, save issue log, operation-result HUD |
| `MetadataEditor/` | Raw metadata value-map editor window, table, field entry, text utilities |
| `MetadataFilenameTool/` | Filename & Metadata window, converter modes, previews, templates, field transfer |
| `OnlineMetadataBrowser/` | Shared online metadata window shell, source picker, embedded web view, virtualized list |
| `MusicBrainzBrowser/` | MusicBrainz search/detail/tagging views and stores |
| `iTunesBrowser/` | iTunes search/detail/tagging views and stores |
| `LRCLIBLyricsBrowser/` | LRCLIB lyrics views and store |
| `MetadataHelp/` | Offline Metadata Field Guide window, Help command and field explanations |
| `Settings/` | Settings tabs, privacy/acknowledgements/license sheets, release-notes rendering |
| `Welcome/` | Welcome splash and progress |

Feature folders may contain their own helpers. Do not create a shared abstraction for a single feature.

## `AudioMator/Infrastructure`

Concrete integrations and adapters.

| Folder | Responsibility |
| --- | --- |
| `TagLib/` | Metadata pipeline adapter, `AudioFile` loading, conflict resolver, native date/numbering projections |
| `FileSystem/` | Watched-folder/bookmark stores, shared bookmark persistence, directory monitor |
| `GitHub/` | Release-notes client |
| `iTunes/` | Search API client, artwork service, provider cores |
| `LRCLIB/` | Request builder, client, models, ranker |
| `MusicBrainz/` | Client, query builders, link parser, matching, models, rate/retry scheduling, filename fallback |
| `OnlineMetadata/` | Cross-provider selection core |
| `Updates/` | Semantic version, latest-release client, update checker/presenter |

## `Config`

Target configuration inputs that must stay outside the synchronized source root:

- `Info.plist` — bundle fields, version references, category, copyright.
- `AudioMator.entitlements` — sandbox, user-selected read/write, network client.

## `AudioMatorTests`

App-hosted XCTest bundle organized by failure semantics. Current inventory: 994 test functions and 113 `XCTestCase` classes in 120 Swift files, plus fixtures and test-support files.

```text
Application/{MetadataEditing,MetadataExchange,Rename,WatchedFolders}
Concurrency/
Integration/{Network,TagLib}
Performance/
Unit/{Core,Presentation}
TestSupport/
Fixtures/
OnlineMetadataPlanSnapshotTests.swift
SensitiveLoggingPolicyTests.swift
```

`Fixtures/Audio` contains committed mp3/m4a/flac/aac/ogg/wav samples; `Fixtures/MetadataExchange` contains ten FLAC copies and text/CSV exchange fixtures; `Fixtures/Artwork` contains the cover image. Tests copy audio fixtures before writing.

## `Tests`

`Tests/AudioMatorCoreLogicTests` is the SwiftPM fast suite: 88 test functions in six `XCTestCase` classes across five source files. It has no UI, TagLib, or live-network dependency. `Package.swift` compiles a selected 33-file Foundation-only subset of `AudioMator/` for this target.

## `scripts`

| Script | Purpose |
| --- | --- |
| `codex-build.sh` | Fail-closed Debug generic macOS build: checked Git discovery, explicit skip or `CODEX_BUILD_COMPLETED` marker, no implicit pruning |
| `prune-app-bundles.sh` | Explicit maintainer cleanup that removes non-canonical `.deriveddata*` directories and app bundles (not run by the build helper) |
| `validate-release.sh` | Unified release gate: policy tests, core tests, full serial app tests, unsigned Release build, artifact validation, and recorded evidence |
| `check-core-evidence.py` | Requires every source-declared core test identity to pass in the core log |
| `check-test-evidence.py` | Requires exact source-to-`xcresult` test identity equality, critical regressions, and no skips/failures |
| `check-commit-messages.py` | Advisory commit-subject checker for the commit-message contract |
| `check-doc-links.py` | Checks relative links and heading anchors in tracked Markdown documentation |
| `tests/test_test_evidence.py` | Policy tests for the evidence gates |
| `tests/test_codex_build_policy.py` | Shell policy tests for the build helper: disposable trees, Git/Xcode/`tee` stubs, call counts, exit statuses, markers and artifact preservation |
| `validate-macos-artifact.sh` | Checks bundle minimum OS and every Mach-O platform/minimum |
| `build-taglib-bridge-smoke.sh` | Builds the bridge smoke executable from package/bridge sources (maintainer-run; agents must not run it) |
| `taglib_bridge_smoke.mm` | Smoke tool source |

## `Docs`

The documentation set. See [the index](../README.md). `Docs/Images` contains README images. Dated engineering evidence is under `Docs/Engineering`; superseded records are under `Docs/Engineering/HISTORY`. Current guidance lives in `Docs/{Product,Architecture,Development,Reference,Security}` and must not link to historical records as current behavior.

## Where to Add Code

| Change | Location |
| --- | --- |
| New app command or lifecycle behavior | `AudioMator/App` |
| New metadata field or edit rule | `Domain/AudioFiles`, `Domain/MetadataEditing` |
| New container behavior | `Infrastructure/TagLib` adapter plus package work (external) |
| New provider | `Infrastructure/<Provider>` and `Features/<Provider>Browser` |
| New main-window UI | `Features/Main` |
| New conversion mode or exchange field | `Domain/MetadataExchange` and `Features/MetadataFilenameTool` |
| New test | Matching `AudioMatorTests` directory; pure logic in `Tests/AudioMatorCoreLogicTests` |
| New build setting | `AudioMator.xcodeproj` and `Docs/Reference/CONFIGURATION.md` |
| New license or attribution | `Core/Legal/LicenseDisclosure.swift`, `Resources/Licenses`, in-app Acknowledgements, and `Docs/THIRD_PARTY_NOTICES.md` |

## Related Documents

- [Configuration](CONFIGURATION.md)
- [Architecture Overview](../Architecture/OVERVIEW.md)
- [Build](../Development/BUILD.md)
- [Testing](../Development/TESTING.md)
