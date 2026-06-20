# Engineering Health Status

Baseline: `V2.4.1B26516` (`67ce047`). Current audited head: `668c6aa`.

This record describes the completed behavior-preserving hardening work and the remaining limits. The tag remains the Expected Behavior baseline; post-tag behavior is accepted only where characterization, integration, build, or source-comparison evidence exists.

## Completed

- Split the five identified mixed-responsibility files without changing their public workflows. Line counts changed from 2,595 to 817 for `MetadataFilenameRenameSheet.swift`, 1,909 to 484 for `MetadataEditorWindow.swift`, 1,821 to 317 for `ITunesBrowserView.swift`, 3,926 to 1,852 for `MusicBrainzClient.swift`, and 1,381 to 216 for `AudioViewModel+MetadataWrite.swift`.
- Isolated deterministic rename, filename-to-metadata, metadata exchange, metadata editor, iTunes, MusicBrainz, online selection, text editing, track/disc, and metadata-write planning logic behind focused source files with fast or app-hosted characterization tests.
- Covered TagLib structured reads, raw inspection, common metadata round trips, track/disc writes, artwork writes, complete erase, inspector clearing, and raw property-map removal against every committed audio fixture.
- Covered `AudioViewModel` write orchestration for inspector edits, filename/metadata plans, metadata exchange, field imports, MuseAmp IDs, LRCLIB lyrics, and MusicBrainz/iTunes provider plans, including progress, reloads, unchanged fields, provider IDs, and track/disc pair composition.
- Preserved MusicBrainz request execution, private DTO decoding, relationship mapping, and rate limiting as one private transport boundary while moving public result/error types, search models, query normalization, and deterministic matching out of the client.

## Verification Evidence

- `swift test --filter AudioMatorCoreLogicTests`: 38 tests passed.
- Full macOS `AudioMator` Xcode test plan: passed, including all 10 `TagLibReadWriteIntegrationTests`.
- `bash scripts/codex-build.sh`: Debug generic macOS build passed.
- Release generic macOS build with signing disabled: passed; the resulting executable contains `x86_64 arm64`. This exercises the compile, optimize, link, resource, and metadata-extraction path required before Archive without creating an archive.
- TagLib bridge smoke exercised `read`, `raw`, `write-track`, and `write-roundtrip` on temporary copies of the committed mp3, m4a, flac, aac, ogg, and wav fixtures. Every command exited successfully; numeric track/disc values and totals round-tripped. Fixture originals were never modified.
- `git diff --check` passed, and no `.deriveddata-codex*`, `.tmp`, or `*.xcresult` paths are tracked.

## Post-Tag Regression Audit

- Reviewed the complete `V2.4.1B26516..HEAD` commit and file surface. The changes are concentrated in helper extraction, characterization/integration tests, documentation, and the five requested large-file splits; no unresolved reproducible regression was found in the covered workflows.
- Mechanical moves retain the tag's field meanings, track/disc composition, provider identifiers, network trigger points, platform branches, and user-visible status text. Focused characterization tests lock these boundaries after extraction.
- One reproducible pipeline issue was intentionally corrected: containers that preserve numeric track/disc values while normalizing compound text now report a container-formatting warning instead of a generic save mismatch. Fixture-backed regression coverage verifies that the numeric number and total remain unchanged before accepting that classification.
- No upstream `TagLibAudioMetadata` source, release configuration, privacy behavior, public product copy, or real music-library file was modified by this hardening series.

## Deferred Risks

- No committed aiff or opus fixture exists. Those formats are not claimed as integration-tested until immutable, redistributable samples are added.
- Live MusicBrainz/iTunes/LRCLIB requests, remote rate-limit behavior, and production API drift remain nondeterministic network boundaries. Current tests cover request construction, deterministic matching, model adaptation, and error presentation, not live services.
- Further splitting `MusicBrainzClient.swift` would require widening private DTO visibility or first adding sanitized response fixtures. The current request/DTO/mapping/rate-limit unit is intentionally retained to avoid an unproved boundary change.
- `MetadataFilenameRenameSheet.swift` remains the stateful workflow shell. Additional extraction would move file-panel, security-scope, or mutation ownership and therefore needs focused UI/application-state characterization first.
- Watched-folder monitoring, real user-library batch actions, and platform-specific SwiftUI/AppKit/iPad interaction remain manual or system-integration concerns. Automated tests use temporary files only.
- Embedded-lyrics behavior beyond the tested LRCLIB raw property-map write path remains dependent on TagLib format support.

## Decisions Needed

- Add licensed aiff and opus fixtures before requiring those formats in the integration matrix.
- Add sanitized MusicBrainz JSON fixtures before separating private transport DTO decoding and relationship mapping.
- Choose a UI automation host and stable accessibility contract before treating platform-specific window, file-panel, and drag/drop behavior as automated coverage.
