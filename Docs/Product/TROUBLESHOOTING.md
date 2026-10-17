# Troubleshooting

This page covers reproducible user and contributor failure modes. It avoids
guessing about causes that cannot be established from the code or the error
message.

## Build and Dependency Resolution

### `swift test` fails before compiling

Typical symptoms:

```text
error: unable to load standard library for target ...
error: error opening '.../ModuleCache/...' for output: Operation not permitted
sandbox-exec: sandbox_apply: Operation not permitted
```

Cause: SwiftPM needs to write its manifest, module, and Clang caches under the
user Library, and it launches its own sandbox. A restricted shell environment can
block both. This is an environment problem, not a project error.

Resolution: run the command in a normal terminal session or grant the build
process access to the user Library and temporary directories. Do not change
project settings to work around a host sandbox.

### Swift package resolution fails

The project resolves `TagLibAudioMetadata` from GitHub. Check network access and
try:

```bash
xcodebuild -resolvePackageDependencies -project AudioMator.xcodeproj
```

Then verify that the resolved version matches
`AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
(currently 0.5.3).

### `xcodebuild` cannot write caches

Sandboxed environments may block writes to SwiftPM, Clang, simulator, or Xcode
caches under `~/Library`. Treat this as an environment issue and rerun with
appropriate permissions before diagnosing project code.

### CI workflow cannot find the toolchain

`.github/workflows/core-logic.yml` sets:

```yaml
env:
  DEVELOPER_DIR: /Applications/Xcode_27.0.app/Contents/Developer
```

and runs on the `xcode-27` runner label. This is a CI-specific path, not the
normal developer setup. On a developer Mac with only `/Applications/Xcode.app`,
do not copy that environment variable. Use the installed stable Xcode 27.

### `scripts/codex-build.sh` reports an AppIcon tool crash

The script recognizes a known environment-specific failure where `actool` or
`ibtoold` crashes while compiling `AudioMator/AppIcon.icon`. When the log contains
those markers, the script reports a known false positive and exits 0. It does not
check for other errors in that case, so always inspect
`.deriveddata-codex/xcodebuild.log` for real failures.

### The build succeeds but the app cannot be launched for testing

Do not treat launching the GUI as build validation. Repository policy reserves
interactive UI acceptance to the maintainer; automated verification is the build
plus the relevant tests. See [Testing](../Development/TESTING.md).

## Metadata Saves

### "The file changed since it was read"

The file's size, modification time, inode, or opaque package version changed
since the draft baseline. Reload the file and reapply the intended edit. Do not
retry with a disabled version check; the code has no supported path for that.

### "The file version could not be verified"

The file is missing, unreadable, replaced, or on a volume that cannot provide the
needed attributes. Restore access and reload. If a rename left the snapshot
refresh-required, reload before editing.

### "This format cannot write the requested metadata fields"

The format's TagLib capability does not include one or more requested fields.
Remove or deselect unsupported fields, or use a different container. AudioMator
does not write a partial payload when a requested field is unsupported.

### The save succeeded but the inspector did not refresh

This is reported as a warning, not a failure. The bytes were committed; the app
could not reload the snapshot before its deadline. Use **Reload from Disk**
rather than retrying the save.

### A batch save stopped partway

Batch operations commit per file. Review the per-file result and the save issue
log. Retrying submits only pending fields for files that still need changes.

### Written metadata looks different after saving

Some containers normalize number text, dates, artwork roles, or key casing.
Confirm the stored representation in Tag Inspector. If numeric values round-trip
and the difference is documented normalization, the write was successful.

## Rename and Conversion

### The preview says a destination already exists

Another file already uses the target name, or two rows target the same name.
Resolve the conflict in the preview. Existing files are never silently
overwritten.

### "The file changed after the preview was shown"

The preview captured a fingerprint. The file changed before the transaction
started. Refresh the preview and reapply.

### A rename failed and left a temporary or destination file

The rename transaction stages each source to a temporary file and then finalizes
destinations. If rollback is incomplete, AudioMator reports recovery items with
the original path, intended path, and observed final locations. Resolve the files
manually before retrying. Do not assume the rollback completed.

### CSV import rejected records

Common causes: ambiguous locator matches, duplicate records for one file, missing
or extra records, invalid typed values, unsupported fields, or a file changed
since preview. The preview identifies the category before writing.

## Watched Folders

### A watched folder is missing or cannot be restored

macOS may invalidate a bookmark after a folder is moved, renamed, or its
permissions change. Re-add the folder. If the saved bookmark data is corrupt,
AudioMator preserves the original data and warns instead of overwriting it.

### Automatic refresh is degraded

Check the sidebar status. AudioMator caps directory monitors at 128 per folder
and reports directories that could not be opened or scanned. Refresh manually or
return to the app to trigger selected-file reconciliation.

### Files changed on disk but the app did not notice

AudioMator does not continuously monitor every open file. Directory events can
miss in-place child writes on some volumes. Use **Reload from Disk** or switch
away and back to the app.

## Online Services

### A lookup times out or is rate-limited

MusicBrainz requests are spaced at roughly one per 1.1 seconds; the client retries
HTTP 503 up to two times. GitHub update checks report rate limiting explicitly.
Wait and retry. There is no offline cache for new queries beyond the in-memory
response cache.

### No result for a correct-looking query

Try a simpler query or filename fallback. Provider matching is heuristic and may
reject ambiguous results. Check the query fields shown in the UI.

### Artwork will not apply

Artwork write support depends on the container and is checked before writing. The
downloaded image may also fail validation or normalization. Check the reported
error and try another candidate.

## Updates

### "Release version is not recognized"

The update checker requires tags of the form `V<version>B<build>`, for example
`V2.7B2697`. Both markers are uppercase; the version core must be dot-separated
integers and the build must be numeric.

### The update check says the app is ahead of the latest release

The local marketing version/build is newer than the latest GitHub release tag.
This can happen with development builds or unpublished releases. It is not an
error.

## Getting More Information

- Save issues: Settings → Logs.
- Build logs: `.deriveddata-codex/xcodebuild.log`.
- Raw tags: Tag Inspector and the metadata dump sheet.
- Dependency boundary issues: see
  [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md).

When reporting a bug, include the AudioMator version and build, macOS version,
file format, the exact operation, and whether the file was on a local or network
volume. Do not include sensitive file contents unless necessary.
