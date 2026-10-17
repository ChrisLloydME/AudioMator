# Architecture Decision Records

Architecture Decision Records (ADRs) capture decisions that constrain future
work: dependency boundaries, persistence and transaction models, state ownership,
and other choices that are expensive to change silently.

## Index

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-atomic-write-and-reload-reservation.md) | Metadata write and reload share one path reservation | Accepted |
| [0002](0002-single-selection-owner.md) | `AudioViewModel` is the single selection owner | Accepted |
| [0003](0003-metadata-contract-and-taglib-adapter.md) | Separate the metadata contract from TagLib adapters | Accepted |
| [0004](0004-metadata-exchange-responsibility-boundaries.md) | Split Metadata Exchange by responsibility | Accepted |

## When to Write an ADR

Write one when a change:

- establishes or changes a layer/dependency boundary,
- changes the persistence or transaction model,
- changes ownership of authoritative state,
- introduces a durable compatibility constraint with an external dependency,
- chooses between alternatives that future maintainers would otherwise revisit.

Do not write an ADR for routine refactors, formatting, or a feature that follows
an existing pattern.

## Process

1. Copy the template below into a new sequentially numbered file.
2. State the context from evidence, not reconstructed history.
3. Record the decision and rejected alternatives.
4. List consequences, including costs and limits.
5. Add verification: tests, commands, or source references.
6. Add the ADR to the index.
7. Update an older ADR's status to `Superseded by ADR-XXXX` when replaced.

## Status Values

- `Proposed` — under discussion; not binding.
- `Accepted` — current decision.
- `Superseded by ADR-XXXX` — replaced.
- `Deprecated` — no longer relevant but kept for history.

## Template

```markdown
# ADR NNNN: Title

- Status: Proposed
- Date: YYYY-MM-DD

## Context

What problem or constraint exists? Cite code, tests, or external limits.
Do not invent history.

## Decision

What is decided, precisely.

## Alternatives

Which alternatives were rejected, and why.

## Consequences

What becomes easier, harder, or constrained. Include costs and known limits.

## Verification

How the decision is enforced or tested.
```
