# Project Structure

This document maps the repository to responsibilities. See [Development](../Development/BUILD.md) for build commands and [Dependency Rules](../Architecture/DEPENDENCY_RULES.md) for allowed imports.

## Top Level

```text
AudioMator/
├── AudioMator.xcodeproj/          Xcode project, shared scheme, package pin
├── AudioMator/                    App source (synchronized Xcode root)
│   ├── App/
│   ├── Core/
│   ├── Domain/
│   ├── Features/
│   ├── Infrastructure/
│   ├── Resources/
│   │   └── Licenses/            Bundled AGPL, LGPL, MPL, MIT, and Boost texts
│   ├── Assets.xcassets/
│   ├── AppIcon.icon/
│   ├── Localizable.xcstrings
│   └── InfoPlist.xcstrings
├── AudioMatorTests/               App-hosted XCTest bundle + fixtures
├── Config/                        Info.plist and entitlements
├── Docs/                          Documentation set (this directory)
├── Tests/AudioMatorCoreLogicTests SwiftPM fast tests
├── scripts/                       Build, validation, bridge smoke helpers
├── Package.swift                  SwiftPM fast-test manifest
├── README.md                      Project entry point
├── CONTRIBUTING.md                Contribution workflow
├── SECURITY.md                    Vulnerability reporting
├── AGENTS.md                      AI coding-agent guidance
└── LICENSE                        AGPL-3.0
```

## `AudioMator/App`

Application entry, lifecycle, commands, and notifications.

- `AudioMatorApp.swift` — `@main`, composition root, scenes.
- `AppDelegate.swift` — first-launch window sizing and terminate-on-last-window.
- `AppNotifications.swift` — notification names used by commands and views.
- `Commands/` — app info, toolbar edit, view layout commands.

Add composition or platform lifecycle code here, not feature logic.

## `AudioMator/Core`

Shared, mostly UI-independent support.

| Folder | Responsibility |
| --- | --- |
| `Audio/` | Tag-number parsing/text, numeric conversion, format-support core |
| `Artwork/` | Artwork image normalization |
| `Concurrency/` | `withAsyncTimeout` deadline wrapper |
| `FileSystem/` | Normalized path semantics |
| `Legal/` | License catalog and bundled license-text loader |
| `Localization/` | `L10n` helper |
| `Network/` | GitHub request headers, network-service disclosure |
| `Platform/` | macOS application/window/security-scope adapters |
| `Text/` | Fuzzy string similarity |

`Core` files compiled by the SwiftPM target must remain Foundation-only.

## `AudioMator/Domain`

Business rules and value models that do not own UI or concrete I/O.

| Folder | Responsibility |
| --- | --- |
| `AudioFiles/` | `AudioFile`, fingerprints, edit models, metadata model core |
| `FileSources/` | Source modes, bookmark records, mutation directory plan, collection core |
| `MetadataEditing/` | Pipeline contract, conflict policy/baseline, text pipeline, mutation coordinator |
| `MetadataExchange/` | Converter modes/fields, template syntax, CSV, import/export planning, field transfer |
| `MuseAmp/` | Deterministic MuseAmp ID generation |
| `Rename/` | Filename templates, extraction, rename plan, collision policy |
| `TrackRenumber/` | Renumber options, padding, result models |

There is **no** `Domain/UIState` folder. UI state lives under `Features/Main/State`.

## `AudioMator/Features`

Feature-owned views, view models, and presentation models.

| Folder | Responsibility |
| --- | --- |
| `Main/` | Main window, sidebar, middle list, inspector, track renumber sheet, `AudioViewModel` and write extensions, batch executor, save issue log |
| `MetadataEditor/` | Raw PropertyMap editor window, table, field entry, text utilities |
| `MetadataFilenameTool/` | Filename & Metadata window, converter modes, previews, templates |
| `OnlineMetadataBrowser/` | Shared online metadata window shell, source picker, embedded web view, virtualized list |
| `MusicBrainzBrowser/` | MusicBrainz search/detail/tagging views and stores |
| `iTunesBrowser/` | iTunes search/detail/tagging views and stores |
| `LRCLIBLyricsBrowser/` | LRCLIB lyrics views and store |
| `MetadataInspector/` | Raw metadata dump sheet |
| `Settings/` | Settings tabs, privacy/acknowledgements/license sheets, release notes rendering |
| `Welcome/` | Welcome splash and progress |

