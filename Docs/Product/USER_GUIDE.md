# User Guide

This guide describes the workflows implemented in AudioMator for macOS. Button placement can change; behavior described here is tied to the current source.

AudioMator edits metadata in place. It does not create a project file, and it does not keep a backup copy of the original audio file or an undo history. Work on copies, or make a backup, when testing unfamiliar formats or tools.

## Getting Files Into the App

AudioMator has two sources, shown in the sidebar.

### Current Session (Quick Import)

1. Choose **Add Files…** (or press Command-O). The command is in the Edit menu and available as a toolbar button.
2. Select one or more audio files.
3. Files are loaded into the session list. The session is not persisted; files disappear from the app when you remove them or quit.

Quick Import reads files concurrently in the background and adds them to the list in batches as they finish. Rows are ordered by file name and path (lexical order), not by the order you selected the files. Duplicate selections of the same path collapse to one row. Failures are reported per file. Selecting the same path again reuses the existing file identity and refreshes the loaded snapshot, keeping the row's position; removing or clearing rows cannot be undone by a read that was already in flight.

A file that is replaced, moved, or has its containing folder replaced while it is being read is skipped and reported, because the read can no longer be tied to the entry you selected. Select that file again to reload it; AudioMator does not silently retry or bind the result to a different file. Access to the files you add is held for the rows that need it and released when the row is removed or the session is cleared.

### Watched Folders

1. Choose **Add Folder…** in the sidebar, **Add Watched Folder…** from the Edit menu, or the add button in Settings → Folders.
2. Choose one or more folders.
3. AudioMator stores security-scoped bookmarks so the folders are restored on later launches.

Watched folders scan recursively, skipping hidden files and package descendants. AudioMator watches each folder's directory entries for added, removed and renamed items; a folder counts as actively monitored only while the open directory still matches the authorized path. Directory changes trigger a debounced rescan (350 ms). Edits inside a file that is already listed are not guaranteed to appear automatically. Use **Refresh Watched Folders** from the Edit menu or a watched folder's context menu, or **Refresh** for a folder in Settings → Folders, to rescan and reattach monitoring. On app activation, the selected files are checked for external changes as well.

If a folder contains too many directories (the monitoring limit is 128 per folder), becomes unavailable, or its path now refers to a different directory, the sidebar and Settings → Folders report degraded automatic refresh with the reason. Restore or reauthorize the folder, then refresh again; a folder that moved to a new path must be added again.

Removing a watched folder from AudioMator does not delete it from disk.

## Selecting Files

The middle list supports single and multiple selection. Selection drives:

- which Inspector, Metadata Editor, conversion, and online tools are active,
- which files Save applies to,
- which files the conversion and online tools operate on.

Changing selection or sidebar source can discard an unsaved Inspector draft. If the draft has changes, AudioMator asks before discarding; the warning can be suppressed in Settings → General.

Files appear in the middle list with configurable columns. Sorting is available by column, and the list also supports a manual order used by track renumbering. Visible columns, toolbar buttons, and Inspector fields are configured in Settings → Interface; each section has a restore action.

## Editing Common Metadata (Inspector)

The right Inspector is a curated common-field editor. Settings → Interface → Inspector Metadata Fields controls its rows for both single and multiple selection. Container-specific fields are not automatically appended; use Metadata Editor for additional PropertyMap fields and Tag Inspector for native inspection. New installations show Title, Artist, Album, Composer, Genre, Year, Track Number, Total Tracks, Disc Number, Total Discs, Comment, Album Artist, Release Date, Publisher, Copyright, Explicit and Credits; Date, Original Release Date, Content Group, Grouping and Work are optional. Existing saved field choices are preserved. Hiding a row changes presentation only: it neither deletes file metadata nor discards an existing draft. Save still applies all pending changes, including a draft entered before its row was hidden.

The Inspector edits the fields visible for the current selection. For a single file it is a direct draft of that file. For multiple files it shows shared values and marks mixed values; edited fields are applied to every selected file.

