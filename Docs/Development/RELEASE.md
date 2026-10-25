# Release Engineering

This document describes the release process that exists in the repository and clearly separates implemented automation from manual or missing steps.

## What Is Implemented

| Capability | Status |
| --- | --- |
| Version/build values in the Xcode project | Implemented as static build settings |
| Unsigned Debug/Release build | Implemented |
| Unsigned app-hosted test run in CI | Implemented |
| Minimum-OS/Mach-O validation script | Implemented |
| Signed/notarized archive creation | **Not implemented** |
| DMG/PKG/installer packaging | **Not implemented** |
| GitHub Release creation or asset upload | **Not implemented** |
| Automatic update download/install | **Not implemented** |
| Changelog generation | **Not implemented** |
| Version bump automation | **Not implemented** |

There is one CI workflow, `Validation`, and it does not publish artifacts.

## Versioning

| Value | Location |
| --- | --- |
| Marketing version | `MARKETING_VERSION` in `project.pbxproj` |
| Build number | `CURRENT_PROJECT_VERSION` in `project.pbxproj` |
| Release tag | GitHub Releases, in the form `V<version>B<build>` |

Current values are recorded in [Configuration](../Reference/CONFIGURATION.md). Example tag: `V2.7B2697`.

The in-app update checker:

- requires uppercase `V` and `B`,
- parses the marketing version as dot-separated integers,
- parses the build as an integer,
- compares marketing segments first, padding missing segments with zero, then the build.

`V2.10B100` is newer than `V2.9B999`; `V2.7B2697` equals `V2.7.0B2697`.

Both Debug and Release currently share the same marketing/build values but use different bundle identifiers. A release build must use the Release bundle ID (`com.LloydME.AudioMator`).

## Current Manual Release Procedure

The following steps are the minimum supported procedure. Only steps marked **implemented** can be verified from repository content.

1. **Choose the version and build.** Edit `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in both app target configurations. Confirm the Release bundle ID.
2. **Run tests.**
   - `swift test` (implemented, 61 tests at audit time).
   - Serial app-hosted `xcodebuild test` (implemented; current counts are in [Testing](TESTING.md)).
3. **Build Release.**
   - `xcodebuild -configuration Release -destination 'generic/platform=macOS'` (implemented; produces a universal binary in the audited environment).
4. **Validate the bundle.**
   - `scripts/validate-macos-artifact.sh <app> 15.0` (implemented).
5. **Smoke test on temporary copies.** Verify import, read, single/batch edit, save, reload, rename, renumber, conversion, and failure reporting. Manual.
6. **Sign.** Sign the app and embedded frameworks with a Developer ID identity, preserving hardened runtime and entitlements. Not automated and not configured in the repository.
7. **Notarize and staple.** Submit to Apple's notary service and staple the ticket. Not automated and not verified in this repository.
8. **Package.** Create the distribution format (DMG, PKG, or ZIP). No packaging script exists.
9. **Publish.** Create a GitHub Release with tag `V<version>B<build>`, upload the artifact, and write release notes. Manual; no automation.
10. **Verify the update path.** Open the published release and confirm the tag parses and the app's **Check for Updates…** reports it correctly.
11. **Announce** through the project's channels.

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

`.github/workflows/core-logic.yml`:

- runs `swift test` (15-minute timeout),
- runs the app-hosted suite serially with signing disabled (45-minute timeout),
- builds an unsigned Release artifact and validates it with `scripts/validate-macos-artifact.sh`.

It has read-only repository permissions, no secrets, no artifact upload, and no release job. Passing CI does not produce a distributable app.

## Compatibility Checks

- Deployment target: macOS 15.0. The validation script enforces that no Mach-O in the bundle declares a higher minimum.
- Architecture: the unsigned generic macOS Release build from this audit produced a universal executable (`x86_64` and `arm64`). The validation script does not check architectures, so verify with `lipo -info` if that matters.
- Package: exact `TagLibAudioMetadata` 0.5.3 pin. A dependency update requires a full test pass, format smoke tests, and privacy/notice review.
- Swift: Xcode 27 stable toolchain; Swift 5 language mode with complete strict concurrency.

There is no automated compatibility matrix for older macOS versions or prerelease toolchains.

## Release Notes and Changelog

There is no `CHANGELOG.md` and no release-note generation. The app displays GitHub release notes fetched from the Releases API (drafts filtered, prereleases included).

For each release, write notes that state:

- user-visible changes,
- behavior changes or removed features,
- known limitations and regressions,
- dependency updates,
- privacy/network changes,
- minimum macOS version.

## Dependency Updates

`TagLibAudioMetadata` is pinned to an exact version in both `project.pbxproj` and `Package.resolved`.

Update procedure:

1. Change the exact version requirement.
2. Resolve packages and confirm `Package.resolved` revision.
3. Build and run the full app-hosted suite, especially `TagLibReadWriteIntegrationTests` and conflict tests.
4. Smoke-test every committed fixture format on temporary copies.
5. Review the package's release notes for behavior changes.
6. Update [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md), [Acknowledgements and Privacy](../ACKNOWLEDGEMENTS_AND_PRIVACY.md), and [Third-Party Notices](../THIRD_PARTY_NOTICES.md).
7. Confirm the TagLib version reported by the new `TagLibAudioMetadataTagLib.framework` and update `AudioMator/Core/Legal/LicenseDisclosure.swift` if it changed.
8. Replace the bundled TagLib, utfcpp, or TagLibAudioMetadata license texts if the new package ships different upstream texts.
9. Record the dependency change in release notes.

There is no Dependabot/Renovate configuration and no automated dependency update.

## License and Notice Review

Before distribution, verify the legal paperwork that ships inside the app:

- `AudioMator.app/Contents/Resources` contains `AudioMator-AGPL-3.0.txt`, `TagLib-LGPL-2.1.txt`, `TagLib-MPL-1.1.txt`, `TagLibAudioMetadata-MIT.txt`, and `utfcpp-Boost-1.0.txt`.
- Settings → About → Acknowledgements lists AudioMator, TagLib, TagLibAudioMetadata, and utf8-cpp (utfcpp), and every license button opens a non-empty text.
- The TagLib entry names both the LGPL-2.1 and MPL-1.1 paths.
- The acknowledged `TagLibAudioMetadata` version matches `Package.resolved`, and the acknowledged TagLib version matches the bundled framework's reported version.
- `Docs/THIRD_PARTY_NOTICES.md` and `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md` match the shipped resources.
- The corresponding TagLib source for the bundled version is reachable, and the release notes identify the TagLib and `TagLibAudioMetadata` versions. If the package applies patches, link to the exact modified source rather than only the upstream tag.
- `AudioMatorTests/LicenseDisclosureTests` passes.

The app's own AGPL-3.0 source is public at <https://github.com/ChrisLloydME/AudioMator>; the release notes should link to the repository and to the upstream TagLib source.

## Rollback and Recovery

Because updates are manual:

- Unpublish or replace a bad GitHub Release and publish a corrected build with a higher build number.
- Keep the previous release artifact available for users who need to reinstall.
- The app does not auto-update, so a bad release does not propagate silently.
- There is no server-side kill switch or staged rollout.

## Release Checklist

- [ ] Version/build updated in both configurations.
- [ ] Release bundle ID confirmed.
- [ ] `swift test` passes.
- [ ] Serial app-hosted suite passes.
- [ ] Release build succeeds.
- [ ] `validate-macos-artifact.sh` passes.
- [ ] Temporary-fixture smoke tests pass.
- [ ] License and notice review above passes, including the five bundled license texts.
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
