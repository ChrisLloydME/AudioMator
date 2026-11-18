# AudioMator accumulated-code cleanup implementation plan

Date: 2026-11-17. Status: proposed work, not an implementation or acceptance claim. Repository scope: AudioMator only. This plan covers accumulated iteration debris across the whole application, not merely compatibility with old package releases.

## 1. Objective and boundaries

Remove obsolete application APIs, unreachable implementations, redundant forwarding layers, duplicated policies, superseded flows, stale state and abandoned configuration introduced by successive feature patches. Leave each surviving responsibility with a clear owner and a demonstrated production entry point. Preserve supported user workflows, stored user data and the metadata integrity contract. Do not substitute a large rewrite, a new universal framework or a file-count reduction target for this work.

The inspected starting point was clean `main` at `9453434e`. Re-read current HEAD, AGENTS.md and current documentation before implementation; this is a navigation baseline, not a requirement to reset to that revision. The published dependency is exact TagLibAudioMetadata 0.8.1, revision `b8ed5475761cb50bacdd7dcd4f6e2f61142303d0`, mapping contract `AM-TLAM-MAPPING-2.2`. Keep that dependency and the checksum-pinned binary unchanged.

The latest 0.8.1 adoption record establishes Debug acceptance at its recorded source, not Release acceptance of today's main or the cleanup branch. Historical 0.8.0 Release results are not current evidence. Recent main also includes operation-result/HUD changes; include those paths in the audit rather than limiting the campaign to old metadata adapters.

Do not enter, inspect, patch, build or commit a sibling package checkout or resolved-source/cache tree. Normal Xcode remote dependency resolution and compilation are allowed. Do not create a local-package override. If a package defect is suspected, preserve the failing evidence, provide a minimal application reproduction and proposed package-only regression, and stop that affected repair; continue independent application work. Do not hide it behind a raw write or a different package revision.

## 2. What qualifies for removal

Classify each candidate before editing:

| Decision | Required evidence and action |
| --- | --- |
| Delete: unreachable | No production entry point after examining direct references, SwiftUI bindings, selectors, notifications, resources, reflection/string lookup, build membership and conditional configurations. Tests alone are not a production use. Remove obsolete test scaffolding only after preserving any distinct behavior it covered. |
| Delete: old internal API compatibility | Exists only to keep removed/older application or package signatures compiling. Migrate all current callers and test doubles to the selected current interface, then remove the wrapper/alias. AudioMator does not promise compatibility for its internal Swift symbols. |
| Merge: duplicate responsibility | Two paths implement the same intended contract. Enumerate differences, choose the actual owner, migrate callers, preserve every required behavior, and remove the losing implementation in the same completed slice. |
| Simplify: active but over-layered | A live abstraction adds no policy or meaningful boundary. Prove that removing it does not erase validation, isolation, cancellation, ownership, error or transaction semantics. |
| Retain: active behavior or protection | Record its current consumer and invariant. A compatibility-sounding name is not a deletion reason. |
| Investigate: insufficient evidence | Identify exactly what is unknown and the smallest way to resolve it. Do not mark it dead, silently skip it or claim the entire campaign complete while a material item is unresolved. |

A grep miss, compiler success, old comment, misleading name or passing unrelated suite is insufficient proof of death. Conversely, a helper called only by a compatibility test is not justified merely because that test exists. Trace why the test exists and move its meaningful assertions to the retained real path.

Explicitly distinguish **compatibility with old internal APIs**, which can be removed, from **support for old user files/data**, which remains supported unless the maintainer requests a product change. This includes ID3 versions, private numbering provenance, CSV profiles, preferences, bookmarks and previously saved settings.

## 3. Mandatory whole-application audit inventory

Create one row per source/configuration/test-support file in the agreed tracked scope, with owner, reviewed status, candidate IDs and disposition. Review all of `AudioMator/App`, `Core`, `Domain`, `Features`, `Infrastructure`, app tests, the selected SwiftPM sources/tests, Xcode project/scheme, Config, scripts and CI. Resources require a focused reference/build-membership review, not a blanket deletion sweep. Historical engineering prose is not a code-cleanup target.

