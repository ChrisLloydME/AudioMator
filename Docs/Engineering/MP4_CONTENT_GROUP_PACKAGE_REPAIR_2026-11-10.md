# MP4 Content Group package repair acceptance

Package branch: `codex/mp4-content-group-verification`, based on published 0.7.1 (`649b7a9`). Application branch: `codex/test-system-upgrade`. No publication, version bump, commit or lock-file update was performed.

The package now recognizes the engine PropertyMap GROUPING projection owned by ©grp while preserving independent native Grouping/Work atoms. It also stops reading absent Content Group from independent Grouping. Package regression covers independent set/replace/remove for all three native owners with absent/present multi-value siblings.

Both package Debug and Release suites passed: 156 XCTest passed, two existing skips, 113 Swift Testing passed. AudioMator's complete serial suite executed 574 tests with zero failures against `.tmp/MappingIntegration.xcworkspace`; the resolution log confirms the local package path. Evidence: `/tmp/audiomator-content-group-local-override.log`. This consumes the package repair directly; no application raw-write workaround or expected-failure exemption is used.

This resolves the historical Content Group blocker only when the local repair source is used. The normal project is still pinned to published 0.7.1, which does not contain the fix. Maintainer publication and a subsequent dependency update/normal-project acceptance remain required before distributing the repaired package with AudioMator. No interactive UI acceptance was performed.
