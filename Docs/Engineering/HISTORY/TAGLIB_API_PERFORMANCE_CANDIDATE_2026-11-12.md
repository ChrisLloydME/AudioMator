# Unreleased package API/performance integration — 2026-11-12

Branch: `codex/package-api-performance-integration`, based on main `9e28ee97`. Package candidate: `codex/api-mapping-performance`, based on published 0.7.3. This is local candidate validation, not package publication or a changed dependency pin.

## Scope

- Remove adapter validation/conflict references to the package's old typed `.date` YEAR alias. Use `.year` and `.standaloneDate` independently.
- Migrate fixture setup and capability/verification calls to current API while preserving every existing assertion and real-file save journey.
- Keep published 0.7.3 project resolution, current application date/CSV meanings, transaction coordination and conflict policy.
- Run the complete existing local-candidate gate: policy, core, serial app-hosted tests, unsigned Release build and artifact validation. No manual app launch.

## Evidence

The complete local-candidate gate passed using the explicitly generated ignored workspace. App production code corresponds to `9c5e1f16`; the initial source record captured the equivalent working-tree diff before that commit.

| Check | Actual result |
| --- | --- |
| Gate policy | Passed |
| Foundation core | 62 tests passed, no missing/unexpected tests |
| Serial app-hosted suite | 579 tests passed, zero failures/skips; named evidence accepted |
| Unsigned Release | Build passed |
| macOS artifact | Validated against deployment target 15.0 |
| Final affected erase journey | One real-file test passed, zero failures/skips, after the package's exact-advisory expectation was added |

Full evidence: `.deriveddata-codex/Validation/20261112-132744-20678/`, produced by `bash scripts/validate-release.sh --local-package /absolute/path/to/TagLibAudioMetadata`. The package source snapshot in that record is `00014a8` (production optimization `3ab2a34`). A later exact-advisory erasure check changes only the intermediate expected state; the final affected app test rebuilt against production `4dd2a60` and passed. Its result is `.deriveddata-codex/Validation/FinalAdvisoryErase.xcresult`; the selected method is `TagLibReadWriteIntegrationTests/testEraseAllMetadataClearsCommonFieldsAcrossWritableAudioFixtures`. The Release build also includes the final erase implementation. There was no manual app launch or UI interaction.

Existing app test-target MainActor/XCTest initializer warnings and the AppIntents metadata-extraction notice remain visible; this change adds no warning suppression and does not claim a warning-free application build. Package strict warnings-as-errors gates are recorded separately in its repository.

The normal dependency remains exact published 0.7.3 at `7ca1b75326388a5902815f70145b600299944ae0`; neither project dependency declaration nor its committed lock was modified. This branch prepares source for the future breaking API release. No new package version, tag, publication or application release was created. Package-only benchmark numbers are not application throughput claims.