Use a second candidate ledger with: ID; file/symbol; suspected origin; current production callers; test-only callers; dynamic/resource/build entry points; old/new behavior differences; chosen owner; delete/merge/simplify/retain/investigate decision; evidence; replacement caller path; tests and assertions; commit; outcome. Include retained candidates so the report does not selectively display easy deletions.

Audit these areas explicitly:

1. **App composition and state:** duplicate selection ownership, shadow copies of drafts, competing loading/error/save flags, stale notification/observer lifetimes, redundant shared-state facades, old command routes, abandoned settings toggles. `AudioViewModel` remains the single selection owner. Do not combine different state lifetimes merely because their properties have similar names.
2. **Feature flows:** Inspector, Metadata Editor, Filename & Metadata, provider browsers/workbench, batch operations, settings/welcome/help. Trace active actions through plan capture, reservations, execution, refresh and result presentation. Find superseded action handlers and alternate routes still kept alive by forwarding layers.
3. **Metadata domain/infrastructure:** overlapping payload builders, scalar/raw-array representations, validation performed only on some routes, duplicate number/date interpretation, obsolete package wrappers, error/status conversions, old manual cleanup orchestration, dead conversion helpers.
4. **Providers and search:** app query types versus provider query types, duplicated query building/normalization, old clients or fallback chains, paging/restart state, cancellation ownership, discarded result adapters. Similar MusicBrainz/iTunes/LRCLIB code may reflect genuinely different contracts; do not force them into one generic provider abstraction.
5. **File sources and mutation:** watched-folder/quick-import reconciliation, bookmarks/security scopes, reload/fingerprint paths, selection preservation, rename/renumber/conversion coordination. Keep late-result and revision protections.
6. **Results, issues and HUD:** overlapping summary/result types, compatibility aliases, duplicate success/failure counting, parallel warning/error formatting and stale presentation state. Preserve committed-but-durability-uncertain and post-commit-refresh-failed distinctions; do not label a committed write as unsaved merely to simplify the result model.
7. **Core/platform/resources:** old deployment/toolchain branches, duplicate string/date/number helpers, stale localized keys and help entries, asset references, abandoned configuration keys. Distinguish an obsolete code branch from still-required observer cleanup or persisted-key migration.
8. **Tests/build/scripts:** old fakes maintaining obsolete APIs, parallel adapters that bypass real behavior, source-shape snapshot tests that freeze dead wrappers, obsolete fixtures, unused target membership, stale SwiftPM source lists, redundant gate scripts. Do not weaken evidence policy or delete historical failure fixtures just to reduce counts.

Every area needs a disposition. Do not stop after cleaning the TagLib adapter or the first few obvious typealiases. For a large area, make several small slices and continue until the audit inventory is complete. Avoid arbitrary line-deletion quotas.

## 4. Concrete navigation leads from the inspected source

These are hypotheses to verify, **not pre-approved deletions or confirmed defects**.

