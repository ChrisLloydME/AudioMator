# AudioMator legacy cleanup ledger

Date: 2026-11-18. Status: dated engineering record, not a current behavior contract. Branch: `codex/audiomator-legacy-cleanup-20261117`. Baseline: `origin/main` at `f36c2a2e` (2026-11-17). Code-complete revision at the final automated gate: `28fe62a6`. This record is the consolidated whole-application audit and candidate/migration ledger for the accumulated-code cleanup campaign described in [the cleanup plan](AUDIOMATOR_LEGACY_CLEANUP_PLAN_2026-11-17.md). It is evidence for what was audited, decided, removed, retained or deferred; current guidance for the surviving implementation lives in the current-state documentation set.

Related records: [automated acceptance record](AUDIOMATOR_LEGACY_CLEANUP_ACCEPTANCE_2026-11-18.md), [cleanup plan](AUDIOMATOR_LEGACY_CLEANUP_PLAN_2026-11-17.md), [agent handoff prompt](AUDIOMATOR_LEGACY_CLEANUP_AGENT_PROMPT_2026-11-17.md), and [Engineering Notes index](README.md). The plan and prompt are preserved handoff documents from 2026-11-17 and are not current behavior contracts.

## 1. Campaign identity, scope and method

| Item | Value |
| --- | --- |
| Repository | AudioMator (this repository only) |
| Baseline | `origin/main` `f36c2a2e` (2026-11-17); worktree clean except the two untracked handoff documents |
| Branch | `codex/audiomator-legacy-cleanup-20261117` |
| Code-complete revision | `28fe62a6` (2026-11-18) |
| Branch commits | 27 commits relative to `origin/main` at the code-complete revision. The handoff brief stated 28; `git rev-list --count origin/main..HEAD` reports 27. This record uses the repository value; the documentation commit will add a further commit after this record. |
| Dependency | Published `TagLibAudioMetadata` 0.8.1, revision `b8ed5475761cb50bacdd7dcd4f6e2f61142303d0`; mapping contract `AM-TLAM-MAPPING-2.2`; unchanged by the campaign |
| Audit evidence | Seven read-only audit reports under `.tmp/cleanup/audit-{app-core,domain,infrastructure,providers,features-main,features-editor,tests-build}.md` (2026-11-18, baseline `f36c2a2e`), plus targeted source traces on the branch. `.tmp/` is git-ignored and not part of the committed record; this ledger normalizes their file and candidate tables. |
| Automated evidence | `.deriveddata-codex/Validation/20261118-104501-44211/` — policy, core, app-hosted, Release build and artifact phases; final gate `EXIT:0`. See the acceptance record for the exact commands and results. |
| Scope | All tracked files in the agreed scope: `AudioMator/**` (186), `AudioMatorTests/**` (106), `Tests/AudioMatorCoreLogicTests/**` (3), `Config/**` (2), `AudioMator.xcodeproj/**` (5), `Package.swift`, `scripts/**` (10) and `.github/**` (1): 314 tracked files. |

Method: each audit built a file ledger with one row per tracked file in its area, traced each candidate from declaration to the whole tracked tree (production callers, app-hosted and SwiftPM tests, SwiftUI/AppKit bindings and selectors, notifications, resource and localization lookups, build membership and configuration), and separated obsolete internal Swift API compatibility from persisted user-data compatibility. The campaign then implemented proven debris in small commits with callers and tests migrated together. This ledger merges the seven file ledgers, normalizes their candidate IDs, and records the campaign outcome for every candidate. `retain` means the audit found a current consumer or protection; `deferred` means the audit proposed a change that this campaign did not schedule, with the reason recorded in §7.

Honest boundaries: (a) the audits are source-inspection evidence, not runtime evidence; (b) the external `TagLibAudioMetadata` checkout, cache and resolved sources were never entered, so package-internal behavior questions remain investigate items; (c) UI interaction, signing, notarization and distribution were not tested; (d) the branch contains 27 commits, not the 28 named in the handoff brief; (e) the candidate ledger records deferred work explicitly rather than claiming that every audited candidate was resolved.

### 1.1 Campaign effect at the code-complete revision

| Measure | Value |
| --- | --- |
| Commits on the branch | 27 relative to `origin/main` at `28fe62a6` |
| Files changed | 117 (108 modified, 8 deleted, 1 added) |
| Lines changed | +3,046 / −8,544 across all changed files (includes the 5,663-line localization-catalog prune and its re-serialization) |
| Production app source, excluding `Localizable.xcstrings` | +363 / −2,355 lines across 77 app files (the added persistence file is 190 lines) |
| App-hosted tests | +566 / −445 lines across 37 test files |
| SwiftPM core tests | +41 / −41 lines in one file; test count stays 62 |
| Package manifest | +1 / −38 lines (31-file source list to 30; 41 excludes to 5) |
| Tracked files deleted | 8: `AppIconPreview.imageset/AppIconPreview.png`, `AppIconPreview.imageset/Contents.json`, `Domain/FileSources/FileCollectionCore.swift`, `Features/Main/ViewModels/AudioViewModel+MetadataFieldImportWrite.swift`, `Features/Main/Views/InspectorPopup.swift`, `Features/Main/Views/MergedMetadataSectionView.swift`, `Features/Main/Views/MiddleListHeaderContextMenuInstaller.swift`, `Features/MetadataInspector/Views/MetadataInspectorSheet.swift` |
| Tracked files added | 1: `Infrastructure/FileSystem/BookmarkCollectionPersistence.swift` |
| App-hosted test inventory | 622 source-declared tests / 80 classes at baseline → 629 / 80 at the code-complete revision |
| Core test inventory | 62 tests / 4 classes throughout; two helpers removed and two replacement core tests added in `88d971b1` |
| Policy tests | 13 throughout |
| Localization catalog | 952 keys and 6 locale slots at baseline → 861 keys at the code-complete revision (91 keys pruned; locale slots and translations retained) |
| Dependency | `TagLibAudioMetadata` 0.8.1 / `b8ed5475761cb50bacdd7dcd4f6e2f61142303d0` unchanged; no local-package override |


## 2. Whole-application file audit

One row per tracked file in the agreed scope (314 rows: 186 `AudioMator/`, 106 `AudioMatorTests/`, 3 `Tests/`, 2 `Config/`, 5 `AudioMator.xcodeproj/`, 10 `scripts/`, 1 `.github/`, and `Package.swift`). The responsibility column is the audit one-line responsibility; candidate IDs are the audit IDs from §3; disposition is the campaign outcome. `Delete` rows are files removed by the campaign. A file marked `Retain` can still contain implemented candidate work; the exact candidate outcomes are in §3. Files added by the campaign are noted as added.

| Area | Files |
| --- | ---: |
| App composition | 7 |
| Core support | 16 |
| Domain | 28 |
| Infrastructure | 34 |
| Features | 87 |
| Resources, localization and legal | 14 |
| Configuration | 2 |
| Xcode project and scheme | 5 |
| Build manifest | 1 |
| Scripts | 10 |
| CI | 1 |
| App-hosted tests: Application/MetadataEditing | 15 |
| App-hosted tests: Application/MetadataExchange | 4 |
| App-hosted tests: Application/Rename | 4 |
| App-hosted tests: Application/WatchedFolders | 4 |
| App-hosted tests: Concurrency | 3 |
| App-hosted tests: Integration/Network | 5 |
| App-hosted tests: Integration/TagLib | 10 |
| App-hosted tests: Performance | 4 |
| App-hosted tests: Unit/Core | 18 |
| App-hosted tests: Unit/Presentation | 11 |
| App-hosted tests: root and support | 5 |
| App-hosted tests: fixtures | 23 |
| SwiftPM core tests | 3 |
| **Total** | **314** |

