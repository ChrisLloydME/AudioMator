# Troubleshooting

This page covers reproducible user and contributor failure modes. It avoids guessing about causes that cannot be established from the code or the error message.

## Build and Dependency Resolution

### `swift test` fails before compiling

Typical symptoms:

```text
error: unable to load standard library for target ...
error: error opening '.../ModuleCache/...' for output: Operation not permitted
sandbox-exec: sandbox_apply: Operation not permitted
```

Cause: SwiftPM needs to write its manifest, module, and Clang caches under the user Library, and it launches its own sandbox. A restricted shell environment can block both. This is an environment problem, not a project error.

Resolution: run the command in a normal terminal session or grant the build process access to the user Library and temporary directories. Do not change project settings to work around a host sandbox.

### Swift package resolution fails

The project resolves `TagLibAudioMetadata` from GitHub. Check network access and try:

```bash
xcodebuild -resolvePackageDependencies -project AudioMator.xcodeproj
```

Then verify that the resolved version matches `AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (currently exact 0.8.3, revision `ebd21c7b1aa9be607133fc4a9de02d2c7890f42f`).

### `xcodebuild` cannot write caches

Sandboxed environments may block writes to SwiftPM, Clang, simulator, or Xcode caches under `~/Library`. Treat this as an environment issue and rerun with appropriate permissions before diagnosing project code.

### CI workflow cannot find the toolchain

`.github/workflows/core-logic.yml` sets:

```yaml
env:
  DEVELOPER_DIR: /Applications/Xcode.app/Contents/Developer
```

and runs on the `xcode-27` runner label. This is a CI-specific path, not the normal developer setup. On a developer Mac with only `/Applications/Xcode.app`, use that stable path and do not copy an older versioned Xcode directory.

### `scripts/codex-build.sh` reports an AppIcon tool crash

The script prints extra diagnostic advice when the build log contains `The file "AppIcon.icon" couldn't be opened.`, `Exception while running actool` and `CompileAssetCatalogVariant`. The run still fails: the helper exits with the Xcode status and does not print `CODEX_BUILD_COMPLETED`, so it is not valid build evidence. Inspect `.deriveddata-codex/xcodebuild.log` for other errors, then validate the icon asset with Xcode on the desktop or retry on a host whose asset tooling works.

### The build succeeds but the app cannot be launched for testing

Do not treat launching the GUI as build validation. Repository policy reserves interactive UI acceptance to the maintainer; automated verification is the build plus the relevant tests. See [Testing](../Development/TESTING.md).

## Metadata Saves

### The file changed after it was checked

The file changed since the draft baseline. Automatic refresh keeps unsaved drafts and their original baseline; non-conflicting changes can be merged when saving. If the same fields changed both on disk and in the draft, choose a conflict strategy in Settings → Conflicts. Under Require manual reload, use Reload from Disk in the file list's context menu, confirm discarding unsaved Inspector edits, and reapply the intended edit. Do not disable version checks.

### The file could not be checked for changes

The file is missing, unreadable, replaced, or on a volume that cannot provide the needed attributes. Restore access and reload. If a rename left the file read-only, choose **Reload from Disk**. For a replacement, review the displayed file and choose **Accept Replacement**. If it changes before acceptance, reload and review it again.

### Changes cannot be saved in this file format

The format's TagLib capability does not include one or more requested fields. Remove or deselect unsupported fields, or use a different container. AudioMator does not write a partial payload when a requested field is unsupported.

### Save reports a filesystem error or a writer rejection

The save details identify the affected file for filesystem problems such as running out of space. When the writer rejects a single-field edit, the details can add the field name. For a multi-field edit, use the writer's original message to see whether it identified a specific field.

### The save succeeded but the inspector did not refresh

This is reported as a warning, not a failure. The bytes were committed; the app could not reload the snapshot before its deadline. Use **Reload from Disk** rather than retrying the save.

### A batch save stopped partway

Batch operations commit per file. Review the per-file result and the save issue log in Settings → Logs. Retrying submits only pending fields for files that still need changes.

### Written metadata looks different after saving

Some containers normalize number text, dates, artwork roles, or key casing. Confirm the stored representation in Tag Inspector. If numeric values round-trip and the difference is documented normalization, the write was successful.

### Erase All Tags left structures behind

Erase-all is best effort. Some containers keep native structures or non-ProjectMap data that the dependency cannot remove. This is a known limitation, not a failed save.

## Rename and Conversion

### The preview says a destination already exists

Another file already uses the target name, or two rows target the same name. Resolve the conflict in the preview. Existing files are never silently overwritten.

### The file changed while a preview was open

The preview captured a fingerprint, but the file changed before the transaction started. Previews follow the currently loaded data automatically. Close and reopen the tool to review its current values; there is no Refresh Preview button. If the file cannot be checked or remains blocked after a move, use Reload from Disk in the file list's context menu. This rereads the file; it does not override a failed write.

### A rename failed and left a temporary or destination file

The rename transaction stages each source to a temporary file and then finalizes destinations. If rollback is incomplete, AudioMator reports recovery items with the original path, intended path, and observed final locations. Resolve the files manually before retrying. Do not assume the rollback completed.

### CSV import rejected records

Common causes: ambiguous locator matches, duplicate records for one file, missing or extra records, invalid typed values, unsupported fields, or a file changed since preview. The preview identifies the category before writing.

## Watched Folders

### A watched folder is missing or cannot be restored