| Lead | Inspection and decision required |
| --- | --- |
| `Infrastructure/TagLib/TagLibAudioMetadataPipeline.swift`: two `metadataPatchForWrite` overloads | The pure builder is used by conflict resolution/tests; the throwing overload also checks unsupported advisory imports, while `url` and `expectedVersion` appear unused inside it. Trace both paths. Prefer one explicit validation/encoding policy with necessary entry-point differences documented. Removing the throwing wrapper must not drop advisory rejection; making a test helper the canonical path must not bypass production validation. Preserve efficient pure planning where needed. |
| `Domain/MetadataEditing/AudioMetadataPipeline.swift` and concrete pipeline | Inventory protocol requirements, extension defaults and concrete overloads, including scalar raw maps, value maps, full-map-to-delta conversion and no-version convenience writes. Compare concrete and existential dispatch. Remove old internal convenience surfaces when no production policy requires them; migrate callers and fakes together. Guarded writes must never fall back to unguarded overloads. A raw value map, exact raw delta and display string map have different semantics and cannot be merged blindly. |
| `TagLibAudioMetadataPipeline.interpretingWrite` and commit-result conversions | A high-level package API returning a commit status does not prove a throwing durability path is dead for every remaining public writer. Trace track-text and other call boundaries before removing catches or status variants. Preserve committed-versus-not-committed reporting and prevent blind retry. |
| `Features/Main/ViewModels/BatchMetadataOperationSummary.swift`: `BatchMetadataWriteSummary` alias | Trace all current references and inspect why the alias remains. If it only forwards the former internal name, migrate callers and remove it. Keep richer operation outcome/status semantics and ordered summaries. |
| `Infrastructure/MusicBrainz/MusicBrainzLuceneQueryBuilder.swift` and `MusicBrainzProviderLuceneQueryBuilder.swift` | Determine whether the first is a genuinely needed app-to-provider boundary or a historical forwarding facade. Compare escaping, ordering, preferred/fallback query sequences and every current consumer before consolidating. Do not change network request behavior under a cleanup label. |
| `AudioFile+TagLibLoading.swift`, `TagLibNumberingProjection.swift` | The numbering projection uses package-classified inventory and canonical authority, distinguishes ambiguity and does not write on import. This is not dead merely because 0.8.1 owns recovery on save. Inspect the `try?` inventory read, snapshot-version match and post-AVFoundation version check separately; do not replace explicit uncertainty with guessed values or suppress meaningful failures. |
| `TagLibDateNativeProjection.swift`, conflict resolver, date helpers | Native identities prevent YEAR/DATE alias collisions and preserve array/precision/conflict intent. Do not replace these protections with scalar Basic values just because a package snapshot exists. Consolidation needs equivalent native-identity evidence. Remove only demonstrably redundant layers or stale internal aliases. |
| `MetadataExchangeCSV.swift`, `MetadataExchangePlanning.swift` | CSV v1 DATE meaning, v2 field/removal semantics and unknown-version rejection are persisted user-data behavior. Keep these unless a separately approved product migration exists. Internal obsolete wrapper names may still be removed. |
| `legacyTagCompatibilityNotes`, AVFoundation credits fallback, read retry | ID3v1 diagnostics and display-only credits fallback can be live product behavior. One retry after a read revision change is not equivalent to retrying a commit. Verify consumers; do not delete based on the words legacy/fallback/retry. |
| `OnlineMetadataVirtualizedList.swift`: Xcode 16.4 comment | The comment may be stale. Determine whether code serves current observer cleanup/lifetime requirements. Removing a stale comment is not proof that cleanup behavior is obsolete. |
| Existing source-structure assertions, including `OnlineMetadataPlanSnapshotTests` | Some tests name implementation files/types. When an implementation legitimately disappears, retain its real behavioral assertions through the replacement path. Do not keep a zombie type solely to satisfy a source-text assertion, or delete all tests that reference the old file. |

Search beyond these leads. In particular, Core split files are sometimes intentional Foundation-only shared compilation units rather than duplicates.

## 5. Invariants that must survive every slice

- YEAR, standalone DATE, RELEASEDATE and ORIGINALDATE remain independent. A year of 2004 and release date in 2017 is valid. No derivation, synchronization, truncation, companion writes or clearing of unedited dates.
- Correct typed patch kinds for supported fields; no generic stringification of booleans/integers, especially store IDs. Preserve absent, unknown, explicit zero, empty text and remove as distinct states where the contract distinguishes them. Advisory 0/1/2 and unset retain their documented meanings; unknown advisory provenance is preserved on unrelated edits and unsupported assignment is rejected.
- Preserve multivalue arrays, duplicates, whitespace/raw intent and opaque owners on unrelated edits. A joined display string is not a lossless raw value map.
- Track/disc number and total are independent first-class intent. With 0.8.1, edited-group recovery/retirement is package-owned; import remains read-only. Canonical values stay authoritative, ambiguity is never guessed, explicit clear/zero cannot be resurrected from old private fields, and the unedited group is preserved. Do not add a storage-policy picker or reimplement native retirement in the application.
- Semantic capability preflight applies to the exact selected fields and actual destination. Raw editing is the explicit lower-level path, not a silent fallback for semantic failure. Qualified/unsupported/read-only fields stay gated.
- All mutations use `FileMutationCoordinator` and the existing pipeline. Keep revision/audio continuity guards, target identity, reservation lifetime and stale-version rejection; no commit retries, clearing versions or substituting similar files.
- Provider preview/checkbox selections become immutable execution plans. Only captured, selected fields are written; unchecked fields remain unchanged. Preserve cancellation boundaries, bounded in-flight work, late-result rejection and input-order summaries.
- Inspector/Editor dirty state compares semantic drafts to the correct baseline. Import/recovery or successful save/reload must not manufacture dirty state; actual failed drafts remain available. Preserve arrays, independent dates, total-only pairs and explicit clears.
- Preserve security scopes/bookmarks, watched-folder generations, import cancellation, settings persistence and localization. Do not invalidate existing user data as a shortcut.
- Keep current architecture, strict concurrency and MainActor isolation. No direct container I/O in views/Domain, blanket isolation suppression, new singleton or generic replacement framework.