### 2.1 App composition

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMator/App/AppDelegate.swift` | First-launch 900×600 sizing/centering + terminate-on-last-window | APP-01, APP-R02 | Retain; 1 open investigate (§5); 1 retained (§4). |
| `AudioMator/App/AppNotifications.swift` | 10 cross-window notification names | APP-R03 | Retain; 1 retained (§4). |
| `AudioMator/App/AudioMatorApp.swift` | Only composition root: 6 scenes, pipeline/store injection, commands, test-host isolation | APP-01 | Retain; 1 open investigate (§5). |
| `AudioMator/App/AudioMatorTestHost.swift` | Debug/test-only host detection, isolated preferences, weak diagnostics | APP-R01 | Retain; 1 retained (§4). |
| `AudioMator/App/Commands/AppInfoCommands.swift` | About route into Settings + Check for Updates menu | — | Retain; no candidate change. |
| `AudioMator/App/Commands/ToolbarEditCommands.swift` | Edit/menu commands; shared `performAddWatchedFolders` seam used by tests | — | Retain; no candidate change. |
| `AudioMator/App/Commands/ViewLayoutCommands.swift` | Toggle Inspector command | — | Retain; no candidate change. |
### 2.2 Core support

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMator/Core/Artwork/ArtworkImageNormalizer.swift` | Artwork size/pixel validation → PNG normalization (background + URL/data entry points) | — | Retain; no candidate change. |
| `AudioMator/Core/Audio/AudioFormatSupport.swift` | TagLib capability snapshot → app extension sets, writable fields, panel UTIs | CORE-R03 | Retain; 1 deferred (§3, §7). |
| `AudioMator/Core/Audio/AudioFormatSupportCore.swift` | Foundation-only capability snapshot builder shared with SwiftPM tests | CORE-R03 | Retain; 1 deferred (§3, §7). |
| `AudioMator/Core/Audio/AudioNumericConversion.swift` | Rounded/clamped numeric conversion, bounded distance, saturating sums | — | Retain; no candidate change. |
| `AudioMator/Core/Audio/AudioTagNumberPair.swift` | Number/total pair text: display components, canonical raw text, replace/make | — | Retain; no candidate change. |
| `AudioMator/Core/Audio/AudioTagNumberText.swift` | Number/total text parsing, validation, write-expectation check | CORE-05 | Retain; touched by `e58fa61f`; 1 candidate(s) implemented (§3). |
| `AudioMator/Core/Audio/MetadataDateTextCore.swift` | Foundation-only plausibility checks for independent date identities | CORE-R04 | Retain; 1 deferred (§3, §7). |
| `AudioMator/Core/Audio/MetadataDateTextFieldSupport.swift` | Package-field-keyed date validation extension (keeps TagLib out of Core) | CORE-R04 | Retain; 1 deferred (§3, §7). |
| `AudioMator/Core/Concurrency/AsyncOperationDeadline.swift` | Non-cooperative async timeout with first-outcome-wins resolution | — | Retain; no candidate change. |
| `AudioMator/Core/FileSystem/FileSystemPathSemantics.swift` | Canonical path identity: symlink resolution, unicode, volume-aware case folding | — | Retain; no candidate change. |
| `AudioMator/Core/Legal/LicenseDisclosure.swift` | License inventory + bundled text loading for Acknowledgements | RES-R01 | Retain; 1 retained (§4). |
| `AudioMator/Core/Localization/L10n.swift` | `L10n.string` wrapper, window-title table, `localizedUI` sugar | CORE-01, CORE-09, CORE-R01 | Retain; touched by `e58fa61f`; 1 candidate(s) implemented (§3); 2 deferred (§3, §7). |
| `AudioMator/Core/Network/GitHubAPIRequest.swift` | GitHub API headers (Accept/version/User-Agent) | — | Retain; no candidate change. |
| `AudioMator/Core/Network/NetworkServiceDisclosure.swift` | Network disclosure registry (hosts, sent data, purposes) | — | Retain; no candidate change. |
| `AudioMator/Core/Platform/MacPlatformSupport.swift` | macOS-only adapters: availability wrappers, window chrome, pasteboard/workspace/pickers, security scope | CORE-02, CORE-03, CORE-04, CORE-06, CORE-07 | Retain; touched by `e58fa61f`; 3 candidate(s) implemented (§3); 2 deferred (§3, §7). |
| `AudioMator/Core/Text/FuzzyStringSimilarity.swift` | Fuzzy matching for provider candidate ranking | — | Retain; no candidate change. |
### 2.3 Domain

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMator/Domain/AudioFiles/AudioFile.swift` | Immutable loaded snapshot: editable tags, independent dates, container values, number inventory, technical/artwork data, fingerprint/version/baseline, row-cont… | DOM-20, DOM-21, DOM-22 | Retain; touched by `f1ff0892`, `2af7fb70`; 1 candidate(s) implemented (§3). |
| `AudioMator/Domain/AudioFiles/AudioFileFingerprint.swift` | Path/size/mtime/device/inode revision guard + validation error messages | — | Retain; no candidate change. |
| `AudioMator/Domain/AudioFiles/AudioMetadataModelCore.swift` | Merged-display helper + duplicate-key helper + artwork replacement decision helper | DOM-08, DOM-09 | Retain; touched by `88d971b1`; 2 candidate(s) implemented (§3). |
| `AudioMator/Domain/AudioFiles/ContainerMetadataField.swift` | Typed `ContainerFieldValue` + MP4-exclusive catalog (26 fields, presentations, registry-derived shapes) | — | Retain; no candidate change. |
| `AudioMator/Domain/AudioFiles/MergedAudioFile.swift` | Merged display projection for multi-selection Inspector | DOM-16 | Retain; touched by `3d3b458f`; 1 candidate(s) implemented (§3). |
| `AudioMator/Domain/AudioFiles/SingleFileEditModel+MetadataPipeline.swift` | `MetadataEditPayload` builders (changed-field diff vs baseline, container patch, artwork intent) | DOM-07 | Retain; 1 deferred (§3, §7). |
| `AudioMator/Domain/AudioFiles/SingleFileEditModel.swift` | Single-file and multi-file draft state, number-pair field projection, dirty-state comparison | DOM-18, DOM-20 | Retain; touched by `623ed1d8`, `2af7fb70`; 2 candidate(s) implemented (§3). |
| `AudioMator/Domain/FileSources/FileCollectionCore.swift` | Pure import sorting/dedupe merge/album grouping + `CoreAudioFileReference` | DOM-10 | Delete: removed in `88d971b1` (refactor(core): remove unused extracted and unwired helpers). |
| `AudioMator/Domain/FileSources/FileMutationDirectoryAccessPlan.swift` | Compute directories needing security-scope access for a mutation | DOM-17 | Retain; touched by `623ed1d8`; 1 candidate(s) implemented (§3). |
| `AudioMator/Domain/FileSources/FileSourceModels.swift` | Source mode/sidebar selection, persisted bookmark records, grants, authorization outcome | DOM-16, DOM-29 | Retain; touched by `3d3b458f`; 1 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Domain/MetadataEditing/AudioMetadataPipeline.swift` | Pipeline protocol, payload/validation value types, commit status/result, convenience extension methods | DOM-01, DOM-07, DOM-12, DOM-23, DOM-24, DOM-25 | Retain; touched by `ae07d55f`, `f1ff0892`, `fde7ecb7`, `97016668`, `2af7fb70`; 2 candidate(s) implemented (§3); 1 deferred (§3, §7); 3 retained (§4). |
| `AudioMator/Domain/MetadataEditing/FileMutationCoordinator.swift` | Normalized-path mutation reservation with starvation-safe waiter scheduling and cancellation | DOM-17, DOM-25 | Retain; touched by `623ed1d8`; 1 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Domain/MetadataEditing/MetadataConflictBaseline.swift` | Exact raw/structured/year/audio-identity baseline from the read that produced the editable snapshot | — | Retain; no candidate change. |
| `AudioMator/Domain/MetadataEditing/MetadataConflictPolicy.swift` | Four conflict policies + persisted `metadata.conflictPolicy` loading | DOM-30 | Retain; 1 retained (§4). |
| `AudioMator/Domain/MetadataEditing/TextEditPipeline.swift` | Text find/replace/case/trim pipeline and step model | — | Retain; no candidate change. |
| `AudioMator/Domain/MetadataExchange/MetadataExchangeCSV.swift` | Versioned profile marker, removal token/sentinel, CSV parse/serialize, export budget, locator index | DOM-27 | Retain; 1 retained (§4). |
| `AudioMator/Domain/MetadataExchange/MetadataExchangeModels.swift` | Converter modes, exchange field schema/projections/validation/import application | DOM-12, DOM-19, DOM-26, DOM-31 | Retain; touched by `623ed1d8`; 2 candidate(s) implemented (§3); 2 retained (§4). |
| `AudioMator/Domain/MetadataExchange/MetadataExchangePlanning.swift` | Export/import plans, validation, locator matching, template rendering/matching, CSV planning | DOM-26, DOM-27, DOM-33 | Retain; 3 retained (§4). |
| `AudioMator/Domain/MetadataExchange/MetadataExchangeTemplate.swift` | Map `{{placeholder}}` tokens to typed exchange fields, preserve unknown placeholders as literals | DOM-11 | Retain; touched by `623ed1d8`; 1 candidate(s) implemented (§3). |
| `AudioMator/Domain/MetadataExchange/MetadataExchangeTemplateSyntax.swift` | Foundation-only `{{…}}` tokenizer | DOM-13 | Retain; 1 candidate(s) implemented (§3). |
| `AudioMator/Domain/MetadataExchange/MetadataFieldTransfer.swift` | Copy/cut field-to-field plan with independent number components | DOM-33 | Retain; 1 retained (§4). |
| `AudioMator/Domain/MuseAmp/MuseAmpCommentIDGenerator.swift` | Stable numeric album/track IDs embedded in the comment JSON + feature `UserDefaults` key | DOM-28 | Retain; 1 retained (§4). |
| `AudioMator/Domain/Rename/FileRenamePlanCore.swift` | Pure rename status enum + collision/existing-file resolution | DOM-14 | Retain; touched by `623ed1d8`; 1 candidate(s) implemented (§3). |
| `AudioMator/Domain/Rename/FileRenameTemplate.swift` | Rename template document/rendering/sanitize/collision preview plan | DOM-14, DOM-16, DOM-21 | Retain; touched by `3d3b458f`, `623ed1d8`; 2 candidate(s) implemented (§3). |
| `AudioMator/Domain/Rename/FileRenameTemplateCore.swift` | Rename template parser, sanitizer, fixed replacement options | DOM-13, DOM-15 | Retain; touched by `623ed1d8`; 2 candidate(s) implemented (§3). |
| `AudioMator/Domain/Rename/FilenameMetadataExtractionCore.swift` | Filename→metadata backtracking matcher + field extraction rules | DOM-32 | Retain; 1 retained (§4). |
| `AudioMator/Domain/Rename/FilenameMetadataTemplate.swift` | Filename→metadata extraction plan, change status, preview/write entries | DOM-16, DOM-21, DOM-32 | Retain; touched by `3d3b458f`; 1 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Domain/TrackRenumber/TrackRenumber.swift` | Renumber direction/options/clamps/pad width/result types | DOM-34 | Retain; 1 retained (§4). |
### 2.4 Infrastructure

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMator/Infrastructure/FileSystem/BookmarkCollectionLoadState.swift` | Shared load-state enum for watched-folder and file-access-grant bookmark collections (`.notLoaded`, `.empty`, `.loaded(recordCount:)`, `.corrupt`). | INF-22 | Retain; touched by `c3425cb7`; 1 candidate(s) implemented (§3). |
| `AudioMator/Infrastructure/FileSystem/DirectoryMonitor.swift` | Bounded `DirectoryMonitoringPlan`, observable `DirectoryMonitoringStatus` messages, and the `DispatchSourceFileSystemObject` directory watcher (open/close/canc… | INF-23, INF-24 | Retain; touched by `6ce7f020`; 1 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Infrastructure/FileSystem/FileAccessGrantStore.swift` | Persistent security-scoped bookmark store for file-access grants: load/resolve/refresh/stale-refresh, corrupt quarantine, unresolved-record preservation, save. | INF-21 | Retain; touched by `c3425cb7`; 1 candidate(s) implemented (§3). |
| `AudioMator/Infrastructure/FileSystem/WatchedFolderStore.swift` | Persistent security-scoped bookmark store for watched folders; same load/resolve/quarantine/save contract as FileAccessGrantStore. | INF-21 | Retain; touched by `c3425cb7`; 1 candidate(s) implemented (§3). |
| `AudioMator/Infrastructure/GitHub/GitHubReleaseNotesClient.swift` | GitHub release-notes HTTP client used by the About → Release Notes sheet; audited as retained in the settings track (SET-05) | — | Retain; no candidate change. |
| `AudioMator/Infrastructure/LRCLIB/LRCLIBCandidateRanker.swift` | Lyrics candidate scoring/ranking and auto-apply threshold | LRC-2 | Retain; 1 retained (§4). |
| `AudioMator/Infrastructure/LRCLIB/LRCLIBClient.swift` | LRCLIB search HTTP client + test-visible request builder seam | LRC-2 | Retain; 1 retained (§4). |
| `AudioMator/Infrastructure/LRCLIB/LRCLIBModels.swift` | LRCLIB query/candidate/error models + client protocol | LRC-2 | Retain; 1 retained (§4). |
| `AudioMator/Infrastructure/LRCLIB/LRCLIBRequestBuilder.swift` | LRCLIB request URL/header construction | LRC-2 | Retain; 1 retained (§4). |
| `AudioMator/Infrastructure/MusicBrainz/MusicBrainzClient.swift` | HTTP client: request build, DTO decode, cache/rate-limit/retry, search+detail orchestration and multi-file fallback order | MBC-1, MBC-2, MBC-3 | Retain; 1 deferred (§3, §7); 2 retained (§4). |
| `AudioMator/Infrastructure/MusicBrainz/MusicBrainzFilenameFallback.swift` | Filename/parent-directory fallback search input used by iTunes/LRCLIB seed paths | — | Retain; no candidate change. |
| `AudioMator/Infrastructure/MusicBrainz/MusicBrainzLinkParser.swift` | App-facing link parser adapter: host policy from disclosure + maps provider error to app error | MBQ-3 | Retain; 1 retained (§4). |
| `AudioMator/Infrastructure/MusicBrainz/MusicBrainzLuceneQueryBuilder.swift` | App-query→provider-query conversion + 6 pure forwarding methods into provider Lucene owner | MBQ-1, MBQ-2 | Retain; 1 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Infrastructure/MusicBrainz/MusicBrainzMatching.swift` | Release/file selection matching, preview scoring/assignment, result ranking | MBM-6, MBC-4 | Retain; 2 retained (§4). |
| `AudioMator/Infrastructure/MusicBrainz/MusicBrainzProviderCore.swift` | Foundation-only provider DTOs (query/file input/filters/link parser) + 2 unused helper fns | MBQ-3, MBQ-4, MBP-1 | Retain; 2 deferred (§3, §7); 1 retained (§4). |
| `AudioMator/Infrastructure/MusicBrainz/MusicBrainzProviderLuceneQueryBuilder.swift` | Sole owner of Lucene escaping/filters/clause sequences/limits | MBQ-1 | Retain; 1 retained (§4). |
| `AudioMator/Infrastructure/MusicBrainz/MusicBrainzRequestScheduling.swift` | Process-wide rate limiter, retry policy, in-memory response cache | MBC-3 | Retain; 1 retained (§4). |
| `AudioMator/Infrastructure/MusicBrainz/MusicBrainzResultModels.swift` | Search/detail result models + client error enum | MBM-1 | Retain; touched by `e993270e`; 1 candidate(s) implemented (§3). |
| `AudioMator/Infrastructure/MusicBrainz/MusicBrainzSearchModels.swift` | App search modes, file inputs, selection summary/preview DTOs, app release filters | MBQ-2 | Retain; touched by `e993270e`; 1 candidate(s) implemented (§3). |
| `AudioMator/Infrastructure/MusicBrainz/MusicBrainzSearchQuery.swift` | App-facing search query DTO with normalization + derived search values | MBQ-2, MBQ-3 | Retain; touched by `e993270e`; 1 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Infrastructure/OnlineMetadata/OnlineMetadataSelectionCore.swift` | Shared multi-file selection summary (majority candidates, distinct/mixed counts) and provider input normalization/representative-file sampling used by MusicBra… | INF-29, INF-30, INF-31 | Retain; 2 retained (§4). |
| `AudioMator/Infrastructure/TagLib/AudioFile+TagLibLoading.swift` | Builds the immutable `AudioFile` snapshot from the package snapshot, container values, AVFoundation credits/technical fallback, and the numbering projection; o… | INF-12, INF-20 | Retain; touched by `f1ff0892`, `20532f7e`; 2 candidate(s) implemented (§3). |
| `AudioMator/Infrastructure/TagLib/MetadataConflictResolver.swift` | Runs inside the mutation reservation: validates path/device/inode, re-reads a verified snapshot, applies conflict policy per native group, writes through the p… | INF-19 | Retain; touched by `c63882cb`; 1 retained (§4). |
| `AudioMator/Infrastructure/TagLib/TagLibAudioMetadataPipeline.swift` | Concrete `AudioMetadataPipeline`: load/conflict/version/raw reads, semantic/raw/erase/number-text writes, commit-status interpretation, raw-dump formatting and… | INF-01, INF-02, INF-03, INF-04, INF-05, INF-06, INF-07, INF-08, INF-09, INF-10, INF-11 | Retain; touched by `c63882cb`, `ae07d55f`, `f1ff0892`, `fde7ecb7`, `97016668`; 8 candidate(s) implemented (§3); 1 open investigate (§5); 3 retained (§4). |
| `AudioMator/Infrastructure/TagLib/TagLibDateNativeProjection.swift` | Exact native projections for the four independent date identities used by conflict comparison; prevents PropertyMap `DATE` alias collisions. | INF-17, INF-18, INF-19 | Retain; touched by `b6b07d4f`; 2 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Infrastructure/TagLib/TagLibNumberingProjection.swift` | Read-only projection of package number inventory into displayed number/total/text; ambiguity is never guessed (0), malformed values stay for correction. | INF-13 | Retain; 1 retained (§4). |
| `AudioMator/Infrastructure/Updates/GitHubUpdateReleaseClient.swift` | GitHub latest-release HTTP client: request, status/rate-limit mapping, tag→`ReleaseVersion` parsing, release metadata DTO. | INF-25 | Retain; touched by `d60400a0`; 1 candidate(s) implemented (§3). |
| `AudioMator/Infrastructure/Updates/SemanticVersion.swift` | `SemanticVersion` and `ReleaseVersion` parsing/comparison for update checks. | INF-27 | Retain; 1 retained (§4). |
| `AudioMator/Infrastructure/Updates/UpdateCheckPresenter.swift` | MainActor alert presenter for the manual update check (single in-flight task, NSAlert for update/up-to-date/ahead/failure, opens GitHub Releases). | INF-26, INF-28 | Retain; 1 deferred (§3, §7); 1 retained (§4). |
| `AudioMator/Infrastructure/Updates/UpdateChecker.swift` | Update-check types/errors/provider protocol and comparison of installed vs published version. | INF-25, INF-27 | Retain; touched by `d60400a0`; 1 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Infrastructure/iTunes/iTunesArtworkCore.swift` | Pure iTunes artwork request URL/JSON→result core (Foundation-only, production service consumes) | ITC-3 | Retain; 1 deferred (§3, §7). |
| `AudioMator/Infrastructure/iTunes/iTunesArtworkService.swift` | Artwork search/download/normalize service | ITC-4 | Retain; 1 retained (§4). |
| `AudioMator/Infrastructure/iTunes/iTunesClient.swift` | iTunes search/lookup client, query types, matcher, link parser, stored-ID/UPC/text fallback chain | ITC-2, ITF-5 | Retain; 2 retained (§4). |
| `AudioMator/Infrastructure/iTunes/iTunesProviderCore.swift` | Test-only parallel iTunes provider DTOs/URL builder/link parser + shared `CoreProviderRequestError` | ITC-1 | Retain; 1 open investigate (§5). |
### 2.5 Features

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMator/Features/LRCLIBLyricsBrowser/ViewModels/LRCLIBLyricsBrowserStore.swift` | Lyrics queue/search/state/cancellation/auto-match apply bookkeeping | LRC-1 | Retain; touched by `e993270e`; 1 candidate(s) implemented (§3). |
| `AudioMator/Features/LRCLIBLyricsBrowser/Views/LRCLIBLyricsBrowserView.swift` | LRCLIB queue UI, candidate list, preview, apply/auto-apply actions | — | Retain; no candidate change. |
| `AudioMator/Features/Main/Application/MetadataBatchExecutor.swift` | Bounded (max 4) task-group executor for independent per-file operations | FM-R02, FM-I09 | Retain; 1 open investigate (§5); 1 retained (§4). |
| `AudioMator/Features/Main/Application/MetadataFileMutationExecutor.swift` | One file's mutation lifecycle: reservation, pre-write validation, commit, independently bounded reload, typed result | FM-D16, FM-R01 | Retain; touched by `2af7fb70`; 1 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Features/Main/Presentation/InspectorArtworkPreview.swift` | Observable async artwork decode/cache for the Inspector, keeps ImageIO off selection handling | FM-R15 | Retain; 1 retained (§4). |
| `AudioMator/Features/Main/Presentation/SingleFileEditModel+Presentation.swift` | Display names/descriptions for advisory, explicit-selection and multi-file edit models | FM-D18, FM-D19 | Retain; touched by `2eb51315`; 2 candidate(s) implemented (§3). |
| `AudioMator/Features/Main/State/InspectorMetadataField.swift` | Curated Inspector quick-edit field catalog and its `MetadataFieldKey` mapping | — | Retain; no candidate change. |
| `AudioMator/Features/Main/State/MiddleListColumn.swift` | Middle-list column catalog: display name, cell text, sort comparison | FM-D12 | Retain; touched by `2eb51315`; 1 candidate(s) implemented (§3). |
| `AudioMator/Features/Main/State/SharedState.swift` | Presentation preferences (sidebar choice, sort, manual order, columns, toolbar, inspector field visibility) and middle-list ordering cache | FM-I02, FM-R16 | Retain; 1 open investigate (§5); 1 retained (§4). |
| `AudioMator/Features/Main/State/ToolbarButtonOption.swift` | Toolbar button catalog: identity, labels, icons, settings descriptions | — | Retain; no candidate change. |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+ArtworkLookup.swift` | iTunes artwork search session lifecycle, request construction, apply-to-draft | FM-R15 | Retain; 1 retained (§4). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+FileActions.swift` | Quick-import context actions and list removal/clear | FM-D05, FM-D06 | Retain; touched by `2eb51315`, `2af7fb70`; 2 candidate(s) implemented (§3). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+FileReload.swift` | Explicit and activation selected-file reload; failure identity dedup | FM-I03, FM-R11 | Retain; 1 open investigate (§5); 1 retained (§4). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+FileRename.swift` | Two-phase multi-file rename transaction, recovery reconciliation, rename result/HUD | FM-D13, FM-D17, FM-R08 | Retain; touched by `2eb51315`; 2 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+Import.swift` | Quick import, file-list actions, embedded-artwork import/preparation | FM-D08, FM-M05, FM-R15 | Retain; touched by `2eb51315`; 1 candidate(s) implemented (§3); 1 deferred (§3, §7); 1 retained (§4). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+InspectorArtwork.swift` | Derives the Inspector artwork preview source from selection/draft | — | Retain; no candidate change. |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+LRCLIBLyricsWrite.swift` | LRCLIB lyrics raw-patch writes (single and auto-match batch) | FM-M02, FM-I08 | Retain; touched by `a9e83a2c`; 1 deferred (§3, §7); 1 open investigate (§5). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+MetadataClear.swift` | Erase-all metadata single and batch writes plus clear-op summary presentation | FM-M01, FM-M02 | Retain; touched by `c44b6d3e`; 1 candidate(s) implemented (§3); 1 deferred (§3, §7). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+MetadataFieldImportWrite.swift` | Per-file one-text-field import writes (legacy Import Field route) | FM-D07, FM-M02 | Delete: removed in `e6828955` (refactor(audio-view-model): remove orphaned metadata field import writer). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+MetadataPlanWrite.swift` | Captured filename-metadata and exchange write plans | FM-M02, FM-M04, FM-R12 | Retain; touched by `a9e83a2c`; 2 deferred (§3, §7); 1 retained (§4). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+MetadataWrite.swift` | Inspector single/multi save orchestration, per-file semantic write, batch summary presenter | FM-M01, FM-M02, FM-I01, FM-R04 | Retain; touched by `a9e83a2c`; 1 candidate(s) implemented (§3); 1 deferred (§3, §7); 1 open investigate (§5); 1 retained (§4). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+MetadataWriteSupport.swift` | Capability checks, save-progress state, per-file execution wrapper, bounded plan executor, shared post-commit warnings | FM-M02, FM-M03, FM-R03, FM-R13 | Retain; 2 deferred (§3, §7); 2 retained (§4). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+MuseAmpIDWrite.swift` | MuseAmp comment-ID batch writes | FM-M02 | Retain; touched by `a9e83a2c`; 1 deferred (§3, §7). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+ProviderTaggingWrite.swift` | MusicBrainz and iTunes captured-plan writes | FM-M02, FM-M04 | Retain; touched by `a9e83a2c`; 2 deferred (§3, §7). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+RawMetadataWrite.swift` | Raw PropertyMap delta writes with per-target success sets | FM-M02, FM-R08 | Retain; touched by `a9e83a2c`; 1 deferred (§3, §7); 1 retained (§4). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel+TrackRenumbering.swift` | Sequential track-number rewrites with per-file verification and renumber result | FM-M03, FM-M06, FM-I08 | Retain; 2 deferred (§3, §7); 1 open investigate (§5). |
| `AudioMator/Features/Main/ViewModels/AudioViewModel.swift` | Main-actor state owner: files/sources, selection, drafts, watched folders, quick import, generations, HUD queue, progress | FM-D09, FM-D10, FM-D15, FM-S02, FM-I02, FM-I03, FM-I04, FM-I05, FM-I07, FM-R01, FM-R05, FM-R06, FM-R07, FM-R09, FM-R17 | Retain; touched by `2eb51315`; 4 candidate(s) implemented (§3); 5 open investigate (§5); 6 retained (§4). |
| `AudioMator/Features/Main/ViewModels/BatchMetadataOperationSummary.swift` | Batch operation summary, issue buckets, operation-kind copy, owned cancellation message classification | FM-D01, FM-M02, FM-R06, FM-R18 | Retain; touched by `a9e83a2c`; 1 candidate(s) implemented (§3); 1 deferred (§3, §7); 2 retained (§4). |
| `AudioMator/Features/Main/ViewModels/InspectorArtworkComparisonCache.swift` | Exact equality cache for multi-selection artwork state | FM-R15 | Retain; 1 retained (§4). |
| `AudioMator/Features/Main/ViewModels/SaveIssueLogStore.swift` | Persisted non-success save issue log (cap 200, corrupt-file quarantine, best-effort writes) | FM-D14, FM-R10 | Retain; touched by `2eb51315`; 1 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Features/Main/Views/AlbumArtworkLookupSheet.swift` | Online artwork search/selection sheet | — | Retain; no candidate change. |
| `AudioMator/Features/Main/Views/ContentPane.swift` | Middle-pane composition, toolbar groups, confirmations, selection-derived actions | FM-I01 | Retain; touched by `2eb51315`; 1 open investigate (§5). |
| `AudioMator/Features/Main/Views/ContentView.swift` | Main window composition, guarded selection/property flows, HUD NSPanel presenter, metadata dump | FM-D10, FM-I06 | Retain; touched by `0be0b842`; 1 candidate(s) implemented (§3); 1 open investigate (§5). |
| `AudioMator/Features/Main/Views/Formatters.swift` | Display formatters for duration, track/disc index, bitrate, sample rate, channels | FM-I09 | Retain; 1 open investigate (§5). |
| `AudioMator/Features/Main/Views/InspectorPane.swift` | Inspector UI: single/multi file sections, editable bindings, artwork controls | FM-D11, FM-S03, FM-I09 | Retain; touched by `2eb51315`; 1 candidate(s) implemented (§3); 1 deferred (§3, §7); 1 open investigate (§5). |
| `AudioMator/Features/Main/Views/InspectorPopup.swift` | Generic dimmed overlay popup container | FM-D03 | Delete: removed in `0be0b842` (refactor: remove unreachable main-window views and seed branch). |
| `AudioMator/Features/Main/Views/MergedMetadataSectionView.swift` | Legacy merged-metadata GroupBox view | FM-D04 | Delete: removed in `0be0b842` (refactor: remove unreachable main-window views and seed branch). |
| `AudioMator/Features/Main/Views/MetadataDumpSheet.swift` | Read-only raw metadata dump sheet | — | Retain; no candidate change. |
| `AudioMator/Features/Main/Views/MiddleListHeaderContextMenuInstaller.swift` | Legacy NSViewRepresentable that installs a column-visibility menu on the table header | FM-D02 | Delete: removed in `0be0b842` (refactor: remove unreachable main-window views and seed branch). |
| `AudioMator/Features/Main/Views/MiddleListTable.swift` | AppKit middle-list bridge: rows, selection mirroring, drag reorder, sort, row/header menus | FM-R16 | Retain; 1 retained (§4). |
| `AudioMator/Features/Main/Views/ReadOnlyMonospacedTextView.swift` | Read-only monospaced NSTextView wrapper | — | Retain; no candidate change. |
| `AudioMator/Features/Main/Views/SidebarPane.swift` | Sidebar source list and watched-folder rows | FM-I02 | Retain; 1 open investigate (§5). |
| `AudioMator/Features/Main/Views/TrackRenumberSheet.swift` | Renumber configuration preview, inline results, invocation | FM-M06, FM-I08 | Retain; 1 deferred (§3, §7); 1 open investigate (§5). |
| `AudioMator/Features/MetadataEditor/MetadataEditorDraftRows.swift` | Projects `targets` + draft property maps into sorted raw-field rows with mixed/uniform state and realigns selection | ME-03, ME-04 | Retain; 2 deferred (§3, §7). |
| `AudioMator/Features/MetadataEditor/MetadataFieldSuggestion.swift` | Builds the Add-Field suggestion catalog from `MetadataFieldRegistry.allSchemas` and resolves typed/raw/alias input to a write key | ME-06 | Retain; touched by `2deff969`; 1 candidate(s) implemented (§3). |
| `AudioMator/Features/MetadataEditor/Views/MetadataEditorTable.swift` | Native two-column raw-field table with multi-selection, context menu and row-height computation | ME-02 | Retain; touched by `2deff969`; 1 candidate(s) implemented (§3). |
| `AudioMator/Features/MetadataEditor/Views/MetadataEditorWindow.swift` | Declares `MetadataEditorTarget` and `MetadataEditorStore`; editor window, load/refresh at present, add/edit/delete/utilities routes, raw-map apply and dismiss… | ME-01, ME-02, ME-03, ME-05, X-06 | Retain; touched by `2deff969`; 2 candidate(s) implemented (§3); 2 deferred (§3, §7); 1 open investigate (§5). |
| `AudioMator/Features/MetadataEditor/Views/MetadataFieldEntrySheet.swift` | Add/Edit Field sheet with package-schema autocomplete, mixed-value explanation and explicit multiline values | ME-02 | Retain; touched by `2deff969`; 1 candidate(s) implemented (§3). |
| `AudioMator/Features/MetadataEditor/Views/MetadataFieldValueEditor.swift` | Monospaced NSTextView with visible space/tab/newline markers and Unicode-safe binding | ME-07 | Retain; 1 retained (§4). |
| `AudioMator/Features/MetadataEditor/Views/MetadataTextUtilitiesSheet.swift` | Text-transform operation picker with per-file/field diff preview and apply | — | Retain; no candidate change. |
| `AudioMator/Features/MetadataFilenameTool/ViewModels/MetadataFieldTransferStore.swift` | Source/destination/operation state for Copy/Cut Metadata Fields and plan construction | MF-09 | Retain; 1 retained (§4). |
| `AudioMator/Features/MetadataFilenameTool/Views/MetadataConverterModePickerView.swift` | Seven-mode converter chooser (title/subtitle/symbol from `MetadataConverterMode`) | — | Retain; no candidate change. |
| `AudioMator/Features/MetadataFilenameTool/Views/MetadataExchangeDetailView.swift` | Text/CSV export and import setup, external-source controls, template editor and preview/status | MF-07, MF-11 | Retain; 1 deferred (§3, §7); 1 retained (§4). |
| `AudioMator/Features/MetadataFilenameTool/Views/MetadataExchangePreviewLists.swift` | Text/CSV export previews and import preview lists | MF-02, MF-05 | Retain; touched by `2deff969`; 1 candidate(s) implemented (§3); 1 deferred (§3, §7). |
| `AudioMator/Features/MetadataFilenameTool/Views/MetadataFieldTransferDetailView.swift` | Copy/Cut Metadata Fields setup and preview | MF-07 | Retain; 1 deferred (§3, §7). |
| `AudioMator/Features/MetadataFilenameTool/Views/MetadataFilenamePreviewLists.swift` | Filename↔metadata comparison previews | MF-01, MF-05, MF-07 | Retain; touched by `2deff969`; 1 candidate(s) implemented (§3); 2 deferred (§3, §7). |
| `AudioMator/Features/MetadataFilenameTool/Views/MetadataFilenameRenameSheet.swift` | Declares `MetadataFilenameToolStore` and `MetadataExchangeExternalTextFileLoader`; the Filename & Metadata window, mode routing, plan computation, apply action… | MF-04, MF-07, MF-08, MF-09 | Retain; 2 deferred (§3, §7); 1 open investigate (§5); 1 retained (§4). |
| `AudioMator/Features/MetadataFilenameTool/Views/MetadataFilenameStatusPresentation.swift` | Pure ready/issue/unchanged summary messages for rename, filename extraction, text/CSV export and import plans | MF-03, MF-07 | Retain; touched by `2deff969`; 1 candidate(s) implemented (§3); 1 deferred (§3, §7). |
| `AudioMator/Features/MetadataFilenameTool/Views/MetadataFilenameTemplateEditors.swift` | Two rich-text chip template editors (filename/rename templates and text/CSV templates) plus chip attachment rendering | MF-06 | Retain; 1 deferred (§3, §7). |
| `AudioMator/Features/MetadataHelp/MetadataFieldGuide.swift` | Offline 100-field + 6-read-only-value explanations, display-name resolution, raw-key DATE family naming and primary-source catalog | HLP-01, HLP-02 | Retain; 1 open investigate (§5); 1 retained (§4). |
| `AudioMator/Features/MetadataHelp/MetadataFieldGuideView.swift` | Field guide window (search/split/detail) and `MetadataFieldGuideCommands` Help-menu command | HLP-01 | Retain; 1 retained (§4). |
| `AudioMator/Features/MetadataInspector/Views/MetadataInspectorSheet.swift` | A raw-metadata dump sheet with Copy/Copy Path toolbar | INS-01 | Delete: removed in `2deff969` (refactor: remove unreachable metadata inspector and preview code). |
| `AudioMator/Features/MusicBrainzBrowser/MusicBrainzMetadataComparisonBuilder.swift` | Read-only comparison rows/presentation for MB detail | X-1, MBM-7 | Retain; 1 deferred (§3, §7); 1 retained (§4). |
| `AudioMator/Features/MusicBrainzBrowser/ViewModels/MusicBrainzBrowserStore.swift` | MB browser main-actor state, cancellation/timeouts, detail cache, recording preload | MBM-2, MBM-6 | Retain; touched by `e993270e`; 1 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Features/MusicBrainzBrowser/ViewModels/MusicBrainzTaggingWorkbenchStore.swift` | MB write-plan construction/caching, field selection, recording-detail loading state machine | MBM-3, MBM-5, MBM-8, X-1 | Retain; touched by `e993270e`; 2 candidate(s) implemented (§3); 1 deferred (§3, §7); 1 retained (§4). |
| `AudioMator/Features/MusicBrainzBrowser/Views/MusicBrainzMetadataDetailView.swift` | MB detail UI, embedded web page, workbench preparation routes | MBM-6 | Retain; 1 retained (§4). |
| `AudioMator/Features/MusicBrainzBrowser/Views/MusicBrainzTaggingWorkbenchView.swift` | MB tagging workbench UI + AppKit assignment/diff row factory | MBM-4 | Retain; touched by `e993270e`; 1 candidate(s) implemented (§3). |
| `AudioMator/Features/OnlineMetadataBrowser/MetadataBrowserSource.swift` | Provider source picker enum (titles/subtitles/icons) | — | Retain; no candidate change. |
| `AudioMator/Features/OnlineMetadataBrowser/Views/EmbeddedWebView.swift` | WKWebView wrapper + HTTPS/host URL policy | — | Retain; no candidate change. |
| `AudioMator/Features/OnlineMetadataBrowser/Views/MetadataSourcePickerView.swift` | Source chooser UI | — | Retain; no candidate change. |
| `AudioMator/Features/OnlineMetadataBrowser/Views/OnlineMetadataBrowserView.swift` | Online Metadata shell: source routing, MB search UI, iTunes/LRCLIB embedding | OMB-3, OMB-5 | Retain; touched by `e993270e`; 1 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Features/OnlineMetadataBrowser/Views/OnlineMetadataVirtualizedList.swift` | AppKit virtualized assignment list, popup mapping, row layout, text-height cache, perf counters | OMB-1, OMB-2, OMB-4 | Retain; touched by `6ce7f020`; 1 candidate(s) implemented (§3); 2 retained (§4). |
| `AudioMator/Features/OnlineMetadataBrowser/Views/OnlineMetadataWorkbenchSelection.swift` | `NSPopUpButton` item→selection mapping (2 unassigned rows + options) | OMB-2 | Retain; 1 retained (§4). |
| `AudioMator/Features/Settings/ReleaseMarkdownBlock.swift` | Minimal Foundation markdown block parser used only by the About → Release Notes sheet | SET-05 | Retain; 1 retained (§4). |
| `AudioMator/Features/Settings/Views/ConflictSettingsTab.swift` | Conflict-policy radio group + explanations, persisted through `MetadataConflictPolicy.defaultsKey` | SET-03 | Retain; 1 retained (§4). |
| `AudioMator/Features/Settings/Views/FileAccessSettingsTab.swift` | Authorized-folder and watched-folder management, bookmark-persistence warnings, folder-access explanation | SET-03 | Retain; 1 retained (§4). |
| `AudioMator/Features/Settings/Views/SettingsView.swift` | Six-tab Settings window: General (welcome/warn/MuseAmp), Interface (toolbar/columns/inspector fields), Folders, Conflicts, Logs, About; About privacy/acknowled… | SET-01, SET-02, SET-03, SET-04, SET-05, SET-06, SET-07 | Retain; touched by `2deff969`; 1 candidate(s) implemented (§3); 1 deferred (§3, §7); 5 retained (§4). |
| `AudioMator/Features/Welcome/Views/MacWelcomeSplashView.swift` | macOS onboarding page renderer, file-access authorization flow, button bar, fixed window sizing | WEL-01, WEL-04 | Retain; 1 deferred (§3, §7); 1 open investigate (§5). |
| `AudioMator/Features/Welcome/Views/WelcomeSplashView.swift` | Thin forwarding wrapper around `MacWelcomeSplashView` plus `WelcomeSplashPage`/`…PageContent`/`…RowContent` static copy | WEL-01, WEL-02, WEL-04 | Retain; 2 deferred (§3, §7); 1 open investigate (§5). |
| `AudioMator/Features/Welcome/WelcomeSplashProgress.swift` | Persisted welcome completion keys, current onboarding version (3) and `shouldPresent` policy | WEL-03 | Retain; 1 retained (§4). |
| `AudioMator/Features/iTunesBrowser/ViewModels/iTunesBrowserStore.swift` | iTunes browser main-actor state/search/cancellation/detail cache/seed | ITF-1 | Retain; touched by `e993270e`; 1 candidate(s) implemented (§3). |
| `AudioMator/Features/iTunesBrowser/ViewModels/iTunesTaggingWorkbenchStore.swift` | iTunes write-plan construction/caching, field selection, capture semantics | ITF-2, ITF-5, X-1 | Retain; touched by `e993270e`; 1 candidate(s) implemented (§3); 1 deferred (§3, §7); 1 retained (§4). |
| `AudioMator/Features/iTunesBrowser/Views/iTunesBrowserDetailViews.swift` | iTunes track/album detail UI incl embedded web page and workbench preparation | — | Retain; no candidate change. |
| `AudioMator/Features/iTunesBrowser/Views/iTunesBrowserSearchComponents.swift` | iTunes search rows/fields/file-selection summary components | — | Retain; no candidate change. |
| `AudioMator/Features/iTunesBrowser/Views/iTunesBrowserView.swift` | iTunes browser shell, seeding, mode picker, storefront bar | ITF-4 | Retain; touched by `e993270e`; 1 candidate(s) implemented (§3). |
| `AudioMator/Features/iTunesBrowser/Views/iTunesTaggingWorkbenchView.swift` | iTunes tagging workbench UI + AppKit assignment/diff row factory | ITF-3 | Retain; touched by `e993270e`; 1 candidate(s) implemented (§3). |
| `AudioMator/Features/iTunesBrowser/iTunesMetadataComparisonBuilder.swift` | iTunes comparison rows/remote values/local fallbacks | X-1, ITF-5 | Retain; 1 deferred (§3, §7); 1 retained (§4). |
### 2.6 Resources, localization and legal

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMator/AppIcon.icon/Assets/music.quarternote.3 4.png` | Icon layer referenced by `icon.json` | — | Retain; no candidate change. |
| `AudioMator/AppIcon.icon/Assets/square.fill.text.grid.1x2 2.png` | Icon layer referenced by `icon.json` | — | Retain; no candidate change. |
| `AudioMator/AppIcon.icon/icon.json` | Icon Composer definition (2 layers); `supported-platforms.circles=[watchOS]` | RES-02 | Retain; 1 open investigate (§5). |
| `AudioMator/Assets.xcassets/AccentColor.colorset/Contents.json` | Accent color, referenced by `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` | RES-R02 | Retain; 1 retained (§4). |
| `AudioMator/Assets.xcassets/AppIconPreview.imageset/AppIconPreview.png` | 2.2 MB preview image, no current reference | RES-01 | Delete: removed in `e58fa61f` (refactor: remove unreachable app preview asset and platform aliases). |
| `AudioMator/Assets.xcassets/AppIconPreview.imageset/Contents.json` | Imageset definition, no current reference | RES-01 | Delete: removed in `e58fa61f` (refactor: remove unreachable app preview asset and platform aliases). |
| `AudioMator/Assets.xcassets/Contents.json` | Asset-catalog root metadata | — | Retain; no candidate change. |
| `AudioMator/InfoPlist.xcstrings` | 3 Info.plist key localizations (`CFBundleDisplayName`, `CFBundleName`, `NSHumanReadableCopyright`) | — | Retain; no candidate change. |
| `AudioMator/Localizable.xcstrings` | 952 app UI strings; 6 locale slots but bundle declares `en` only | L-01, L-02, L-03, RES-R03 | Retain; touched by `28fe62a6`; 3 candidate(s) implemented (§3); 1 retained (§4). |
| `AudioMator/Resources/Licenses/AudioMator-AGPL-3.0.txt` | AGPL-3.0 text loaded by `LicenseDisclosure` | RES-R01 | Retain; 1 retained (§4). |
| `AudioMator/Resources/Licenses/TagLib-LGPL-2.1.txt` | LGPL-2.1 text (TagLib dual license) | RES-R01 | Retain; 1 retained (§4). |
| `AudioMator/Resources/Licenses/TagLib-MPL-1.1.txt` | MPL-1.1 text (TagLib dual license) | RES-R01 | Retain; 1 retained (§4). |
| `AudioMator/Resources/Licenses/TagLibAudioMetadata-MIT.txt` | MIT text for package 0.8.1 | RES-R01 | Retain; 1 retained (§4). |
| `AudioMator/Resources/Licenses/utfcpp-Boost-1.0.txt` | Boost-1.0 text for utfcpp bundled with TagLib | RES-R01 | Retain; 1 retained (§4). |
### 2.7 Configuration

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `Config/AudioMator.entitlements` | Sandbox + user-selected read/write + outgoing network | — | Retain; no candidate change. |
| `Config/Info.plist` | Bundle identity/version/category/copyright; declares English localization | PRJ-02, PRJ-03 | Retain; 1 deferred (§3, §7); 1 open investigate (§5). |
### 2.8 Xcode project and scheme

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMator.xcodeproj/project.pbxproj` | Targets, synchronized roots, build settings, exact 0.8.1 package pin | PRJ-01, PRJ-02, PRJ-03, PRJ-04, PRJ-R01, TST-27 | Retain; 2 deferred (§3, §7); 2 open investigate (§5); 2 retained (§4). |
| `AudioMator.xcodeproj/project.xcworkspace/contents.xcworkspacedata` | Workspace self-reference only | — | Retain; no candidate change. |
| `AudioMator.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` | Empty shared workspace settings (no custom build locations) | PRJ-R02 | Retain; 1 retained (§4). |
| `AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | Pins TagLibAudioMetadata 0.8.1 / `b8ed5475…`; matches AGENTS and docs | — | Retain; no candidate change. |
| `AudioMator.xcodeproj/xcshareddata/xcschemes/AudioMator.xcscheme` | Shared scheme; Debug test action with `AUDIOMATOR_TEST_HOST`/restore/serial isolation | TST-27 | Retain; 1 retained (§4). |
### 2.9 Build manifest

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `Package.swift` | 31-file Foundation-only SwiftPM harness; explicit excludes; test target | TST-13, TST-19 | Retain; touched by `88d971b1`, `bd149370`; 1 candidate(s) implemented (§3); 1 retained (§4). |
### 2.10 Scripts

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `scripts/build-taglib-bridge-smoke.sh` | Maintainer-only bridge smoke build; locates package bridge sources/framework | SCR-03, TST-18 | Retain; 2 open investigate (§5). |
| `scripts/check-commit-messages.py` | Advisory commit-message contract checker | — | Retain; no candidate change. |
| `scripts/check-core-evidence.py` | CLI wrapper: require complete named core-test execution | SCR-R01 | Retain; 1 retained (§4). |
| `scripts/check-test-evidence.py` | App-test inventory vs xcresult identity gate + frozen CRITICAL set/floors | SCR-R01, TST-20 | Retain; 2 retained (§4). |
| `scripts/codex-build.sh` | Incremental Debug build, bundle pruning, known AppIcon actool false-positive detection | SCR-02, TST-12, TST-32 | Retain; touched by `dcae77f3`; 1 candidate(s) implemented (§3); 1 deferred (§3, §7); 1 retained (§4). |
| `scripts/prune-app-bundles.sh` | Removes alternate `.deriveddata*` and stale `.app` bundles | — | Retain; no candidate change. |
| `scripts/taglib_bridge_smoke.mm` | Maintainer bridge smoke tool (read/raw/write-track/write-roundtrip) | SCR-03, TST-18 | Retain; 2 open investigate (§5). |
| `scripts/tests/test_test_evidence.py` | 13 unit tests for the evidence gate and current test inventory floor | SCR-R01, TST-20 | Retain; 2 retained (§4). |
| `scripts/validate-macos-artifact.sh` | Unsigned bundle minOS/Mach-O platform validation | — | Retain; no candidate change. |
| `scripts/validate-release.sh` | Unified policy→core→app→Release→artifact gate; `--tests-only`/`--local-package` | SCR-01 | Retain; 1 deferred (§3, §7). |
### 2.11 CI

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `.github/workflows/core-logic.yml` | Single `Validation` workflow: parallel `swift-test` + full `validate-release.sh` gate and evidence upload | SCR-R02, TST-11 | Retain; 1 deferred (§3, §7); 1 retained (§4). |
### 2.12 App-hosted tests: Application/MetadataEditing

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMatorTests/Application/MetadataEditing/AudioMetadataPipelineContractTests.swift` | Pipeline commit-status interpretation, artwork-intent mapping, restricted-format preflight, value-map delta convenience | TST-29, TST-31 | Retain; touched by `c63882cb`, `97016668`; 2 retained (§4). |
| `AudioMatorTests/Application/MetadataEditing/BatchMetadataOperationSummaryTests.swift` | Exact write/clear HUD vocabulary and subtitle composition | — | Retain; no candidate change. |
| `AudioMatorTests/Application/MetadataEditing/ErrorPresentationRepairTests.swift` | HUD detail budgets/omission notices, cancellation/skipped wording, number-pair validation messages (behavioral, not source-text) | TST-24 | Retain; 1 retained (§4). |
| `AudioMatorTests/Application/MetadataEditing/FileReloadWorkflowTests.swift` | Recovery markers, explicit/activation reload, dirty-draft and late-reload guards | — | Retain; touched by `97016668`; no candidate change. |
| `AudioMatorTests/Application/MetadataEditing/FileRevisionConflictTests.swift` | Revision/fingerprint rejection under permission, timestamp and content changes | — | Retain; no candidate change. |
| `AudioMatorTests/Application/MetadataEditing/InspectorAndMetadataEditorWorkflowTests.swift` | View-model selection/draft ownership and every single/batch write route (inspector, editor, provider, filename, CSV, transfers, erase, MuseAmp, renumber trigge… | TST-01, TST-09 | Retain; touched by `e6828955`, `97016668`, `2af7fb70`; 2 candidate(s) implemented (§3). |
| `AudioMatorTests/Application/MetadataEditing/InspectorDirtyStateTests.swift` | Semantic dirty-state equality (values, advisories, artwork, split numbers) | — | Retain; no candidate change. |
| `AudioMatorTests/Application/MetadataEditing/InspectorFieldConfigurationTests.swift` | Curated Inspector field defaults, persistence/recovery, single controlled route (critical identities) | — | Retain; touched by `2eb51315`; no candidate change. |
| `AudioMatorTests/Application/MetadataEditing/MetadataConflictStrategyTests.swift` | Conflict-policy matrix + real-adapter resolver behavior; fixture fake implements guarded writes | — | Retain; touched by `97016668`, `726e6ec9`; no candidate change. |
| `AudioMatorTests/Application/MetadataEditing/MetadataEditorStoreTests.swift` | Editor raw draft maps, upsert/delete/apply and partial-retry | — | Retain; touched by `97016668`; no candidate change. |
| `AudioMatorTests/Application/MetadataEditing/ProviderTaggingCancellationTests.swift` | Batch writer cancellation/commit outcome across 7 workflows + `ProviderSemanticWriteTests`; real TagLib base pipeline | TST-07 | Retain; touched by `ae07d55f`, `7662fc26`, `97016668`; 1 candidate(s) implemented (§3). |
| `AudioMatorTests/Application/MetadataEditing/StableInodeContentReplacementTests.swift` | Different PCM payload replacing audio in place must reject/resave | — | Retain; no candidate change. |
| `AudioMatorTests/Application/MetadataEditing/TextEditPipelineTests.swift` | Ordered text transformations and find/replace semantics | — | Retain; no candidate change. |
| `AudioMatorTests/Application/MetadataEditing/TrackRenumberExecutionTests.swift` | Renumber execution, skips, refresh, version guard, durability-uncertain outcome | — | Retain; touched by `97016668`; no candidate change. |
| `AudioMatorTests/Application/MetadataEditing/TrackRenumberTests.swift` | Pure pad width/start normalization extremes | — | Retain; no candidate change. |
### 2.13 App-hosted tests: Application/MetadataExchange

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMatorTests/Application/MetadataExchange/MetadataExchangeFixtureTests.swift` | Committed pipe/tab/comma/semicolon parsing + audio fixture existence | TST-30 | Retain; 1 retained (§4). |
| `AudioMatorTests/Application/MetadataExchange/MetadataExchangeProfileTests.swift` | CSV/text profile markers, v2 semantics, unknown-version and legacy DATE meaning | — | Retain; no candidate change. |
| `AudioMatorTests/Application/MetadataExchange/MetadataExchangeTests.swift` | Planner import/export, matching/locators, limits, CSV parser/serializer | TST-14 | Retain; 1 retained (§4). |
| `AudioMatorTests/Application/MetadataExchange/MetadataFieldTransferTests.swift` | Copy/cut/field-transfer rules, validation, source-clear safety | — | Retain; no candidate change. |
### 2.14 App-hosted tests: Application/Rename

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMatorTests/Application/Rename/FileRenameTemplateTests.swift` | Rename template parse/plan/sanitize/collision rejection | — | Retain; no candidate change. |
| `AudioMatorTests/Application/Rename/FileRenameTransactionTests.swift` | Rename rollback/finalization failure reporting | — | Retain; touched by `2eb51315`; no candidate change. |
| `AudioMatorTests/Application/Rename/FilenameMetadataTemplateTests.swift` | Filename→metadata extraction plan, ambiguity and size rejection | — | Retain; touched by `726e6ec9`; no candidate change. |
| `AudioMatorTests/Application/Rename/RenameRefreshSafetyTests.swift` | Post-rename reload/recovery and stale-read write safety | — | Retain; touched by `97016668`; no candidate change. |
### 2.15 App-hosted tests: Application/WatchedFolders

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMatorTests/Application/WatchedFolders/DirectoryMonitoringPlanTests.swift` | Watched-folder plan bounds, restore/corruption quarantine, degraded status | — | Retain; touched by `c3425cb7`; no candidate change. |
| `AudioMatorTests/Application/WatchedFolders/FileAccessGrantStoreTests.swift` | Security-scope bookmark persistence and corrupt-collection handling | — | Retain; touched by `c3425cb7`; no candidate change. |
| `AudioMatorTests/Application/WatchedFolders/SecurityScopedResourceAccessTests.swift` | Balanced start/stop of security-scoped access | — | Retain; no candidate change. |
| `AudioMatorTests/Application/WatchedFolders/WatchedFolderRefreshOrderingTests.swift` | Rescan generations, last-known-good retention, deferred-reload ordering | — | Retain; touched by `97016668`; no candidate change. |
### 2.16 App-hosted tests: Concurrency

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMatorTests/Concurrency/FileMutationSerializationTests.swift` | Reservation serialization, late-result guards, timeout/commit semantics | TST-05 | Retain; touched by `ae07d55f`, `fde7ecb7`, `97016668`, `2af7fb70`; 1 candidate(s) implemented (§3). |
| `AudioMatorTests/Concurrency/OnlineMetadataStressTests.swift` | 200-track MusicBrainz presentation off-main deadline | — | Retain; no candidate change. |
| `AudioMatorTests/Concurrency/QuickImportCancellationTests.swift` | Import cancellation/late-result/retry, watched-folder refresh fallbacks | — | Retain; touched by `97016668`; no candidate change. |
### 2.17 App-hosted tests: Integration/Network

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMatorTests/Integration/Network/ArtworkLookupResponsivenessTests.swift` | Artwork lookup timeout/cancel/dismiss/release fakes | — | Retain; touched by `97016668`; no candidate change. |
| `AudioMatorTests/Integration/Network/LRCLIBLyricsTests.swift` | LRCLIB request/decode/rank/store plus raw-patch lyrics write assertions | TST-03 | Retain; touched by `97016668`; 1 candidate(s) implemented (§3). |
| `AudioMatorTests/Integration/Network/OnlineMetadataPageTraversalTests.swift` | Page/detail traversal render budgets with injected clients | — | Retain; touched by `e993270e`; no candidate change. |
| `AudioMatorTests/Integration/Network/ProviderNetworkFaultTests.swift` | HTTP/malformed/timeout mapping, artwork normalization, stale-ID fallback | — | Retain; no candidate change. |
| `AudioMatorTests/Integration/Network/ProviderSearchRestartTests.swift` | Non-cooperative client restart/timeout/cancel state (URLProtocol-free fakes) | — | Retain; no candidate change. |
### 2.18 App-hosted tests: Integration/TagLib

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMatorTests/Integration/TagLib/AutomaticNumberRecoveryTests.swift` | Read-only numbering recovery, ambiguity, dirty state, migration/clear | — | Retain; no candidate change. |
| `AudioMatorTests/Integration/TagLib/MappingPackageConformanceTests.swift` | Independent package-vs-app date/year probes | — | Retain; touched by `c63882cb`; no candidate change. |
| `AudioMatorTests/Integration/TagLib/MetadataBoundaryMatrixTests.swift` | Dedicated/common/exchange/provider/container field matrices, real writes + reloads | — | Retain; touched by `c63882cb`; no candidate change. |
| `AudioMatorTests/Integration/TagLib/MetadataSaveJourneyTests.swift` | Provider/editor/inspector real save journeys (17 critical regression identities) | — | Retain; no candidate change. |
| `AudioMatorTests/Integration/TagLib/NumberTextDependencyContractTests.swift` | Unsupported number-text rejection and unrelated-edit preservation | — | Retain; touched by `ae07d55f`; no candidate change. |
| `AudioMatorTests/Integration/TagLib/StoreIdentifierWriteTests.swift` | Store-ID typed writes incl. generated AIFF and invalid-ID atomicity | — | Retain; touched by `c63882cb`; no candidate change. |
| `AudioMatorTests/Integration/TagLib/TagLibDateMappingIntegrationTests.swift` | Native date storage, ID3v2.3 safe failure, independent date edits | — | Retain; touched by `c63882cb`; no candidate change. |
| `AudioMatorTests/Integration/TagLib/TagLibMappingContractIntegrationTests.swift` | Mapping contract matrix (numbers, advisory, dates, MP4 shapes) on real files | TST-04 | Retain; touched by `f1ff0892`, `726e6ec9`; 1 candidate(s) implemented (§3). |
| `AudioMatorTests/Integration/TagLib/TagLibReadWriteIntegrationTests.swift` | Real TagLib read/write/erase/raw/artwork across six fixtures | TST-02, TST-03, TST-05 | Retain; touched by `c63882cb`, `ae07d55f`, `fde7ecb7`, `97016668`, `2af7fb70`; 3 candidate(s) implemented (§3). |
| `AudioMatorTests/Integration/TagLib/TagLibUpgradeContractTests.swift` | Exact package pin/lock/docs contract, adapter existential contract, FLAC/date/number guards | TST-03 | Retain; touched by `fde7ecb7`; 1 candidate(s) implemented (§3). |
### 2.19 App-hosted tests: Performance

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMatorTests/Performance/MainMetadataFlowPerformanceTests.swift` | Bounded concurrent batch saves and selection/publication work bounds | — | Retain; touched by `c63882cb`, `97016668`; no candidate change. |
| `AudioMatorTests/Performance/MetadataIOPerformanceTests.swift` | IO-stage timings and bounded guarded concurrency across formats | — | Retain; no candidate change. |
| `AudioMatorTests/Performance/OnlineMetadataWorkbenchPerformanceFixture.swift` | Shared deterministic 10/50/200-track workbench scenario factory | — | Retain; no candidate change. |
| `AudioMatorTests/Performance/OnlineMetadataWorkbenchPerformanceTests.swift` | Workbench row virtualization/menu/plan-cache work bounds, informational medians | — | Retain; no candidate change. |
### 2.20 App-hosted tests: Unit/Core

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMatorTests/Unit/Core/AudioTagNumberPairTests.swift` | Tag-number text/pair parsing, display and edit-model integration | TST-14 | Retain; touched by `e58fa61f`, `726e6ec9`; 1 retained (§4). |
| `AudioMatorTests/Unit/Core/EmbeddedWebURLPolicyTests.swift` | HTTPS provider-host allow-list for embedded web view | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Core/FormattersTests.swift` | Duration/sample-rate formatter validity and rounding | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Core/FuzzyStringSimilarityTests.swift` | Normalization/score/token-sequence matching behavior | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Core/GitHubAPIRequestTests.swift` | Shared GitHub request headers | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Core/LicenseDisclosureTests.swift` | License registry completeness, bundled text presence, AGPL/repo sync, markers | TST-25 | Retain; 1 retained (§4). |
| `AudioMatorTests/Unit/Core/MuseAmpCommentIDGeneratorTests.swift` | Stable numeric MuseAmp IDs and comment payload format | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Core/MusicBrainzFilenameFallbackTests.swift` | Filename/directory fallback and duration overflow behavior | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Core/MusicBrainzLinkParserTests.swift` | Recording/release link parsing and host rejection | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Core/MusicBrainzLuceneQueryBuilderTests.swift` | App query→provider Lucene adaptation and file-cluster queries | TST-10 | Retain; no candidate change. |
| `AudioMatorTests/Unit/Core/MusicBrainzMatchingTests.swift` | Ranker/assignment/representative/release-verification policy | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Core/MusicBrainzResultModelsTests.swift` | Result-model conversion, counts, client error descriptions | — | Retain; touched by `e993270e`; no candidate change. |
| `AudioMatorTests/Unit/Core/MusicBrainzSearchQueryTests.swift` | App search-query normalization/selection summary | — | Retain; touched by `e993270e`; no candidate change. |
| `AudioMatorTests/Unit/Core/NetworkServiceDisclosureTests.swift` | Network disclosure registry completeness and production host inventory | TST-25 | Retain; 1 retained (§4). |
| `AudioMatorTests/Unit/Core/ReleaseMarkdownBlockTests.swift` | Release-note Markdown block parser/normalization | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Core/SaveIssueLogStoreTests.swift` | Issue-log persistence/limit/corruption quarantine/unwritable fallback | — | Retain; touched by `c44b6d3e`; no candidate change. |
| `AudioMatorTests/Unit/Core/TestHostIsolationTests.swift` | Test-host flag logic and isolated host/store behavior | TST-27 | Retain; 1 retained (§4). |
| `AudioMatorTests/Unit/Core/UpdateCheckerTests.swift` | Version comparison/update detection and GitHub release mapping via URLProtocol | — | Retain; touched by `d60400a0`; no candidate change. |
### 2.21 App-hosted tests: Unit/Presentation

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMatorTests/Unit/Presentation/ArtworkImportConcurrencyTests.swift` | Gated normalization leaves main actor responsive | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Presentation/IndependentDateIntentTests.swift` | Independent date intents across single/multi edit + payload changed-fields | TST-30 | Retain; touched by `c63882cb`; 1 retained (§4). |
| `AudioMatorTests/Unit/Presentation/InspectorArtworkPreviewTests.swift` | Artwork preview cache/bounds/slow-decode/late-publish behavior | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Presentation/MappingAcceptanceRepairTests.swift` | Purchase-date/rate routes, unknown advisory, removal tokens, foreign DATE, private-pair cleanup + 2 source-absence checks | TST-22, TST-30 | Retain; touched by `c63882cb`; 2 retained (§4). |
| `AudioMatorTests/Unit/Presentation/MetadataEditorDraftRowsTests.swift` | Editor row labels/mixed values/selection alignment (critical identities) | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Presentation/MetadataFieldGuideTests.swift` | Field-guide inventory equality, source/privacy agreement, search (critical identities) | TST-25 | Retain; 1 retained (§4). |
| `AudioMatorTests/Unit/Presentation/MetadataFilenameStatusPresentationTests.swift` | External text decoding limits + rename/filename/exchange status messages | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Presentation/MiddleListSelectionTests.swift` | Ordering cache/selection reorder/reload invariants | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Presentation/MusicBrainzMetadataComparisonBuilderTests.swift` | Presentation builder fallback/preview preservation | TST-21 | Retain; 1 retained (§4). |
| `AudioMatorTests/Unit/Presentation/WatchedFolderSettingsSelectionTests.swift` | Settings folder selection diffing | — | Retain; no candidate change. |
| `AudioMatorTests/Unit/Presentation/iTunesMetadataComparisonBuilderTests.swift` | iTunes row classification/explicitness/ranking behavior | — | Retain; no candidate change. |
### 2.22 App-hosted tests: root and support

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMatorTests/OnlineMetadataPlanSnapshotTests.swift` | Provider plan/preview behavior + 3 source-structure/concurrency checks | TST-21 | Retain; touched by `97016668`; 1 retained (§4). |
| `AudioMatorTests/SensitiveLoggingPolicyTests.swift` | App-wide diagnostic-console logging policy + detector self-test | TST-23 | Retain; 1 retained (§4). |
| `AudioMatorTests/TestSupport/AudioFileTestFactory.swift` | In-memory `AudioFile` factory (304 call sites) | TST-08 | Retain; touched by `7662fc26`; 1 candidate(s) implemented (§3). |
| `AudioMatorTests/TestSupport/AudioViewModelTestFactory.swift` | Isolated `AudioViewModel` factory (per-suite defaults + temp issue log) | — | Retain; no candidate change. |
| `AudioMatorTests/TestSupport/ID3v23FixtureBuilder.swift` | Builds valid ID3v2.3 MP3 copy for TDAT coverage (used by 1 test) | — | Retain; no candidate change. |
### 2.23 App-hosted tests: fixtures

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `AudioMatorTests/Fixtures/Artwork/testCover.jpg` | Artwork replacement source used by TagLib read/write and mapping tests | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/Audio/testAudioFile.aac` | AAC source fixture | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/Audio/testAudioFile.flac` | Xiph/FLAC source fixture (wide reuse) | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/Audio/testAudioFile.m4a` | MP4 atom read/write/number/advisory/date source fixture | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/Audio/testAudioFile.mp3` | ID3v2.4 MP3 read/write/raw/date/performance source fixture | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/Audio/testAudioFile.ogg` | Ogg Vorbis source fixture | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/Audio/testAudioFile.wav` | WAV/ID3 source fixture (incl. same-inode replacement test) | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/Audio/aurora-01.flac` | Byte-identical FLAC copies named by `expected_metadata.txt`; used by `MetadataExchangeFixtureTests.testMetadataExchangeAudioFixturesExistForExpectedRows` | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/Audio/aurora-02.flac` | Byte-identical FLAC copies named by `expected_metadata.txt`; used by `MetadataExchangeFixtureTests.testMetadataExchangeAudioFixturesExistForExpectedRows` | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/Audio/aurora-03.flac` | Byte-identical FLAC copies named by `expected_metadata.txt`; used by `MetadataExchangeFixtureTests.testMetadataExchangeAudioFixturesExistForExpectedRows` | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/Audio/aurora-04.flac` | Byte-identical FLAC copies named by `expected_metadata.txt`; used by `MetadataExchangeFixtureTests.testMetadataExchangeAudioFixturesExistForExpectedRows` | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/Audio/aurora-05.flac` | Byte-identical FLAC copies named by `expected_metadata.txt`; used by `MetadataExchangeFixtureTests.testMetadataExchangeAudioFixturesExistForExpectedRows` | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/Audio/aurora-06.flac` | Byte-identical FLAC copies named by `expected_metadata.txt`; used by `MetadataExchangeFixtureTests.testMetadataExchangeAudioFixturesExistForExpectedRows` | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/Audio/aurora-07.flac` | Byte-identical FLAC copies named by `expected_metadata.txt`; used by `MetadataExchangeFixtureTests.testMetadataExchangeAudioFixturesExistForExpectedRows` | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/Audio/aurora-08.flac` | Byte-identical FLAC copies named by `expected_metadata.txt`; used by `MetadataExchangeFixtureTests.testMetadataExchangeAudioFixturesExistForExpectedRows` | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/Audio/aurora-09.flac` | Byte-identical FLAC copies named by `expected_metadata.txt`; used by `MetadataExchangeFixtureTests.testMetadataExchangeAudioFixturesExistForExpectedRows` | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/Audio/aurora-10.flac` | Byte-identical FLAC copies named by `expected_metadata.txt`; used by `MetadataExchangeFixtureTests.testMetadataExchangeAudioFixturesExistForExpectedRows` | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/TextImport/expected_metadata.txt` | Expected normalized records for all four delimited fixtures | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/TextImport/txt2metadata_csv_comma.csv` | Comma CSV fixture (escaped quotes) | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/TextImport/txt2metadata_csv_semicolon.csv` | Semicolon CSV fixture (embedded commas/semicolons) | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/TextImport/txt2metadata_pipe.txt` | Pipe-delimited import fixture | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/MetadataExchange/TextImport/txt2metadata_tab.txt` | Tab-delimited import fixture | — | Retain; no candidate change. |
| `AudioMatorTests/Fixtures/README.md` | Fixture provenance/mutation policy (accurate) | — | Retain; no candidate change. |
### 2.24 SwiftPM core tests