Feature folders may contain their own helpers. Do not create a shared abstraction for a single feature.

## `AudioMator/Infrastructure`

Concrete integrations and adapters.

| Folder | Responsibility |
| --- | --- |
| `TagLib/` | Metadata pipeline adapter, `AudioFile` loading, conflict resolver |
| `FileSystem/` | Watched-folder/bookmark stores, directory monitor |
| `GitHub/` | Release-notes client |
| `iTunes/` | Search API client, artwork service, provider cores |
| `LRCLIB/` | Request builder, client, models, ranker |
| `MusicBrainz/` | Client, query builder, link parser, matching, models, scheduling |
| `OnlineMetadata/` | Cross-provider selection core |
| `Updates/` | Semantic version, latest-release client, update checker/presenter |

## `Config`

Target configuration inputs that must stay outside the synchronized source root:

- `Info.plist` — bundle fields, version references, category, copyright.
- `AudioMator.entitlements` — sandbox, user-selected read/write, network client.

## `AudioMatorTests`

App-hosted XCTest bundle (438 test functions at audit time) organized by failure semantics:

```text
Application/{MetadataEditing,MetadataExchange,Rename,WatchedFolders}
Concurrency/
Integration/{Network,TagLib}
Performance/
Unit/{Core,Presentation}
TestSupport/
Fixtures/
```

`Fixtures/Audio` contains the committed mp3/m4a/flac/aac/ogg/wav samples; `Fixtures/MetadataExchange` contains exchange fixtures; `Fixtures/Artwork` contains the cover image. Tests copy audio fixtures before writing.

## `Tests`

`Tests/AudioMatorCoreLogicTests` is the SwiftPM fast suite (61 test functions at audit time). It has no UI, TagLib, or live-network dependency.

## `scripts`

| Script | Purpose |
| --- | --- |
| `codex-build.sh` | Incremental or forced Debug generic macOS build; prunes extra derived data/app bundles |
| `prune-app-bundles.sh` | Removes non-canonical `.deriveddata*` directories and app bundles |
| `validate-macos-artifact.sh` | Checks bundle minimum OS and every Mach-O platform/minimum |
| `build-taglib-bridge-smoke.sh` | Builds the bridge smoke executable from package/bridge sources |
| `taglib_bridge_smoke.mm` | Smoke tool source |

## `Docs`

The documentation set. See [the index](../README.md). `Docs/Images` contains README images. Historical engineering records are under `Docs/Engineering/HISTORY`.

## Where to Add Code

| Change | Location |
| --- | --- |
| New app command or lifecycle behavior | `AudioMator/App` |
| New metadata field or edit rule | `Domain/AudioFiles`, `Domain/MetadataEditing` |
| New container behavior | `Infrastructure/TagLib` adapter plus package work (external) |
| New provider | `Infrastructure/<Provider>` and `Features/<Provider>Browser` |
| New main-window UI | `Features/Main` |
| New conversion mode | `Domain/MetadataExchange` and `Features/MetadataFilenameTool` |
| New test | Matching `AudioMatorTests` directory; pure logic in `Tests/AudioMatorCoreLogicTests` |
| New build setting | `AudioMator.xcodeproj` and `Docs/Reference/CONFIGURATION.md` |
| New license or attribution | `Core/Legal/LicenseDisclosure.swift`, `Resources/Licenses`, in-app Acknowledgements, and `Docs/THIRD_PARTY_NOTICES.md` |

## Related Documents

- [Configuration](CONFIGURATION.md)
- [Architecture Overview](../Architecture/OVERVIEW.md)
- [Build](../Development/BUILD.md)