## 6. Implementation phases and exit gates

### Phase 0 — Establish the real baseline

Read AGENTS.md, commit-message contract, architecture/state/mutation/testing documents and the 0.8.1 adoption record. Record branch/HEAD, status, exact remote lock and toolchain. Create a new branch such as `codex/audiomator-legacy-cleanup-20261117`; never implement on main. Preserve user changes. These handoff plan/prompt files may be untracked: preserve them and include them in a documentation commit on the new branch; their presence alone is not a reason to abandon the task. Do not restore/reset unrelated dirty files.

Run policy and core tests, then the canonical Debug test lane using `bash scripts/validate-release.sh --tests-only`. Derive current test inventory from current sources and gate output; 62 core/596 app in the adoption record is historical evidence, not a fixed requirement for current main. Record all baseline failures/warnings without reclassifying them as green.

Exit: reproducible baseline, new branch, safe working tree handling, complete audit scope and initial candidate ledger. No mass deletion yet.

### Phase 1 — Trace ownership and choose consolidation slices

Enumerate all files and candidates. For each major operation, sketch the production path: UI command → captured input/draft → plan/validation → coordinator → pipeline → completion/reload → state/HUD. Include provider search, import/watch and settings flows, not only writes. Identify which objects own each state lifetime.

Order slices by evidence and risk: proven-dead symbols/configuration; internal aliases and test-only compatibility surfaces; duplicate pure conversions/query facades; divergent metadata validation; feature/state/result consolidation. Risky state/async changes must not ride along with a low-risk alias removal.

Exit: every intended deletion has a decision and replacement/retention proof. Differences between implementations are listed rather than silently treated as equivalent.

### Phase 2 — Remove proven debris in small completed slices

For each slice: capture the old behavior that matters; add or select a targeted behavioral regression where necessary; migrate production callers; migrate fakes/tests; remove the obsolete implementation; update target/resource/source-list membership; compile the app and run appropriate tests; update the ledger and commit. Complete caller migration and deletion together—do not leave both old and new implementations active as the purported finished result.

Do not write trivial tests that assert a private symbol is absent or mirror a new helper. Use source checks only for genuine architecture, inventory and build-boundary rules. For renames, retain test identity when behavior is unchanged. Changing a file/type referenced by a source-snapshot test requires a reasoned replacement of its structural claim plus preservation of behavioral coverage.

Exit per slice: one owner, no stale references, relevant real behavior passes, no unsupported fallback, reviewable commit.

### Phase 3 — Consolidate live policy and state carefully

When two implementations differ, establish the intended contract from current product behavior, normative metadata rules and reproducible tests. Choose a canonical owner within the existing architecture. Do not prefer a shorter implementation that drops validation. Keep separate APIs when they intentionally represent different intent, data fidelity or lifetimes.

For discovered functional defects, add a focused reproducer and fix them in separate `fix:` commits. Capture pre-fix failure when feasible; otherwise explicitly state source-inferred status. A baseline test failure does not automatically prove a production defect. Never change expected values simply because the new implementation produces different output.

Exit: changed policies are explicit, intentional differences are retained, each real defect has a demonstrated regression, and no competing active path remains for the same responsibility.

