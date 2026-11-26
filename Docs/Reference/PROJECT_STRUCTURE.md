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
- `AppDelegate.swift` — first-launch window centering and terminate-on-last-window.
- `AudioMatorTestHost.swift` — isolated preferences and startup behavior when running as the test host.
- `AppNotifications.swift` — cross-window notification names.
- `Commands/` — app info, edit/toolbar commands, view layout commands.

Add composition or platform lifecycle code here, not feature logic.

## `AudioMator/Core`

Shared, mostly UI-independent support.

| Folder | Responsibility |
| --- | --- |
| `Audio/` | Tag-number parsing/text, numeric conversion, format-support core, date picker draft, calendar serialization and viewport bounds |
| `Artwork/` | Artwork image validation and PNG normalization |
| `Concurrency/` | `withAsyncTimeout` deadline wrapper |
| `FileSystem/` | Normalized path semantics |
| `Legal/` | License catalog and bundled license-text loader |
| `Localization/` | `L10n` helper and window-title table |
| `Network/` | GitHub request headers, network-service disclosure |
| `Platform/` | macOS application, window and security-scope adapters, including the shared search dropdown |
| `Text/` | Fuzzy string similarity |

`Core` files compiled by the SwiftPM target must remain Foundation-only.

## `AudioMator/Domain`

Business rules and value models that do not own UI or concrete file transactions.

| Folder | Responsibility |
| --- | --- |
| `AudioFiles/` | `AudioFile`, fingerprint, edit models, metadata model core, container field identities |
| `FileSources/` | Source modes, sidebar selection, watched-folder hierarchy (`WatchedFolderHierarchy`), bookmark records, mutation directory access plan |
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
| `DateTimePicker/` | Semantic and raw-key eligibility, native date controls, time-zone selection and the shared picker sheet. Calendar serialization and draft state live in `Core/Audio/MetadataDateTimeCore.swift` |
| `MetadataEditor/` | Raw metadata value-map editor window, table, field entry, text utilities |
| `MetadataFilenameTool/` | Filename & Metadata window, converter modes, previews, templates, field transfer |
| `OnlineMetadataBrowser/` | Shared online metadata window shell, source picker, embedded web view, virtualized list |
| `MusicBrainzBrowser/` | MusicBrainz search/detail/tagging views and stores |
| `iTunesBrowser/` | iTunes search/detail/tagging views and stores |
| `LRCLIBLyricsBrowser/` | LRCLIB lyrics views and store |
| `MetadataHelp/` | Offline Metadata Field Guide window, field explanations, `iTunesStoreGenreCatalog.swift` for the optional resource loader and matching, and `iTunesStoreGenreLookup.swift` for the genre section and media detail |
| `Settings/` | Settings tabs and shared grouped-row styling, privacy/acknowledgements/license sheets, release-notes rendering |
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

App-hosted XCTest bundle organized by failure semantics. The current file, class, and test-function inventory is maintained in [Testing](../Development/TESTING.md#app-hosted-suite-map); this page does not duplicate the counts.

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

`Tests/AudioMatorCoreLogicTests` is the SwiftPM fast suite. `Package.swift` compiles a selected Foundation-only subset of `AudioMator/` for this target. See [Testing](../Development/TESTING.md#swiftpm-fast-target) for the current source list and inventory.

## `scripts`

| Script | Purpose |
| --- | --- |
| `codex-build.sh` | Fail-closed Debug generic macOS build: checked Git discovery, explicit skip or `CODEX_BUILD_COMPLETED` marker, no implicit pruning |
| `prune-app-bundles.sh` | Explicit maintainer cleanup that removes non-canonical `.deriveddata*` directories and app bundles (not run by the build helper) |
| `validate-release.sh` | Checks documentation links, runs policy, core and serial app tests, then runs a clean unsigned Release build and validates the artifact. Records source and test evidence |
| `check-core-evidence.py` | Requires every source-declared core test to pass and checks the reviewed floor and critical identities |
| `check-test-evidence.py` | Checks exact source-to-`xcresult` app test identity equality, the reviewed floor, critical regressions, and zero skips/failures |
| `check-commit-messages.py` | Advisory commit-subject checker for the commit-message contract |
| `check-doc-links.py` | Checks relative links and heading anchors in tracked Markdown documentation |
| `tests/test_test_evidence.py` | Policy tests for the evidence gates |
| `tests/test_codex_build_policy.py` | Shell policy tests for the build helper: disposable trees, Git/Xcode/`tee` stubs, call counts, exit statuses, markers and artifact preservation |
| `tests/test_rename_crash_recovery.py` | Real child-process `SIGKILL` crash-gate recovery tests compiling production rename journal and exclusive-move sources across 7 crash gates |
| `validate-macos-artifact.sh` | Checks the Release bundle ID, macOS minimum and Mach-O platforms, both required architectures in the app and TagLib, and five non-empty license resources |
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
