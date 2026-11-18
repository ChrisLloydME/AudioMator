# Local package advisory-review repair acceptance — 2026-11-14

App branch: `codex/package-api-performance-integration`; app production remains `f2b18801` (subsequent app commits document evidence). Local package production: `a93c2f0` on `codex/api-mapping-performance`.

The package fixes final-state advisory erase verification and preserves unchanged unknown native advisory codes. Its exact raw expectation is additive; the current adapter source compiles without changes. The public breaking API candidate and fixed native mapping contract remain as documented in the earlier integration record.

`bash scripts/validate-release.sh --local-package /absolute/path/to/TagLibAudioMetadata` passed all 13 policy tests, 62 core tests and 580 serial app-hosted tests, with complete named evidence and no failures/skips. Unsigned Release build and macOS artifact validation also passed. Evidence: `.deriveddata-codex/Validation/20261114-111021-13368/`.

Normal dependency declaration and committed lock remain exact published 0.7.3, revision `7ca1b75326388a5902815f70145b600299944ae0`. Local overrides are ignored workspaces. No manual app launch, UI acceptance, package publication, version bump or tag occurred. Existing application test-target warnings were not suppressed; package strict/sanitizer evidence and its prebuilt-TagLib instrumentation limit are recorded in the package repository's `REM-2026-11-14-independent-review-repairs.md`.