A background refresh (watched-folder rescan or imported-file reload) does not recreate or replace a dirty Inspector draft, and a save keeps the original expected revision until it succeeds. After a successful save, fields you did not edit again follow the value read back from disk; edits made while the save was in flight stay pending. If some files in a batch fail, Save retries only those files or your newer changes.

If a watched folder, Quick Import list or settings removal makes some of a dirty draft's files unavailable, AudioMator prunes the selection as usual but keeps your captured values in a review state. The Inspector explains which files are unavailable and shows the captured changes; **Save is suspended** until every captured file is available again and you choose **Resume Editing**, or you choose **Discard Edits**. Captured values are never applied to other files.

1. Select one or more files.
2. Edit fields in the Inspector.
3. Choose **Save** in the Inspector toolbar or **Save Edits** from the Edit menu to write pending changes, or **Cancel** in the Inspector toolbar (**Cancel Edits** in the Edit menu) to discard them. Both save commands apply to the current selection.

On macOS 26 and later, the Inspector toolbar controls align to the right edge of the pane. Use **Hide Inspector** to close the pane. When it is closed, **Show Inspector** appears at the right of the middle pane's toolbar; the View menu also offers **Toggle Inspector**.

Saves write only the fields that changed from the draft's baseline. Before writing, AudioMator checks that the format supports each requested field. If any requested field is unsupported, the file is not written and the unsupported fields are reported.

For multiple files, Inspector, MusicBrainz/iTunes plans, filename/CSV imports and related batch work process up to four independent files concurrently while still serializing operations that touch the same path. Results are per file; a batch can partially succeed. Cancelling stops files that have not started; already started saves finish and report their outcomes. The save issue log records save warnings and failures, plus per-file outcomes for incomplete batches (Settings → Logs). A single operation cancelled before writing does not create a save issue entry; an incomplete batch retains the unprocessed files as warning records so each selected file is accounted for.

### Date and time editing

You can type or paste date text such as `circa 1998`, `Spring 2024`, `2024/6/2`, or an ISO timestamp. AudioMator applies the same text handling as for other metadata values and performs no date-format validation, calendar correction, or time-zone conversion on this path. The Inspector trims leading and trailing whitespace and treats an empty value as a clear. Metadata Editor handles raw values as an ordered list, where an empty value is a distinct entry and **Delete Field** removes the key. Container support, writer verification, and conflict handling still apply. CSV, text, and filename imports likewise skip date-format validation, while their normal input and target checks still apply.

Year, Date, Release Date, and Original Release Date are independent. The Inspector shows a calendar button only on a visible row with a recognized writable route for every file in the selection. Metadata Editor shows **Choose Date…** only for the exact raw key it will write and requires the same field identity across the selection. The table lists eligible routes, subject to the concrete file's write capabilities and refresh state.

| Tag family | Inspector | Metadata Editor raw keys |
| --- | --- | --- |
| ID3v2.4 | Year, Date, Release Date, Original Release Date | `RELEASEDATE`, `ORIGINALDATE`, `ITUNESPURCHASEDATE` |
| MP4 / M4A | Year, Date, Release Date, Original Release Date | `DATE` → Year (`©day`), `RELEASEDATE`, `ORIGINALDATE` |
| Vorbis comments | Year, Date, Release Date, Original Release Date | `YEAR`, `DATE`, `RELEASEDATE`, `ORIGINALDATE`, `ITUNESPURCHASEDATE` |
| APEv2 | Year, Date, Release Date, Original Release Date | `YEAR`, `RELEASEDATE`, `ORIGINALDATE`, `ITUNESPURCHASEDATE`. `DATE` is eligible for WavPack. |
| ASF / WMA | Year, Date, Original Release Date | `DATE` → Year |

An existing raw key stays the same when edited. Adding the named **Date** field uses raw `DATE` when the selected files have the verified independent Date route in Vorbis comments or WavPack. A raw `DATE` selection spanning MP4 and Vorbis has different field identities and stays text-only. Existing ID3v2.3 dates, custom keys, and the MP4 raw `ITUNESPURCHASEDATE` key do not get the picker. MP4's raw purchase key would write a separate atom from its native `purd` value. The Inspector's WAV Year picker requires a known ID3v2.4 tag.

