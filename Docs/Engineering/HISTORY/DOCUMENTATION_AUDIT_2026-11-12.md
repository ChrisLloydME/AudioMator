# Documentation audit — 2026-11-12

Date: 2026-11-12 (Asia/Shanghai). Repository baseline: `21f5940c` (`chore: target published TagLibAudioMetadata 0.7.3`). Branch: `codex/taglib-0.7.3-release-readiness`. Scope: repository documentation under `Docs/`, plus the root `README.md`, `CONTRIBUTING.md`, and `AGENTS.md` where they link into it.

No functional source, tests, Xcode project settings, dependency versions, or license resources were changed by this audit. No app launch, UI automation, live-network request, signing, notarization, or publication was performed.

## Findings

- The documentation indexes still described package 0.7.0 as the mapping implementation and presented superseded 0.7.0/0.7.1/0.7.2 records as current guidance.
- The 0.7.0 agent prompt remained under `Docs/Development` and was linked as current development guidance after the adoption was complete.
- `Docs/Product/TROUBLESHOOTING.md` still said the resolved package was 0.7.0.
- `Docs/Development/BUILD.md`, `TESTING.md`, and `CONFIGURATION.md` contained appended or duplicated status sections, stale 2026-10-17 test counts, and an obsolete `Xcode_27.0.app` CI path.
- `Docs/Reference/PROJECT_STRUCTURE.md` reported 438 app tests, 61 core tests, and an incomplete scripts table.
- `Docs/Development/TESTING.md` reported 30 SwiftPM source files; the manifest selects 31.
- `Docs/Reference/DEPENDENCY_LIMITATIONS.md` and `Docs/Architecture/METADATA_PIPELINE.md` still described 0.7.0-era blockers, including the FLAC semantic-comment failure that later releases fixed.
- `Docs/Architecture/METADATA_MAPPING_SPEC.md` and ADR 0005 described contract 2.2 as an unimplemented target after published 0.7.3 implemented it.
- Several current-state documents ended with duplicate "published mapping repair dependency" sections.
- Source inspection on 2026-11-12 found 579 app-hosted test functions in 76 classes, 62 SwiftPM test functions in four classes, and 31 Foundation-only SwiftPM sources.

## Changes

- Rebuilt the documentation and engineering indexes around current guidance versus dated evidence.
- Classified 0.7.0, 0.7.1, 0.7.2, and local-candidate records as superseded or historical, with the published 0.7.3 readiness record as current release evidence.
- Moved the obsolete 0.7.0 agent prompt to `Docs/Engineering/HISTORY/AUDIOMATOR_MAPPING_070_AGENT_PROMPT.md` and added a historical banner.
- Updated build, testing, configuration, project-structure, dependency-limitation, mapping-specification, ADR, product, troubleshooting, legal, and agent documents to published 0.7.3 and current behavior.
- Documented the unified `scripts/validate-release.sh` gate, evidence gates, and unsigned Archive evidence consistently.
- Updated exchange-profile v2 user guidance for the marker line and `<remove>` handling.
- Removed appended duplicate sections and consolidated current facts into their canonical documents.
- Added the metadata exchange profile v2 and number-normalization details to the architecture and user-facing docs.

## Verification

- Re-read the implementation for changed claims: Xcode project settings, `Config/Info.plist`, entitlements, `Package.resolved`, `Package.swift`, `.github/workflows/core-logic.yml`, `scripts/validate-release.sh`, `scripts/check-core-evidence.py`, `scripts/check-test-evidence.py`, and the current test inventory.
- Re-counted test functions and `XCTestCase` classes from source.
- Ran a relative-link check over all repository Markdown files; no missing relative targets remained after the reorganization.
- Ran `python3 -m unittest discover -s scripts/tests`: 13 policy tests passed.
- Ran `swift test --disable-sandbox --filter AudioMatorCoreLogicTests`: 62 tests passed, zero failures. A first run without `--disable-sandbox` was blocked by the host's `sandbox_apply` restriction, consistent with the documented environment limitation.
- Did not run the app-hosted suite or `scripts/validate-release.sh` for this documentation-only change. The test and release figures cited are the recorded 0.7.3 gate results in [the release readiness evidence](TAGLIB_073_RELEASE_READINESS_2026-11-12.md), not a new run.

## Remaining Boundaries

- Engineering records remain dated evidence; they are not rewritten to current behavior.
- Maintainer UI acceptance, signing, notarization, packaging, and publication remain outside automated and documentation verification.
- The shared mapping specification is normative for both repositories. This audit updated its status and evidence references, not its contract terms.
