# AudioMator Test Coverage Map

This map records the current automated coverage baseline for the main app behavior areas. The expected behavior baseline is the current commit plus characterization tests already present in `Tests/AudioMatorCoreLogicTests` and `AudioMatorTests`.

## Baseline

- Initial worktree check for this pass: `git status --short` was clean before edits.
- Fast deterministic target: `swift test --filter AudioMatorCoreLogicTests`.
- App-hosted coverage: `AudioMatorTests` through the `AudioMator` Xcode scheme.
- Committed audio fixtures: mp3, m4a, flac, aac, ogg, wav, plus metadata-exchange flac fixtures and artwork fixture.

## Coverage Matrix

| Area | Current automated coverage | Primary files |
| --- | --- | --- |
| Track/disc parsing and display | Fast tests cover raw text preservation, numeric fallback, total clearing, strict numeric fields, and write-expectation matching. App-hosted TagLib tests cover cross-format text writes and container normalization. | `AudioTagNumberPairTests.swift`, `AudioMatorCoreLogicTests.swift`, `TagLibReadWriteIntegrationTests.swift` |
| Metadata read/write pipeline | App-hosted integration tests cover structured reads, raw dumps, core metadata round trips, track/disc round trips, erase-all, raw property-map removal, advisory writes, and inspector-style clears. | `TagLibReadWriteIntegrationTests.swift` |
| Artwork | App-hosted tests cover write and clear for primary committed formats with image fixture data. Fast tests cover artwork support and replacement-decision policy. | `TagLibReadWriteIntegrationTests.swift`, `AudioMatorCoreLogicTests.swift` |
| Raw metadata editor | App-hosted tests cover draft row construction, multi-target edits, raw property-map apply, deletion, text utilities, and reload behavior. | `MetadataEditorStoreTests.swift`, `MetadataEditorDraftRowsTests.swift`, `InspectorAndMetadataEditorWorkflowTests.swift` |
| Inspector writes and batch writes | App-hosted tests cover stale edit rejection, single and multi-file writes, modified-field filtering, provider/tagging plans, imported values, MuseAmp comments, progress completion, warnings, and refreshes. | `InspectorAndMetadataEditorWorkflowTests.swift`, `BatchMetadataOperationSummaryTests.swift`, `SaveIssueLogStoreTests.swift` |
| Metadata exchange and filename tools | App-hosted tests exercise the production rename, filename-to-metadata, and metadata-exchange planners, including fixture import/export planning and status text. Fast tests cover only shared CSV parsing, locator indexing, export budgets, rename parsing/collision policy, and filename matching helpers used by production. | `MetadataExchangeTests.swift`, `MetadataExchangeFixtureTests.swift`, `FilenameMetadataTemplateTests.swift`, `FileRenameTemplateTests.swift`, `FileRenameTransactionTests.swift`, `MetadataFilenameStatusPresentationTests.swift`, `AudioMatorCoreLogicTests.swift` |
| Track renumbering | Fast tests cover pad width policy. App-hosted tests cover write verification, disk readback refresh, and mutation serialization with metadata writes/erase. | `TrackRenumberTests.swift`, `TrackRenumberExecutionTests.swift`, `FileMutationSerializationTests.swift` |
| Online metadata providers | Fast and app-hosted tests cover deterministic MusicBrainz/iTunes request/query/link helpers, selection summaries, comparison rows, captured plan snapshots, file fingerprint rejection, result models, and explicit state mapping. | `MusicBrainz*Tests.swift`, `iTunesMetadataComparisonBuilderTests.swift`, `OnlineMetadataPlanSnapshotTests.swift`, `AudioMatorCoreLogicTests.swift` |
| LRCLIB lyrics | Fast and app-hosted tests cover request building, decoding, ranking, store no-result/cancel/queue behavior, and synced-lyrics raw property-map write path. | `LRCLIBLyricsTests.swift`, `AudioMatorCoreLogicTests.swift` |
| File collection, rename, and filesystem mutation | Fast tests cover sorting, grouping, duplicate detection, rename planning, and rename cycles. App-hosted tests cover transactions and rollback reporting. | `AudioMatorCoreLogicTests.swift`, `FileRenameTransactionTests.swift`, `DirectoryMonitoringPlanTests.swift` |
| Watched folders | App-hosted tests cover bounded directory-monitor planning and degraded status text. Current UI persistence and bookmark failures remain best-effort and compile-guarded. | `DirectoryMonitoringPlanTests.swift` |
| Updates and release notes | App-hosted tests cover semantic version comparison, update result mapping, GitHub release metadata, rate-limit mapping, and markdown block parsing. | `UpdateCheckerTests.swift`, `GitHubAPIRequestTests.swift`, `ReleaseMarkdownBlockTests.swift` |
| Logging/privacy hygiene | App-hosted policy tests prevent reintroducing metadata value logging, warning payload printing, and app-source `print`/`debugPrint`/`NSLog` calls. | `SensitiveLoggingPolicyTests.swift` |
| Platform-specific UI | Covered mainly by app build checks and focused view-model/presentation tests. Full SwiftUI/AppKit/iPad interaction remains outside fast deterministic coverage. | `AudioMatorTests`, Xcode build |

## Metadata Pipeline Risk List

| Risk | Current status |
| --- | --- |
| Container-normalized track/disc text could look like a failed write | Covered. Tests assert numeric round-trip and accept documented text normalization where containers drop total text. |
| Raw property-map removal may leave MP4 freeform atoms behind | Covered for m4a freeform deletion, track total deletion, and inspector-style text clearing. |
| Erase-all differs by format support | Covered as best effort across committed writable fixtures for common fields and structured numbers. |
| Artwork support varies by container | Covered for primary committed artwork-capable fixtures; additional formats need new committed fixtures. |
| Advisory/explicit metadata could overwrite sibling fields or map non-advisory values incorrectly | Covered for explicit, clean, not-explicit, unset, and non-advisory raw values. |
| Concurrent file mutations can overlap | Covered by shared reservation tests for write, erase, renumber, and normalized URL aliases. |
| Diagnostic logging can leak file paths or metadata context | Covered by source policy tests; current app source contains no `print`, `debugPrint`, or `NSLog` calls. |

## Remaining Gaps

- Additional TagLib fixture formats beyond the committed mp3, m4a, flac, aac, ogg, and wav samples.
- Full end-to-end `AudioViewModel` orchestration for watched-folder scans, filesystem write failures, HUD timing, and user-initiated batch UI actions.
- Live provider network execution, DTO/rate-limit behavior beyond deterministic client/request tests, and service-side changes.
- Embedded lyrics paths that require full TagLib-backed format writes beyond the current LRCLIB raw property-map path.
- Platform-specific SwiftUI/AppKit/iPad UI behavior that is best covered by app-hosted UI tests, manual QA, or future helper extraction.
