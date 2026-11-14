# Diagnostic package candidate integration — 2026-11-14

This checkout evaluates the local `codex/diagnostic-native-owner-repairs` package candidate; the published exact dependency remains 0.7.3. No package publication or dependency pin change occurs.

The legacy-date integration test previously pinned TagLib's synthesized YEAR (`2004-04-03`) and empty DATE as expected behavior. The repaired package exposes literal YEAR `2004` and TDAT `0304`, matching the independent-field contract. The test now asserts those values while retaining date-write rejection, byte immutability and observed v2.3 evidence checks. Production app code is unchanged.

## Current local-candidate evidence

`bash scripts/validate-release.sh --local-package /Users/lloyd/Developer/Xcode/TagLibAudioMetadata` passed. Evidence: `.deriveddata-codex/Validation/20261114-231903-1620/`.

- Gate-policy tests passed.
- Core gate accepted all 62 expected tests.
- Serial app-hosted gate accepted all 580 expected tests, with no skips or failures.
- Unsigned Release build and macOS artifact checks passed.

The source record captures AudioMator `625024d3` and package `12f6ce2` plus the candidate diff hash `3f9119fc2a43d13405d740d00376d9e8956633a91b8f1f42588abf87d1fc068d`. That production diff is committed as package `5a78449`; later `55a9f0c` and `de282df` change regression gates/tests only. Package documentation changes do not alter the compiled candidate. The package follow-up protects staged v2.3 date owners across facade writers, binds structured preservation to its read version and removes empty MP4 artwork ownership on explicit clear.

No interactive app launch or UI acceptance was performed. Published dependency resolution and app production code remain unchanged.
