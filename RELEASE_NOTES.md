# AudioMator Release Notes

## Current Release Overview

AudioMator is now a local-first macOS audio metadata editor with a full three-pane workflow for browsing files, inspecting tags, editing metadata, managing artwork, and applying focused batch operations. The app is designed around native macOS interactions, with session-based imports for quick one-off work and persistent watched folders for longer-lived libraries.

## Highlights

- Native macOS three-column layout with sidebar, file list, and inspector
- Session-based file imports for temporary editing work
- Persistent watched folders that remain available across launches
- Automatic watched-folder refresh when directory contents change
- Single-file metadata editing and multi-file shared-field editing
- Embedded artwork preview and editing
- Raw metadata inspection through a Tag Inspector sheet
- Batch track renumbering based on the current list order
- Finder and clipboard utilities for loaded files
- Local processing with no account, cloud sync, or remote upload workflow

## Library and File Management

- Import local audio files into a temporary `Session Files` list
- Browse loaded files in a table with `Filename`, `Title`, `Artist`, `Album`, and `Duration`
- Select one file, multiple files, or all loaded files
- Reorder files in the center list with drag and drop
- Use the current visible order as the source order for batch track renumbering
- Clear the current session list with confirmation
- Keep watched folders pinned in the sidebar across launches
- View either `All Watched Files` or a specific watched folder
- Remove watched folders from the sidebar
- Deduplicate watched-folder entries and normalize file identity across rescans

## Metadata Inspection

- Inspect single-file metadata in the right-side Inspector
- View merged multi-selection metadata when several files are selected
- Review read-only technical information:
  - Duration
  - Bitrate
  - Sample rate
  - Channel count
  - Format
- Review read-only `Credits` data when available
- Open a `Tag Inspector` sheet to inspect raw metadata from the selected file or files
- See TagLib-derived raw properties and ID3v2 frame details when available
- See AVFoundation metadata output in the same dump for broader inspection coverage
- Copy the raw metadata dump to the clipboard

## Metadata Editing

AudioMator currently supports editing these user-facing metadata fields:

- Title
- Artist
- Album
- Composer
- Genre
- Year
- Track Number
- Disc Number
- Comment
- Album Artist
- Release Date
- Publisher
- Copyright
- Explicit status

Additional editing behavior:

- Save metadata changes back to disk through the TagLib write path
- Cancel pending inspector edits without saving
- Detect unsaved inspector changes
- Show a confirmation dialog before discarding unsaved edits when changing selection or hiding the Inspector
- Keep untouched fields unchanged during multi-file editing, even when selected files contain mixed values
- Show `Multiple Values` placeholders for mixed multi-file fields
- Display save feedback with success, warning, partial-save, and failure HUD states

## Artwork Support

- Display embedded artwork in the Inspector
- Double-click artwork to replace or add cover art for a single file
- Import artwork from the clipboard
- Clear artwork from a file
- Replace artwork across multiple selected files
- Clear artwork across multiple selected files
- Keep existing artwork unchanged during a multi-file edit session
- Preview shared, missing, mixed, or pending artwork states before saving

## Batch and Utility Tools

- Batch-renumber track numbers from the current list order
- Run renumbering on the full list or only on the current selection
- Choose ascending or descending numbering
- Set a custom starting number
- Optionally pad numbers with leading zeros
- Review renumbering results with counts for succeeded, skipped, and failed files
- Open selected files in their default app
- Reveal selected files in Finder
- Copy selected file paths
- Copy selected filenames
- Clear supported metadata fields from selected files through the `Erase All Tags` action

## Editing Experience and UI Workflow

- Show and hide the Inspector from the toolbar or View menu
- Use a quick-edit sheet for text-heavy metadata fields
- Preview whitespace and hidden characters in a monospaced live preview while editing long text
- Access toolbar actions from the menu bar
- Use keyboard shortcuts for common commands such as `Select All` and `Add Files`
- Open a multi-page welcome screen on first launch
- Reopen the welcome screen later from the Help menu

## Supported Format Coverage

### File discovery and loading

AudioMator currently scans or imports common local audio formats including:

- `mp3`
- `aac`
- `m4a`
- `m4b`
- `m4p`
- `mp4`
- `wav`
- `aiff`
- `aif`
- `flac`

### Metadata writing

AudioMator currently writes metadata for:

- `mp3`
- `mp2`
- `aac`
- `m4a`
- `m4b`
- `m4p`
- `mp4`
- `flac`
- `wav`
- `aiff`
- `aif`

### Embedded artwork writing

AudioMator currently writes embedded artwork for:

- `mp3`
- `mp2`
- `aac`
- `m4a`
- `m4b`
- `m4p`
- `mp4`
- `flac`

## Current Notes and Limitations

- `Credits` are currently displayed as read-only information
- Artwork writing is not available for every writable metadata format
- The `Erase All Tags` command is best understood as a best-effort metadata-clearing action for supported fields, not a universal deep tag wipe across every format
- Manual file import is disabled while a watched-folder source is selected
- Session file lists are temporary and are cleared when the app closes