macOS may invalidate a bookmark after a folder is moved, renamed, or its permissions change. Re-add the folder. If the saved bookmark data is corrupt, AudioMator preserves the original data in a corrupt-backup preference key, refuses to overwrite it, and reports the problem.

### Automatic refresh is degraded

Check the sidebar status and Settings → Folders. AudioMator caps directory monitors at 128 per folder and reports directories that could not be opened or scanned. Refresh manually or return to the app to trigger selected-file reconciliation.

### Files changed on disk but the app did not notice

AudioMator does not continuously monitor every open file. Directory events can miss in-place child writes on some volumes. Use **Reload from Disk** or switch away and back to the app.

## Online Services

### A lookup times out or is rate-limited

MusicBrainz requests are spaced at one per 1.1 seconds; the client retries HTTP 503 up to two times. GitHub update checks report rate limiting explicitly. Wait and retry. There is no offline cache for new queries beyond the in-memory response cache.

### The Online Metadata window opened but no search ran

Opening Online Metadata, choosing a source tile, returning to Sources, reopening the window, and LRCLIB Previous/Next deliberately prepare local fields without contacting a provider. Press the provider's **Search** button (or Return) to run the query, use **Find in MusicBrainz** from the file list for that explicit lookup, or use **Auto Apply Best Matches** in LRCLIB. Results remain cached per row while navigating, so returning to a row does not send another request unless you press Search.

### A provider response is rejected as malformed

MusicBrainz validates the exact response shape before caching it. A successful HTTP response with an unexpected schema, an unrepresentable number, or a malformed numeric field is not cached; retrying the same search or lookup performs a fresh request and can succeed without reopening the window. The error names the field or shape that could not be read. Other providers report malformed responses the same way as before and are not cached by MusicBrainz's response cache.

### No result for a correct-looking query

Try a simpler query or filename fallback. Provider matching is heuristic and may reject ambiguous results. Check the query fields shown in the UI.

### Artwork will not apply

Artwork write support depends on the container and is checked before writing. The downloaded image may also fail validation or normalization. Check the reported error and try another candidate.

### Online artwork download failed or was cancelled

A failed online artwork search and a failed candidate download are reported separately. **Search Again** retries only a failed search; it never repeats a download. After a failed, timed-out or cancelled download the result grid and selected candidate stay available: press **Try Again** for the same candidate, or select another candidate and apply it without searching again. While a download runs, applying and switching candidates are disabled; **Stop Download** cancels it without closing the sheet. A failed download does not change the file or the Inspector draft.

### Artwork wasn't applied because the selection changed

An artwork command is tied to the Inspector draft that was active when you chose the image or online result. If you change the selection, reopen a draft for the same files, remove one of the captured files, or issue a newer artwork command (another image, another online result, **Clear Artwork** or **Keep Current Artwork**) before the image finishes loading, the handoff is rejected and nothing is written to the draft or to disk. The message names the affected selection; a stale **Fetch Online…** sheet stays open with its results for reference only. Select the intended files again and choose the artwork again. Artwork is never transferred to a different selection or to a surviving subset of a batch implicitly.

### Lyrics will not apply because the file changed

LRCLIB applies synced lyrics only to the file revision that was reviewed when the browser queued it. Close and reopen LRCLIB (or rerun Online Metadata) so the current title/artist/album values are reviewed and a new search is issued, then apply the result. If you returned to Sources, choose LRCLIB and press Search first. Do not expect Reload from Disk alone to authorize an old lyrics result.

### Lyrics search or apply stopped when I left LRCLIB

Returning to Sources, closing the Online Metadata window, or starting a new LRCLIB session cancels outstanding lookups and any lyrics write that has not started saving. If a save had already started, it finishes and its real result, including any reload warning, appears in the HUD and Settings → Logs; files later in the queue are reported as not processed. Late provider responses cannot start another request or write.

### Another save is still in progress

Lyrics application uses the shared save progress. If a previous save is still finishing its bounded reload, wait for it to complete and try again. This is reported rather than writing concurrently with another folder mutation.

## Updates

### "Release version is not recognized"

The update checker requires tags of the form `V<version>B<build>`, for example `V3.0B3604`. Both markers are uppercase; the version core must be dot-separated integers and the build must be numeric.

### The update check says the app is ahead of the latest release

The local marketing version/build is newer than the latest GitHub release tag. This can happen with development builds or unpublished releases. It is not an error.

## Getting More Information

- Save issues: Settings → Logs.
- Build logs: `.deriveddata-codex/xcodebuild.log`.
- Raw tags: Tag Inspector (Metadata Details sheet).
- Field meanings and storage: Help → Metadata Field Guide.
- Dependency boundary issues: see [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md).

When reporting a bug, include the AudioMator version and build, macOS version, file format, the exact operation, and whether the file was on a local or network volume. Do not include sensitive file contents unless necessary.

### Invalid Total Tracks or Total Discs

A nonempty total must be a whole number from 0 through 2147483647. Invalid text and extra slashes stop the semantic save before any write; they are not interpreted as a request to clear the total. Empty input still explicitly removes that component. Existing text numbering does not prevent edits to unrelated fields.

### Automatic refresh could not be completed

The last loaded values remain visible when rereading a selected file fails. An automatic-refresh warning is not repeated for the same file, path and reason failures. A completed refresh with no failures updates that state, and changing the selection suppresses a stale warning. Explicit Reload from Disk always reports its result: a complete failure as a failure, and a partial failure as a warning. These are read failures, not failed saves, and are not added to Save Logs.
