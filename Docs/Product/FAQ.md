# FAQ

## General

### Is AudioMator free and open source?

The source is licensed under the GNU Affero General Public License v3.0; see
[`LICENSE`](../../LICENSE). Distribution and modification are governed by that
license. The repository does not state any separate commercial licensing terms.

### Does AudioMator upload my audio files?

No. Ordinary reading, writing, artwork replacement, renaming, renumbering, and
conversion happen locally. Network requests occur only for explicitly started
online features and contain metadata-derived search terms, not audio file bytes.
See [Security and Data Integrity](../Security/SECURITY_AND_DATA_INTEGRITY.md).

### Does AudioMator modify files in place?

Yes. Metadata writes and renames operate on the selected files. AudioMator does
not keep an automatic backup or an undo history. Keep backups when working with
valuable files.

### Is there undo?

No document-level undo is implemented. Inspector **Cancel** discards an unsaved
draft; Metadata Editor closing discards its draft. Once a write commits, the
previous bytes are not retained by the app.

### Does AudioMator support video files?

No. The format list comes from TagLib audio format support. Video containers are
outside the documented scope.

### Can AudioMator convert between formats (for example FLAC to MP3)?

No. AudioMator edits metadata in existing files; it does not transcode audio.

## Formats and Metadata

### Which formats are supported?

The readable, writable, and artwork-writable extension lists are discovered from
`TagLibAudioMetadata` at runtime. A readable format is not necessarily writable,
and writable fields differ by container. See
[Supported Formats](OVERVIEW.md#supported-formats).

### Why did my track number change from `02/09` to something else?

Containers store number and total differently. AudioMator submits numeric values
and text intent separately; a container may normalize the combined text while
preserving the numbers. This is reported as formatting normalization, not a
failed write. Use Tag Inspector to see the stored representation.

### Why is a field reported as unsupported?

Before writing, AudioMator asks the dependency which fields a format can write.
If any requested field is unsupported, the file is not written. This is a
format-capability limitation, not a UI bug.

### Why can't I edit container-specific frames or atoms?

The Metadata Editor exposes TagLib's PropertyMap projection. Container-native
structures that TagLib does not project are not editable there. Tag Inspector may
still display them.

### Why are Year and Release Date separate?

They are separate edit intents. Some formats can store both independently; MP4
has one standard date slot, so an independent Year edit is rejected rather than
silently overwriting Release Date.

### Why does Erase All Metadata not remove everything?

Erase-all is best effort because supported tag surfaces differ by container. Some
formats retain structures the package cannot remove or that are not represented
in PropertyMap.

## Saving and Conflicts

### Why was my save refused?

Common reasons:

- the file changed on disk after the draft baseline,
- the file was replaced, moved, deleted, or became unreadable,
- the requested field is unsupported for the format,
- the draft conflicts with disk changes under the current conflict strategy,
- directory access could not be authorized.

The save issue log (Settings → Logs) records non-success outcomes.

### Does "Merge non-conflicting changes" overwrite external edits?

It merges changes to fields you did not edit. If the same field changed both in
your draft and on disk, it preserves your draft and stops with a conflict report.
The priority strategies make a different choice. See
[File Revision and Reload](../Architecture/FILE_REVISION_AND_RELOAD.md).

### Why did a permission change cause a conflict if the tags did not change?

The revision guards use filesystem metadata (including status change time) and an
opaque package version, not a content hash. Permission and timestamp changes can
therefore invalidate a revision even when bytes are unchanged. This is
conservative by design.

### A batch save partially succeeded. What now?

Retry the failed files. Files that already committed retain their new baseline
and retrying does not reapply the completed fields. Review the issue summary and
Settings → Logs.

## Files and Folders

### Where did my Quick Import files go?

Current Session is not persisted. Removing files or quitting clears the session
list. The files remain on disk.

### Does removing a watched folder delete it?

No. It removes AudioMator's bookmark and list entry.

### Why is automatic refresh degraded?

AudioMator monitors at most 128 directories per watched folder, and macOS may
refuse to monitor some directories. The sidebar reports omitted or failed
directories. A manual **Reload from Disk** or returning to the app still checks
selected files.

### Can I edit files on a network volume or file provider?

The code does not prohibit it, but verification and atomic write behavior depend
on the volume and the dependency. No throughput or reliability claim is made for
network volumes, file providers, or external disks.

## Online Features

### When does AudioMator use the network?

Only when you explicitly start MusicBrainz, iTunes, LRCLIB, release-note, or
update-check operations. There is no background synchronization.

### Why did a lookup fail or return nothing?

The service may be unavailable or rate-limited, the query may be too ambiguous,
or the network may be blocked. Provider clients have timeouts, cancellation, and
error reporting; they do not retry indefinitely.

### Does AudioMator install updates?

No. The manual update check only reports a newer release and can open the GitHub
Releases page. It does not download or install an update.

## MuseAmp

### What does MuseAmp compatibility do?

When enabled, the track list context menu can generate MuseAmp album/track IDs
and write them as a JSON Comment value. This replaces the existing Comment on the
selected files. AudioMator is not affiliated with MuseAmp.

## Development

### Which Xcode version is required?

The repository targets stable Xcode 27 (see
[Build](../Development/BUILD.md)). This audit used Xcode 27.1. Beta toolchains
are not supported by repository policy.

### Why does `swift test` not cover UI or TagLib behavior?

The SwiftPM target intentionally compiles a selected set of Foundation-only
production files as a fast sensor. TagLib, AppKit, SwiftUI, network clients, and
app-hosted behavior are tested through the Xcode test target. See
[Testing](../Development/TESTING.md).
