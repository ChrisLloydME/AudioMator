# Fast Core-Logic Test Gaps

The SwiftPM `AudioMatorCoreLogicTests` target is intentionally limited to deterministic, non-UI, non-TagLib, non-network behavior. Current fast coverage includes text editing, track/disc number parsing, rename template parsing and sanitizing, rename collision policy, filename-to-metadata matching, metadata exchange CSV/import/export planning cores, LRCLIB request/ranking logic, iTunes artwork/request normalization, iTunes and MusicBrainz provider query/link/selection helpers, fuzzy matching, MuseAmp ID generation, audio-format support policy, file collection ordering/grouping, merged metadata policy, duplicate detection, and artwork replacement decisions.

Remaining behavior that still needs app-hosted Xcode tests or future small helper extraction:

- TagLib read/write round trips and container-specific metadata normalization.
- Full `AudioViewModel` orchestration around selection sync, HUDs, watched-folder scans, filesystem writes, and user-initiated batch actions.
- Provider network clients, DTO decoding, rate limiting, and live request execution. Fast tests cover deterministic request/link/query helpers only.
- Full iTunes and MusicBrainz album/track matching still embedded in provider result types where extracting it would require a broader model move.
- Embedded lyrics application paths that flow through `AudioViewModel`, raw metadata pipelines, or TagLib-backed writes.
- Platform-specific SwiftUI/AppKit/iPad view state that is best verified by app-hosted tests or compile/build checks.
