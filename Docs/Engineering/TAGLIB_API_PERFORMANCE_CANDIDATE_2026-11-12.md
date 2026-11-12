# Unreleased package API/performance integration — 2026-11-12

Branch: `codex/package-api-performance-integration`, based on main `9e28ee97`. Package candidate: `codex/api-mapping-performance`, based on published 0.7.3. This is local candidate validation, not package publication or a changed dependency pin.

## Scope

- Remove adapter validation/conflict references to the package's old typed `.date` YEAR alias. Use `.year` and `.standaloneDate` independently.
- Migrate fixture setup and capability/verification calls to current API while preserving every existing assertion and real-file save journey.
- Keep published 0.7.3 project resolution, current application date/CSV meanings, transaction coordination and conflict policy.
- Run the complete existing local-candidate gate: policy, core, serial app-hosted tests, unsigned Release build and artifact validation. No manual app launch.

## Evidence

Pending completion. Package-only benchmark numbers are not application throughput claims.