| Path | Responsibility | Candidate IDs | Disposition |
| --- | --- | --- | --- |
| `Tests/AudioMatorCoreLogicTests/AsyncOperationDeadlineTests.swift` | Deadline timeout/cancellation semantics | — | Retain; no candidate change. |
| `Tests/AudioMatorCoreLogicTests/AudioMatorCoreLogicTests.swift` | 52 pure-policy tests for Core/Domain/pure Infrastructure cores | — | Retain; touched by `88d971b1`, `e58fa61f`; no candidate change. |
| `Tests/AudioMatorCoreLogicTests/Concurrency/MusicBrainzRequestSchedulingTests.swift` | 3 rate-limiter + 3 response-cache tests | — | Retain; no candidate change. |

## 3. Candidate and decision ledger

Every candidate ID from the seven audits is listed with its decision, campaign outcome and replacement owner. Decision vocabulary follows the cleanup plan §2: `delete` (unreachable or old internal API), `merge` (duplicate responsibility), `simplify` (over-layered but live), `retain` (active behavior, protection or persisted user data), `investigate` (insufficient evidence), plus `migrate`/`document` for test and documentation migrations. `Implemented` rows name the commit; `Deferred` rows are not implemented in this campaign and carry the reason; open investigations are in §5. Retained rows are summarized in §4.

