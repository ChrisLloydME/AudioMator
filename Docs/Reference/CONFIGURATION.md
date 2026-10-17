# Configuration

This document records the configuration that affects builds, runtime behavior,
persistence, and network access. Values change; verify them in the project before
a release.

## Xcode Project

- Project: `AudioMator.xcodeproj`
- Shared scheme: `AudioMator`
- App target: `AudioMator`
- Test target: `AudioMatorTests` (app-hosted)

Both source roots (`AudioMator/`, `AudioMatorTests/`) use Xcode's file-system
synchronized groups. New files under those roots are included automatically.

## App Target Settings

| Setting | Debug | Release |
| --- | --- | --- |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.TheLloydME.AudioMator.Beta` | `com.LloydME.AudioMator` |
| `MARKETING_VERSION` | `2.7` | `2.7` |
| `CURRENT_PROJECT_VERSION` | `2697` | `2697` |
| `MACOSX_DEPLOYMENT_TARGET` | `15.0` | `15.0` |
| `SDKROOT` | `macosx` | `macosx` |
| `SUPPORTED_PLATFORMS` | `macosx` | `macosx` |
| `SWIFT_VERSION` | `5.0` | `5.0` |
| `SWIFT_STRICT_CONCURRENCY` | `complete` | `complete` |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` | `MainActor` |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` | `YES` |
| `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` | `YES` | `YES` |
| `ENABLE_APP_SANDBOX` | `YES` | `YES` |
| `ENABLE_HARDENED_RUNTIME` | `YES` | `YES` |
| `ENABLE_INCOMING_NETWORK_CONNECTIONS` | `NO` | `NO` |
| `ENABLE_OUTGOING_NETWORK_CONNECTIONS` | `YES` | `YES` |
| `ENABLE_USER_SELECTED_FILES` | `readwrite` | `readwrite` |
| `CODE_SIGN_STYLE` | `Automatic` | `Automatic` |
| `DEVELOPMENT_TEAM` | `YM5G2M8PV9` | `YM5G2M8PV9` |
| `CODE_SIGN_ENTITLEMENTS` | `Config/AudioMator.entitlements` | same |
| `GENERATE_INFOPLIST_FILE` | `NO` | `NO` |
| `INFOPLIST_FILE` | `Config/Info.plist` | same |
| `ASSETCATALOG_COMPILER_APPICON_NAME` | `AppIcon` | `AppIcon` |

Other differences are standard Xcode Debug/Release defaults: Debug uses `dwarf`,
`-Onone`, `ENABLE_TESTABILITY=YES`, `ONLY_ACTIVE_ARCH=YES`, and the `DEBUG`
compilation condition; Release uses `dwarf-with-dsym`, whole-module
optimization, and `ENABLE_NS_ASSERTIONS=NO`.

Debug and Release use different bundle identifiers, so they do not share
sandbox containers, preferences, or bookmarks.

### Test Target

- Bundle identifier: `com.TheLloydME.AudioMatorTests`
- Marketing version `1.0`, build `1`
- Deployment target `15.0`
- Swift language mode `5.0`, strict concurrency `complete`
- `TEST_HOST` points at the built `AudioMator.app`

The scheme marks the testable non-parallel.

## Info.plist

`Config/Info.plist` contains:

- `CFBundleDevelopmentRegion = en`
- `CFBundleDisplayName = AudioMator`
- `CFBundleExecutable = $(EXECUTABLE_NAME)`
- `CFBundleIdentifier = $(PRODUCT_BUNDLE_IDENTIFIER)`
- `CFBundleLocalizations = [en]`
- `CFBundleName = $(PRODUCT_NAME)`
- `CFBundlePackageType = APPL`
- `CFBundleShortVersionString = $(MARKETING_VERSION)`
- `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`
- `LSApplicationCategoryType = public.app-category.utilities`
- `NSHumanReadableCopyright = Copyright © 2025-2026 Christopher Lloyd`

`LSMinimumSystemVersion` is injected by Xcode from the deployment target. There
are no usage-description keys and no App Transport Security exceptions.

## Entitlements

`Config/AudioMator.entitlements`:

| Entitlement | Value | Purpose |
| --- | --- | --- |
| `com.apple.security.app-sandbox` | `true` | Sandboxed app |
| `com.apple.security.files.user-selected.read-write` | `true` | Read/write files the user selects or authorizes |
| `com.apple.security.network.client` | `true` | Outgoing network for explicit online features |

Not present:

- incoming network connections,
- `com.apple.security.files.bookmarks.app-scope`,
- Keychain or other capability entitlements.

The missing `bookmarks.app-scope` entitlement is a documented risk for
cross-launch security-scoped bookmark restoration; see
[Security and Data Integrity](../Security/SECURITY_AND_DATA_INTEGRITY.md).

## Swift Package

- Manifest: `Package.swift`
- Package name: `AudioMatorCoreLogic`
- Tools version: 6.0
- Platform: macOS 15
- Library target: `AudioMatorCoreLogic` (selected source files)
- Test target: `AudioMatorCoreLogicTests` at `Tests/AudioMatorCoreLogicTests`
- No external package dependencies

This package is a test harness, not the app dependency graph.

## External Package

`AudioMator.xcodeproj/project.pbxproj`:

```text
repositoryURL = "https://github.com/ChrisLloydME/TagLibAudioMetadata.git"
kind = exactVersion
version = 0.5.3
```

`Package.resolved`:

- identity: `taglibaudiometadata`
- version: `0.5.3`
- revision: `03473c9ae199026b806a5f75c387ca036e325284`

## Scheme

`AudioMator.xcscheme`:

- Build action includes the app for running, testing, profiling, archiving, and
  analyzing.
- Test action uses Debug and includes `AudioMatorTests`, non-parallel.
- Launch action uses Debug.
- Profile action uses Release.
- Analyze action uses Debug.
- Archive action uses Release and reveals the archive in Organizer.

## Workspace

`project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` is an empty
dictionary. There are no custom workspace-level build locations.

## CI Environment

`.github/workflows/core-logic.yml`:

```yaml
env:
  DEVELOPER_DIR: /Applications/Xcode_27.0.app/Contents/Developer
