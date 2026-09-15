# Metadata Architecture Maintenance Progress

Last updated: 2026-09-15

## Scope

This journal tracks AudioMator-side work for the coordinated metadata correctness and architecture review. TagLibAudioMetadata remains an independent product and has its own journal in that repository.

## Current findings

- AudioMator currently declares TagLibAudioMetadata `upToNextMinorVersion` from `0.4.5`; `Package.resolved` selects version `0.4.5` at revision `107e7d7b1a4148fe4b3aa9845a296b4934b1a790`.
- The sibling TagLibAudioMetadata checkout is not automatically used by Xcode and contains newer snapshot/patch APIs absent from the resolved release.
- `TagLibAudioMetadataPipeline.writeMetadata` currently performs the ordinary metadata write before `MetadataPipelineSupport.writeContentAdvisory`, so one user save can span independently committed mutations.
- The compatibility metadata object is populated through `edit.isExplicit`, which collapses the four-state advisory model before a follow-up advisory correction.
- The pipeline still owns app-side MP4-like classification and property-map/advisory cleanup behavior.

## Confirmed hypotheses

- Investigation target 1: confirmed at source level; the current save path has multiple mutation stages.
- Investigation target 2: confirmed at source level; the main compatibility write receives a Boolean advisory projection before the typed state is repaired later.
- Dependency coordination: confirmed; the application is on released package 0.4.5, not the sibling checkout.

## Pending verification

- Characterize partial-failure behavior and existing fault-injection seams.
- Trace raw metadata storage and editing end to end for lossiness and whole-map reconstruction.
- Trace edit-session concurrency tokens and timeout behavior.
- Verify AVFoundation overrides, remaining format checks, WAV behavior, and documentation claims.
- Select and implement the package release/revision integration strategy after package work passes tests.

## Architectural direction

- AudioMator should construct semantic edits and delegate container representation plus atomic commit to TagLibAudioMetadata.
- Do not introduce new container-specific behavior in AudioMator while migrating.
- Preserve user-file compatibility and explicitly distinguish package defects from application workarounds.

## Completed tasks

- Established clean `main` baseline and current dependency resolution.
- Created this durable journal before substantive refactoring.

## Tests and validation

- Not yet run for this maintenance series.

## Commits

- Pending.

