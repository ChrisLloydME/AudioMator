# Fast Core-Logic Test Gaps

The SwiftPM `AudioMatorCoreLogicTests` target is intentionally limited to deterministic, non-UI, non-TagLib, non-network behavior. Current fast coverage includes text editing, track/disc number parsing, rename template parsing and sanitizing, rename collision policy, filename-to-metadata matching, metadata exchange CSV/import/export planning cores, LRCLIB request/ranking logic, iTunes artwork/request normalization, iTunes and MusicBrainz provider query/link/selection helpers, fuzzy matching, MuseAmp ID generation, audio-format support policy, file collection ordering/grouping, merged metadata policy, duplicate detection, and artwork replacement decisions.

App-hosted Xcode coverage now includes TagLib read/write round trips, artwork writes, raw property-map removal, inspector-style clearing, and track/disc number normalization across the committed audio fixtures.

Large-file split progress: `AudioViewModel+MetadataWrite.swift` has started moving unrelated operations out; batch track renumbering now lives in a dedicated `AudioViewModel+TrackRenumbering.swift` extension while preserving the existing write path. `MetadataFilenameRenameSheet.swift` has started moving the converter picker into `MetadataConverterModePickerView.swift`, preview-only SwiftUI components into `MetadataFilenamePreviewLists.swift`, metadata exchange previews into `MetadataExchangePreviewLists.swift`, and AppKit token editors into `MetadataFilenameTemplateEditors.swift`; rename, filename-to-metadata, and metadata exchange behavior remains covered by fast planning tests plus app build checks. `MetadataEditorWindow.swift` has moved text-transform utility sheet UI into `MetadataTextUtilitiesSheet.swift`, field entry/autocomplete UI into `MetadataFieldEntrySheet.swift`, and NSTableView bridging into `MetadataEditorTable.swift` while keeping the raw property-map store and write path unchanged.

Remaining behavior that still needs app-hosted Xcode tests or future small helper extraction:

- Additional TagLib fixture formats beyond the currently committed mp3, m4a, flac, aac, ogg, and wav samples.
- Full `AudioViewModel` orchestration around selection sync, HUDs, watched-folder scans, filesystem writes, and user-initiated batch actions.
- Provider network clients, DTO decoding, rate limiting, and live request execution. Fast tests cover deterministic request/link/query helpers only.
- MusicBrainz Lucene query construction and link parsing now have fast core coverage through provider-core helpers, with app-hosted tests retaining client type adaptation and error mapping coverage.
- Full iTunes and MusicBrainz album/track matching still embedded in provider result types where extracting it would require a broader model move.
- Embedded lyrics application paths that flow through `AudioViewModel`, raw metadata pipelines, or TagLib-backed writes.
- Platform-specific SwiftUI/AppKit/iPad view state that is best verified by app-hosted tests or compile/build checks.
