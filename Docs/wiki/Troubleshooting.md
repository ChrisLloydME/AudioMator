# Troubleshooting

## Swift package resolution fails

Confirm GitHub network access, then run:

```bash
xcodebuild -resolvePackageDependencies -project AudioMator.xcodeproj
```

The current project resolves `TagLibAudioMetadata` and Sparkle. `TagLibAudioMetadata` is required for the app metadata pipeline.

## `swift test` fails

Start with the fast target:

```bash
swift test --filter AudioMatorCoreLogicTests
```

If your change is UI-only or app-only, the SwiftPM target may not include the affected files. Check the failing test name and compare it with `Package.swift` to see which source files are included.

## Codex build reports an AppIcon tool crash

`scripts/codex-build.sh` recognizes a known Codex CLI environment issue where `actool`/`ibtoold` crashes while compiling `AudioMator/AppIcon.icon`. If the log matches the known AppIcon failure and there are no other compiler errors, the script treats it as an environment-specific false positive.

Still inspect the log for unrelated compiler errors.

## xcodebuild cannot write caches

Sandboxed environments may block `xcodebuild` from writing SwiftPM, Clang, simulator, or Xcode cache files under the user Library. Treat those errors as environment issues first, then rerun with appropriate permissions before diagnosing project code.

## Online metadata lookup returns no result

Confirm that the selected network feature was explicitly started and that network access is available.

Typical search inputs differ by provider:

- MusicBrainz: title, artist, album, album artist, track/disc information, duration, release identifiers, ISRC, barcode, MusicBrainz links, or manual search text.
- iTunes: title, artist, album, UPC, Apple Music/iTunes links, store IDs, and storefront country.
- LRCLIB: title, artist, album, and duration.

If file metadata is incomplete, try filename fallback or manual query text.

## Written metadata looks different after saving

Use Tag Inspector or raw metadata inspection to see what AudioMator reads from the file. Some containers normalize track/disc text even when the numeric value is preserved.

For MP4/M4A track/disc behavior, the TagLib bridge smoke tool can validate `trkn`/`disk` round trips on temporary files.

## Watched folders do not appear

Watched folders are macOS-only. On macOS, confirm that the folder still exists and remains accessible. Also check whether you are looking at the current session source rather than the watched-folder source.

## Release tag is not recognized

The manual update checker expects GitHub release tags in this form:

```text
V{version}B{build}
```

Example:

```text
V2.3B26512
```

Only the version before `B` is used for update comparison.