### Phase 4 — Validate through actual application entry points

The minimum matrix in section 7 is mandatory for changed responsibilities. Pure-helper tests and fake-only tests cannot establish saving correctness. Use application-owned temporary fixture copies through the real `TagLibAudioMetadataPipeline`, current published remote dependency, production plan/coordinator boundaries and actual reloads.

When testing provider actions, stub transport/provider responses but retain the production selection, plan capture and file-write layers. Real network traffic is unnecessary. For native ownership checks, use existing independent app test readers where available; package write plus package read is useful consistency evidence, not an independent native oracle. Add only small necessary native checks; do not duplicate the package's entire mapping registry/parser.

For central modified routes, perform bounded sensitivity checks against the actual retained tests: temporarily omit the real write call or alter selected-field/clear handling and confirm the named required test fails at the intended disk/state assertion. Compile errors, zero executed tests and unrelated failures do not count. Save/restore only the controlled files and verify byte hashes before/after; never use broad reset/clean or patch the dependency. Two representative checks are sufficient if they match the changed risks; do not build a separate probe harness or an unrelated mutation-testing platform. If only proven-dead symbols are removed, explain which existing live-route controls still prove behavior instead of inventing a meaningless mutation quota.

Exit: real I/O and state assertions demonstrate the retained implementation, not merely an adapter label, expected count, or successful mock response.

### Phase 5 — Finalize coverage and automated acceptance

Reconcile the file audit and candidate ledger. Every file must be reviewed, and every material candidate must be deleted/merged/simplified or explicitly retained with current evidence. Do not claim completion with an unexplained “later” bucket. A bounded external blocker can remain only if clearly separated from completed scope and reported as incomplete where it affects acceptance.

Run full `bash scripts/validate-release.sh` on a stable source tree through the normal project. This includes policy, core, full serial app tests, Release build and artifact validation. Never use `--local-package`. Where changed platform/resource/build handling warrants it, validate an unsigned archive under `.deriveddata-codex`; signing/publication are out of scope.

Counts alone are insufficient. Require the source-declared test identity sets, critical named tests, zero unexpected skips/failures and actual command exit statuses. If obsolete API tests legitimately disappear, map each removed assertion/behavior to retained replacement tests in the ledger, then update the inventory/policy transparently. Do not lower a floor or remove critical tests merely to accept missing execution.

Update current documentation for changed architecture/contracts and add a dated cleanup record, not a wholesale historical-document rewrite. Run `git diff --check`, verify changed Markdown links and run `python3 scripts/check-commit-messages.py --range origin/main..HEAD`. If the range already contains unrelated violations, report and distinguish them; do not rewrite origin/main or claim success. Keep new commits compliant.

Exit: clean/reviewable source state; complete audit and migration record; accepted automated gates tied to the exact tested source; documentation-only follow-ups clearly identified; no package/pin changes; no generated output committed. Do not push, open/merge PRs, tag, publish or manually launch the application.

## 7. Required behavior matrix for changed paths

