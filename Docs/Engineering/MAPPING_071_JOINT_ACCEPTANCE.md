# AudioMator / TagLibAudioMetadata 0.7.1 joint Mapping acceptance

Date: 2026-11-10. Contract: `AM-TLAM-MAPPING-2.2`. Scope: source repair and local-override acceptance. The maintainer explicitly owns manual publication; this task creates no tag or GitHub Release.

## Repositories and candidate identity

- Package branch: `codex/mapping-conformance-repairs`.
- Package production-code commit: `284dd89b4002a2e5f324bcd30d9cfd7966c68a96`.
- Package candidate-preparation HEAD observed: `941509cd09f046bd16c5234a9dac2ce5cb483244`. It changes release/version documentation only; production code and tests are identical to `284dd89`.
- Package target: 0.7.1, not published by this task.
- AudioMator branch: `codex/metadata-mapping-spec`, uncommitted application implementation/repairs preserved for review.
- AudioMator exact-version requirement and disclosure: 0.7.1. The old 0.7.0 lock resolution is removed; no nonexistent 0.7.1 tag/revision resolution is fabricated.
- Local override: ignored `.tmp/MappingIntegration.xcworkspace`, containing the AudioMator project and the package checkout. No `XCLocalSwiftPackageReference`, package source vendoring or cache-source patches are committed.

## Resolved issues

1. YEAR, DATE, RELEASEDATE and ORIGINALDATE use separate application identities, drafts, set/remove intents, preview values and patch fields. Provider release dates do not manufacture Year. No date companions or year-component replacement remain.
2. Xiph/APE native reads no longer conflate engine DATE with native YEAR. Absence and exact native arrays are retained.
3. Semantic YEAR edits do not delete native DATE. Raw deltas, raw replacement and Basic/number/advisory PropertyMap replay preserve the native owners, including spelling, arrays, malformed text and native types when untouched.
4. Date preservation checks native frame/atom/key owners rather than rejecting or masking changes through an ambiguous engine DATE alias. Only value-preserving legacy YEAR promotion when creating the first rich tag is allowed.
5. FLAC comment set/replace/remove verifies the active Xiph surface rather than requiring an unrelated secondary ID3 comment collection. Field-transfer tests assert successful committed results again, not expected failures.
6. MusicBrainz recording ID set/replace/remove uses the qualified UFID owner codec instead of treating the owner URL as a frame ID.
7. Semantic write capability follows the primary write family rather than all secondary readable tag families.
8. Purchase Date has an actual typed read/edit/write/reload route. RATE has a visible read-only route. Native target names come from the registry.
9. Private numbering cleanup rejects malformed replacement values, invalidates stale previews when input changes, keeps policy controls available, and displays planned native values. Both historical prefixes and foreign-namespace preservation are covered through real structured fixtures and captured package plans.
10. CSV/text removal tokens cannot silently turn literal metadata into deletions. Versioned and legacy syntax remain distinct; text escaping is reversible.
11. Unknown advisory values remain unknown and are preserved on unrelated saves and same-file exchange. Unsupported assignment of a new unknown code is rejected explicitly, never coerced to unset/false/Clean.

## Explicit capability boundaries

- Existing ID3v2.3 independent date writes are **read-only** until a verified codec exists. The package exposes `StructuredMetadata.id3v2MajorVersion`; typed and Basic date edits reject before mutation. AudioMator explains the restriction before save.
- The legacy v2.3 combined date display is not certified independent native YEAR/DATE evidence. Canonical date export, field transfer and date-based filenames reject those unverified projections rather than propagate a derived value. Raw inspection remains a separate low-level surface.
- ID3v2.4 date locations are positively exercised across MP3/AAC/WAV fixtures. No tag conversion or user-file migration is automatic.
- MP4 RATE has no invented write scale; MKV registrations have no native codec; media-kind labels are not guessed from codes. Unknown advisory assignment is not available through the known-state typed API.
- These are bounded capabilities, not claims that every field/format/variant is verified.

## Verification evidence

Stable `/Applications/Xcode.app`, `.deriveddata-codex`, serial app-hosted tests, unsigned local build (`CODE_SIGNING_ALLOWED=NO`), expanded cache access. No interactive app launch, UI automation, user-library file writes, signing or notarization.

| Check | Result |
| --- | --- |
| Package strict Swift/C build | Passed, warnings treated as errors |
| Package Debug | 158 XCTest declarations: 156 passed, 2 existing opt-in skips; 112 Swift Testing tests in 25 suites passed |
| Package Release | Same counts; zero failures |
| Package consumers | Facade and low-level consumers passed |
| Package docs / generated references | Passed, 45 Markdown files |
| AudioMator core | 62 passed, zero failures |
| AudioMator local-override full Debug suite | 540 passed, zero failures/skips |
| AudioMator local-override Release build | Passed |
| macOS artifact validation | Passed; app minimum 15.0 and two Mach-O files checked |

[Hosted CI on production-code commit 284dd89](https://github.com/ChrisLloydME/TagLibAudioMetadata/actions/runs/42762857244) completed successfully. That is separate evidence from local runs; the tag consumer is not evidence for an unpublished 0.7.1 tag. The subsequent documentation-only candidate preparation has its own CI run.

Representative positive tests: `MappingIndependenceRepairTests`, `MappingPackageConformanceTests`, `TagLibDateMappingIntegrationTests`, `TagLibUpgradeContractTests.testFLACSemanticCommentSetReplaceAndClearContract`, restored field-transfer integration tests, and `MappingAcceptanceRepairTests`. Earlier failures recorded in the 0.7.0 ledgers are retained as history, not relabeled as passing behavior.

Exact app acceptance command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -workspace .tmp/MappingIntegration.xcworkspace \
  -scheme AudioMator -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 CODE_SIGNING_ALLOWED=NO test
```

Logs for this candidate: `/tmp/audiomator-071-core.log`, `/tmp/audiomator-071-local-final.log`, `/tmp/audiomator-071-local-release.log`, `/tmp/audiomator-071-local-artifact.log`, `/tmp/taglib-mapping-strict.log`, `/tmp/taglib-mapping-final-debug.log`, `/tmp/taglib-mapping-final-release.log`. Local result files are not committed.

## Manual publication handoff

1. Review and merge/publish the package candidate as 0.7.1, using the final candidate commit selected by the maintainer. Do not retag 0.7.0 or replace the immutable binary asset; TagLib 2.3.1 revision 2 is unchanged.
2. In AudioMator, run normal Xcode package resolution for the existing exact 0.7.1 requirement. Commit the genuine generated `Package.resolved` version/revision pair.
3. Rerun the normal `.xcodeproj` tests/build after remote resolution and perform maintainer UI acceptance before an app release. The present report proves local-override integration, not remote 0.7.1 resolution, signing, notarization or universal format conformance.

There is no requirement to make this application development tree compile or pass against 0.7.0. Compatibility workarounds for that superseded package are not reintroduced.
