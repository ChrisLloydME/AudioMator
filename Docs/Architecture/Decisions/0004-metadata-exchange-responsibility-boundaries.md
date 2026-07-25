# ADR 0004: Split Metadata Exchange by responsibility

- Status: Accepted
- Date: 2026-07-25

## Context

One 2,178-line file owned localized field schema, template tokenization, field mapping, export/import plan models, record matching, and planner implementation. Most planner tests were app-hosted because the file mentioned `AudioFile` and localization even though template tokenization was pure.

## Decision

- `MetadataExchangeModels.swift` owns converter modes, field schema, value projection, import validation, and relative-path behavior.
- `MetadataExchangeTemplateSyntax.swift` owns a Foundation-only tokenizer and is compiled directly by the SwiftPM fast target.
- `MetadataExchangeTemplate.swift` maps syntax placeholders to typed metadata fields while preserving unknown placeholders as literals.
- `MetadataExchangePlanning.swift` owns export/import result models, planner orchestration, locator matching, and bounded text matching.
- Keep CSV parsing and resource/index cores in `MetadataExchangeCSV.swift`; they already form a pure, bounded test surface.
- Add deterministic fixed-seed properties rather than production random fuzzing.

## Consequences

Syntax and escaping regressions run in milliseconds without mocking `AudioFile`. Full plan behavior remains app-hosted because it intentionally consumes real snapshots, fingerprints, and localized field semantics. The split follows change reasons rather than an arbitrary line limit; planning remains a larger cohesive file until a new independent behavior justifies another boundary.
