# ADR 0003: Separate metadata contract from TagLib adapters

- Status: Accepted
- Date: 2026-07-25
- Amended: 2026-09-22

## Context

`AudioMetadataPipeline.swift` mixed the application-facing payload and protocol with 800+ lines of TagLib writes, verification, compatibility cleanup, and error translation. `AudioFile.swift` similarly mixed the immutable snapshot model with TagLib, AVFoundation, CoreMedia, and platform image construction. This made the physical Domain boundary contradict the documented dependency direction and caused an actor-isolation warning when a value-copy helper called the model initializer.

## Decision

- Keep `MetadataEditPayload`, `AudioMetadataWriteResult`, and `AudioMetadataPipeline` in `Domain/MetadataEditing`.
- Move the concrete implementation to `Infrastructure/TagLib/TagLibAudioMetadataPipeline.swift`.
- Keep the immutable `AudioFile` value and copy helpers in Domain with a nonisolated memberwise initializer.
- Move async TagLib/AVFoundation loading and native artwork construction to `Infrastructure/TagLib/AudioFile+TagLibLoading.swift`.
- Store immutable artwork `Data` on the sendable snapshot. Decode `NSImage` only in the MainActor presentation extension so AppKit objects do not cross concurrency boundaries.
- Do not add another Swift module in this batch. Disk boundaries, dependency rules, and app-hosted integration tests provide the intended control with lower project risk.
- Retain the package's `MetadataFieldKey`, `MetadataFileVersion`, and
  `RawMetadataPatch` as shared semantic contract types. They keep field
  capabilities, transaction revisions, and exact raw deltas aligned across the
  boundary. Domain must not call concrete TagLib managers or own container and
  filesystem transaction behavior.

## Consequences

Domain no longer imports AVFoundation, CoreMedia, or AppKit for `AudioFile` or
the pipeline contract. It does import `TagLibAudioMetadata` for the three shared
semantic types named above; this is a controlled package-contract dependency,
not an isolated app-owned domain module. Concrete TagLib I/O remains in
Infrastructure and adapter construction remains at the app composition root.
Real format behavior still requires app-hosted TagLib tests; SwiftPM remains a
selected-source fast sensor rather than pretending to compile the production
app module.
