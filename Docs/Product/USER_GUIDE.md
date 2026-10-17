# User Guide

This guide describes the workflows implemented in AudioMator for macOS. Button placement can change; behavior described here is tied to the current source.

AudioMator edits metadata in place. It does not create a project file, and it does not keep a backup copy of the original audio file. Work on copies, or make a backup, when testing unfamiliar formats or tools.

## Getting Files Into the App

AudioMator has two sources, shown in the sidebar.

### Current Session (Quick Import)

1. Choose **Add Files** (or press Command-O).
2. Select one or more audio files.
3. Files are loaded into the session list. The session is not persisted; files disappear from the app when you remove them or quit.

Quick Import reads files concurrently in the background and adds them to the list in batches as they finish. Failures are reported per file. Selecting the same path again reuses the existing file identity and refreshes the loaded snapshot.

### Watched Folders

1. Use **Add Folder…** (in the sidebar or Settings → Folders).
2. Choose one or more folders.
3. AudioMator stores security-scoped bookmarks so the folders are restored on later launches.

Watched folders scan recursively, skipping hidden files and package descendants. Directory changes trigger a debounced rescan (350 ms). On app activation, the selected files are checked for external changes as well. If a folder contains too many directories or some cannot be monitored, the sidebar reports degraded automatic refresh; a manual reload or activation can still refresh files.

Removing a watched folder from AudioMator does not delete it from disk.

## Selecting Files

The middle list supports single and multiple selection. Selection drives:

- which Inspector or Metadata Editor targets are active,
- which files Save applies to,
- which files the conversion and online tools operate on.

Changing selection or sidebar source can discard an unsaved Inspector draft. If the draft has changes, AudioMator asks before discarding; the warning can be suppressed in Settings → General.

Files appear in the middle list with configurable columns. Sorting is available by column, and the list also supports a manual order used by track renumbering. Visible columns, toolbar buttons, and Inspector fields are configured in Settings → Interface.

## Editing Common Metadata (Inspector)

The Inspector edits the fields visible for the current selection. For a single file it is a direct draft of that file. For multiple files it shows shared values and marks mixed values; edited fields are applied to every selected file.

1. Select one or more files.
2. Edit fields in the Inspector.
3. Choose **Save** to write pending changes, or **Cancel** to discard them.

Saves write only the fields that changed from the draft's baseline. Before writing, AudioMator checks that the format supports each requested field. If any requested field is unsupported, the file is not written and the unsupported fields are reported.

For multiple files, Inspector saves process up to four independent files concurrently while still serializing operations that touch the same path. Results are per file; a batch can partially succeed. The save issue log records non-success outcomes (Settings → Logs).

### Artwork

Artwork can be replaced from a local image or clipboard data, or cleared. The original embedded bytes are retained for unchanged files. Replacement bytes and MIME type are sent to the metadata pipeline as one artwork patch. Artwork write support is format-dependent and is preflighted like other fields.

## Editing Raw Metadata (Metadata Editor)

The Metadata Editor exposes the TagLib PropertyMap projection as ordered value lists. One line represents one value; duplicates, empty values, whitespace, and literal semicolons are preserved.

- Open it from the toolbar or the **Metadata Tools** menu.
- Add, edit, or delete fields for the selected files.
- Text utilities can trim, replace, change case, and add prefixes/suffixes across selected fields.
- **Apply** writes only changed keys as a raw patch, preserving unrelated external keys and value arrays.

Container-native structures that TagLib does not project into PropertyMap do not appear here. Use Tag Inspector to inspect them.

The editor's draft is independent of the Inspector draft. Closing the editor discards its changes.

## Inspecting Raw Tags (Tag Inspector)

Tag Inspector is read-only. It shows:

- a TagLib properties section,
- ID3v2 frames when available,
- preserved bridge sections such as legacy ID3v1 data,
- AudioMator compatibility notes when legacy and canonical values differ.

Use it when a value read back after saving differs from what you entered, or when you need to confirm what the dependency actually parses.

## Saving, Conflicts, and Reloading

### Conflict strategies

Settings → Conflicts controls what happens when a file changes on disk while an Inspector or Metadata Editor draft is open:

| Strategy | Behavior |
| --- | --- |
| Merge non-conflicting changes (default) | Merge edits to untouched fields; keep the draft and stop when the same field changed on both sides. Exact single-field convergence is accepted. |
| Prefer my changes | Apply the draft to conflicting fields. |
| Prefer disk changes | Keep the disk value for conflicting fields and report the discarded draft fields. |
| Require manual reload | Stop if the revision changed and require a reload. |

Preview-based tools, online write plans, track renumbering, lyrics application, and Clear All Metadata keep stricter revision requirements and are not affected by this setting.

### Reload from Disk

Use **Reload from Disk** in the list context menu to reread selected files. If the Inspector has unsaved changes, AudioMator asks before discarding them.

Returning to AudioMator also checks the selected files. Unchanged revisions are skipped; changed or missing files are reread. A clean draft follows the refreshed file. A dirty draft keeps its original baseline and pending edits.

The conflict setting does not continuously watch every open file. Watched-folder events and activation checks are the refresh triggers.

### Failure reporting

AudioMator distinguishes:

- nothing was written,
- written and refreshed successfully,
- written but the in-memory snapshot could not be refreshed,
- partial batch success,
- cancellation before the mutation started,
- manual recovery required after an incomplete rename rollback.

