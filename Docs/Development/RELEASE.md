# Release Engineering

This document describes the release process that exists in the repository and clearly separates implemented automation from manual or missing steps. Values were verified by source inspection on 2026-11-18; no build, archive, signing, or notarization was performed for this audit.

## What Is Implemented

| Capability | Status |
| --- | --- |
| Version/build values in the Xcode project | Implemented as static build settings |
| Unsigned Debug/Release build | Implemented; `scripts/validate-release.sh` builds unsigned Release |
| Unsigned Xcode Archive | Not part of the current gate; last recorded with published 0.8.0 ([historical evidence](../Engineering/HISTORY/TAGLIB_080_RELEASE_READINESS_2026-11-16.md#unsigned-archive)) |
| Unsigned app-hosted test run in CI | Implemented |
| Minimum-OS/Mach-O validation script | Implemented |
| Signed/notarized archive creation | **Not implemented** |
| DMG/PKG/installer packaging | **Not implemented** |
| GitHub Release creation or asset upload | **Not implemented** |
| Automatic update download/install | **Not implemented** |
| Changelog generation | **Not implemented** |
| Version bump automation | **Not implemented** |

There is one CI workflow, `Validation`. It uploads test logs and `.xcresult` evidence, but does not publish a distributable release. Local and CI acceptance use `bash scripts/validate-release.sh`; see [the metadata test contract](METADATA_TEST_STRATEGY.md). A failing mapping regression blocks release even when unrelated tests pass.

## Versioning

| Value | Location | Current value |
| --- | --- | --- |
| Marketing version | `MARKETING_VERSION` in `project.pbxproj` | `2.7` in both app configurations |
| Build number | `CURRENT_PROJECT_VERSION` in `project.pbxproj` | `26112` in both app configurations |
| Release tag | GitHub Releases, in the form `V<version>B<build>` | Local tag `V2.7B26112` exists at `9599e016` (2026-11-12) |

Current values are also recorded in [Configuration](../Reference/CONFIGURATION.md); verify them in `AudioMator.xcodeproj/project.pbxproj` before a release. The current project values match the local tag `V2.7B26112` (its tagged project also declares `2.7`/`26112`); `git describe` reports 92 commits since that tag, and remote tag presence was not checked. A new publication therefore needs a maintainer decision on new `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` values and a tag that does not already exist.

The in-app update checker:

- requires an uppercase `V` and `B` in the tag,
- parses the marketing version as dot-separated integers,
- parses the build as an integer,
- compares marketing segments first, padding missing segments with zero, then the build.

`V2.10B100` is newer than `V2.9B999`; `V2.7B26112` equals `V2.7.0B26112`. The update check asks `api.github.com` for `/releases/latest`, which excludes drafts and prereleases.

Both Debug and Release currently share the same marketing/build values but use different bundle identifiers. A release build must use the Release bundle ID (`com.LloydME.AudioMator`); Debug is `com.TheLloydME.AudioMator.Beta`.

## Current Manual Release Procedure

The following steps are the minimum supported procedure. The repository implements the build, gate, and artifact checks; signing, notarization, packaging, publication, and UI acceptance remain manual.

1. **Choose the version and build.** Edit `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in both app target configurations, and confirm the Release bundle ID. Do not reuse an existing published tag.
2. **Run the unified gate.** `bash scripts/validate-release.sh` runs the policy tests (29 at this revision), 97 core tests, the complete serial app-hosted suite (1010 source-declared tests at this revision), an unsigned Release build, and artifact validation, and records evidence under `.deriveddata-codex/Validation/`.
3. **Smoke test on temporary copies.** Verify import, read, single/batch edit, save, reload, rename, renumber, metadata/filename conversion, and failure reporting. Manual.
4. **Sign.** Sign the app and embedded frameworks with a Developer ID identity, preserving hardened runtime and entitlements. Not automated and not configured in the repository.
5. **Notarize and staple.** Submit to Apple's notary service and staple the ticket. Not automated and not verified in this repository.
6. **Package.** Create the distribution format (DMG, PKG, or ZIP). No packaging script exists.
7. **Publish.** Create a GitHub Release with tag `V<version>B<build>`, upload the artifact, and write release notes. Manual; no automation.
8. **Verify the update path.** Open the published release and confirm the tag parses and the app's **Check for Updates…** reports it correctly.
9. **Announce** through the project's channels.

For an unsigned archive validation separate from the gate, use the settings in [the 0.8.0 evidence](../Engineering/HISTORY/TAGLIB_080_RELEASE_READINESS_2026-11-16.md#unsigned-archive) with the normal project and `-disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile`. That record predates the current 0.8.2 pin; re-run the archive if it matters for the release.

Do not describe the app as signed, notarized, or installer-packaged unless the corresponding step was actually performed and verified.

## Signing and Notarization Requirements

If a signed distribution is produced, it must satisfy:

- App Sandbox with the existing entitlements:
  - `com.apple.security.app-sandbox`,
  - `com.apple.security.files.user-selected.read-write`,
  - `com.apple.security.network.client`.
- Hardened Runtime enabled.
- A valid Developer ID Application identity and matching provisioning setup.
- Notarization and stapling for distribution outside the Mac App Store.

The repository does not include a certificate, provisioning profile, export options plist, or notarization credentials. The `DEVELOPMENT_TEAM` value in the project is a local signing setting, not a distribution configuration.

## CI

`.github/workflows/core-logic.yml` (`Validation`):

- runs `swift test` (15-minute timeout),
- runs `bash scripts/validate-release.sh` (45-minute timeout), which includes the complete serial app-hosted suite, unsigned Release build, and `scripts/validate-macos-artifact.sh`,
- uploads `.deriveddata-codex/Validation/` evidence with `actions/upload-artifact`, including on failure.

It has read-only repository permissions, no release secrets and no release job. Passing CI does not produce a distributable app.

## Compatibility Checks

- Deployment target: macOS 15.0. The validation script enforces that the bundle's `LSMinimumSystemVersion` equals 15.0 and that no Mach-O in the bundle declares a higher minimum.
- Architecture: the last recorded unsigned Release build produced a universal executable (`x86_64` and `arm64`), but that was an earlier dependency revision. The validation script does not check architectures, so verify with `lipo -info` if that matters.
- Package: exact `TagLibAudioMetadata` 0.8.2 pin (revision `6b03cb97d96f2f7c25080b7145e4bf3340a9f868`). A dependency update requires a full test pass, format smoke tests, and privacy/notice review.
- Swift: Xcode 27.2 stable toolchain; Swift 5 language mode with complete strict concurrency.

There is no automated compatibility matrix for older macOS versions or prerelease toolchains.

## Release Notes and Changelog

There is no `CHANGELOG.md` and no release-note generation. The app displays GitHub release notes fetched from the Releases API (drafts filtered, prereleases included, first 50 releases requested).

For each release, write notes that state:

- user-visible changes,
- behavior changes or removed features,
- known limitations and regressions,
- dependency updates,
- privacy/network changes,
- minimum macOS version.

## Dependency Updates

`TagLibAudioMetadata` is pinned to an exact version in both `project.pbxproj` and `AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Update procedure:

1. Change the exact version requirement in the Xcode project.
2. Resolve packages and confirm the `Package.resolved` version and revision.
3. Build and run the full app-hosted suite, especially `TagLibReadWriteIntegrationTests`, `MappingPackageConformanceTests`, and conflict tests; then run `bash scripts/validate-release.sh`.
4. Smoke-test every committed fixture format on temporary copies.
5. Review the package's release notes for behavior changes.
6. Update [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md), [Acknowledgements and Privacy](../ACKNOWLEDGEMENTS_AND_PRIVACY.md), and [Third-Party Notices](../THIRD_PARTY_NOTICES.md).
7. Confirm the TagLib version reported by the embedded `TagLibAudioMetadataTagLib.framework` and update `AudioMator/Core/Legal/LicenseDisclosure.swift` if it changed.
8. Replace the bundled TagLib, utfcpp, or TagLibAudioMetadata license texts if the new package ships different upstream texts.
9. Record the dependency change in release notes.

There is no Dependabot/Renovate configuration and no automated dependency update.

## License and Notice Review

Before distribution, verify the legal paperwork that ships inside the app:

- The built app's `Contents/Resources` contains `AudioMator-AGPL-3.0.txt`, `TagLib-LGPL-2.1.txt`, `TagLib-MPL-1.1.txt`, `TagLibAudioMetadata-MIT.txt`, and `utfcpp-Boost-1.0.txt`. The current Debug build product has these five files at the top level; the Release bundle must be checked manually, because `validate-macos-artifact.sh` does not inspect resources.
- Settings → About → Acknowledgements lists AudioMator, TagLib, TagLibAudioMetadata, and utf8-cpp (utfcpp), and every license button opens a non-empty text.
- The TagLib entry names both the LGPL-2.1 and MPL-1.1 paths.
- The acknowledged `TagLibAudioMetadata` version matches `Package.resolved`, and the acknowledged TagLib version matches the bundled framework's reported version.
- `Docs/THIRD_PARTY_NOTICES.md` and `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md` match the shipped resources.
- The corresponding TagLib source for the bundled version is reachable, and the release notes identify the TagLib and `TagLibAudioMetadata` versions. If the package applies patches, link to the exact modified source rather than only the upstream tag.
- `AudioMatorTests/Unit/Core/LicenseDisclosureTests.swift` passes.

The app's own AGPL-3.0 source is public at <https://github.com/ChrisLloydME/AudioMator>; the release notes should link to the repository and to the upstream TagLib source.

## Rollback and Recovery

Because updates are manual:

- Unpublish or replace a bad GitHub Release and publish a corrected build with a higher build number.
- Keep the previous release artifact available for users who need to reinstall.
- The app does not auto-update, so a bad release does not propagate silently.
- There is no server-side kill switch or staged rollout.

## Release Checklist

- [ ] Version/build updated in both configurations and tag not previously published.
- [ ] Release bundle ID confirmed.
- [ ] `swift test` passes.
- [ ] `bash scripts/validate-release.sh` passes (policy, core, serial app-hosted, Release build, artifact).
- [ ] Temporary-fixture smoke tests pass.
- [ ] License and notice review above passes, including the five bundled license texts in the Release bundle.
- [ ] In-app Acknowledgements lists every bundled component and opens every license text.
- [ ] Privacy/third-party docs reviewed for dependency or network changes.
- [ ] Code signing applied (manual).
- [ ] Notarization and stapling complete (manual).
- [ ] Package created (manual).
- [ ] GitHub Release tag is `V<version>B<build>`.
- [ ] Update check reports the new release.
- [ ] Release notes published.

## Related Documents

- [Build](BUILD.md)
- [Testing](TESTING.md)
- [Configuration](../Reference/CONFIGURATION.md)
- [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md)

Local package candidates may be validated with the explicit `--local-package` option documented in [Build](BUILD.md#local-package-candidate-gate). Candidate acceptance does not authorize publication or establish that the current published dependency is repaired. Source-declared core/app test inventories and critical save journeys are mandatory evidence; missing named tests or skipped/expected-failure results block the gate. See [current published-pin acceptance](../Engineering/TAGLIB_081_DEBUG_ADOPTION_2026-11-17.md) and the [2026-11-18 cleanup acceptance](../Engineering/AUDIOMATOR_LEGACY_CLEANUP_ACCEPTANCE_2026-11-18.md); the earlier [state-coverage evidence](../Engineering/HISTORY/METADATA_STATE_COVERAGE_2026-11-11.md) describes a local candidate and remains historical.
