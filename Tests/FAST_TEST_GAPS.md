# Fast Core-Logic Test Gaps

The SwiftPM `AudioMatorCoreLogicTests` target is intentionally limited to deterministic, non-UI, non-TagLib, non-network behavior. Current fast coverage includes text editing, track/disc number parsing, rename template parsing and sanitizing, filename-to-metadata matching, CSV parsing/serialization, LRCLIB request/ranking logic, fuzzy matching, and MuseAmp ID generation.

Remaining behavior that still needs app-hosted Xcode tests or future small helper extraction:

- TagLib read/write round trips and container-specific metadata normalization.
- Full metadata exchange import plans that need `AudioFile` and `SingleFileEditModel`.
- Full metadata-to-filename rename plans that need real destination existence checks.
- iTunes and MusicBrainz album/track matching and Lucene query construction still embedded in larger provider files.
- Artwork replacement and embedded lyrics application paths that flow through `AudioViewModel` or raw metadata pipelines.
- Sorting, filtering, grouping, and selection behavior owned by SwiftUI/AppKit view models.
