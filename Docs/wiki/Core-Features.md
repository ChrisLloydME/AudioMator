# Core Features

AudioMator is organized around local audio metadata inspection, editing, verification, and enrichment.

## Metadata Editing

AudioMator has two editing surfaces:

- Inspector: a simpler interface for common fields and everyday metadata edits.
- Metadata Editor: a lower-level editor for TagLib PropertyMap fields. Its canonical model preserves ordered value arrays, duplicates, whitespace, empty values, and literal semicolons; one line in the editor represents one value.

Related code is under `AudioMator/Features/Main/Views/InspectorPane.swift`, `AudioMator/Features/MetadataEditor/`, and the metadata-write extensions in `AudioMator/Features/Main/ViewModels/`.

## Artwork Handling

AudioMator can replace artwork from local images or clipboard data. iTunes artwork lookup is an explicit online workflow that uses Apple iTunes Search API and Apple artwork CDN hosts.

## Automatic Track Number Assignment

Users can reorder audio files in the center list and generate track numbers from that order. `AudioMator/Domain/TrackRenumber/TrackRenumber.swift` contains the core model for direction, start number, zero padding, failures, warnings, and result reporting. `AudioMator/Features/Main/Views/TrackRenumberSheet.swift` provides the UI.

## Metadata and Text Conversion

AudioMator supports six converter modes:

- Metadata to Filename.
- Filename to Metadata.
- Metadata to Text.
- Text to Metadata.
- Metadata to CSV.
- CSV to Metadata.

The filename modes keep file extensions intact, parse filename stems through templates, and preview rename or write plans before applying them. Text and CSV modes export one record per selected file or import records back into writable metadata fields. CSV supports comma, semicolon, pipe, and tab dialects, RFC-style quoted fields, embedded line breaks, optional headers, and reversible spreadsheet-formula protection. Imports can match by selection order or by unambiguous file-name, base-name, absolute-path, relative-path, and index locators.

Relevant code lives in:

- `AudioMator/Domain/Rename/`
- `AudioMator/Domain/MetadataExchange/`
- `AudioMator/Features/MetadataFilenameTool/`

The tool builds preview plans before applying writes. Invalid typed values, ambiguous or duplicate matches, missing source fingerprints, and files changed after preview fail closed. Blank cells do not clear tags unless the user enables clearing. Plain-text templates do not escape separators or line breaks, so CSV is the reversible choice for complex values. Batch writes are serialized and reported per file rather than committed atomically as one batch.

## Online Metadata Lookup

The online metadata source picker includes:

- MusicBrainz for release, recording, relationship, credit, and MusicBrainz ID lookup.
- iTunes for catalog metadata from tags, filenames, UPCs, links, and store IDs.
- LRCLIB for synced lyrics from selected track metadata.

Implementations are under `AudioMator/Infrastructure/MusicBrainz/`, `AudioMator/Infrastructure/iTunes/`, and `AudioMator/Infrastructure/LRCLIB/`. The shared Online Metadata window shell and source picker live under `AudioMator/Features/OnlineMetadataBrowser/`; provider-specific UI flows live under `AudioMator/Features/MusicBrainzBrowser/`, `AudioMator/Features/iTunesBrowser/`, and `AudioMator/Features/LRCLIBLyricsBrowser/`.

## Tag Inspector and Raw Metadata

Tag Inspector is a read-only view for raw tags and file properties detected by AudioMator. The editable raw surface is TagLib's PropertyMap projection, not every container-native frame or atom. Saves are delta based, so an edited key does not reconstruct unrelated metadata. The test suite covers exact multi-value round trips, raw property-map removal, and TagLib structured reads.

## Metadata Editor Utilities

The Metadata Editor includes text utilities for single-file and multi-file workflows. The text pipeline supports trimming, find/replace, case conversion, prefix/suffix insertion, whole-text matching, and case-sensitive matching.

## Track and Disc Number Model

AudioMator treats these as structured fields:

- `Track Number`
- `Total Tracks`
- `Disc Number`
- `Total Discs`

Different containers store these values differently across ID3v2, PropertyMap-style formats, and MP4/M4A. Post-write verification distinguishes harmless container normalization from a real write mismatch where possible.

## Supported Formats

AudioMator discovers readable, metadata-writable, and artwork-writable extensions from `TagLibAudioMetadata` at runtime through `AudioFormatSupport`. Format-specific behavior depends on the underlying container and TagLib support. The committed audio fixtures currently cover `mp3`, `m4a`, `flac`, `aac`, `ogg`, and `wav`.
