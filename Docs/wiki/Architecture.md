# Architecture

AudioMator uses a layered source layout: App for entry points and system integration, Core for shared foundation code, Domain for testable business logic, Infrastructure for file-system and service integrations, and Features for user-facing workflows and feature-owned view models.

## App Entry

`AudioMator/App/AudioMatorApp.swift` is the `@main` entry. It creates a `TagLibAudioMetadataPipeline` and injects that pipeline into the main `AudioViewModel` and `MetadataEditorStore`. It also creates shared UI state and stores for MusicBrainz, LRCLIB lyrics, filename/metadata tooling, and metadata editing.

On macOS, the app declares the main window, Settings window, Online Metadata window, Filename & Metadata window, and Metadata Editor window. It also registers app info, sidebar, toolbar edit, and view layout commands. On iPadOS, it uses a single `WindowGroup`.

## Metadata Pipeline

Metadata writes are routed through the app metadata pipeline and `AudioViewModel` write extensions. UI code should not directly write container-specific metadata.

Track and disc values are structured, not just raw strings. `AudioTagNumberPair` and `AudioTagNumberText` preserve numeric intent and user-facing text intent. The write layer then handles container-specific behavior for ID3v2, PropertyMap-style formats, and MP4/M4A where supported.

## Domain Layer

`AudioMator/Domain/` contains business logic and models that can be tested with fewer UI or service dependencies:

- `AudioFiles`: audio file models, fingerprints, and merged metadata policy.
- `FileSources`: current-session and watched-folder source models.
- `MetadataEditing`: text editing pipeline and file mutation coordination.
- `MetadataExchange`: TXT/CSV parsing, serialization, and metadata exchange cores.
- `MuseAmp`: deterministic comment ID generation.
- `Rename`: rename templates, filename metadata extraction, and rename plans.
- `TrackRenumber`: track renumbering options, planning, failures, warnings, and results.
- `UIState`: toolbar options, list columns, inspector fields, and shared state models.

## Infrastructure Layer

`AudioMator/Infrastructure/` contains external integrations:

- `FileSystem`: directory monitoring and watched-folder persistence.
- `GitHub`: GitHub release-note request logic.
- `iTunes`: iTunes Search API, artwork lookup, and provider core logic.
- `LRCLIB`: lyrics request construction, models, and candidate ranking.
- `MusicBrainz`: search, link parsing, query construction, result models, matching, and client code.
- `OnlineMetadata`: cross-provider selection core.
- `Updates`: semantic version comparison, GitHub release update checks, and macOS presentation.

Network-backed features should remain explicit and user initiated.

## Features Layer

`AudioMator/Features/` is organized by user-facing workflow:

- `Main`: main window, sidebar, center list, inspector, track renumbering, and main view model.
- `MetadataEditor`: advanced metadata editor window and table views.
- `MetadataFilenameTool`: filename/metadata conversion.
- `OnlineMetadataBrowser`: shared Online Metadata window shell and source picker.
- `MusicBrainzBrowser`, `iTunesBrowser`, `LRCLIBLyricsBrowser`: provider-specific online workflows hosted by the shared entry point.
- `MetadataInspector`, `Settings`, `Welcome`, and `iPad`: raw inspection, settings, welcome screens, and iPad workspace.

## File Mutation Coordination

`AudioMator/Domain/MetadataEditing/FileMutationCoordinator.swift` coordinates file mutations. Its source comment notes that a rename transaction cannot overlap metadata writes to the same source or destination. New write paths should reuse the existing coordination model instead of introducing independent concurrent file mutations.

## Testability Boundary

`Package.swift` defines an `AudioMatorCoreLogic` SwiftPM target containing selected non-UI, non-TagLib, non-network files. Fast tests cover rename logic, filename metadata matching, metadata exchange, LRCLIB request/ranking, iTunes request normalization, MusicBrainz provider helpers, fuzzy matching, MuseAmp ID generation, audio format policy, file collection ordering, merged metadata policy, duplicate detection, and artwork replacement decisions.

TagLib integration, UI behavior, network clients, and full app orchestration are covered outside the fast SwiftPM target through app-hosted Xcode tests and build checks.
