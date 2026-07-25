# ADR 0003: Separate metadata contract from TagLib adapters

- Status: Accepted
- Date: 2026-07-25

## Context

`AudioMetadataPipeline.swift` mixed the application-facing payload and protocol with 800+ lines of TagLib writes, verification, compatibility cleanup, and error translation. `AudioFile.swift` similarly mixed the immutable snapshot model with TagLib, AVFoundation, CoreMedia, and platform image construction. This made the physical Domain boundary contradict the documented dependency direction and caused an actor-isolation warning when a value-copy helper called the model initializer.

## Decision

- Keep `MetadataEditPayload`, `AudioMetadataWriteResult`, and `AudioMetadataPipeline` in `Domain/MetadataEditing`.
- Move the concrete implementation to `Infrastructure/TagLib/TagLibAudioMetadataPipeline.swift`.
- Keep the immutable `AudioFile` value and copy helpers in Domain with a nonisolated memberwise initializer.
- Move async TagLib/AVFoundation loading and native artwork construction to `Infrastructure/TagLib/AudioFile+TagLibLoading.swift`.
- Keep `PlatformImage?` on the snapshot for now. Inspector and artwork bindings consume the decoded native image directly; replacing it with data would spread decoding and lifecycle work without improving the metadata contract.
- Do not add another Swift module in this batch. Disk boundaries, dependency rules, and app-hosted integration tests provide the intended control with lower project risk.

## Consequences

Domain no longer imports TagLib, AVFoundation, CoreMedia, AppKit, or UIKit for `AudioFile` or the pipeline contract. Concrete adapter construction remains at the app composition root. Real format behavior still requires app-hosted TagLib tests; SwiftPM remains a fast pure-logic sensor rather than pretending to cover platform adapters.