| Area | Required positive and negative evidence |
| --- | --- |
| Patch planning/dispatch | Actual caller → retained validator/encoder; valid input yields exact selected typed fields; unsupported advisory/kinds reject before write; concrete and existential calls agree; deleted compatibility route is no longer required by fakes. |
| Dates/native owners | YEAR 2004 with a distinct release date; sparse/malformed/multivalue dates survive unrelated edits; independent date edit/clear does not alter siblings; conflict comparison uses actual native identities. |
| Numbers/provenance | Native-only, private-only, mixed/contradictory, total-only, ambiguous and explicit-clear layouts; read-only import; edited track/disc migration, untouched sibling group; stale revisions reject; no false Inspector dirty state after recovery/reload. |
| Provider writes | MusicBrainz/iTunes captured selected fields, unchecked preservation, valid integer IDs and rejection of invalid ones, single/batch writes, selection changes after capture, cancellation and out-of-order completions. |
| Inspector/Editor | Untouched open/close remains clean, real edit becomes dirty, revert becomes clean, successful save/reload resets correct baselines, failed save retains drafts, arrays/clear/zero intent survive. |
| Conflict/transaction | Exact stale version and unavailable audio identity behavior; no fallback commit; same-file serialization/reservations, external metadata changes, post-commit refresh failure and durability uncertainty remain distinguishable. |
| Raw editor/exchange | Exact arrays and unknown owners; explicit removal versus unedited; scalar display not used to reconstruct lossless values; CSV v1/v2 and removal semantics, unknown-version rejection, rename/renumber preserved. |
| Provider query consolidation | Literal escaping, Unicode/empty inputs, query order/filter behavior, mode transitions, restart/pagination and stale response rejection. No unintended extra request or shared mutable state. |
| Source/state/HUD | Selection owner unchanged; watched-folder/quick-import cancellation and ordering; warnings versus failures versus committed-but-refresh-failed outcomes; accurate per-file totals, stable input order and presentation lifecycle. |
| Resource/config cleanup | Removed resource is truly unreferenced and not a persisted identity; app and test builds still include required files, acknowledgements/privacy/localization remain accurate, SwiftPM core subset still compiles. |

Existing starting suites include `AutomaticNumberRecoveryTests`, `MetadataSaveJourneyTests`, `MetadataBoundaryMatrixTests`, `TagLibMappingContractIntegrationTests`, `TagLibUpgradeContractTests`, `InspectorDirtyStateTests`, `InspectorAndMetadataEditorWorkflowTests`, `MetadataEditorStoreTests`, `FileRevisionConflictTests`, `MetadataConflictStrategyTests`, `ProviderTaggingCancellationTests`, `BatchMetadataOperationSummaryTests`, query/paging/network-fault suites, watched-folder/import suites and Metadata Exchange suites. Resolve their current paths and inventories; names may evolve. Never substitute only the core SwiftPM subset for the app module.

## 8. Tooling and honest evidence

Use stable Xcode at `/Applications/Xcode.app`. All Xcode builds use `.deriveddata-codex`; app-hosted tests are serial (`-parallel-testing-enabled NO -maximum-parallel-testing-workers 1`). Internal ACP/Xcode build/test tools may be used if actually exposed; discover their documented capabilities. Do not invent tool names, claim unexecuted shell gates or equate an internal build-success message with a full test result. Retrieve diagnostics, exact executed tests and completion status. Use the canonical shell gate when available; if the host lacks it, say exactly which acceptance requirement cannot be established.

Caches/Library sandbox failures require an authorized rerun with proper access, not production-code edits. A host blocker is not a pass. Do not add warnings suppression, test gating, `XCTSkip`, expected failures, broad `try?`, swallowed exceptions, synthetic green summaries or reduced inventories to finish the campaign. Distinguish baseline warnings, new warnings, product defects and evidence defects.

If reporting performance, use an unchanged workload, configuration, metadata density and correctness assertions with before/after measurements. This is not a concurrency or performance redesign; do not remove safeguards for speed or assert a speedup from fewer lines. Large performance work gets a separate proposal.

## 9. Deliverables and reporting contract

1. New implementation branch, baseline identity and scoped status.
2. Whole-application file audit and candidate/decision/migration ledger.
3. Meaningful incremental commits following `type(scope): imperative summary`, lowercase imperative, at most 72 characters; omit invented scopes. Do not amend published history.
4. Targeted reproductions and real-entry-point regressions for substantive changes; transparent test migration map.
5. Exact final commands/tool actions, source revision/hash, normal dependency lock, executed test identities/counts, exit statuses, warning/skip inventory and ignored evidence locations.
6. Dated English engineering record and updated matching current guidance. Keep build outputs, `.tmp`, `.xcresult`, archives and personal state ignored.
7. Final summary separating removed debris, retained compatibility/product behavior, fixed actual defects, unresolved blockers and unexecuted verification. Report remaining material duplication honestly, not as completion because some files were deleted.

The final statement must say either “automated cleanup acceptance passed for <revision>” with evidence, or “not accepted/blocked” with exact reasons. Manual UI, signing, notarization and actual distribution are not established by this campaign. The application must not be launched interactively.
