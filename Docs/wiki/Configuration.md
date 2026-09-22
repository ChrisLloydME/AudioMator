# Configuration

## Xcode Project

The main project is `AudioMator.xcodeproj`, and the main scheme is `AudioMator`. The app entry point is `AudioMator/App/AudioMatorApp.swift`.

Visible app target settings include:

- `MARKETING_VERSION = 2.7`
- `CURRENT_PROJECT_VERSION = 2692`
- `PRODUCT_BUNDLE_IDENTIFIER = com.LloydME.AudioMator`
- Beta/debug bundle identifier: `com.TheLloydME.AudioMator.Beta`
- `SUPPORTED_PLATFORMS = macosx`
- `MACOSX_DEPLOYMENT_TARGET = 15.0`

The test target uses `com.TheLloydME.AudioMatorTests` and macOS deployment target `15.0`.

## Info.plist

`Config/Info.plist` contains:

- `CFBundleDisplayName = AudioMator`
- `CFBundleName = $(PRODUCT_NAME)`
- `CFBundleShortVersionString = $(MARKETING_VERSION)`
- `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`
- `LSApplicationCategoryType = public.app-category.utilities`
- `CFBundleLocalizations = en`
- `NSHumanReadableCopyright = Copyright © 2025-2026 Christopher Lloyd`

## Entitlements

`Config/AudioMator.entitlements` enables:

- App Sandbox.
- User-selected file read/write access.
- Network client access.

These entitlements match the project model: local editing needs user-selected file access, and online lookup or update checks need outbound network access.

## Swift Package Configuration

`Package.swift` defines an `AudioMatorCoreLogic` library and an `AudioMatorCoreLogicTests` test target. This package is not the full app target. It excludes App, Features, UI, network clients, TagLib-dependent app paths, and other platform-specific code so fast tests stay deterministic.

The Xcode workspace resolves the independent `TagLibAudioMetadata` package at
exact version `0.5.2`. Newer main-branch APIs are not adopted until that package
is separately released and the app integration is deliberately migrated.

## Localization

Localization files live at `AudioMator/Localizable.xcstrings` and `AudioMator/InfoPlist.xcstrings`. Use `String(localized:)` for user-facing strings.

## Update Check Configuration

The current macOS update check reads GitHub Releases and expects this release tag format:

```text
V{version}B{build}
```

Example:

```text
V2.3B26512
```

The update checker compares version segments first and then the build number. The current update presenter opens GitHub Releases for manual download; it does not install updates.

## Network Service Disclosure

`AudioMator/Core/Network/NetworkServiceDisclosure.swift` lists the current disclosed service hosts:

- MusicBrainz: `musicbrainz.org`
- iTunes Search API: `itunes.apple.com`
- Apple artwork hosts: `is5-ssl.mzstatic.com`, `a5.mzstatic.com`
- LRCLIB: `lrclib.net`
- Release notes and update checks: `api.github.com`
- GitHub Releases page: `github.com`

When adding or changing network behavior, update `NetworkServiceDisclosure`, `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md`, and any user-facing documentation that describes privacy or network use.
