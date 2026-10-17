# ADR 0002: AudioViewModel is the single selection owner

- Status: Accepted
- Date: 2026-07-25
- Amended: 2026-09-18 (iPadOS product removed)

## Context

At the time of the decision, `SharedState.selectedAudioIDs` bound the macOS/iPad
lists while `AudioViewModel.selectedAudioIDs` drove draft and save behavior.
`ContentPane` and the former iPad workspace copied changes between them with
`onChange`/`onAppear`, so a missing or reordered callback could leave presentation
selection and mutation targets different. The iPadOS product was later removed;
the single-owner invariant still applies to macOS.

## Decision

`AudioViewModel` exclusively owns selected file IDs. `setSelectedAudioIDs`
intersects requested IDs with the visible file collection and rebuilds the
single/multi-file draft in the same main-actor operation. Rebuilding the visible
collection prunes selection and updates the draft when selected files disappear.
Views receive a guarded binding to this owner; `SharedState` retains only sidebar
choice, ordering, and persisted presentation preferences.

## Alternatives

- **Keep selection only in SharedState:** rejected because mutation and draft
  invariants would still depend on a separate generic presentation store and
  require injection through every application use case.
- **Introduce a third SelectionStore:** rejected because it adds identity and
  lifecycle without reducing the number of owners required by the current
  single-window session model.
- **Keep bidirectional mirroring:** rejected because callback ordering is the
  defect being removed.

## Consequences

- Selection, mutation targets, and inspector draft share one source of truth.
- Unknown or no-longer-visible IDs cannot remain selected.
- File removal and source changes prune selection without view lifecycle
  callbacks.
- Selection changes that may discard a draft still pass through `ContentView`
  confirmation before calling the owner.

## Verification

- App-hosted tests cover unknown-ID filtering, single/multi draft transitions,
  selected-file removal, and clear-list pruning.
- macOS inspector workflow tests verify the remaining product consumer.