### 3.1 App composition, Core, resources, configuration and scripts

| ID | Candidate (audited item) | Decision | Campaign outcome | Owner / replacement |
| --- | --- | --- | --- | --- |
| APP-01 | First-launch window sizing implemented twice (`AppDelegate` vs SwiftUI `.defaultSize`) | investigate | Open investigation — see §5 | Unresolved |
| CORE-01 | `AppWindowTitle.rawMetadata` / `.renumberTracks` / `.settings` dead static properties | delete | Implemented — e58fa61f: deleted three dead `AppWindowTitle` statics | Removed; no replacement needs to exist |
| CORE-02 | `MacPasteboard.image` dead accessor | delete | Implemented — e58fa61f: deleted `MacPasteboard.image` | Removed; no replacement needs to exist |
| CORE-03 | `NSImage.audiomatorPNGData` dead extension | delete | Implemented — e58fa61f: deleted `NSImage.audiomatorPNGData` | Removed; no replacement needs to exist |
| CORE-04 | `NSColor.audiomatorTextBackground` / `.audiomatorSecondaryLabel` / `.audiomatorTertiaryLabel` dead aliases | delete | Implemented — e58fa61f: deleted three dead `NSColor` aliases | Removed; no replacement needs to exist |
| CORE-05 | `AudioTagNumberText.parsedPair(from:)` is test-only after the package-patch refactor | delete | Implemented — e58fa61f: deleted `parsedPair(from:)`; assertions moved to `components`/`AudioTagNumberPair` paths | Removed; no replacement needs to exist |
| CORE-06 | `audiomatorNavigationSubtitle` is a pure pass-through wrapper | simplify | Deferred — Cross-area 2-call-site wrapper; audit marked it optional and the campaign did not schedule UI-site churn. | Direct `navigationSubtitle(_:)` calls at the two feature views |
| CORE-07 | `AudiomatorScrollEdgeEffectStyle` single-value enum + unused `style` parameter | simplify | Deferred — 30-call-site scroll-edge helper simplification; audit marked it optional/low priority; no policy change was required. | `audiomatorScrollEdgeEffect(for:)` keeps the availability gate; drop the style parameter/enum |
| CORE-09 | `String.localizedUI` single-use sugar | simplify | Deferred — Single-call localization sugar; audit marked it not worth a standalone commit. | `String(localized:)` at the single call site |
| L-01 | 68 unreferenced catalog keys (old copy/status/labels from superseded screens) | delete | Implemented — 28fe62a6: pruned 68 unreferenced catalog keys (catalog 952→861 keys) | Removed; no replacement needs to exist |
| L-02 | 8 stale `%@` format-variant duplicates of live `%lld` keys | delete | Implemented — 28fe62a6: pruned 8 stale `%@` format-variant keys | Removed; no replacement needs to exist |
| L-03 | Test-only catalog key `"Inspector"` (line 6861, stale) | delete | Implemented — 28fe62a6: pruned the test-only `Inspector` key | Removed; no replacement needs to exist |
| PRJ-01 | `EXCLUDED_SOURCE_FILE_NAMES = Info.plist` is an obsolete leftover | delete | Deferred — Build-setting removal needs its own Real Xcode Debug/Release build and built-plist check; not scheduled in this campaign. | `Config/Info.plist` remains the only Info.plist source; remove the exclusion setting |
| PRJ-02 | Three `INFOPLIST_KEY_*` duplicates per configuration are inert | delete | Deferred — Same build-configuration slice as PRJ-01 (generated-plist settings inert against the custom plist); deferred with it. | `Config/Info.plist` remains the single source of truth for those keys |
| PRJ-03 | Localization configuration is internally inconsistent (investigate) | investigate | Open investigation — see §5 | Unresolved |
| PRJ-04 | `CURRENT_PROJECT_VERSION = 26112` conflicts with current configuration documentation | investigate | Open investigation — see §5 | Unresolved |
| RES-01 | `AppIconPreview` imageset is unreferenced (2.2 MB) | delete | Implemented — e58fa61f: deleted the 2.2 MB `AppIconPreview` imageset | Removed; no replacement needs to exist |
| RES-02 | `AppIcon.icon/icon.json` declares a watchOS circle platform while the app is macOS-only | investigate | Open investigation — see §5 | Unresolved |
| SCR-01 | `validate-release.sh` local-package source indirection is redundant | simplify | Deferred — Developer-tooling simplification only; not scheduled. | `PACKAGE_SOURCE="$LOCAL_PACKAGE"`; drop the unused positional rebuild |
| SCR-02 | `codex-build.sh` build-relevance allowlist has drifted from the repository | simplify | Deferred — Developer-tooling allowlist rule needs a synthetic changed-file dry run; not scheduled. | Path-prefix build-relevance rule under `AudioMator/`, `AudioMatorTests/`, `Config/`, `AudioMator.xcodeproj/`, `Package.swift`, `Package.resolved`, build scripts |
| SCR-03 | Bridge smoke tooling may no longer match the published package layout (investigate) | investigate | Open investigation — see §5 | Maintainer-only bridge smoke tool; stale candidate fallbacks only |

