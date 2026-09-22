# User Guide

Exact button placement may change as the UI evolves, but the main workflows are stable.

## Import Files

AudioMator supports current-session imports and persistent watched folders. Session import is useful for one-off edits. Watched folders keep folders available across launches and are shown in the sidebar.

## Inspect and Edit Common Fields

Select a file and use the Inspector for common metadata fields. The Inspector is the everyday editing surface. When you save, AudioMator writes through its metadata pipeline and performs verification where the pipeline supports it.

Use the Metadata Editor when you need lower-level control over available metadata fields, including adding, removing, or editing a wider field set.

## Clean Text in Batches

Metadata Editor Utilities can apply text cleanup across fields. The text pipeline covers edge trimming, find/replace, case transforms, and prefix/suffix insertion. These operations are useful for normalizing title, artist, album, or other repeated fields.

## Renumber Tracks

Arrange files in the intended order, then open Renumber Tracks. The feature can generate track numbers based on the visible order or selected rows. Before writing, confirm both the list order and the selected range.

## Convert Between Filenames and Metadata

The Filename & Metadata tool supports six modes:

- Metadata to Filename.
- Filename to Metadata.
- Metadata to Text.
- Text to Metadata.
- Metadata to CSV.
- CSV to Metadata.

Review the preview carefully before applying changes, especially with complex filenames, irregular delimiters, or unusual metadata values.

Text export and import use one record per line and a literal template such as
`{{fileName}} | {{artist}} | {{title}}`. Plain text has no escaping syntax: use
CSV if a value can contain a line break or the template's literal separators.

CSV column templates accept comma, semicolon, pipe, or tab delimiters. CSV
supports quoted fields, doubled quotes, embedded delimiters and line breaks,
optional headers, and spreadsheet-formula protection on export. AudioMator can
open UTF-8, UTF-16, Windows-1252, and Mac Roman text files; exported files use
UTF-8 and CSV rows use CRLF line endings.

Imports with File Name, Base Name, Path, Relative Path, or Index fields match
each record to the selected files using all supplied locators. Without a locator,
records match selected files in selection order. Ambiguous matches, duplicate
records for one file, missing records, extra records, invalid typed values, and
files changed since preview are not written. Empty imported values are ignored
unless the clear-empty-values option is enabled.

The converter accepts at most 100,000 files or records and 32 MB of source or
generated text. Plain-text records are limited to 256 KB and CSV fields to 1 MB.
Writes are verified per file but are not an all-or-nothing batch transaction, so
the result summary may contain both successes and failures.

## Use Online Metadata Sources

The Online Metadata window hosts MusicBrainz, iTunes, and LRCLIB workflows. Using these features sends search terms or identifiers to the selected service. Ordinary local audio file contents are not uploaded for these lookup workflows.

MusicBrainz is suited to releases, recordings, relationships, credits, identifiers, and MusicBrainz IDs. iTunes is suited to Apple catalog metadata, UPC/link/store ID lookup, and artwork candidates. LRCLIB is suited to synced lyrics lookup and can review multiple selected files one by one.

## Customize the Workspace

Settings includes General, Toolbar, Columns, Inspector, and About tabs. Toolbar settings control which toolbar buttons are visible. Column settings control the center list. Inspector settings control which metadata fields appear in the right-side inspector.

## Inspect Raw Tags

Use Tag Inspector to see raw tags and file properties detected by AudioMator. This is the first place to check when a written value looks different after saving, when a container normalizes track/disc text, or when TagLib behavior differs by format.

## Check for Updates

The app includes a manual Check for Updates flow. It queries GitHub Releases, compares the release tag version in the form `V{version}B{build}`, and opens the GitHub Releases page when a download is available.

The update dialog opens GitHub Releases for manual download. It does not silently install updates.