```

- Runner label: `xcode-27`
- `swift-test` timeout: 15 minutes
- `xcode-test` timeout: 45 minutes
- App-hosted test command disables parallel testing and signing.
- Release artifact build also disables signing and validates the bundle.

The runner and toolchain path are external provisioning details.

## Local Persistence

### UserDefaults keys

| Key | Content |
| --- | --- |
| `watchedFolderRecords` | JSON `[WatchedFolderRecord]` with security-scoped bookmark data |
| `watchedFolderRecords.corruptBackup` | Quarantined corrupt bookmark payload |
| `fileAccessGrantRecords` | JSON `[FileAccessGrantRecord]` with bookmark data |
| `fileAccessGrantRecords.corruptBackup` | Quarantined corrupt grant payload |
| `metadata.conflictPolicy` | `MetadataConflictPolicy` raw value |
| `middleList.visibleColumns` | Ordered visible column raw values |
| `middleList.sort.column` | Sort column raw value |
| `middleList.sort.ascending` | Sort direction |
| `toolbar.visibleButtons` | Visible toolbar button raw values |
| `inspector.metadata.visibleFields` | Visible inspector field raw values |
| `settings.selectedTab` | Last selected settings tab |
| `museAmpSupportEnabled` | MuseAmp compatibility toggle |
| `hasCompletedWelcomeSplash` | Welcome completion flag |
| `completedWelcomeSplashVersion` | Last completed welcome version (currently 3) |
| `suppressesUnsavedInspectorDiscardWarning` | Discard-warning suppression |
| `hasLaunchedBefore` | First-launch window sizing flag |

### Files

| Path | Content | Limit |
| --- | --- | --- |
| `Application Support/AudioMator/SaveIssueLog.json` | Save issue entries (file names + messages) | 200 entries |

Audio files themselves are not copied into app storage.

## Network Configuration

- All app requests use `URLSession.shared`; there is no custom session
  configuration, proxy, cookie, cache, or certificate pinning.
- MusicBrainz, iTunes, and LRCLIB requests use a 15-second timeout.
- GitHub requests set no explicit timeout.
- No API keys, tokens, or Keychain usage.
- No ATS exceptions.
- No privacy manifest (`PrivacyInfo.xcprivacy`).

Endpoints and request data are documented in
[Online Metadata](../Architecture/ONLINE_METADATA.md).

## Related Documents

- [Build](../Development/BUILD.md)
- [Release Engineering](../Development/RELEASE.md)
- [Security and Data Integrity](../Security/SECURITY_AND_DATA_INTEGRITY.md)