A "saved but could not refresh" result means the disk write succeeded. Do not retry it as though it failed; reload instead.

## Filename, Text, CSV, and Field Conversion

Open **Filename & Metadata** from the toolbar. The tool has seven modes:

1. **Metadata to Filename** — build a new base name from a template, keeping the extension.
2. **Filename to Metadata** — parse a filename stem with a match template and write the captured values.
3. **Metadata to Text** — render one record per file with a text template.
4. **Text to Metadata** — parse one record per line and write matched fields.
5. **Metadata to CSV** — export a column-based CSV.
6. **CSV to Metadata** — import CSV columns into selected files.
7. **Copy or Cut Metadata Fields** — copy or move one field into another for each selected file.

Templates use `{{field}}` placeholders. Filename templates support fields such as `{{title}}`, `{{artist}}`, `{{album}}`, `{{albumArtist}}`, `{{trackNumber}}`, `{{discNumber}}`, `{{year}}`, `{{releaseDate}}`, `{{comment}}`, `{{publisher}}`, `{{copyright}}`, and `{{credits}}`.

### Preview before writing

Every mode builds a preview plan before applying changes. The preview identifies unmatched, ambiguous, invalid, unchanged, and writable rows. Files changed since the preview are rejected inside the file mutation reservation.

### Text and CSV rules

- Plain-text templates have no escaping syntax. Use CSV when a value can contain a line break or the template's literal separators.
- CSV templates support comma, semicolon, pipe, and tab delimiters, quoted fields, doubled quotes, embedded line breaks, optional headers, and reversible spreadsheet-formula protection.
- Imports can match by selection order or by unambiguous locators: File Name, Base Name, Path, Relative Path, or Index.
- Blank imported values are ignored unless **clear empty values** is enabled.
- AudioMator can read UTF-8, UTF-16, Windows-1252, and Mac Roman text. Export is UTF-8; CSV rows use CRLF.
- Limits: 100,000 files/records, 32 MB of source or generated text, 256 KB per plain-text record, and 1 MB per CSV field.

Writes are verified per file and are not an all-or-nothing batch transaction.

### Copy or Cut Metadata Fields

Choose a source field, a destination field, and **Copy** or **Cut**. Each file uses its own source value. Copy keeps the source; Cut clears it in the same save. Files with an empty source are skipped. Files with invalid destinations or unverifiable revisions are skipped. Operations that would leave a total without a number are blocked because the current dependency cannot save them reliably.

## Renumbering Tracks

1. Arrange files in the intended order in the middle list (or select a subset).
2. Choose **Renumber Tracks**.
3. Choose ascending or descending direction, a start number (0–9,999), and zero-padding.
4. Review the preview and apply.

Renumbering rewrites track number text with verification enabled, then reloads each file from disk. Unsupported formats are skipped and counted. Failures and warnings are reported per file. The operation is serialized with other file mutations.

## Online Metadata, Artwork, and Lyrics

Open **Online Metadata** from the toolbar. Choose a source:

- **MusicBrainz** — recordings, releases, relationships, credits, identifiers.
- **iTunes** — Apple catalog metadata, UPC/link/store-ID lookup, artwork.
- **LRCLIB** — synced lyrics for the selected track metadata.

Network requests start only after an explicit search or lookup action. Review results and the write plan before applying. Provider results are written through the same metadata pipeline and revision guards as manual edits.

MusicBrainz requests are rate-limited to roughly one request per 1.1 seconds and identify the app in the `User-Agent`. Provider outages, rate limits, malformed responses, and cancellations are surfaced in the UI; partial provider failures are possible.

See [Online Metadata](../Architecture/ONLINE_METADATA.md) and [Acknowledgements and Privacy](../ACKNOWLEDGEMENTS_AND_PRIVACY.md) for data sent to each service.

## MuseAmp Compatibility IDs

With Settings → General → **MuseAmp Compatibility** enabled, the track list context menu can generate MuseAmp album/track IDs. The operation writes a JSON payload into each selected file's Comment field:

```json
{"albumID":"…","trackID":"…","v":1}
```

This replaces the existing Comment value on those files. IDs are deterministic for the same album/track identity within a generation run. AudioMator is not affiliated with MuseAmp.

## Settings

Settings contains six tabs:

- **General** — welcome screen, unsaved-draft warning, MuseAmp compatibility.
- **Interface** — visible toolbar buttons, list columns, and Inspector fields.
- **Folders** — watched folders and file-access authorizations.
- **Conflicts** — Inspector/Metadata Editor conflict strategy.
- **Logs** — locally persisted save issue history.
- **About** — version, links, release notes, and manual update check.

## Checking for Updates

**Check for Updates…** asks the GitHub Releases API for the latest release. The release tag must look like `V2.7B2697`. AudioMator compares version segments and then the build number. It only reports whether a newer release exists and offers to open the GitHub Releases page; it does not download or install an update.

## Where AudioMator Stores Data

- Watched-folder and file-access bookmarks: app preferences (`UserDefaults`).
- Interface preferences and conflict policy: app preferences.
- Save issue log: `Application Support/AudioMator/SaveIssueLog.json` inside the app sandbox container.
- User-selected audio files: unchanged location; metadata is written in place.

AudioMator does not store copies of audio files.