Every field that opens the picker offers **Year**, **Year & Month**, and **Full Date**. **Full Date** shows an open monthly calendar and lets you turn on **Add Time** with hour, minute, or second precision. The **Time Zone** dropdown uses the same search control as the Metadata Editor field selector, matches the width of the input, and scrolls vertically when needed. Search by city, region, or identifier, and choose the result with a click or the arrow keys and Return. The system time zone and UTC are quick choices. A recognized existing timestamp keeps its instant when you change the display zone. After entering a new local time, the selected zone is used to interpret it. If daylight saving makes the chosen local time ambiguous or nonexistent, choose a specific occurrence or a valid time.

**Tag Value Preview** is the final row of the active group and shows the exact value that **Apply** will put in the active Inspector draft or raw value entry. The file is written only when you save the draft. Time values are converted to UTC and marked in the preview. Native ID3v2.4 timestamps omit the `Z`, and date-specific text tags use `Z` unless the same value must also fit an ID3v2.4 target in the batch. Pure dates keep their selected calendar values. Blank, mixed, or unrecognized values open with a starting date and remain untouched until Apply. The format writer still verifies each save and reports any rejected value. The title and grouped rows scroll together when needed, and the sheet buttons stay in the bottom action bar.

### Numbering compatibility

Older numbering values are handled internally and can appear in the normal Track Number, Total Tracks, Disc Number and Total Discs fields. Opening or importing files does not rewrite them. Saving a number change uses the intended field values and preserves the other pair; there is no separate Restore/Cleanup operation. If a number or total cannot be determined safely, enter its intended value in that ordinary field and save again. Unrelated edits preserve existing numbering data. Numeric components are required for semantic edits; text such as `A1` is preserved during unrelated edits but must be changed in Metadata Editor.

### Artwork

Artwork can be replaced from a local image, the photo library, or clipboard data, or cleared. The original embedded bytes are retained for unchanged files. Replacement bytes and MIME type are sent to the metadata pipeline as one artwork patch. Artwork write support is format-dependent and is preflighted like other fields. Single-file controls offer **Choose Artwork…** (Finder or Photo Library), **Fetch Online…**, and **Clear Artwork**; the context menu adds **Import from Clipboard**. Multi-selection controls offer the same actions with **Clear All**, and **Keep Current Artwork** in the context menu.

**Fetch Online…** reports search and download problems separately. A failed search offers **Search Again**, which retries only the search. A failed, timed-out or cancelled candidate download keeps the result grid and selected candidate, shows the reason next to the preview, and changes the primary action to **Try Again**; you can also pick another candidate and apply it without searching again. While a download runs, applying and switching candidates are disabled, and **Stop Download** cancels it without closing the sheet. The selected preview falls back through Apple's preferred image URLs in order, and choosing another candidate starts again at the first URL.

Artwork is applied to the Inspector draft that was active when you chose the image or candidate. If the selection or draft changes, a captured file becomes unavailable, or a newer artwork command runs (including **Clear Artwork**, **Clear All**, **Keep Current Artwork** or another online result) before the image finishes loading, nothing is applied and a message explains what changed. A stale **Fetch Online…** result stays visible for reference but cannot be applied; select the intended files again and choose the artwork again. Artwork from one selection is never transferred to another selection implicitly, and staged artwork is not written to disk until you save the Inspector edits.

## Editing Raw Metadata (Metadata Editor)

The Metadata Editor exposes the TagLib PropertyMap projection as ordered value lists. Each list entry is one exact value; duplicates, blank entries, whitespace, literal semicolons, and line breaks inside a single value are preserved as that value's data.

- Open it from the toolbar or from **Metadata Editor…** in the Edit menu.
- **Add Field…** and **Edit Selected…** open a full-width text editor for one value at a time. If the field has multiple values, the **Value** pop-up above the editor selects which one to edit. **Add Value** appends a blank entry and selects it. **Remove Value** removes the selected entry when there are multiple values. To remove the last value and its key, use **Delete Field** in the main Metadata Editor. A blank entry is a real value.
- When the selected files disagree, or a field is missing from some of them, the editor starts with no values. Enter the replacement list explicitly; saving replaces the whole list on every selected file.
- **Utilities…** previews the ordered values per file and field, transforms each value independently, and applies exactly the values it showed. A stale preview is rejected; review the updated preview and apply again.
- **Done** writes only changed keys as a raw patch, preserving unrelated external keys and value arrays. An unchanged confirmation creates no change and no write. **Cancel** or closing the window discards the draft.
- Some containers reject a blank, duplicate or multiline array element. The save reports the failure and no substitute write is made; see [dependency limitations](../Reference/DEPENDENCY_LIMITATIONS.md).

