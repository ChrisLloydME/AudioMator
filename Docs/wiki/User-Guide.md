# User Guide

Exact button placement may change as the UI evolves, but the main workflows are stable.

## Import Files

On macOS, AudioMator supports current-session imports and persistent watched folders. Session import is useful for one-off edits. Watched folders keep folders available across launches and are shown in the sidebar.

On iPadOS, files are imported through session-scoped document picking. The app does not keep a watched-folder model on iPadOS.

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

## Use Online Metadata Sources

The Online Metadata window hosts MusicBrainz, iTunes, and LRCLIB workflows. Using these features sends search terms or identifiers to the selected service. Ordinary local audio file contents are not uploaded for these lookup workflows.

MusicBrainz is suited to releases, recordings, relationships, credits, identifiers, and MusicBrainz IDs. iTunes is suited to Apple catalog metadata, UPC/link/store ID lookup, and artwork candidates. LRCLIB is suited to synced lyrics lookup and can review multiple selected files one by one.

## Customize the Workspace

On macOS, Settings includes General, Toolbar, Columns, Inspector, and About tabs. Toolbar settings control which toolbar buttons are visible. Column settings control the center list. Inspector settings control which metadata fields appear in the right-side inspector.

On iPadOS, Settings focuses on list metadata and About information.

## Inspect Raw Tags

Use Tag Inspector to see raw tags and file properties detected by AudioMator. This is the first place to check when a written value looks different after saving, when a container normalizes track/disc text, or when TagLib behavior differs by format.

## Check for Updates on macOS

The macOS app includes a manual Check for Updates flow. It queries GitHub Releases, compares the release tag version in the form `V{version}B{build}`, and opens the GitHub Releases page when a download is available.

The update dialog opens GitHub Releases for manual download. It does not silently install updates.
