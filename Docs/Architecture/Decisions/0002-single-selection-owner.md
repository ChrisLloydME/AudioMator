# ADR 0002: AudioViewModel is the single selection owner

- Status: Accepted
- Date: 2026-07-25
- Amended: 2026-09-18 (iPadOS product removed)
- Amended: 2026-11-19 (F3 detached pending-review draft session)

## Context

At the time of the decision, `SharedState.selectedAudioIDs` bound the macOS/iPad lists while `AudioViewModel.selectedAudioIDs` drove draft and save behavior. `ContentPane` and the former iPad workspace copied changes between them with `onChange`/`onAppear`, so a missing or reordered callback could leave presentation selection and mutation targets different. The iPadOS product was later removed; the single-owner invariant still applies to macOS.

## Decision

`AudioViewModel` exclusively owns selected file IDs. `setSelectedAudioIDs` intersects requested IDs with the visible file collection and rebuilds the single/multi-file draft in the same main-actor operation. Rebuilding the visible collection prunes selection and updates the draft when selected files disappear. Views receive a guarded binding to this owner; `SharedState` retains only sidebar choice, ordering, and persisted presentation preferences.

The F3 remediation keeps this invariant and adds a **detached Inspector pending-review draft session**. When a dirty draft's captured targets disappear from every source membership (passive watch/import prune or an intentional removal that did not first discard the draft), selection still prunes exactly as above, but the draft payload, captured baselines and completed-target ledger are retained by `AudioViewModel` as a pending review outside the selection set. Save is suspended until every captured target is available again and the user explicitly resumes, or the user discards the review. Values are never transferred to surviving or new targets. A deliberate selection change, sidebar change, Inspector hide, explicit reload or confirmed removal still passes through the existing discard decision; a confirmation response is revalidated against the specific draft session/generation that displayed it.

## Alternatives

- **Keep selection only in SharedState:** rejected because mutation and draft invariants would still depend on a separate generic presentation store and require injection through every application use case.
- **Introduce a third SelectionStore:** rejected because it adds identity and lifecycle without reducing the number of owners required by the current single-window session model.
- **Keep bidirectional mirroring:** rejected because callback ordering is the defect being removed.

## Consequences

- Selection, mutation targets, and inspector draft share one source of truth.
- Unknown or no-longer-visible IDs cannot remain selected.
- File removal and source changes prune selection without view lifecycle callbacks.
- Selection changes that may discard a draft still pass through `ContentView` confirmation before calling the owner.
- A pruned dirty draft is retained as a detached pending review, not as unknown selected IDs; selection membership keeps its visible-only filter.

## Verification

- App-hosted tests cover unknown-ID filtering, single/multi draft transitions, selected-file removal, and clear-list pruning.
- macOS inspector workflow tests verify the remaining product consumer.