Container-native structures that TagLib does not project into PropertyMap do not appear here. Use Tag Inspector to inspect them.

The editor's draft is independent of the Inspector draft.

## Inspecting Raw Tags (Tag Inspector)

Tag Inspector is read-only. It opens as a Metadata Details sheet and shows:

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
| Merge non-conflicting changes (Recommended; default) | Merge edits to untouched fields; keep the draft and stop when the same field changed on both sides. Exact single-field convergence is accepted. |
| Prefer my changes | Apply the draft to conflicting fields. |
| Prefer disk changes | Keep the disk value for conflicting fields and report the discarded draft fields. |
| Require manual reload | Stop if the revision changed and require a reload. |

Track number/total tracks, disc number/total discs, and artwork are handled as groups. Preview-based tools, online write plans, track renumbering, lyrics application, and Erase All Tags keep stricter revision requirements and are not affected by this setting.

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

A "saved but could not refresh" result means the disk write succeeded. Do not retry it as though it failed; reload instead. A post-commit durability failure is also reported as saved with a warning.

## Filename, Text, CSV, and Field Conversion

Open **Filename & Metadata** from the toolbar or the Edit menu. The tool has seven modes:

1. **Metadata to Filename** — build a new base name from a template, keeping the extension.
2. **Filename to Metadata** — parse a filename stem with a match template and write the captured values.
3. **Metadata to Text** — render one record per file with a text template.
4. **Text to Metadata** — parse one record per line and write matched fields.
5. **Metadata to CSV** — export a column-based CSV.
6. **CSV to Metadata** — import CSV columns into selected files.
7. **Copy or Cut Metadata Fields** — copy or move one field into another for each selected file.

Templates use `{{field}}` placeholders. Filename and text templates support `{{title}}`, `{{artist}}`, `{{album}}`, `{{albumArtist}}`, `{{composer}}`, `{{genre}}`, `{{trackNumber}}`, `{{discNumber}}`, `{{year}}`, `{{date}}`, `{{releaseDate}}`, `{{originalReleaseDate}}`, `{{comment}}`, `{{publisher}}`, `{{copyright}}` and `{{credits}}`; unmatched parts can use `{{_ignore}}`.

### Preview before writing

Every mode builds a preview plan before applying changes. The preview identifies unmatched, ambiguous, invalid, unchanged, and writable rows. Files changed since the preview are rejected inside the file mutation reservation. There is no Refresh Preview button.

### Text and CSV rules

- Text and CSV exports start with `# AudioMator-Metadata-Profile: 2`, which marks the exchange profile and lets reimports preserve independent Year, Date, Release Date and Original Release Date values. Files without the marker are read with the legacy v1 meanings; unknown newer profile versions are rejected.
- In a v2 export, an unquoted `<remove>` cell removes that field; a quoted `"<remove>"` is literal text. Text exports escape a literal leading `<remove>` and any leading backslash run so both values round-trip. Legacy or unmarked imports treat `<remove>` as literal text.
- Plain-text templates otherwise have no general escaping syntax. Use CSV when a value can contain a line break or the template's literal separators.
- CSV templates support comma, semicolon, pipe, and tab delimiters, quoted fields, doubled quotes, embedded line breaks, optional headers, and reversible spreadsheet-formula protection. Export is UTF-8 with CRLF rows.
- Imports can match by selection order or by unambiguous locators: File Name, Base Name, Path, Relative Path, or Index.
- Blank imported values are ignored unless **Clear blank imported values** is enabled.
- AudioMator can read UTF-8, UTF-16, Windows-1252, and Mac Roman text.
- Limits: 100,000 files/records, 32 MB of source or generated text, 256 KB per plain-text record, and 1 MB per CSV field.