### 3.2 Domain

| ID | Candidate (audited item) | Decision | Campaign outcome | Owner / replacement |
| --- | --- | --- | --- | --- |
| DOM-01 | `Domain/MetadataEditing/AudioMetadataPipeline.swift:231–236` no-version `writeMetadata(_:to:)`; concrete duplicate `Infrastructure/TagLib/TagLibAudioMetadataPipeline.swift:121–123` (Infrast… | delete | Implemented — ae07d55f: deleted no-version `writeMetadata(_:to:)` from protocol extension and concrete adapter; tests pass explicit `expectedVersion:` | Removed; no replacement needs to exist |
| DOM-02 | `AudioMetadataPipeline.swift:264–266` no-version `eraseAllMetadata(at:)`; concrete `TagLibAudioMetadataPipeline.swift:186–188` | delete | Implemented — ae07d55f: deleted no-version `eraseAllMetadata(at:)` from both layers | Removed; no replacement needs to exist |
| DOM-03 | `AudioMetadataPipeline.swift:188–194` requirement; `:268–281` no-version convenience; adapter `TagLibAudioMetadataPipeline.swift:202–240` (both overloads); adapter private `numberTextWriteW… | delete | Implemented — 97016668: deleted requirement, convenience, both adapter overloads and number-text warning helpers; legacy tests replaced by typed-path round-trip regression | Removed; no replacement needs to exist |
| DOM-04 | `AudioMetadataPipeline.swift:161` requirement `rawMetadataPropertyMap(for:)`; default `227–229`; adapter override `TagLibAudioMetadataPipeline.swift:88–109`; helpers `630–632` (`normalizedP… | delete | Implemented — fde7ecb7: deleted `rawMetadataPropertyMap` requirement/default/override and its three conversion helpers; exact value-map assertions migrated | Removed; no replacement needs to exist |
| DOM-05 | `AudioMetadataPipeline.swift:238–247` scalar `writeRawMetadataPropertyMap(_:to:)`; concrete duplicate `TagLibAudioMetadataPipeline.swift:139–141` | delete | Implemented — fde7ecb7: deleted scalar `writeRawMetadataPropertyMap` from both layers | Removed; no replacement needs to exist |
| DOM-06 | `AudioMetadataPipeline.swift:195` requirement `numberingInventory(at:)`; default `283–285`; adapter forward `TagLibAudioMetadataPipeline.swift:242–244` | delete | Implemented — f1ff0892: deleted `numberingInventory(at:)` requirement/default/forward; tests read package inventory directly | Removed; no replacement needs to exist |
| DOM-07 | `Domain/AudioFiles/SingleFileEditModel+MetadataPipeline.swift:5–22` unguarded `init(_ edit: SingleFileEditModel)` | delete | Deferred — Unguarded test-only payload initializer removal needs a baseline-comparison review of 14 test call sites; not scheduled. | `MetadataEditPayload(edit, comparedTo:)` is the only payload builder |
| DOM-08 | `Domain/AudioFiles/AudioMetadataModelCore.swift:9–20` `AudioMetadataMergeCore.duplicateKeys` | delete | Implemented — 88d971b1: deleted `duplicateKeys`; core test rewritten to retained `mergedValue` behavior | Removed; no replacement needs to exist |
| DOM-09 | `AudioMetadataModelCore.swift:23–37` `ArtworkReplacementDecision` + `ArtworkReplacementCore.decision` | delete | Implemented — 88d971b1: deleted `ArtworkReplacementDecision`/`ArtworkReplacementCore` | Removed; no replacement needs to exist |
| DOM-10 | `Domain/FileSources/FileCollectionCore.swift:1–49` `FileCollectionCore` + `CoreAudioFileReference` | delete | Implemented — 88d971b1: deleted `FileCollectionCore.swift` and its SwiftPM source entry; core test replaced 1:1 by fingerprint test (core count stays 62) | Removed; no replacement needs to exist |
| DOM-11 | `Domain/MetadataExchange/MetadataExchangeTemplate.swift:37–43` `usesFileNameMatching` / `usesBaseNameMatching` | delete | Implemented — 623ed1d8: deleted `usesFileNameMatching`/`usesBaseNameMatching` | Removed; no replacement needs to exist |
| DOM-12 | `Domain/MetadataExchange/MetadataExchangeModels.swift:335–337` `MetadataExchangeField.writeOrderIndex` | delete | Implemented — 623ed1d8: deleted `MetadataExchangeField.writeOrderIndex` | Removed; no replacement needs to exist |
| DOM-13 | `Domain/Rename/FileRenameTemplateCore.swift:112–174` `FileRenameTemplateParser` vs `Domain/MetadataExchange/MetadataExchangeTemplateSyntax.swift:13–54` `MetadataExchangeTemplateSyntaxParser` | merge | Implemented — 623ed1d8: rename parser now consumes `MetadataExchangeTemplateSyntaxParser`; field mappings stay separate | `MetadataExchangeTemplateSyntaxParser` tokenizer; separate field mappings |
| DOM-14 | `Domain/Rename/FileRenamePlanCore.swift:3–20` `FileRenameCoreStatus` ↔ `Domain/Rename/FileRenameTemplate.swift:45–100,391–431` `FileRenamePreviewStatus` + two 14-case mapping switches | simplify | Implemented — 623ed1d8: both status enums use aligned raw values; two 14-case switches replaced by raw-value round-trip | Raw-value status round-trip |
| DOM-15 | `Domain/Rename/FileRenameTemplateCore.swift:176–195` `FileRenameCompatibilityOptions` + `FileRenameSanitizer(options:)` | simplify | Implemented — 623ed1d8: fixed sanitizer policy inlined; `FileRenameCompatibilityOptions` removed | Fixed `FileRenameSanitizer` policy |
| DOM-16 | Unused `import Combine` in `Domain/AudioFiles/MergedAudioFile.swift:1`, `Domain/FileSources/FileSourceModels.swift:2`, `Domain/Rename/FileRenameTemplate.swift:2`, `Domain/Rename/FilenameMet… | simplify | Implemented — 3d3b458f: removed four unused `import Combine` lines from Domain values | Foundation-only Domain value types |
| DOM-17 | `Domain/FileSources/FileMutationDirectoryAccessPlan.swift:24–26` single-use `isSameOrDescendant` wrapper; `Domain/MetadataEditing/FileMutationCoordinator.swift:35–37` `normalizedFileKey` on… | simplify | Implemented — 623ed1d8: inlined single-use path forwarders; `FileSystemPathSemantics` remains owner | `FileSystemPathSemantics` |
| DOM-18 | `Domain/AudioFiles/SingleFileEditModel.swift:499–542` `MultiFileEditableTextField.value(from file:)` number cases vs `:346–360` `SingleFileEditModel` display projection (same `AudioTagNumbe… | simplify | Implemented — 623ed1d8: single `NumberPairDisplayText` projection used by single- and multi-file routes | `NumberPairDisplayText` |
| DOM-19 | `Domain/MetadataExchange/MetadataExchangeModels.swift:418–436` `exportPalette` vs `importPalette` | simplify | Implemented — 623ed1d8: `importPalette = exportPalette + [.ignore]` | `exportPalette` |
| DOM-20 | Duplicated `isExplicit` convenience: `Domain/MetadataEditing/AudioMetadataPipeline.swift:62` (**zero consumers**), `Domain/AudioFiles/AudioFile.swift:56` (tests only), `Domain/AudioFiles/Si… | simplify | Implemented — 2af7fb70: deleted `MetadataEditPayload.isExplicit` plus two test-only convenience mirrors; assertions use `contentAdvisory?.isExplicit` | `ContentAdvisory.isExplicit` |
| DOM-21 | `Domain/Rename/FilenameMetadataTemplate.swift:5–42` `FileRenameMetadataField.currentMetadataValue(from:)` vs `Domain/Rename/FileRenameTemplate.swift:189–232` `FileRenameFieldValueResolver.r… | investigate | Resolved as a deliberate difference: 726e6ec9 pins stored-raw-text comparison for filename→metadata against numeric-pair rendering for rename preview; no merge performed and no behavior change claimed | Stored raw text is the conservative comparison owner for filename→metadata; numeric pair renders rename previews; documented difference |
| DOM-22 | `Domain/AudioFiles/AudioFile.swift:334–350` `AudioFile.normalizedNumberText(rawText:number:total:)` vs `Core/Audio/AudioTagNumberPair.swift:46–55` `canonicalRawText` (cross-area: Core) | investigate | Resolved as a deliberate difference: 726e6ec9 pins snapshot text rules against canonical pair text (total-only and no-slash layouts); consolidation deferred until a product decision | Store loader text rule stays in `AudioFile.normalizedNumberText`; canonical pair text stays in `AudioTagNumberPair`; difference pinned by test |
| DOM-23 | Guarded writes `AudioMetadataPipeline.swift:172–183` + fail-closed defaults `:200–215`; adapter `TagLibAudioMetadataPipeline.swift:157–184` | retain | Retained — see §4 | See §4 |
| DOM-24 | `AudioMetadataPipeline.swift:249–262` `writeRawMetadataValueMap` full-map→exact delta | retain | Retained — see §4 | See §4 |
| DOM-25 | Test-double seams: `conflictSnapshot` default throw (`:219–221`), `metadataFileVersion` default throw (`:223–225`), `requiresTransactionalDirectoryAccess` default `false` (`:217`), guarded-… | retain | Retained — see §4 | See §4 |
| DOM-26 | `MetadataExchangeField.propertyMapKey` (`MetadataExchangeModels.swift:339–416`), used only by CSV header aliases (`MetadataExchangePlanning.swift:709`), with the deliberate legacy rule that… | retain | Retained — see §4 | See §4 |
| DOM-27 | `MetadataExchangeProfile` (`MetadataExchangeCSV.swift:9–76`): marker prefix/current v2/legacy v1, unknown-version rejection, `<remove>` token + internal sentinel; resource limits `:78–83` | retain | Retained — see §4 | See §4 |
| DOM-28 | `MuseAmpCommentIDGenerator` (`Domain/MuseAmp/MuseAmpCommentIDGenerator.swift:1–107`), `museAmpSupportEnabledDefaultsKey` | retain | Retained — see §4 | See §4 |
| DOM-29 | `WatchedFolderRecord` / `WatchedFolder` / `FileAccessGrantRecord` / `FileAccessGrant` / `FileAccessAuthorizationOutcome` (`Domain/FileSources/FileSourceModels.swift:24–54`) | retain | Retained — see §4 | See §4 |
| DOM-30 | `MetadataConflictPolicy` + `metadata.conflictPolicy` key (`Domain/MetadataEditing/MetadataConflictPolicy.swift:4–15`) | retain | Retained — see §4 | See §4 |
| DOM-31 | `ContentAdvisory.fromMetadataText` (`SingleFileEditModel.swift:25–37`) vs `ContentAdvisory.fromiTunesExplicitness` (`:39–51`) | retain | Retained — see §4 | See §4 |
| DOM-32 | Two template matchers: `MetadataExchangeTextMatcher` (`MetadataExchangePlanning.swift:1359–1535`) and `FilenameMetadataTemplateMatcher` (`FilenameMetadataExtractionCore.swift:94–293`) | retain | Retained — see §4 | See §4 |
| DOM-33 | Exchange row builders: `MetadataExchangePlanning.makeImportRow` (`:1184–1275`) vs `MetadataFieldTransferPlanner.makeRow` (`Domain/MetadataExchange/MetadataFieldTransfer.swift:57–141`) | retain | Retained — see §4 | See §4 |
| DOM-34 | `TrackRenumberOptions`/clamps/pad width/result (`Domain/TrackRenumber/TrackRenumber.swift:1–56`), including `TrackRenumberResult.empty` (`:48`) and `FileRenameCollisionPolicy` (`FileRenameP… | retain | Retained — see §4 | See §4 |

### 3.3 Infrastructure

| ID | Candidate (audited item) | Decision | Campaign outcome | Owner / replacement |
| --- | --- | --- | --- | --- |
| INF-01 | `metadataPatchForWrite`: pure builder vs throwing advisory validation | simplify | Implemented — c63882cb: single throwing `metadataPatchForWrite(from:)` is the one validation/encoding policy; conflict planning uses `try` (see fixed defect in acceptance record) | Single throwing `TagLibAudioMetadataPipeline.metadataPatchForWrite(from:)` |
| INF-02 | non-versioned `writeMetadata(_:to:)` convenience (protocol extension + concrete shadow) | delete | Implemented — ae07d55f: no-version write convenience removed with Domain side (DOM-01) | Removed; no replacement needs to exist |
| INF-03 | non-versioned `eraseAllMetadata(at:)` convenience (protocol extension + concrete shadow) | delete | Implemented — ae07d55f: no-version erase convenience removed with Domain side (DOM-02) | Removed; no replacement needs to exist |
| INF-04 | legacy `writeTrackNumberText` surface and app-side number-text warning normalization | delete | Implemented — 97016668: legacy `writeTrackNumberText` concrete overloads and warning-normalization helpers deleted; typed number-component semantic writes are the only path | Removed; no replacement needs to exist |
| INF-05 | concrete `writeRawMetadataPropertyMap` duplicate | delete | Implemented — fde7ecb7: concrete scalar property-map write duplicate deleted | Versioned value-map raw writer |
| INF-06 | `rawMetadataPropertyMap(for:)` requirement/override and four conversion helpers | delete | Implemented — fde7ecb7: property-map read surface and four conversion helpers deleted; `RawMetadataValueMap` is the raw owner | `RawMetadataValueMap`/`rawMetadataValueMap` exact arrays |
| INF-07 | `numberingInventory(at:)` pipeline forwarding | delete | Implemented — f1ff0892: pipeline inventory forwarding deleted; Infrastructure loader keeps the only inventory read | Infrastructure loader/package inventory read |
| INF-08 | `interpretingWrite` catch of `committedButDurabilityUncertain` | investigate | Open investigation — see §5 | Retain the package-error adapter catch; returned commit status is the primary owner |
| INF-09 | `ambiguousNumberRecovery` error mapping (retain, add assertion) | retain | Implemented — 726e6ec9: retained mapping, added direct domain/code/message assertion for ambiguous-number recovery errors | `TagLibAudioMetadataPipeline.interpretingWrite` mapping retained; direct domain/code/message assertion added |
| INF-10 | ID3v1 compatibility notes and raw-dump formatting (retain) | retain | Retained — see §4 | See §4 |
| INF-11 | single read retry in `loadAudioFile` (retain) | retain | Retained — see §4 | See §4 |
| INF-12 | stored numbering inventory state on `AudioFile` | delete | Implemented — f1ff0892: removed stored `trackNumberInventory`/`discNumberInventory` snapshot state and loader assignment | Loaded number projection (`track`/`trackTotal`/text) |
| INF-13 | `TagLibNumberingProjection.pair` (retain) | retain | Retained — see §4 | See §4 |
| INF-14 | `try?` inventory read (retain) | retain | Retained — see §4 | See §4 |
| INF-15 | inventory/snapshot version match (retain) | retain | Retained — see §4 | See §4 |
| INF-16 | post-AVFoundation fingerprint/version guard (retain) | retain | Retained — see §4 | See §4 |
| INF-17 | `TagLibDateNativeProjection` snapshot-based overloads | delete | Implemented — b6b07d4f: deleted five zero-caller snapshot-based date projection overloads | Live `values(for:structured:basicYear:fileExtension:)` dispatcher |
| INF-18 | public per-field structured date helpers | simplify | Implemented — b6b07d4f: per-field structured date helpers made private to the projection | Removed; no replacement needs to exist |
| INF-19 | native date identities in conflict groups (retain) | retain | Retained — see §4 | See §4 |
| INF-20 | redundant artwork optional branch | simplify | Implemented — 20532f7e: redundant artwork optional branch simplified to direct optional assignment | Removed; no replacement needs to exist |
| INF-21 | duplicate bookmark-collection persistence in FileAccessGrantStore/WatchedFolderStore | merge | Implemented — c3425cb7: shared `BookmarkCollectionPersistence.swift`; two thin typed stores keep names, keys and behavior; two stale-bookmark refresh tests added | `BookmarkCollectionPersistence` plus two thin typed stores |
| INF-22 | unread `BookmarkCollectionLoadState.loaded(recordCount:)` payload | simplify | Implemented — c3425cb7: unread `recordCount` payload dropped from `BookmarkCollectionLoadState` | `BookmarkCollectionLoadState` without the unread count |
| INF-23 | old-toolchain isolated-deinit fallback | delete | Implemented — 6ce7f020: removed pre-Swift-6.2 isolated-deinit fallback; `isolated deinit` retained | Removed; no replacement needs to exist |
| INF-24 | directory monitoring plan/status (retain) | retain | Retained — see §4 | See §4 |
| INF-25 | unused `UpdateReleaseMetadata` payload fields | delete | Implemented — d60400a0: removed unused `displayName`/`releaseURL` payload and decode guards; four GitHub error/JSON tests added as replacement coverage | `version` + `tagName` are the consumed update payload |
| INF-26 | redundant `MainActor.run` in `UpdateCheckPresenter` | simplify | Deferred — Optional concurrency-idiom simplification in a presenter with no automated test; deferred as low value. | See audit evidence |
| INF-27 | update-check comparison/error behavior (retain) | retain | Retained — see §4 | See §4 |
| INF-28 | `UpdateCheckPresenter.shared` singleton (retain) | retain | Retained — see §4 | See §4 |
| INF-29 | `OnlineMetadataSelectionCore.normalizedPositiveIndex` (retain) | retain | Retained — see §4 | See §4 |
| INF-30 | `OnlineMetadataSelectionCore.representativeFiles` | investigate | Resolved by the providers audit decision (X-2: delete) but not implemented in this campaign; the helper remains test-only | Production representative selection stays in `MusicBrainzClient`; test-only helper remains |
| INF-31 | Online metadata selection summary/majority helpers (retain) | retain | Retained — see §4 | See §4 |

### 3.4 Providers, online browsers and cross-area candidates

| ID | Candidate (audited item) | Decision | Campaign outcome | Owner / replacement |
| --- | --- | --- | --- | --- |
| ITC-1 | test-only parallel iTunes provider core (`iTunesProviderCore.swift`) | investigate | Open investigation — see §5 | Unresolved |
| ITC-2 | iTunes client fallback chain / request builders | retain | Retained — see §4 | See §4 |
| ITC-3 | test-only preferred-URL copies on `iTunesArtworkCoreResult` | simplify | Deferred — Test-only preferred-URL copies; audit marked low priority and allowed retaining them as fast-target samples. | `iTunesArtworkService` preferred URLs remain the production owner; core copies are test samples |
| ITC-4 | artwork service | retain | Retained — see §4 | See §4 |
| ITF-1 | dead `hasFileSelection` in `iTunesBrowserStore` | delete | Implemented — e993270e: removed dead `hasFileSelection` store property | `hasSearchText`/`fileSelectionSummary` |
| ITF-2 | two uncalled iTunes workbench store helpers (`track(for:)`, `isDuplicateAssignment`) | delete | Implemented — e993270e: removed two uncalled iTunes workbench helpers | Retained plan/capture semantics |
| ITF-3 | dead private `iconText` helper in iTunes workbench view | delete | Implemented — e993270e: removed dead iTunes workbench `iconText` helper | Shared AppKit factory helpers |
| ITF-4 | unused 2-argument convenience init in `iTunesBrowserView` | delete | Implemented — e993270e: removed unused 2-argument `iTunesBrowserView` init | 3-argument production init |
| ITF-5 | comparison builders vs workbench `remoteValue` (retained consumer; see MBM-7) | retain | Retained — see §4 | See §4 |
| LRC-1 | dead `LRCLIBLyricsBrowserStore.currentQuery` | delete | Implemented — e993270e: removed dead `currentQuery` store member | `currentFile`/`query` through store actions |
| LRC-2 | LRCLIB infrastructure (request builder/models/ranker/client) | retain | Retained — see §4 | See §4 |
| MBC-1 | duplicated artist-credit join expressions in `MusicBrainzClient` | simplify | Deferred — Intra-file artist-credit join duplication; behavior-neutral but not scheduled. | One private artist-credit join helper in `MusicBrainzClient` |
| MBC-2 | multi-file fallback chain in `MusicBrainzClient` | retain | Retained — see §4 | See §4 |
| MBC-3 | rate limiter / retry / response cache helpers | retain | Retained — see §4 | See §4 |
| MBC-4 | matching/ranking layer (`MusicBrainzMatching.swift`) | retain | Retained — see §4 | See §4 |
| MBM-1 | dead `musicBrainzURL` helpers on result models | delete | Implemented — e993270e: removed three dead `musicBrainzURL` helpers; detail-model URLs retained | Detail-model URL helpers |
| MBM-2 | zero-reference computed properties in `MusicBrainzBrowserStore` | delete | Implemented — e993270e: removed `visibleResultMode` and `hasFileSelection` | Views derive the same state from current query/file summary |
| MBM-3 | zero-reference members in `MusicBrainzTaggingWorkbenchStore` | delete | Implemented — e993270e: removed `recordingPreloadProgress`, `initialScore` and `isDuplicateAssignment` | `recordingPreloadCompletedCount`/`TotalCount` and `duplicateTrackIDs` |
| MBM-4 | dead private `iconText` helper in MB workbench view | delete | Implemented — e993270e: removed dead MB workbench `iconText` helper | Shared AppKit factory helpers |
| MBM-5 | duplicate field-order helper in MB workbench store | simplify | Implemented — e993270e: field ordering now uses `writeOrderIndex` property | `MusicBrainzTagWriteField.writeOrderIndex` |
| MBM-6 | workbench routes / destinations (hypothesis: dead) | retain | Retained — see §4 | See §4 |
| MBM-7 | Comparison builders vs workbench `remoteValue` (duplicate field mapping, retained for different output contracts) | retain | Retained — see §4 | See §4 |
| MBM-8 | workbench `PerformanceProbe` | retain | Retained — see §4 | See §4 |
| MBP-1 | `MusicBrainzProviderCore.deduplicatedIDs` | delete | Deferred — Folded into MBQ-4 by the providers audit; deferred with it. | Covered by MBQ-4 |
| MBQ-1 | `MusicBrainzLuceneQueryBuilder` vs `MusicBrainzProviderLuceneQueryBuilder` (primary lead) | retain | Retained — see §4 | See §4 |
| MBQ-2 | dead derived members of the app `MusicBrainzSearchQuery` / filters | delete | Implemented — e993270e: removed dead `summaryText`, `quantizedDuration` and `normalizedTrackNumber` members and the filters summary; one test-only assertion migrated | Provider Lucene builder owns normalization; app DTO stays lean |
| MBQ-3 | app query/filters/file-input types vs provider DTOs (conversion boundary) | retain | Retained — see §4 | See §4 |
| MBQ-4 | test-only provider DTO surface (dead in production) | delete | Deferred — Test-only provider DTO surface removal is coupled to the fast-core test floor (must rewrite a core test 1:1) and to X-2; deferred as a coordinated follow-up. | Provider Lucene DTOs keep only builder-consumed members; app types own matching/normalization |
| OMB-1 | stale "Xcode 16.4" conditional + comment in virtualized list | simplify | Implemented — 6ce7f020: removed Xcode-16.4 compiler fallback and stale comment; `isolated deinit` observer removal retained | `isolated deinit` + `removeObserver` |
| OMB-2 | "dead workbench selection/route types" hypothesis | retain | Retained — see §4 | See §4 |
| OMB-3 | unused init in online shell | delete | Implemented — e993270e: removed unused 4-argument `OnlineMetadataBrowserView` init | 3-argument production init |
| OMB-4 | virtualization/UI instrumentation | retain | Retained — see §4 | See §4 |
| OMB-5 | shell `iTunesBrowserStore` ownership (duplicate observable state hypothesis) | retain | Retained — see §4 | See §4 |
| X-1 | duplicated comparison-normalization helper (4 identical copies) | merge | Deferred — Shared comparison-normalization helper would add a new Core file and touch four call sites; deferred as a separate behavior-preserving slice. | One shared comparison-normalization helper (new Core file or explicitly named static) |
| X-2 | `OnlineMetadataSelectionCore.representativeFiles` (INF-30) is orphaned by the MBQ-4 decision | delete | Deferred — Provider representative helper chain is test-only; deletion is coordinated with MBQ-4 and the core-test floor; deferred. | `MusicBrainzClient.representativeFilesForReleaseLookup` |
| X-3 | `DirectoryMonitor` has the same `#if compiler(>=6.2)` fallback | simplify | Implemented — 6ce7f020: same toolchain-branch cleanup as OMB-1/INF-23; convention now consistent | `isolated deinit` convention |

### 3.5 Features/Main

| ID | Candidate (audited item) | Decision | Campaign outcome | Owner / replacement |
| --- | --- | --- | --- | --- |
| FM-D01 | `typealias BatchMetadataWriteSummary = BatchMetadataOperationSummary` (`BatchMetadataOperationSummary.swift:171` @f36c2a2e, removed at HEAD) | delete | Implemented — a9e83a2c: migrated 21 references and deleted `BatchMetadataWriteSummary` typealias | `BatchMetadataOperationSummary` |
| FM-D02 | whole file `Features/Main/Views/MiddleListHeaderContextMenuInstaller.swift` (148 lines) | delete | Implemented — 0be0b842: deleted unreachable `MiddleListHeaderContextMenuInstaller.swift` | Removed; no replacement needs to exist |
| FM-D03 | whole file `Features/Main/Views/InspectorPopup.swift` (107 lines) | delete | Implemented — 0be0b842: deleted unreachable `InspectorPopup.swift` | Removed; no replacement needs to exist |
| FM-D04 | whole file `Features/Main/Views/MergedMetadataSectionView.swift` (53 lines) | delete | Implemented — 0be0b842: deleted unreachable `MergedMetadataSectionView.swift` | Removed; no replacement needs to exist |
| FM-D05 | `AudioViewModel+FileActions.swift:6,10,14` `openWithDefaultApp`, `revealInFinder`, `copyFilePath` | delete | Implemented — 2eb51315: deleted dead open/reveal/copy file-action wrappers | `ContentPane` selection handlers |
| FM-D06 | `AudioViewModel+FileActions.removeFromList` (`:18-22`) | delete | Implemented — 2af7fb70: deleted `removeFromList`; test now drives retained `removeQuickImportFile(id:)` | `removeQuickImportFile(id:)` |
| FM-D07 | `AudioViewModel+MetadataFieldImportWrite.swift:5-64` `importMetadataFieldValues` | delete | Implemented — e6828955: deleted orphaned `AudioViewModel+MetadataFieldImportWrite.swift` and its test; plan-write/provider journeys remain the coverage | Captured plan paths (`applyFilenameMetadataPlan`/`applyMetadataExchangeWriteEntries`) |
| FM-D08 | `AudioViewModel+Import.swift:52-54,145-147` `canImportArtwork(for:)` (two overloads) | delete | Implemented — 2eb51315: deleted two uncalled `canImportArtwork` probes | `validateArtworkEditingSupport` preflight |
| FM-D09 | `AudioViewModel.swift:211-262` four convenience inits: `init(metadataPipeline:)`, `init(metadataPipeline:artworkLookupService:artworkLookupOperationTimeout:)`, `init(metadataPipeline:saveIs… | delete | Implemented — 2eb51315: deleted four unused `AudioViewModel` convenience inits | Designated `AudioViewModel` init plus retained preview `init()` |
| FM-D10 | `ContentView.swift:366-420` `currentMusicBrainzSearchSeed()` and its `??` fallback at `ContentView.swift:172` | delete | Implemented — 0be0b842: deleted unreachable MusicBrainz search-seed fallback branch | `currentMusicBrainzMatchSeed()` |
| FM-D11 | `InspectorPane.swift:72-84` `boolBinding(for:keyPath:)` | delete | Implemented — 2eb51315: deleted dead `boolBinding` | Removed; no replacement needs to exist |
| FM-D12 | `MiddleListColumn.swift:199-201` `compareBool` | delete | Implemented — 2eb51315: deleted dead `compareBool` | Removed; no replacement needs to exist |
| FM-D13 | `AudioViewModel+FileRename.swift:13-21` `FileRenameResult.empty`, `:23-25` `FileRenameResult.didSucceed` | delete | Implemented — 2eb51315: deleted `FileRenameResult.empty`/`.didSucceed` | Removed; no replacement needs to exist |
| FM-D14 | `SaveIssueLogStore.swift:51` `static let defaultLimit = 200` | delete | Implemented — 2eb51315: deleted unused `defaultLimit` constant | Removed; no replacement needs to exist |
| FM-D15 | `AudioViewModel.swift:188` `securityScopedSupplementalMutationDirectoryURLs` (plus its read in `activeMutationDirectoryURLs` `:1384` and cleanup in `deinit` `:322`) | delete | Implemented — 2eb51315: deleted never-populated supplemental security-scope registry and its cleanup | Quick-import, watched-folder and grant security scopes |
| FM-D16 | `MetadataFileMutationExecutor.swift:8-10` `MetadataFileMutationSuccess.didReloadFile` | delete | Implemented — 2af7fb70: deleted `didReloadFile`; three assertions migrated to `reloadedFile` | `reloadedFile`/`reloadErrorDescription` |
| FM-D17 | `AudioViewModel+FileRename.swift:46-48` `FileRenameRecoveryItem.rollbackError` | delete | Implemented — 2eb51315: deleted `rollbackError`; two assertions use `rollbackErrors` | `rollbackErrors` |
| FM-D18 | `SingleFileEditModel+Presentation.swift:46-71` `MultiFileEditableTextField.displayName` | delete | Implemented — 2eb51315: deleted `MultiFileEditableTextField.displayName`; assertions use field-guide names | `MetadataFieldGuide.displayName(for:)` |
| FM-D19 | `SingleFileEditModel+Presentation.swift:73-81` `MultiFileExplicitEditState.displayName` | delete | Implemented — 2eb51315: deleted `MultiFileExplicitEditState.displayName` | `InspectorPane` explicit picker labels |
| FM-I01 | `App/Commands/ToolbarEditCommands.swift:81-86` "Save Edits" command calls `viewModel.saveSingleEdits()` | investigate | Open investigation — see §5 | Menu route through `saveInspectorEdits()` if product intent confirms |
| FM-I02 | `AudioViewModel.swift:178` `activeSidebarSelection` vs `SharedState.swift:23` `selectedSidebarItem` | investigate | Open investigation — see §5 | `SharedState` as single sidebar owner if a design decision removes the view-model shadow |
| FM-I03 | `AudioViewModel+MetadataWrite.swift:27-36` `saveInspectorEdits` guards only `metadataSaveProgress`; `AudioViewModel+FileReload.swift:24` reload guards both `isReloadingSelectedFiles` and `m… | investigate | Open investigation — see §5 | One save/reload gating policy after a deterministic reproducer |
| FM-I04 | `AudioViewModel.swift:198,776-787,864` `refreshRequiredFileIDs` retained across remove/re-import | investigate | Open investigation — see §5 | Define recovery-state lifetime across remove/re-import with a real-file test |
| FM-I05 | Session maps grow for removed paths: `fileIDsByKey` (`:179`), `quickImportTokensByURLKey` (`:176`), `appliedFileModelRefreshGenerations`/`pendingMetadataReloadsByID` (`:194-196`), `watchedF… | investigate | Open investigation — see §5 | Prune per-path session caches if measurement justifies it |
| FM-I06 | `ContentView.swift:587-715` `MetadataWriteHUDScreenPresenter.Coordinator` NSPanel | investigate | Open investigation — see §5 | Tear down HUD panel with its hosting view if reproduced |
| FM-I07 | `AudioViewModel.swift:500-544` HUD queue | investigate | Open investigation — see §5 | Bound/coalesce queued HUDs only on product request |
| FM-I08 | `MetadataCancellation.isMessage` string classification (`BatchMetadataOperationSummary.swift:175-187`) + `MetadataWriteExecutionResult.failure(MetadataCancellation.message)` (`MetadataWrite… | investigate | Open investigation — see §5 | Typed cancellation through per-file write results (later slice) |
| FM-I09 | `Formatters.swift` vs `InspectorPane.technicalSection:864-872` | investigate | Open investigation — see §5 | Use shared formatters in technical rows after a display decision |
| FM-M01 | `AudioViewModel+MetadataWrite.swift:287-297` `presentBatchMetadataOperationSummary` vs `AudioViewModel+MetadataClear.swift:147-157` `presentBatchMetadataClearSummary` | merge | Implemented — c44b6d3e: clear path now calls the single `presentBatchMetadataOperationSummary` | `presentBatchMetadataOperationSummary` |
| FM-M02 | 10 per-file result-aggregation switch blocks: `AudioViewModel+MetadataWrite.swift:172-195`; `+MetadataPlanWrite:67-95,183-210`; `+ProviderTaggingWrite:41-67,118-144`; `+LRCLIBLyricsWrite:20… | merge | Deferred — Ten-block result-aggregation consolidation is a medium-risk refactor across all batch paths; not scheduled in this campaign. | `BatchMetadataOperationSummary` recording helpers |
| FM-M03 | `AudioViewModel+MetadataWriteSupport.swift:169-179` (executeMetadataFileMutation) vs `AudioViewModel+TrackRenumbering.swift:159-167` (renumber loop) | merge | Deferred — Shared post-commit warning assembly is behavior-sensitive; deferred. | `MetadataFileMutationSuccess.presentationWarnings` (or free function beside `MetadataCommitWarning`) |
| FM-M04 | `AudioViewModel+MetadataPlanWrite.swift:5-108` vs `:110-224`; `AudioViewModel+ProviderTaggingWrite.swift:4-79` vs `:81-156` | merge | Deferred — Captured-plan execution skeleton consolidation touches filename, exchange and provider write signatures; deferred. | One private `runCapturedMetadataPlan(entries:...)` helper with thin per-feature wrappers |
| FM-M05 | `AudioViewModel+Import.swift` six artwork-preparation blocks: `28-50, 56-83, 85-112` (single) and `120-143, 149-178, 180-209` (multi); plus three identical multi-file failure HUDs at `135-1… | merge | Deferred — Six artwork-preparation blocks have no automated UI coverage; deferred to a maintainer-verified slice. | One artwork-preparation helper; keep single/multi error presentation differences |
| FM-M06 | `TrackRenumberSheet.swift:52-67` preview sequence/pad width vs `AudioViewModel+TrackRenumbering.swift:75-88` execution sequence/pad width | merge | Deferred — Renumber preview/execution sequence sharing is behavior-neutral but not scheduled. | Pure domain `TrackRenumberPlan` sequence/pad helper |
| FM-R01 | `MetadataFileMutationExecutor` + `MetadataFileMutationResult`/`MetadataFileMutationSuccess` | retain | Retained — see §4 | See §4 |
| FM-R02 | `MetadataBatchExecutor` (max 4) | retain | Retained — see §4 | See §4 |
| FM-R03 | `MetadataWriteExecutionResult`/`MetadataWriteSuccessOutcome` (`MetadataWriteSupport.swift:16-24`) | retain | Retained — see §4 | See §4 |
| FM-R04 | `saveInspectorEdits` dispatcher | retain | Retained — see §4 | See §4 |
| FM-R05 | `MetadataWriteHUD` + `MetadataWriteHUDStyle` + `MetadataSaveProgress` (`AudioViewModel.swift:13-107`) | retain | Retained — see §4 | See §4 |
| FM-R06 | `BatchMetadataOperationSummary` + `BatchMetadataWriteIssue` + `BatchMetadataOperationKind` (`BatchMetadataOperationSummary.swift`) | retain | Retained — see §4 | See §4 |
| FM-R07 | `AudioViewModel` generation/cancellation machinery: `quickImportGeneration`, `quickImportTokensByURLKey`, `folderScanTokens`, `watchedFolderMutationEpochs`, `nextFileModelRefreshGeneration`… | retain | Retained — see §4 | See §4 |
| FM-R08 | `RawMetadataApplyResult` + `FileRenameResult` + `TrackRenumberResult` as separate result models | retain | Retained — see §4 | See §4 |
| FM-R09 | `refreshRequiredFileIDs` recovery flag | retain | Retained — see §4 | See §4 |
| FM-R10 | `SaveIssueLogStore` persistence | retain | Retained — see §4 | See §4 |
| FM-R11 | `lastAutomaticReloadFailures` dedup | retain | Retained — see §4 | See §4 |
| FM-R12 | `applyFilenameMetadataPlan`/`applyMetadataExchangeWriteEntries` public signatures | retain | Retained — see §4 | See §4 |
| FM-R13 | `executeBoundedMetadataPlan` wrapper | retain | Retained — see §4 | See §4 |
| FM-R14 | `MetadataCommitWarning` text | retain | Retained — see §4 | See §4 |
| FM-R15 | `InspectorArtworkPreview`, `InspectorArtworkComparisonCache`, artwork lookup session | retain | Retained — see §4 | See §4 |
| FM-R16 | `SharedState` preferences + middle-list ordering cache | retain | Retained — see §4 | See §4 |
| FM-R17 | `AudioViewModel.selectedAudioIDs` + `updateEditForSelection` + `inspectorEditSourceFilesByID` + `completedInspectorEditsByID` | retain | Retained — see §4 | See §4 |
| FM-R18 | `MetadataCancellation` owned-message classification | retain | Retained — see §4 | See §4 |
| FM-R19 | `AudioViewModel()` convenience init + `ContentView_Previews` | retain | Retained — see §4 | See §4 |
| FM-R20 | `activeQuickImportTaskCount` | retain | Retained — see §4 | See §4 |
| FM-S01 | `AudioViewModel.swift:23` stored `let subtitle` in `MetadataWriteHUD` (assigned at `:31`, never read by production; `detailPreview`/`omissionNotice`/`MetadataWriteHUDView` use `summary`/`de… | simplify | Deferred — HUD subtitle storage removal is low value; deferred. | Keep init parameter/split; derive full text for tests |
| FM-S02 | `AudioViewModel.swift:990-992` `ensureRenameDirectoryAccess` | simplify | Implemented — 2eb51315: callers use `ensureMutationDirectoryAccess`; alias removed | `ensureMutationDirectoryAccess` |
| FM-S03 | `InspectorPane.swift:620-628` and `:650-659` unsupported-field reason computed twice per row (Text + `.disabled`) | simplify | Deferred — Duplicate per-row capability computation is a performance-only nicety; deferred. | Compute unsupported reason once per row |

### 3.6 Metadata Editor, Filename & Metadata tool, Settings, Welcome and Help

| ID | Candidate (audited item) | Decision | Campaign outcome | Owner / replacement |
| --- | --- | --- | --- | --- |
| HLP-01 | Field guide data/view/command pipeline | retain | Retained — see §4 | See §4 |
| HLP-02 | Domain field-name catalogs duplicate guide labels (layer boundary prevents reuse) | investigate | Open investigation — see §5 | One shared field-name source (Foundation-only) after a drift test |
| INS-01 | Entire unused raw-metadata inspector sheet | delete | Implemented — 2deff969: deleted unreachable `MetadataInspectorSheet.swift`; live raw dump remains `MetadataDumpSheet` | `MetadataDumpSheet` is the live raw dump |
| ME-01 | Unreachable `store.loadErrorMessage ??` fallback in empty-rows state | delete | Implemented — 2deff969: removed provably unreachable editor load-error fallback | Editor empty state without the dead fallback |
| ME-02 | Redundant `displayName` fallbacks (table cell, edit-field sheet) | delete | Implemented — 2deff969: removed redundant display-name fallbacks in table and entry sheet | `MetadataEditorDraftRows`/`MetadataEditorStore` labels |
| ME-03 | Duplicated uniform/mixed computation | merge | Deferred — Editor uniform/mixed computation merge is coupled to edit-sheet context; deferred. | `MetadataEditorDraftRows` uniform-value helper |
| ME-04 | Unlocalized duplicated "Multiple Values" formatting | merge | Deferred — Localized mixed-value label fix is a user-visible localization change; deferred (English output identical, but needs a decision on commit type). | Shared localized `Multiple Values` constant |
| ME-05 | Duplicated selection-count summary strings | merge | Deferred — Window selection-count summary consolidation spans two features; deferred. | Shared selection-summary formatting helper |
| ME-06 | `MetadataFieldSuggestion.category` stored but never read | delete | Implemented — 2deff969: removed unread `MetadataFieldSuggestion.category` storage | `searchKeys` keeps category text searchable |
| ME-07 | `MetadataFieldValueEditor.minimumHeight` never overridden | retain | Retained — see §4 | See §4 |
| ME-08 | Editor re-reads current snapshot/baseline at present (no duplicate save policy) | retain | Retained — see §4 | See §4 |
| MF-01 | Two superseded private SwiftUI preview clusters + 3 dead `tint` extensions | delete | Implemented — 2deff969: deleted two superseded private SwiftUI preview clusters and dead tint extensions | Live AppKit preview lists |
| MF-02 | Superseded private SwiftUI import-row cluster + dead `csvCell` + dead `tint` | delete | Implemented — 2deff969: deleted superseded private import-row cluster and dead `csvCell`/`tint` | Live AppKit import preview list |
| MF-03 | Unreachable "no issues" guard branches in plan summaries | delete | Implemented — 2deff969: removed two unreachable "no issues" guard branches | `MetadataFilenameStatusPresentation` |
| MF-04 | `MetadataFilenameToolMode` + `@State mode` shadow the selected converter mode; unreachable footer fallback; unused conformances | simplify | Deferred — Filename-tool mode shadow removal touches a large view file with no UI automation; deferred to a maintainer-verified slice. | `selectedConverterMode` is the single mode owner; derive filename presentation |
| MF-05 | Duplicated AppKit row/container support between the two preview files | merge | Deferred — Shared AppKit preview row support touches both preview files; deferred. | One shared AppKit preview row/container factory |
| MF-06 | Duplicated rich-text chip template editors and chip rendering | merge | Deferred — Chip template editor unification is gated by an investigate checklist; deferred. | One parameterized chip template editor (after investigate checklist) |
| MF-07 | Three duplicated status symbol/tint derivations | merge | Deferred — Three status symbol/tint derivations need new unit tests; deferred. | `MetadataFilenameStatusPresentation` symbol/tint mapping |
| MF-08 | Two near-identical "skipped row → BatchMetadataWriteIssue" builders with divergent fallback text | investigate | Open investigation — see §5 | Unresolved |
| MF-09 | `MetadataFilenameToolStore` + `MetadataExchangeExternalTextFileLoader` (dedupe, presentation id, security scope, byte limits, 4 encodings) | retain | Retained — see §4 | See §4 |
| MF-10 | Domain planning/CSV v1+v2/rename/renumber/transfer contracts consumed by this window | retain | Retained — see §4 | See §4 |
| MF-11 | Defensive unreachable switch cases in exchange detail (filename/transfer modes) | retain | Retained — see §4 | See §4 |
| SET-01 | Unused `copyrightText` private helper | delete | Implemented — 2deff969: deleted unused About `copyrightText` helper | `formattedAboutDescription(copyright:)` |
| SET-02 | Legacy persisted settings-tab aliases "toolbar"/"columns"/"inspector" → Interface | retain | Retained — see §4 | See §4 |
| SET-03 | Persisted toggles/keys: welcome completion/version, suppress-discard warning, MuseAmp compatibility, selected tab, conflict policy | retain | Retained — see §4 | See §4 |
| SET-04 | Welcome launch preference write policy duplicated between Settings and ContentView | simplify | Deferred — Welcome launch-preference policy centralization spans Settings and ContentView; deferred. | `WelcomeSplashProgress` launch-preference policy helpers |
| SET-05 | Release-notes loading path appears current and singular | retain | Retained — see §4 | See §4 |
| SET-06 | About privacy/acknowledgements/license sheets read the single `LicenseDisclosure` source | retain | Retained — see §4 | See §4 |
| WEL-01 | Thin `WelcomeSplashView` wrapper around `MacWelcomeSplashView` (residual of removed platform abstraction) | merge | Deferred — Welcome wrapper removal requires a Main-track ContentView edit and maintainer visual check; deferred. | `MacWelcomeSplashView` called directly from the sheet |
| WEL-02 | Never-overridden `topPadding` property and unused `CaseIterable` conformance | delete | Deferred — Dead `topPadding` flexibility removal is coupled to WEL-01; deferred. | Literal 8 (or private constant); drop `CaseIterable` |
| WEL-03 | Welcome completion/version keys and version-3 gating | retain | Retained — see §4 | See §4 |
| WEL-04 | Onboarding copy is mostly plain `String`, not localized | investigate | Open investigation — see §5 | Unresolved |
| X-01 | Stale catalog keys/comments only used by INS-01 | delete | Implemented — 28fe62a6: removed catalog keys used only by the removed inspector sheet | Removed with the dead sheet; catalog pruned |
| X-02 | Stale catalog keys only used by MF-01/MF-02 dead SwiftUI code | delete | Implemented — 28fe62a6: removed catalog keys used only by the removed SwiftUI preview clusters | Removed with the dead preview clusters; catalog pruned |
| X-03 | 33 stale `iPad`/`+iOS` source comments in the shared catalog | investigate | Partially addressed: 28fe62a6 removed 17 stale iPad comment lines with pruned keys; remaining catalog comments are deferred pending an extraction diff | See outcome |
| X-04 | Unused `AppWindowTitle.rawMetadata` convenience | delete | Implemented — e58fa61f: deleted unused `AppWindowTitle.rawMetadata` (with CORE-01) | Removed with CORE-01 |
| X-05 | Stale structure documentation for removed feature folder; MetadataHelp missing | document | Documentation completed in this ledger and the acceptance record: `Docs/Reference/PROJECT_STRUCTURE.md` features table now reflects the removed `MetadataInspector/` folder and adds `MetadataHelp/` | See outcome |
| X-06 | Editor store/target state classes declared in a Views file; consumed by Main feature extension | investigate | Open investigation — see §5 | Unresolved |

### 3.7 Tests, build, scripts and evidence

| ID | Candidate (audited item) | Decision | Campaign outcome | Owner / replacement |
| --- | --- | --- | --- | --- |
| TST-01 | Delete orphaned metadata-field import writer test | delete | Implemented — e6828955: deleted orphaned import-writer test with its production route | Retained plan/provider/editor journeys |
| TST-02 | Delete test-only legacy `writeTrackNumberText` route and its 2 tests | delete | Implemented — 97016668: deleted the two legacy route tests; added typed-path replacement test `testTrackAndDiscNumberIntentWritesRoundTripNumericValuesAcrossWritableAudioFixtures` | Typed number-component round-trip test |
| TST-03 | Delete test-only `rawMetadataPropertyMap` / `writeRawMetadataPropertyMap` property-map route | delete | Implemented — fde7ecb7: rewrote property-map assertions as exact `RawMetadataValueMap` arrays and dropped the property-map half of the existential dispatch test | `RawMetadataValueMap` exact-array assertions |
| TST-04 | Delete test-only `numberingInventory(at:)` protocol requirement | delete | Implemented — f1ff0892: both inventory tests now read `TagLibMetadataManager.numberingInventory` directly | Direct `TagLibMetadataManager.numberingInventory` |
| TST-05 | Delete test-only no-version write/erase conveniences | delete | Implemented — ae07d55f: migrated all no-version write/erase call sites to explicit `expectedVersion:` | Versioned protocol requirements |
| TST-06 | Migrate 24 fake `writeTrackNumberText` stubs with TST-02 | migrate | Implemented — 97016668: removed all 24 forced `writeTrackNumberText` fake stubs with the protocol requirement | Removed with the protocol requirement |
| TST-07 | Delete unused fake member `PausedProviderReloadPipeline.hasCommitted` | delete | Implemented — 7662fc26: removed unused `PausedProviderReloadPipeline.hasCommitted` | `writeCount` |
| TST-08 | Simplify `AudioFileTestFactory` unused parameters | simplify | Implemented — 7662fc26: removed two unused `AudioFileTestFactory` parameters | Explicit `AudioFile` construction for missing fields |
| TST-09 | Migrate `removeFromList` use in the selection/draft test (conditional on task-5) | migrate | Implemented — 2af7fb70: migrated the selection/draft test to `removeQuickImportFile(id:)` | `removeQuickImportFile(id:)` |
| TST-10 | Migrate `MusicBrainzLuceneQueryBuilderTests` if the app facade is consolidated (conditional on task-4) | investigate | Resolved as retain: the app Lucene facade is a real app-DTO→provider-DTO boundary (MBQ-1); no test migration performed | See outcome |
| TST-11 | Simplify CI duplicate core execution | simplify | Open investigation — see §5 | Retain `swift-test` with a documented rationale, or remove it if the gate is the only intended core run |
| TST-12 | Simplify undocumented `--full` build alias | simplify | Implemented — dcae77f3: removed undocumented `--full` alias; `--force` is the only flag | `--force` |
| TST-13 | Simplify `Package.swift` redundant exclude entries | simplify | Implemented — bd149370: reduced `Package.swift` exclude list to five non-Swift resources against the explicit 30-file source list | Explicit `sources:` list plus five non-Swift excludes |
| TST-14 | Cross-target duplicate pure-helper assertions (retained, not obsolete) | retain | Retained — see §4 | See §4 |
| TST-15 | (identifier intentionally unassigned) | unassigned | No candidate exists; identifier intentionally unassigned | — |
| TST-16 | Stale test inventory in `Docs/Development/TESTING.md` (documentation update, not code) | document | Documentation completed: this campaign re-counted the inventory from source and updated `Docs/Development/TESTING.md` (629 app tests/80 classes; 62 core tests/4 classes; 30 SwiftPM files) | See outcome |
| TST-17 | Test-target Swift isolation warning debt (investigate) | investigate | Open investigation — see §5 | Test-target isolation build-setting decision; no suppression |
| TST-18 | Stale `build-taglib-bridge-smoke.sh` candidate path / package-boundary tool (investigate) | investigate | Open investigation — see §5 | Maintainer-only bridge smoke tool; stale candidate fallbacks only |
| TST-19 | SwiftPM fast-target files without core coverage (retain; deliberate boundary) | retain | Retained — see §4 | See §4 |
| TST-20 | Evidence-floor inconsistency (retain; document, do not lower) | retain | Retained — see §4 | See §4 |
| TST-21 | Source-structure assertions in `OnlineMetadataPlanSnapshotTests` (retain; optional simplification) | retain | Retained — see §4 | See §4 |
| TST-22 | Source-absence assertions in `MappingAcceptanceRepairTests` (retain) | retain | Retained — see §4 | See §4 |
| TST-23 | Pinned legacy-logger absence checks in `SensitiveLoggingPolicyTests` (retain) | retain | Retained — see §4 | See §4 |
| TST-24 | `ErrorPresentationRepairTests` behavioral HUD/cancellation/number-pair tests (retain) | retain | Retained — see §4 | See §4 |
| TST-25 | license, network-disclosure, field-guide and dependency-pin contract tests (retain) | retain | Retained — see §4 | See §4 |
| TST-26 | 23 committed fixtures (retain) | retain | Retained — see §4 | See §4 |
| TST-27 | Xcode test-target/scheme membership (retain) | retain | Retained — see §4 | See §4 |
| TST-28 | 24 `AudioMetadataPipeline` test doubles (retain/migrate) | retain | Retained — see §4 | See §4 |
| TST-29 | `interpretingWrite` durability-semantics pinning test (retain) | retain | Retained — see §4 | See §4 |
| TST-30 | `metadataPatchForWrite` pinning tests (retain) | retain | Retained — see §4 | See §4 |
| TST-31 | whole-value-map delta convenience test (retain) | retain | Retained — see §4 | See §4 |
| TST-32 | `codex-build.sh` AppIcon actool false-positive handling (retain) | retain | Retained — see §4 | See §4 |
| TST-33 | prune/validate/evidence scripts (retain) | retain | Retained — see §4 | See §4 |
| TST-34 | performance suites (retain) | retain | Retained — see §4 | See §4 |
| TST-35 | external-text-loader cases in status tests (retain) | retain | Retained — see §4 | See §4 |
| TST-36 | Xcode scheme/project metadata drift (retain, not actionable) | retain | Retained — see §4 | See §4 |
| TST-37 | frozen CRITICAL identity set in the evidence gate (retain) | retain | Retained — see §4 | See §4 |
| TST-38 | source-policy `#filePath` layout dependency (retain) | retain | Retained — see §4 | See §4 |

## 4. Retained-compatibility and protection register

These candidates were not removed or simplified. They cover persisted user data, file-format compatibility, mutation integrity and evidence policy; the audits recorded the consumer and invariant for each. `Retain` candidates also appear in §3 with their decision.

### 4.1 Persisted user data, preferences and file-format compatibility

The campaign removed internal Swift API compatibility only. It did not remove or rename persisted user data or user-file formats. The following are retained with their current consumers:

- **`DOM-26` — CSV header compatibility.** `MetadataExchangeField.propertyMapKey` and the legacy header rule that `DATE` means YEAR remain the persisted external-CSV contract; header aliases do not relax ordering or validation.
- **`DOM-27` — exchange profile v1/v2.** Marker prefix, current v2 and legacy v1 semantics, unknown-version rejection, `<remove>` token/internal sentinel and resource limits are persisted text/CSV behavior. No on-disk or text semantics changed.
- **`DOM-28` — MuseAmp IDs.** The numeric album/track IDs embedded in comment JSON and the `museAmpSupportEnabled` defaults key are written into and read from user files/preferences; the algorithm, JSON shape and key are retained.
- **`DOM-29` — bookmark records.** `WatchedFolderRecord`, `FileAccessGrantRecord` and related `Codable` shapes and `UserDefaults` keys are the persisted security-scoped bookmark store. The shared persistence helper (`c3425cb7`) preserves keys, record shapes, scoped-then-unscoped fallback, unresolved-record retention and corrupt-collection quarantine.
- **`DOM-30` — conflict policy key.** `metadata.conflictPolicy` and all four documented policies remain selectable; unknown/missing values still select `mergeNonConflicting`.
- **`DOM-31` — advisory source dialects.** Exchange (`"1"`, `"2"`, `"true"`) and iTunes (`"explicit"`, `"cleaned"`, `"notexplicit"`) advisory parsers stay separate because they accept different source vocabularies.
- **`APP-R02` — `hasLaunchedBefore`.** Persisted first-launch key is retained untouched; `APP-01` window-sizing investigation must not delete it.
- **`PRJ-R01` — Debug/Release bundle identifiers.** The intentional `.Beta` vs release identifier split is retained because it separates sandbox containers, preferences and bookmarks for existing installations.
- **`SET-02` — legacy settings-tab aliases.** Persisted `settings.selectedTab` values `toolbar`, `columns` and `inspector` still migrate to the Interface tab; unknown values fall back to General.
- **`SET-03` — persisted settings surface.** Welcome completion/version, suppress-discard warning, MuseAmp compatibility, selected tab and conflict policy keys all have live consumers and are retained; no storage-policy/numbering-provenance UI exists.
- **`WEL-03` — welcome progress.** `hasCompletedWelcomeSplash`/`completedWelcomeSplashVersion` and version-3 re-onboarding gating are persisted user data and retained.
- **`L-R01` — 25 stale-flagged field labels.** The catalog marks 25 current package field-label keys as `stale`; they are live through `MetadataFieldGuide.displayName(for:)` dynamic lookup and the field-guide tests. They were not deleted by the localization prune.
- **`L-R02` — dormant localizations.** All non-deleted locale payloads and locale slots are retained even though `CFBundleLocalizations` declares English only; this remains a product/localization decision (`PRJ-03`).
- **`RES-R01` — licenses and `InfoPlist.xcstrings`.** Bundled AGPL/LGPL/MPL/MIT/Boost texts, `LicenseDisclosure` entries, the acknowledgements sheet and `InfoPlist.xcstrings` remain in sync with the unchanged 0.8.1 dependency.
- **`TST-26` — fixtures.** All 23 committed fixtures remain referenced; the campaign deleted no historical failure fixture to reduce counts.

### 4.2 Mutation integrity, concurrency and presentation protections

- **`DOM-23` — guarded writes.** Audio-identity-guarded writes still fail closed: no fallback to unguarded overloads, and unavailable identities throw rather than write. `INF-01`’s consolidation keeps advisory rejection before any write.
- **`DOM-24` — exact raw delta.** `writeRawMetadataValueMap` still computes set/remove/untouched keys exactly and forwards the expected version; `AudioMetadataPipelineContractTests` pins unchanged keys and version forwarding.
- **`DOM-25` — test-double seams and mutation queue observability.** Fail-closed protocol defaults and `queuedMutationCount` remain because they are the only way the reservation/starvation/cancellation tests can observe the queue.
- **`DOM-32` / `DOM-33` / `DOM-34` — distinct matchers, row builders and renumber rules.** Exchange text matching, filename extraction matching, copy/cut transfer rows versus CSV import rows, and renumber clamps/pad width/results have different contracts and were not merged.
- **`INF-08` — durability catch.** `committedButDurabilityUncertain` conversion stays; a committed write is never turned into a retryable failure. Removal needs package-interface evidence (§5).
- **`INF-10` / `INF-11` / `INF-13`–`INF-16` / `INF-19` / `INF-24`.** ID3v1 compatibility notes and raw-dump formatting, the single read retry, native numbering projection and inventory read/version guards, independent native date identities and the directory-monitoring plan/status are live behavior and were retained.
- **`CORE-R01`–`CORE-R04` / `APP-R01` / `APP-R03` / `RES-R02` / `PRJ-R02` / `SCR-R01` / `SCR-R02`.** Retained Core dual-compilation splits (format support and date text), the localization entry-point split, test-host isolation, all 10 notification routes, the accent color, the intentionally empty workspace settings, the evidence-gate floors/CRITICAL identities and the parallel CI core job are unchanged.
- **`MBQ-1` / `MBQ-3` / `MBC-2`–`MBC-4`.** The provider Lucene builder remains the single query-policy owner with the app Lucene facade as the app-DTO→provider-DTO conversion seam; the MusicBrainz fallback chain, rate limiter/response cache/retry policy and matching/ranking layer are retained with their tests.
- **`MBM-6` / `MBM-7` / `MBM-8` / `ITC-2` / `ITC-4` / `LRC-2` / `OMB-2` / `OMB-4` / `OMB-5`.** Provider routes, comparison builders versus captured write intent, performance probes, the iTunes client fallback chain and artwork service, LRCLIB infrastructure, workbench popup mapping, virtualization instrumentation and shell store ownership are retained.
- **`FM-R01`–`FM-R20`.** The per-file mutation executor, bounded batch executor, write-result presentation types, HUD vocabulary/queue, batch summary vocabulary, generation/cancellation machinery, separate result models, recovery flag, save-issue log, reload-failure deduplication, bounded-plan executor, commit-warning wording, artwork preview/cache, presentation preferences, single selection owner, cancellation classification, preview entry points and quick-import accounting all keep their documented invariants.
- **`ME-07` / `ME-08` / `MF-09`–`MF-11` / `SET-05` / `SET-06` / `HLP-01`.** The field-value editor presentation seam, the editor snapshot/baseline refresh protection, the filename-tool store and external-text loader, the CSV/rename/transfer contracts consumed by the window, defensive exchange switches, the single release-notes path and the license/privacy sheets, and the field-guide data/view/command pipeline are retained.

### 4.3 Evidence, test and build-policy surfaces

- **`SCR-R01`** — the app-test floor (579), core floor (62), 13 policy tests and frozen CRITICAL identities were not weakened. The app inventory grew to 629; the core count stayed at 62.
- **`TST-14` / `TST-19`–`TST-38`** — cross-target pure-helper duplication, fast-target files without core coverage, source-structure assertions, source-absence guards, sensitive-logging policy checks, evidence-floor asymmetry, fixtures, Xcode test membership, pipeline-contract pins, the AppIcon build fallback, gate scripts, performance suites, external-text-loader cases, Xcode metadata drift and `#filePath` layout dependencies are retained as documented in the audit. `TST-21`/`TST-22`/`TST-23` remain deliberate source-policy guards, not cleanup debris.

## 5. Investigate register

Open investigations from the audits and campaign. Resolved investigations are listed after the table.

| ID | Item | Exact unknown | Smallest resolution |
| --- | --- | --- | --- |
| APP-01 | First-launch window sizing/centering duplication (`AppDelegate` vs `.defaultSize`) | Unknown: real first-launch window geometry/centering with and without the AppDelegate block. Smallest resolution: maintainer launches two fresh Debug builds with an empty defaults container and compares; `hasLaunchedBefore` remains persisted user data. | See Exact unknown |
| RES-02 | `AppIcon.icon/icon.json` watchOS circle platform | Unknown: whether Icon Composer emitted the watchOS circle platform as a harmless tool default and whether editing `icon.json` changes the compiled icon. Smallest resolution: inspect in Icon Composer on the maintainer machine; otherwise leave untouched. | See Exact unknown |
| PRJ-03 | Localization configuration consistency (`knownRegions`/catalog locales vs `CFBundleLocalizations = [en]`) | Unknown: maintainer intent for the "temporarily disable localization" state (English-only bundle vs dormant translations). Smallest resolution: maintainer states localization intent; then document or trim `knownRegions` without deleting translations. | See Exact unknown |
| PRJ-04 | `CURRENT_PROJECT_VERSION = 26112` versus documentation | Unknown: intended release build-number scheme (`CURRENT_PROJECT_VERSION = 26112` vs docs recording 2697). Smallest resolution: maintainer confirms identity; one explicit `build:`/`docs:` commit updates the setting or the docs. | See Exact unknown |
| SCR-03 | Bridge smoke tooling versus published package layout | Unknown: TagLibAudioMetadata 0.8.1 bridge source layout and `TagLibMetadataExtractor` API used by the maintainer-only smoke tool. Smallest resolution: maintainer runs `bash scripts/build-taglib-bridge-smoke.sh` per `DEBUGGING.md`, or the package owner confirms path/API; then remove dead fallbacks. | See Exact unknown |
| INF-08 | Reachability of thrown `committedButDurabilityUncertain` | Unknown: whether any remaining writer can still throw `committedButDurabilityUncertain` in published 0.8.1. The catch is retained as documented contract; removal needs package-interface evidence and a positive committed-outcome test, not app-source inference. | See Exact unknown |
| ITC-1 | Test-only `iTunesProviderCore` parallel adapter | Unknown: maintainer intent for the test-only `iTunesProviderCore` parallel adapter — delete the fast-test DTO surface (moving URL/link assertions to app-hosted tests) or adopt it in the production client. No production caller exists today. | See Exact unknown |
| MF-08 | Divergent skipped-row fallback text | Unknown: whether the divergent skipped-row fallback text in `applyFilenameMetadata` vs `skippedExchangeIssues` is intended. Smallest resolution: locate product copy/tests for skipped-row text, then unify or document. | See Exact unknown |
| WEL-04 | Onboarding copy localization coverage | Unknown: whether onboarding copy is intentionally English-only or a localization regression. Smallest resolution: maintainer/product decision; converting 26 strings is a localization slice, not cleanup. | See Exact unknown |
| HLP-02 | Domain display-name catalogs versus the field guide | Unknown: whether Domain display-name catalogs drift from `MetadataFieldGuide`. Smallest resolution: app-hosted test comparing overlapping labels; consolidation needs a Foundation-only shared name source. | See Exact unknown |
| X-06 | Editor store/target placement in a Views file | Organization only: `MetadataEditorTarget`/`MetadataEditorStore` are declared in a Views file. Smallest resolution: confirm no source-scan test depends on the path, then move to a ViewModels file; no behavior debt. | See Exact unknown |
| FM-I01 | Save Edits menu command route | Unknown: whether the "Save Edits" menu command should route through `saveInspectorEdits()`. Needs maintainer intent and a route test; current command bypasses the live dispatcher and progress guards. | See Exact unknown |
| FM-I02 | Sidebar selection duplicate ownership | Unknown: whether `SharedState.selectedSidebarItem` should be the single sidebar owner. Needs a design decision; every current write route funnels through `ContentView`, so no defect is reproduced. | See Exact unknown |
| FM-I03 | Save/reload gating interleaving | Unknown: whether save and reload gating can interleave harmfully; no reproducer exists. Needs a deterministic controllable-pipeline test before changing flags. | See Exact unknown |
| FM-I04 | Recovery-state lifetime across remove/re-import | Unknown: whether re-import should clear `refreshRequiredFileIDs`. Needs maintainer product decision and a real-file test; current behavior is conservative. | See Exact unknown |
| FM-I05 | Per-path session cache growth | Unknown: whether per-path session maps grow materially at realistic scale. Needs a repeated import/remove measurement; no user-visible defect established. | See Exact unknown |
| FM-I06 | HUD NSPanel teardown when the main window closes | Unknown: whether closing the main window with a visible HUD leaves an NSPanel. Needs maintainer UI reproduction; automated UI coverage is out of scope. | See Exact unknown |
| FM-I07 | Stale queued HUD product behavior | Unknown: whether queued HUD messages go stale enough to change product behavior. Needs maintainer UX decision; queuing is deliberate. | See Exact unknown |
| FM-I08 | Typed cancellation classification | Unknown: whether to migrate cancellation classification from localized strings to a typed result enum. Needs agreement and presenter/log migration without user-visible text change. | See Exact unknown |
| FM-I09 | Unknown/zero technical-value display | Unknown: intended display for unknown/zero technical values (blank vs `0`). Product decision; current list and Inspector differ. | See Exact unknown |
| TST-11 | CI duplicate core execution | Unknown: whether the CI `swift-test` job is deliberate fast feedback (retain with comment) or duplicate core execution (remove). Needs maintainer intent; the release gate’s own core phase stays mandatory. | See Exact unknown |
| TST-17 | Test-target Swift isolation warning debt | Unknown: whether the test target should be switched to `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` (plus explicit `@MainActor`) or retain the current isolation warnings. Needs a compile trial and a post-change warning count; no suppression is acceptable. | See Exact unknown |
| TST-18 | Bridge smoke tool stale candidate path | Unknown: same package-boundary question as SCR-03 for the bridge smoke tool; maintainer-only execution is forbidden to agents. | See Exact unknown |

Resolved or converted investigations: `DOM-21` and `DOM-22` were resolved by deliberate-difference regression tests in `726e6ec9` instead of consolidation (the two projections have different contracts; a product decision would be required to merge them). `INF-30`/`X-2` were resolved as a providers-area delete decision but are deferred with `MBQ-4`. `TST-10` was resolved as retain: the app Lucene facade is a real boundary and its tests remain. `X-03` was partially addressed by the localization prune; the remaining catalog comments are deferred. `X-05` and `TST-16` are completed by this documentation record.

No investigation above was silently skipped or counted as a removal. The campaign acceptance in the acceptance record is an automated-gate acceptance of the code-complete revision; it does not claim these unknowns are resolved.

## 6. Remaining material duplication not resolved in this campaign

The campaign did not pursue a file-count or line-count target and did not claim that deleting files removed all duplication. The following material duplication remains, with the owning candidate IDs:

| Area | Remaining duplication | Candidate IDs |
| --- | --- | --- |
| Online metadata feature stores | Four byte-equivalent comparison-normalization helpers (`MusicBrainzTaggingWorkbenchStore`, `iTunesTaggingWorkbenchStore`, both comparison builders). | `X-1` |
| Provider test surface | Test-only `iTunesProviderCore` parallel DTO/URL/link adapter; test-only `MusicBrainzProviderCore` DTO members and representative-file helper chain. | `ITC-1`, `MBQ-4`, `MBP-1`, `X-2` |
| MusicBrainz client | Five copies of the artist-credit join expression inside `MusicBrainzClient.swift`. | `MBC-1` |
| Batch write aggregation | Ten per-file result-aggregation switch blocks across the `AudioViewModel` write extensions. | `FM-M02` |
| Post-commit warnings | Durability/reload warning assembly duplicated between `AudioViewModel+MetadataWriteSupport` and `AudioViewModel+TrackRenumbering`. | `FM-M03` |
| Captured plan execution | Parallel plan-execution skeletons for filename/exchange and provider captured plans. | `FM-M04` |
| Artwork import | Six artwork-preparation blocks plus three identical multi-file failure HUDs. | `FM-M05` |
| Renumber preview/execution | Number sequence and pad-width computed twice (sheet preview vs execution). | `FM-M06` |
| Metadata Editor | Duplicated uniform/mixed computation; unlocalized `Multiple Values`; duplicated selection-count summaries. | `ME-03`, `ME-04`, `ME-05` |
| Filename & Metadata tool | Shadow converter-mode state, duplicated AppKit preview row support, two near-identical chip template editors, three status symbol/tint derivations. | `MF-04`, `MF-05`, `MF-06`, `MF-07` |
| Settings/Welcome | Welcome launch-preference policy written in two views; thin `WelcomeSplashView` wrapper and dead `topPadding`/`CaseIterable` flexibility. | `SET-04`, `WEL-01`, `WEL-02` |
| Field labels | Domain exchange/rename label catalogs duplicate field-guide labels across a layer boundary. | `HLP-02` |
| Core/Platform helpers | Pure pass-through platform wrappers (`audiomatorNavigationSubtitle`, scroll-edge style enum/parameter, `localizedUI`). | `CORE-06`, `CORE-07`, `CORE-09` |
| Update presenter | Redundant `MainActor.run`/weak-self flow in `UpdateCheckPresenter`. | `INF-26` |
| Build configuration | Inert `EXCLUDED_SOURCE_FILE_NAMES` and duplicated `INFOPLIST_KEY_*` settings against the custom `Config/Info.plist`; build-relevance allowlist drift; redundant local-package positional indirection. | `PRJ-01`, `PRJ-02`, `SCR-02`, `SCR-01` |
| Test target | Test-host Swift isolation warnings; CI runs the core suite twice; cross-target pure-helper assertions retained by policy. | `TST-17`, `TST-11`, `TST-14` |

Material removals completed: the obsolete internals, unreachable views/resources, legacy pipeline write surfaces and test-only compatibility scaffolding listed as implemented in §3. Those removals were verified by the real compiled test target and gate, not by line counts.

## 7. Deferred candidates and campaign boundary

Candidate outcome counts across the 255 audit candidate IDs (some families are grouped, e.g. `MBM-7`/`ITF-5`): 101 implemented, 33 deferred, 23 open investigate, 7 resolved by test/decision or documentation, and 91 retained without removal. The following audit-proposed changes were not implemented; they are the campaign’s explicit remaining backlog, not an unexplained “later” bucket.

| Candidate IDs | Deferred work | Reason |
| --- | --- | --- |
| `CORE-06` | `audiomatorNavigationSubtitle` is a pure pass-through wrapper | Cross-area 2-call-site wrapper; audit marked it optional and the campaign did not schedule UI-site churn. |
| `CORE-07` | `AudiomatorScrollEdgeEffectStyle` single-value enum + unused `style` parameter | 30-call-site scroll-edge helper simplification; audit marked it optional/low priority; no policy change was required. |
| `CORE-09` | `String.localizedUI` single-use sugar | Single-call localization sugar; audit marked it not worth a standalone commit. |
| `DOM-07` | `Domain/AudioFiles/SingleFileEditModel+MetadataPipeline.swift:5–22` unguarded `init(_ edit: SingleFileEditModel)` | Unguarded test-only payload initializer removal needs a baseline-comparison review of 14 test call sites; not scheduled. |
| `FM-M02` | 10 per-file result-aggregation switch blocks: `AudioViewModel+MetadataWrite.swift:172-195`; `+MetadataPlanWrite:67-95,183-210`; `+ProviderT… | Ten-block result-aggregation consolidation is a medium-risk refactor across all batch paths; not scheduled in this campaign. |
| `FM-M03` | `AudioViewModel+MetadataWriteSupport.swift:169-179` (executeMetadataFileMutation) vs `AudioViewModel+TrackRenumbering.swift:159-167` (renum… | Shared post-commit warning assembly is behavior-sensitive; deferred. |
| `FM-M04` | `AudioViewModel+MetadataPlanWrite.swift:5-108` vs `:110-224`; `AudioViewModel+ProviderTaggingWrite.swift:4-79` vs `:81-156` | Captured-plan execution skeleton consolidation touches filename, exchange and provider write signatures; deferred. |
| `FM-M05` | `AudioViewModel+Import.swift` six artwork-preparation blocks: `28-50, 56-83, 85-112` (single) and `120-143, 149-178, 180-209` (multi); plus… | Six artwork-preparation blocks have no automated UI coverage; deferred to a maintainer-verified slice. |
| `FM-M06` | `TrackRenumberSheet.swift:52-67` preview sequence/pad width vs `AudioViewModel+TrackRenumbering.swift:75-88` execution sequence/pad width | Renumber preview/execution sequence sharing is behavior-neutral but not scheduled. |
| `FM-S01` | `AudioViewModel.swift:23` stored `let subtitle` in `MetadataWriteHUD` (assigned at `:31`, never read by production; `detailPreview`/`omissi… | HUD subtitle storage removal is low value; deferred. |
| `FM-S03` | `InspectorPane.swift:620-628` and `:650-659` unsupported-field reason computed twice per row (Text + `.disabled`) | Duplicate per-row capability computation is a performance-only nicety; deferred. |
| `INF-26` | redundant `MainActor.run` in `UpdateCheckPresenter` | Optional concurrency-idiom simplification in a presenter with no automated test; deferred as low value. |
| `ITC-3` | test-only preferred-URL copies on `iTunesArtworkCoreResult` | Test-only preferred-URL copies; audit marked low priority and allowed retaining them as fast-target samples. |
| `MBC-1` | duplicated artist-credit join expressions in `MusicBrainzClient` | Intra-file artist-credit join duplication; behavior-neutral but not scheduled. |
| `MBP-1` | `MusicBrainzProviderCore.deduplicatedIDs` | Folded into MBQ-4 by the providers audit; deferred with it. |
| `MBQ-4` | test-only provider DTO surface (dead in production) | Test-only provider DTO surface removal is coupled to the fast-core test floor (must rewrite a core test 1:1) and to X-2; deferred as a coordinated follow-up. |
| `ME-03` | Duplicated uniform/mixed computation | Editor uniform/mixed computation merge is coupled to edit-sheet context; deferred. |
| `ME-04` | Unlocalized duplicated "Multiple Values" formatting | Localized mixed-value label fix is a user-visible localization change; deferred (English output identical, but needs a decision on commit type). |
| `ME-05` | Duplicated selection-count summary strings | Window selection-count summary consolidation spans two features; deferred. |
| `MF-04` | `MetadataFilenameToolMode` + `@State mode` shadow the selected converter mode; unreachable footer fallback; unused conformances | Filename-tool mode shadow removal touches a large view file with no UI automation; deferred to a maintainer-verified slice. |
| `MF-05` | Duplicated AppKit row/container support between the two preview files | Shared AppKit preview row support touches both preview files; deferred. |
| `MF-06` | Duplicated rich-text chip template editors and chip rendering | Chip template editor unification is gated by an investigate checklist; deferred. |
| `MF-07` | Three duplicated status symbol/tint derivations | Three status symbol/tint derivations need new unit tests; deferred. |
| `PRJ-01` | `EXCLUDED_SOURCE_FILE_NAMES = Info.plist` is an obsolete leftover | Build-setting removal needs its own Real Xcode Debug/Release build and built-plist check; not scheduled in this campaign. |
| `PRJ-02` | Three `INFOPLIST_KEY_*` duplicates per configuration are inert | Same build-configuration slice as PRJ-01 (generated-plist settings inert against the custom plist); deferred with it. |
| `SCR-01` | `validate-release.sh` local-package source indirection is redundant | Developer-tooling simplification only; not scheduled. |
| `SCR-02` | `codex-build.sh` build-relevance allowlist has drifted from the repository | Developer-tooling allowlist rule needs a synthetic changed-file dry run; not scheduled. |
| `SET-04` | Welcome launch preference write policy duplicated between Settings and ContentView | Welcome launch-preference policy centralization spans Settings and ContentView; deferred. |
| `TST-11` | Simplify CI duplicate core execution | CI duplication decision needs maintainer intent; deferred. |
| `WEL-01` | Thin `WelcomeSplashView` wrapper around `MacWelcomeSplashView` (residual of removed platform abstraction) | Welcome wrapper removal requires a Main-track ContentView edit and maintainer visual check; deferred. |
| `WEL-02` | Never-overridden `topPadding` property and unused `CaseIterable` conformance | Dead `topPadding` flexibility removal is coupled to WEL-01; deferred. |
| `X-1` | duplicated comparison-normalization helper (4 identical copies) | Shared comparison-normalization helper would add a new Core file and touch four call sites; deferred as a separate behavior-preserving slice. |
| `X-2` | `OnlineMetadataSelectionCore.representativeFiles` (INF-30) is orphaned by the MBQ-4 decision | Provider representative helper chain is test-only; deletion is coordinated with MBQ-4 and the core-test floor; deferred. |

Campaign boundary: the automated gate proves the code-complete revision compiles, passes the complete named test inventory, builds Release and validates the artifact. It does not prove any deferred candidate is safe to remove now, and it does not cover interactive UI, signing, notarization, distribution, live network behavior or the external package boundary. The acceptance record states this boundary explicitly.

## 8. References

- Handoff plan: [AudioMator accumulated-code cleanup implementation plan](AUDIOMATOR_LEGACY_CLEANUP_PLAN_2026-11-17.md) (2026-11-17; preserved handoff document, not current guidance).
- Handoff prompt: [AudioMator legacy cleanup agent handoff prompt](AUDIOMATOR_LEGACY_CLEANUP_AGENT_PROMPT_2026-11-17.md) (2026-11-17; preserved handoff document).
- Acceptance: [AudioMator legacy cleanup automated acceptance](AUDIOMATOR_LEGACY_CLEANUP_ACCEPTANCE_2026-11-18.md).
- Audit evidence: `.tmp/cleanup/audit-app-core.md`, `audit-domain.md`, `audit-infrastructure.md`, `audit-providers.md`, `audit-features-main.md`, `audit-features-editor.md`, `audit-tests-build.md` (read-only, 2026-11-18; `.tmp/` is git-ignored).
- Gate evidence: `.deriveddata-codex/Validation/20261118-104501-44211/` (`source.txt`, `policy.log`, `core.log`, `core-gate.json`, `app.log`, `test-summary.json`, `test-tree.json`, `test-gate.json`, `AppTests.xcresult`, `release.log`, `artifact.log`); baseline Debug evidence `.deriveddata-codex/Validation/20261118-094024-15062/`. Both paths are git-ignored outputs.
- Current guidance updated by this campaign: [Testing](../Development/TESTING.md), [Metadata Pipeline](../Architecture/METADATA_PIPELINE.md), [Dependency Rules](../Architecture/DEPENDENCY_RULES.md), [Build](../Development/BUILD.md), [Project Structure](../Reference/PROJECT_STRUCTURE.md), [Security and Data Integrity](../Security/SECURITY_AND_DATA_INTEGRITY.md), [Architecture Overview](../Architecture/OVERVIEW.md) and the [Engineering Notes index](README.md).

