# ADR 0002: AudioViewModel is the single selection owner

- Status: Accepted and implemented
- Date: 2026-07-25

## Context

`SharedState.selectedAudioIDs` bound the macOS/iPad lists while `AudioViewModel.selectedAudioIDs` drove draft and save behavior. `ContentPane` and `IPadWorkspaceView` copied changes between them with `onChange`/`onAppear`, so a missing or reordered callback could leave presentation selection and mutation targets different.

## Decision

`AudioViewModel` exclusively owns selected file IDs. `setSelectedAudioIDs` intersects requested IDs with the visible file collection and rebuilds the single/multi-file draft in the same main-actor operation. Rebuilding the visible collection prunes selection and updates the draft when selected files disappear. Views receive a guarded binding to this owner; `SharedState` retains sidebar choice, ordering and persisted presentation preferences only.

## Alternatives

- **Keep selection in SharedState only**：rejected because mutation and draft invariants would still depend on a separate generic presentation store and require injection through every application use case.
- **Introduce a third SelectionStore object**：rejected because it adds identity and lifecycle without reducing the number of owners needed by the current single-window session model.
- **Retain bidirectional mirroring**：rejected because callback ordering is the defect being removed.

## Consequences

- Selection, mutation targets and inspector draft share one source of truth.
- Unknown or no-longer-visible IDs cannot remain selected.
- File removal and source changes prune selection without view lifecycle callbacks.
- Selection changes that may discard a draft still pass through `ContentView` confirmation before calling the owner.

## Verification

- App-hosted test covers unknown-ID filtering, single/multi draft transitions, selected-file removal and clear-list pruning.
- macOS inspector workflow tests and generic iOS compile verify both platform consumers.