Writes are verified per file and are not an all-or-nothing batch transaction.

### Copy or Cut Metadata Fields

Choose a source field, a destination field, and **Copy** or **Cut**. Each file uses its own source value. Copy keeps the source; Cut clears it in the same save. Files with an empty source are skipped. Files with invalid destinations or unverifiable revisions are skipped. Operations that leave a total without a number retain the total.

## Renumbering Tracks

1. Arrange files in the intended order in the middle list (or select a subset).
2. Choose **Renumber Tracks…**.
3. Choose ascending or descending direction and a start number from 1 to 9,999 (default 1). There is no zero-padding option; a blank or invalid start disables Apply.
4. Review the preview, which shows the numeric number each reviewed file will store, then apply.

Renumbering applies the reviewed plan with the package revision captured at review time, then reloads each file from disk. Unsupported, refresh-required and duplicate targets are skipped without consuming numbers, and a file that already has the desired number is reported as unchanged with no write. Totals, disc numbers and unrelated fields are preserved. Failures and warnings are reported per file, and the operation is serialized with other file mutations.

## Online Metadata, Artwork, and Lyrics

Open **Online Metadata** from the toolbar or the Edit menu. Choose a source:

- **MusicBrainz** — recordings, releases, relationships, credits, identifiers.
- **iTunes** — Apple catalog metadata, UPC/link/store-ID lookup, artwork.
- **LRCLIB** — synced lyrics for the selected track metadata.

Opening Online Metadata or choosing a source only prepares the local query fields and shows the provider picker; no provider is contacted. Each provider starts network requests only from its own explicit action: the **Search** button (or Return) in the MusicBrainz or iTunes form, **Auto Apply Best Matches** or **Search** in LRCLIB, or the file list's **Find in MusicBrainz** command, which opens or retargets the MusicBrainz source and submits that captured query once. Selecting a source tile, returning to Sources, reopening the window, and LRCLIB Previous/Next do not start requests; use Search to run a query for the current row or provider.

Review results and the write plan before applying. Provider results are written through the same metadata pipeline and revision guards as manual edits.

The iTunes source searches the selected storefront country. Changing the storefront clears the current results and navigation so a new search starts in the chosen region; album and track details follow the storefront that produced the result, not the region currently shown in the picker. Track links opened from an album detail keep that album's region.

LRCLIB synced lyrics are bound to the file revision that was reviewed when the browser queued the file. Editing or replacing that file and reloading it while LRCLIB is open can reuse the same stable ID and path; applying the old lyrics result is then refused and asks you to close and reopen LRCLIB (or rerun Online Metadata) so the current values are reviewed again. Leaving LRCLIB with **Sources**, closing the Online Metadata window, or starting a new LRCLIB session cancels outstanding lookups and any lyrics write that has not started saving. A save that already started completes and is reported in the HUD and Settings → Logs. Returning to LRCLIB from Sources keeps the queued files so you can search again; it clears the previous results and review.

MusicBrainz requests are rate-limited to one request per 1.1 seconds and identify the app in the `User-Agent`; HTTP 503 responses are retried up to two times. Provider outages, rate limits, malformed responses, and cancellations are surfaced in the UI; partial provider failures are possible.

See [Online Metadata](../Architecture/ONLINE_METADATA.md) and [Acknowledgements and Privacy](../ACKNOWLEDGEMENTS_AND_PRIVACY.md) for data sent to each service.

## MuseAmp Compatibility IDs

With Settings → General → **MuseAmp Compatibility** enabled, the track list context menu shows **Create MuseAmp IDs…**. The operation writes a JSON payload into each selected file's Comment field:

```json
{"albumID":"…","trackID":"…","v":1}
```

This replaces the existing Comment value on those files. IDs are deterministic for the same album/track identity within a generation run. AudioMator is not affiliated with MuseAmp.

## Settings

Settings contains six tabs:

- **General** — welcome screen on launch, warn before discarding Inspector edits, MuseAmp compatibility.
- **Interface** — visible toolbar buttons, list columns, and Inspector metadata fields, each with a restore action.
- **Folders** — file-access authorizations and watched folders.
- **Conflicts** — Inspector/Metadata Editor conflict strategy.
- **Logs** — locally persisted save issue history, with copy and clear actions.
- **About** — version, build, contact link, release notes, acknowledgements, privacy, and the manual update check.

## Checking for Updates

**Check for Updates…** (App menu or Settings → About) asks the GitHub Releases API for the latest release. The release tag must look like `V2.7B26112`. AudioMator compares version segments and then the build number. It only reports whether a newer release exists and offers to open the GitHub Releases page; it does not download or install an update. Rate-limited or malformed responses are reported explicitly.

## Where AudioMator Stores Data

- Watched-folder and file-access bookmarks: app preferences (`UserDefaults`).
- Interface preferences and conflict policy: app preferences.
- Save issue log: `Application Support/AudioMator/SaveIssueLog.json` inside the app sandbox container; the log keeps at most 200 entries.
- User-selected audio files: unchanged location; metadata is written in place.
- Rename recovery records: `Application Support/AudioMator/RenameJournal/` inside the app sandbox container. They contain the recorded original, temporary and new names plus local file-entry identity evidence, and are retained only until the interrupted rename is restored, acknowledged, or confirmed complete. They never contain metadata, drafts, or access bookmarks.

AudioMator does not store copies of audio files.

## Recovery and Unusual Number Text

After a rename, a file becomes editable again automatically only when the app can read its metadata in full and confirm it is the same file entry at the new location. If that check fails, or a different file now has the name, metadata editing stays disabled even if the app can still read basic file details. Automatic activation checks and watched-folder rescans never re-enable editing. Resolve any pending Inspector draft and choose **Reload from Disk**. If a different file has replaced the original, check the details and choose **Accept Replacement** to resume editing. If the replacement changes again before acceptance, reload and review it again. The recovery block also prevents renaming until resolved.

If a rename is interrupted before it finishes — for example the app quits or the Mac loses power — AudioMator keeps a local rename recovery record. The next launch shows a warning and never moves files by itself. Open **Settings > Folders > Rename Recovery** to review the recorded original and new names and where each file was found. Choose **Restore Original Names** to put every verified file back: restoration verifies each file entry, never overwrites another file, and stops if a conflicting file has appeared. Choose **Remove Record** only when the app shows the rename completed or that no files moved; removing a record does not move files. If another copy of AudioMator is using rename recovery, wait and check again. Renames are only allowed on volumes that support safe exclusive renaming; a folder on another volume is rejected before anything moves.

Inspector number-text edits require numeric components with the current metadata engine. Existing values such as `A1/12` remain intact during unrelated edits; use Metadata Editor for raw textual values. Renumbering excludes refresh-required files before assigning numbers. Cancelling a provider, filename, CSV/text, raw-map, or renumber batch preserves an in-progress commit and stops before the next file; the summary accounts for unprocessed files.

## Number Pairs and External Changes

Track and disc numbers can be blank while their totals remain set. Clearing an individual number preserves its total; clearing the complete pair clears both. After an external revision change, automatic conflict strategies require the package to verify unchanged audio. Formats or layouts without audio-content identity support require Reload from Disk before saving the draft. Review or discard the draft before reloading.

## Operation Result HUD

Success, warning, and failure results use a centered SF Symbol above the title, followed by a summary and any detailed reasons. Batch results use complete sentences, group file names with their reasons, and state when additional files have issues. Detail groups are kept together within the notification budget; omitted groups are identified with a total count and up to three shortened headings, and an oversized single reason has an explicit omitted-character count. The HUD contains no log-navigation link, remains noninteractive, and does not take keyboard focus. Success results stay visible for 3 seconds, warnings for 8 seconds, and failures for 10 seconds.

An error does not automatically mean that nothing was saved. A partial result identifies the files that succeeded; a save followed by a readback or durability warning is still reported as saved. Detailed reasons from macOS and TagLib remain available in the result or save logs. Automatic refresh, explicit Reload from Disk, and conflict handling retain their existing behavior. Reload from Disk is in the file list's context menu and asks before discarding unsaved Inspector edits.
