# Dependency Rules

These rules define allowed dependencies between source areas. They are enforced
by code review, the SwiftPM source list, and the app-hosted test target.

## Allowed Direction

```text
App composition
  └─ Features / application use cases
       ├─ Domain contracts and values
       ├─ Core support
       └─ injected Infrastructure adapters

Infrastructure adapters
  ├─ Domain contracts and values
  └─ Core support

Domain
  ├─ Foundation
  ├─ Core pure support
  └─ TagLibAudioMetadata semantic types (documented exception)
```

| Layer | May depend on | Must not depend on |
| --- | --- | --- |
| `App` | Everything, for composition only | Business logic implementations |
| `Features` | Domain, Core, Infrastructure protocols/types, SwiftUI/AppKit | Direct TagLib manager calls, container format code, owning file transactions |
| `Domain` | Foundation, pure `Core`, package semantic types | SwiftUI, AppKit, Combine, URLSession, concrete TagLib managers, file transactions |
| `Infrastructure` | Domain, Core, system frameworks, package APIs | Feature views or view models |
| `Core` | Foundation and focused system frameworks | Feature, Domain, or Infrastructure types (pure Core files must stay Foundation-only) |

## The Metadata Contract Exception

Domain reuses stable semantic types from `TagLibAudioMetadata`:

- `MetadataFieldKey` — field capability and identity,
- `MetadataFileVersion` — opaque transaction revision,
- `MetadataSnapshot` — read-only conflict/raw baseline supplied by the adapter,
- `RawMetadataPatch` — exact raw delta.

This keeps one contract for field capabilities, revisions, and raw edits across
the boundary. It is a controlled package-contract dependency, not a claim that
Domain is package-independent.

Still forbidden in Domain:

- calling `TagLibMetadataManager`,
- constructing `MetadataSnapshot`, `MetadataPatch`, or structured format values,
- reading or writing files,
- owning atomic commit or verification behavior.

The concrete adapter and all loading/commit code stay in
`Infrastructure/TagLib`. This is recorded in
[ADR 0003](Decisions/0003-metadata-contract-and-taglib-adapter.md).

## Platform Boundaries

- AppKit/SwiftUI belong in App, Features, or focused adapters — not Domain.
- AVFoundation and CoreMedia fallbacks belong in the TagLib loading adapter.
- Artwork `Data` is stored on the sendable snapshot; `NSImage` decoding stays in
  MainActor presentation code.
- Metadata, rename, exchange, and renumber rules must remain UI-framework
  independent.

## Mutation Boundaries

- UI may submit explicit mutation input and consume results; it must not write
  TagLib metadata or move files directly.
- Every disk mutation goes through `FileMutationCoordinator`.
- Semantic writes preflight the exact requested fields. The raw editor is the
  documented low-level exception.
- Reload after a successful write belongs to the same mutation ownership scope.
  Snapshot replacement happens on the main actor.
- After a rename, a failed full reload must recover fingerprint and revision; if
  either fails, the snapshot is refresh-required and writes fail closed.
- Results must distinguish: not written, written and refreshed, written but not
  refreshed, partial batch, cancelled, manual recovery required.

## SwiftPM Fast Target

`Package.swift` defines `AudioMatorCoreLogic` as a **selected-source test
harness**, not a production module consumed by the app.

- It compiles an explicit list of 30 Foundation-only production files.
- It excludes all UI, AppKit, SwiftUI, Combine, TagLib, networking, file system,
  update, and app-client code.
- The app target remains authoritative.

A file added to the fast target must not import AppKit, SwiftUI, Combine,
TagLibAudioMetadata, or a network API. If a pure helper is extracted from an
app-only file, add it to the source list deliberately and test it.

## Enforcement and Review

- A new cross-layer import must state the caller, the coupling it replaces, and
  the independent test benefit.
- A new protocol must have a real second implementation or a test seam; do not
  add abstraction for a single feature without evidence.
- `AudioFile` may hold a native artwork snapshot defined by `Core/Platform` to
  avoid repeated decoding, but TagLib/AVFoundation/AppKit construction stays in
  Infrastructure.
- App-hosted tests cover adapters, real `AudioFile` loading, TagLib writes, the
  file system, and main-actor orchestration.
- SwiftPM tests cover deterministic, dependency-light policy.

## UI Framework Policy

The project uses SwiftUI for most UI and AppKit where it produces a more complete
native result, reduces complexity, or improves performance. There is no rule
requiring one framework everywhere. The constraints are:

- keep state ownership in view models or domain state,
- do not hide authoritative state inside a view,
- do not add feature singletons,
- use `String(localized:)` for user-facing strings,
- do not add `print`, `debugPrint`, or `NSLog` diagnostics to app code.

## Related Documents

- [Architecture Overview](OVERVIEW.md)
- [ADR 0001: write/reload reservation](Decisions/0001-atomic-write-and-reload-reservation.md)
- [ADR 0002: single selection owner](Decisions/0002-single-selection-owner.md)
- [ADR 0003: metadata contract and TagLib adapter](Decisions/0003-metadata-contract-and-taglib-adapter.md)
- [ADR 0004: metadata exchange boundaries](Decisions/0004-metadata-exchange-responsibility-boundaries.md)
