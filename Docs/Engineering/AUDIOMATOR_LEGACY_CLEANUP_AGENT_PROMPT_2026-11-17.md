# Startup prompt — AudioMator accumulated-code cleanup

Copy the following prompt into the third-party agent running in this AudioMator repository.

---

You are implementing a whole-application cleanup in AudioMator. You have access only to this repository. Your task is to remove accumulated dead code, obsolete internal APIs, redundant layers, duplicated policies/state and abandoned build/test scaffolding left by successive iterations. Package API migration is only one source of this debris; do not limit the audit to TagLib integration.

Read these first:

- `AGENTS.md` and `Docs/Development/COMMIT_MESSAGES.md`.
- `Docs/Engineering/AUDIOMATOR_LEGACY_CLEANUP_PLAN_2026-11-17.md` — the full implementation and acceptance contract for this task.
- `Docs/Architecture/OVERVIEW.md`, `Docs/Architecture/DEPENDENCY_RULES.md`, `Docs/Architecture/STATE_AND_MUTATION_MODEL.md`, `Docs/Architecture/METADATA_PIPELINE.md` and `Docs/Architecture/METADATA_MAPPING_SPEC.md`.
- `Docs/Development/TESTING.md`, `Docs/Development/METADATA_TEST_STRATEGY.md` and `Docs/Development/DOCUMENTATION.md`.
- `Docs/Engineering/TAGLIB_081_DEBUG_ADOPTION_2026-11-17.md` for dated evidence, not a current-tree release verdict.

Execute the plan; do not respond with another plan or stop after an inventory. Create a new branch such as `codex/audiomator-legacy-cleanup-20261117` from the current checked-out baseline, record its actual revision/status, and keep working through small verified commits. Do not reset to the plan's inspection hash or modify main. The supplied plan/prompt files may be untracked handoff documents: preserve and include them in your documentation commit on the new branch. Preserve unrelated user edits and do not revert them.

The dependency is exact published TagLibAudioMetadata 0.8.1, revision `b8ed5475761cb50bacdd7dcd4f6e2f61142303d0`; keep it unchanged. Do not enter/inspect/patch/build a sibling package checkout, package cache or resolved-source tree. Normal Xcode dependency resolution is allowed. No local override, package-source copy, vendor code, dependency downgrade or raw-write fallback is permitted. A suspected package defect requires a minimal app reproduction and package-owner regression recommendation; stop that affected repair instead of hiding it, and continue independent app cleanup.

Your first implementation deliverables are a baseline and two ledgers: every tracked source/config/test-support file in scope, and each cleanup candidate's callers, dynamic/build/resource references, decision, behavioral differences, replacement owner, tests and commit. Cover App, all Core/Domain/Infrastructure/Features, state and async lifetimes, providers, Inspector/Editor, watched folders/import, rename/renumber/exchange, operation summaries/HUD/error handling, resources/configuration and test/build infrastructure. “No candidates found” requires inspected evidence. Do not finish after one adapter or several typealias removals.

A candidate can be deleted, merged, simplified, retained with evidence, or investigated. A missing grep hit, old name or successful build does not prove dead code. Inspect SwiftUI, selector/notification, resource, conditional-target and test-only entry points. Tests that solely keep an obsolete internal wrapper alive do not justify that wrapper. Move meaningful behavioral assertions to the retained real path before deleting obsolete scaffolding. Do not lower coverage to match deletions.

Current leads to verify, not blindly delete:

1. Two `metadataPatchForWrite` paths in `TagLibAudioMetadataPipeline`: the throwing path checks unsupported advisory imports, while URL/version parameters appear unused. Consolidate policy without losing that validation or forcing unsafe planning/writes.
2. Protocol defaults/concrete overloads in `AudioMetadataPipeline`: scalar raw maps, exact array maps, deltas, no-version convenience writes and existential dispatch. Migrate genuine obsolete internal surfaces and fakes; preserve distinct fidelity/guard contracts.
3. `BatchMetadataWriteSummary` alias and overlapping operation result/HUD representations. Remove historical names where justified, not richer committed/error semantics.
4. MusicBrainz app/provider query builders and DTO forwarding. Compare escaping, filters, order and current consumers before choosing one owner. Avoid a new generic provider framework.
5. Number/date projections, loading fallbacks and retry paths: these may be current safety/product behavior, not garbage. Investigate them before deciding.
6. Source-structure snapshot tests and old test doubles may pin obsolete files/types. Replace legitimate structural claims and preserve actual behavior tests rather than retaining zombies to keep source-text checks green.

