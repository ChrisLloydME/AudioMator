# Contributing to AudioMator

AudioMator is a macOS audio metadata editor licensed under the GNU Affero General Public License v3.0. Contributions are welcome through focused pull requests.

This document states the current repository conventions. Where a convention is a recommendation rather than an enforced requirement, it is labeled.

## Before You Start

- Search existing issues and pull requests.
- For large changes, open an issue or discussion first describing the behavior, affected layers, and verification plan.
- Do not include real user media, personal metadata, credentials, or signing material in issues or commits.
- Security issues must be reported privately; see [SECURITY.md](SECURITY.md).

## Development Environment

Requirements:

- macOS with stable Xcode 27.
- Swift Package Manager.
- Network access for the first `TagLibAudioMetadata` resolution.

```bash
git clone https://github.com/ChrisLloydME/AudioMator.git
cd AudioMator
open AudioMator.xcodeproj
```

Use the `AudioMator` scheme and a macOS destination. Do not add beta-Xcode selection logic or assume a prerelease toolchain.

See [Build](Docs/Development/BUILD.md) for details.

## Repository Boundaries

- `AudioMator/App/` — entry points, commands, notifications, lifecycle.
- `AudioMator/Core/` — shared Foundation/system support.
- `AudioMator/Domain/` — business rules and value models; no UI or concrete I/O.
- `AudioMator/Features/` — native UI and feature-owned view models.
- `AudioMator/Infrastructure/` — file system, TagLib adapter, network clients.
- `Config/` — Info.plist and entitlements. Keep these outside the synchronized source root.
- `Docs/` — documentation. Update it with behavior changes.
- `Tests/` — SwiftPM fast tests; `AudioMatorTests/` — app-hosted tests.

Do not add a new top-level folder without a clear architectural boundary.

## Change Scope

- Keep a change focused on one behavior or refactor.
- Do not rewrite unrelated UI, metadata pipeline code, project settings, or dependencies.
- Do not revert user changes in a dirty worktree.
- Preserve the existing metadata write pipeline; do not write container metadata directly from UI code.
- Do not modify the external `TagLibAudioMetadata` repository or package checkout as part of an AudioMator change. Report dependency defects with a reproduction.

## Build and Test Expectations

Fast checks:

```bash
swift test
```

Build:

```bash
bash scripts/codex-build.sh
bash scripts/codex-build.sh --force   # forced validation build
```

App-hosted tests (serial):

```bash
xcodebuild \
  -project AudioMator.xcodeproj \
  -scheme AudioMator \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  test
```

Run the smallest relevant suite. Use `-only-testing:AudioMatorTests/<Class>` when appropriate. Add or update tests for behavior changes. Do not claim coverage that does not exist; see [Testing](Docs/Development/TESTING.md) for current gaps.

Agents must verify their own changes through code inspection, compilation, and the smallest relevant automated tests. Interactive UI acceptance remains the maintainer's responsibility. Do not launch the app manually, use GUI automation, or take screenshots as proof of completion.

## Code Conventions

Existing requirements:

- 4-space indentation.
- Prefer `guard` and early returns.
- Use value types unless identity, observation, or lifecycle requires a class.
- Use Swift concurrency where it fits surrounding code.
- Keep UI state ownership in feature view models or domain state.
- Do not add feature singletons.
- Use `String(localized:)` for user-facing strings.
- Do not add `print`, `debugPrint`, or `NSLog` diagnostics in app code.
- Respect `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and complete strict concurrency. Do not suppress isolation warnings.
- Keep Domain free of SwiftUI, AppKit, Combine, TagLib managers, and file transactions. See [Dependency Rules](Docs/Architecture/DEPENDENCY_RULES.md).

Proposed (not formally enforced):

- Prefer a small feature-owned helper over a broad shared abstraction until a second caller exists.
- Add an ADR for a boundary or persistence decision that future work must respect.

## Metadata Rules

- Track Number, Total Tracks, Disc Number, and Total Discs are structured, first-class fields.
- Preserve both numeric values and user-facing text intent where the pipeline supports it.
- Account for container normalization after writes. A changed text representation is not a write failure if the numeric values round-trip.
- Erase-all is best effort because tag surfaces differ by container.
- Preflight exact requested fields against format capability before writing.

## Network and Privacy Rules

Network features must be explicit and user initiated. When adding or changing one:

- Update `NetworkServiceDisclosure`.
- Update [Acknowledgements and Privacy](Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md).
- Update [Online Metadata](Docs/Architecture/ONLINE_METADATA.md).
- Update [Third-Party Notices](Docs/THIRD_PARTY_NOTICES.md) if a service or license obligation is added.
- Add deterministic tests for request construction, matching, and error mapping.
- Never upload audio file content.

## License and Attribution Rules

- Keep `AudioMator/Core/Legal/LicenseDisclosure.swift`, `AudioMator/Resources/Licenses`, and the in-app Acknowledgements sheet in sync.
- Add the copyright notice and full license text for every new bundled dependency.
- Do not remove the TagLib or `TagLibAudioMetadata` notices while distributing their code.
- Update [Third-Party Notices](Docs/THIRD_PARTY_NOTICES.md) and [Acknowledgements and Privacy](Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md) in the same change.
- Run `AudioMatorTests/LicenseDisclosureTests` after changing a bundled license or resource name.

## Documentation

A behavior change is incomplete until its documentation is updated. Use the [documentation update matrix](Docs/Development/DOCUMENTATION.md#update-matrix).

- Keep current-state docs in `Docs/Product`, `Docs/Architecture`, `Docs/Development`, `Docs/Reference`, and `Docs/Security`.
- Do not add current guidance under `Docs/Engineering/HISTORY`.
- Do not duplicate an existing explanation; link to it.
- Label proposals and unverified behavior.

## Pull Request Expectations

A pull request should include:

- a clear description of the problem and the change,
- affected layers and user-visible behavior,
- tests added or updated, and commands run,
- documentation updated,
- screenshots only for user-facing UI changes, if the contributor chooses,
- known limitations or follow-up work.

Reviewers check:

- correctness and scope,
- dependency direction,
- error and cancellation handling,
- data-integrity behavior,
- test relevance,
- documentation accuracy.

## Commit Messages

Use a short imperative subject with a conventional prefix where it fits, for example:

```text
fix: preserve unedited track pairs on disc-only saves
docs: document metadata write and reload contracts
test: cover stale revision after rename
```

Keep commits coherent. Avoid mixing unrelated refactors and behavior changes.

## Dependency Updates

`TagLibAudioMetadata` is pinned to an exact version. See [Release Engineering](Docs/Development/RELEASE.md#dependency-updates). Dependency updates must run the full relevant test suite and re-check format behavior, licenses, and privacy disclosures.

## Issue Reporting

Include:

- AudioMator version and build (Settings → About),
- macOS version,
- file format and whether the file is on a local or network volume,
- the exact operation and any preview/report text,
- a minimal reproduction with a temporary copy if possible,
- whether the issue reproduces on the current `main`.

Do not attach copyrighted audio unless you have the right to share it.

## License

By contributing, you agree that your contribution is licensed under the repository's AGPL-3.0 license. Do not contribute code you cannot license under those terms.

## Related Documents

- [Documentation index](Docs/README.md)
- [Architecture Overview](Docs/Architecture/OVERVIEW.md)
- [Testing](Docs/Development/TESTING.md)
- [Documentation Maintenance](Docs/Development/DOCUMENTATION.md)
- [AGENTS.md](AGENTS.md)
