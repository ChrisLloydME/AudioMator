# Store identifier semantic-type repair

Date: 2026-11-10. AudioMator base: `737d4f10`; dependency resolved by the normal project to published TagLibAudioMetadata 0.7.1, revision `649b7a962df7822f1d67de8c3ffd1c9528108387`. This is an application adapter repair; no package checkout/source or user audio was modified.

The maintainer reported 30 AIFF saves rejected with `itunesArtistID`/`itunesCatalogID`/`itunesAlbumID requires integer; received text`. The shared patch builder encoded these dedicated fields using its generic text helper. They were not covered by the generic typed container editor's registry-based conversion, so even valid decimal IDs were rejected.

The patch boundary now converts only requested fields declared integer-only by `MetadataFieldRegistry` to `.integer`. Empty inputs stay `.remove`, text-based identifiers stay `.text`, and invalid/overflowing values are rejected by package validation before any partial file save. No value is silently skipped, clamped or truncated. Existing unedited metadata is filtered out before conversion.

Regression tests: `StoreIdentifierWriteTests` verifies integer patch kinds for all three dedicated IDs and unchanged text semantics for MusicBrainz IDs, plus real AIFF set/replace/clear and reload using a temporary audio file generated with AVFoundation. Invalid and out-of-range IDs combined with a Title edit must leave all file bytes unchanged.

Validation commands use stable `/Applications/Xcode.app`, normal `AudioMator.xcodeproj`/`AudioMator` scheme, `.deriveddata-codex`, unsigned local builds, and serial app-hosted execution. Focused log: `/tmp/audiomator-store-id-focused.log`; full-suite log: `/tmp/audiomator-store-id-full.log`; Release build: `/tmp/audiomator-store-id-release.log`. No app was manually launched or interacted with.

Results: the focused three tests passed; the final Debug app-hosted suite executed 543 tests with zero failures; the universal macOS Release build succeeded; `git diff --check` passed. These checks used published package 0.7.1 without a local override. Interactive UI acceptance and retrying the maintainer's original files remain unperformed.