Keep old **internal API** compatibility separate from old **user-file/data** support. CSV v1/v2 semantics, ID3 versions, bookmarks/preferences, AVFoundation display-only credits, ID3v1 diagnostics and 0.8.1 numbering recovery may remain necessary. Import must not write files. Canonical numbering is authoritative, ambiguous provenance cannot be guessed, explicit clear/zero must not resurrect private totals, and only the edited group migrates. Do not reintroduce an application storage-policy UI or native alias-retirement implementation.

Preserve the four independent date identities; YEAR 2004 with release date in 2017 is valid. Preserve typed values, advisory unknown/unset/0/1/2, raw arrays, duplicates, opaque owners and unchecked provider fields. Keep captured selection plans, draft/dirty-state lifetimes, cancellation/generation checks, bounded scheduling and ordered outcomes. All disk mutations remain under `FileMutationCoordinator` and the pipeline. Never drop expected versions, downgrade guarded calls, retry commits or replace targets by resemblance. Read retry is a different policy. `AudioViewModel` remains the selection owner; strict concurrency and actor isolation remain enabled.

Work in one small completed slice at a time: establish meaningful before-behavior, migrate current production callers and fakes, remove the old implementation, update target/resource membership, compile, run relevant tests, update the ledger, commit. Do not leave a parallel implementation or deprecated forwarding wrapper as the final fix. When merging live implementations, enumerate their differences before selecting the contract. Separate actual defect fixes from behavior-preserving refactors and capture a pre-fix regression when possible. Never regenerate expectations from the implementation's new output just to make it pass.

Verification must exercise real production paths. For write changes, use fresh application-repository fixture copies through the real adapter/coordinator, captured provider plans and actual file reload; mock only remote transport where appropriate. Include independent native/untouched-owner/audio assertions where existing app readers support them. Test concrete and existential protocol behavior where dispatch changes. A helper-only test, fake success result, test name, adapter label or declaration count is not proof that a save occurred. For central route changes, carry out the bounded actual-test sensitivity checks in the plan; restored source hashes and intended named failures are required. Do not build an alternate probe harness to claim formal tests detect a defect.

Use the existing suites for save journeys, mapping boundaries, independent dates/number totals, automatic recovery, Inspector/Editor state, conflict/revision handling, providers/cancellation, queries, watched folders, result/HUD and exchange. Resolve current inventory rather than hardcoding the old 596-test adoption count. Retain all relevant failure and preservation assertions when moving/deleting tests. Never add skips, expected failures, conditional passes, exception swallowing or synthetic evidence to make the branch green.

Use stable `/Applications/Xcode.app`, `.deriveddata-codex` for every Xcode build and serial app-hosted testing. ACP/Xcode Code Intelligence build/test tools can be used only if actually exposed; discover real capabilities and retrieve real diagnostics/completion/test identities. Do not invent tools or claim shell gates you could not run. Shell canonical commands, when available:

```sh
python3 -m unittest discover -s scripts/tests
swift test --filter AudioMatorCoreLogicTests
bash scripts/validate-release.sh --tests-only
# Final normal-project acceptance, after the complete cleanup:
bash scripts/validate-release.sh
git diff --check
python3 scripts/check-commit-messages.py --range origin/main..HEAD
```

Read the complete plan for phase exits, behavior matrix and exact evidence policy. Run focused checks after slices; run the full final gate once the source is stable. If environment/tool restrictions block a required check, state that exact limitation and do not label the branch accepted. A baseline failure is not a pass and is not automatically a production defect. Preserve new warning/error distinctions. No interactive application launch, UI automation, live provider calls, push, PR, merge, tag or publication.

Commit as you work: `type(scope): imperative summary`, lowercase imperative, whole subject at most 72 characters, no final period or invented scope. Follow the complete local contract. Do not rewrite published history. Update matching current documentation and one dated cleanup record, without rewriting the historical archive or collecting generated outputs in Git.

Finish only when the whole agreed audit is complete, proven debris is removed/consolidated, retained behavior has explicit justification and the normal automated acceptance passes on the recorded source—or report exact unresolved blockers and incomplete scope. Your final response must distinguish removed debris, retained data compatibility/protections, actual fixed bugs, deleted-test replacement coverage, test/tool execution, unexecuted checks, warning/skip counts, exact tested commit/dependency and evidence paths. A deletion total or an impressive inventory alone is not completion.

Start now with repository status, baseline/branch creation and the complete audit ledger, then implement the verified cleanup slices through acceptance.
