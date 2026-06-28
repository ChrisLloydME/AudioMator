# Release Notes and Versioning

Use this page to prepare release notes and verify AudioMator version metadata before publishing a GitHub Release.

## Current Version Settings

The Xcode app target currently uses:

- `MARKETING_VERSION = 2.5`
- `CURRENT_PROJECT_VERSION = 26601`

Engineering health notes reference a historical baseline tag, `V2.4.1B26516`, and an audited head, `668c6aa`. Treat those as maintenance references, not release notes.

## Release Tag Rule

The manual update checker expects GitHub Releases to use:

```text
V{version}B{build}
```

Example:

```text
V2.3B26512
```

Only the version before `B` is used for update comparison. The build number is ignored when deciding whether a newer version exists.

## Pre-Release Checklist

- Run `swift test --filter AudioMatorCoreLogicTests` or `swift test`.
- Run `bash scripts/codex-build.sh --force` for a generic macOS build.
- If TagLib bridge or format-write behavior changed, run bridge smoke tests on temporary files.
- Check whether `README.md` still matches platform, format, privacy, and network behavior.
- Check whether `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md` and `Docs/THIRD_PARTY_NOTICES.md` cover any new service or dependency.
- Confirm that the release tag matches `V{version}B{build}`.
- Confirm that the app bundle version and build number match the release tag.

## Release Notes Structure

A release note should start with the release tag, then list only changes included in that release.

Recommended sections:

- New Features: user-visible capabilities added in the release.
- Fixes & Improvements: bug fixes, workflow improvements, stability work, and performance work, written in terms of user impact.
- Compatibility Notes: macOS, iPadOS, TagLib, file-format, or Xcode compatibility notes.
- Privacy / Network Notes: any change to network triggers, transmitted fields, service hosts, or update-check behavior.
- Verification: the test and build commands run for the release.

If a section has no relevant changes, omit it instead of writing an empty heading.

## Good Release Inputs

Before writing a release note, collect the actual release scope from:

- The diff since the previous release tag.
- The app version and build number in Xcode build settings.
- Test output for SwiftPM, app-hosted tests, build checks, or bridge smoke tests.
- Updated privacy, third-party, and compatibility notes.
- Any known platform limitations that users should see before installing.

Current project areas worth checking before the next release include manual update checks, structured track/disc number handling, metadata/text conversion, platform differences between macOS and iPadOS, and privacy boundaries for online metadata sources.
