# ADR 0005: Adopt a versioned native metadata interoperability mapping contract

- Status: Accepted (current published pin: TagLibAudioMetadata 0.8.2)
- Date: 2026-11-09

## Context

At the 0.6.0 baseline (revision `c135fe0a3c52ba76054731e2afe3e56b83f6d40e`), AudioMator sent Year to `.date` and Release Date to `.releaseDate`. That package version disallowed typed MP4 `.date` and assigned `.releaseDate` to `©day`, differing from the intended interoperable YEAR location. Replacing a stored date with a year also lost its original precision. Other issues included work and grouping, encoder fields, and native store identifiers.

## Decision

Adopt [AM-TLAM-MAPPING-2.2](../METADATA_MAPPING_SPEC.md) as the accepted interoperability contract. The package and application repositories maintain one shared contract. Use the specification’s explicit native mappings as the compatibility authority, with non-colliding supplementary engine mappings and documented divergence decisions. Semantic keys are independent of engine PropertyMap aliases; native identity determines projection. Version 2.2 keeps Year, Date, Release Date and Original Release Date independent, removing the earlier automatic year projection/component edits. Different years are valid, including Year=2004 with Release Date=2017-06-09. YEAR owns its declared native slots, including MP4 ©day; independent DATE and RELEASEDATE use separate registered locations. No cross-field derivation, filling, synchronization, clearing or equality check is permitted. Preserve exact baselines, native identity and unknown metadata; do not automatically migrate user files.

Standalone historical total aliases must be recovered without losing their sole values. Both AUDIOMATOR and TAGLIBAUDIOMETADATA number-text namespaces are retired by explicit per-pair plans; no default writer creates or renames them. Native trkn/disk or TRCK/TPOS carry totals; normal Vorbis/APE total fields remain supported. Unrelated saves preserve all legacy fields.

The package owns registry, container projection, native transactions and verification. AudioMator owns user intent, preview, selection, mutation coordination and reporting. The adapter may not bypass capabilities through a raw or legacy writer. Package release and app pin adoption are separate steps; this ADR changes neither dependency resolution nor executable behavior.

## Alternatives

- Automatically deriving or synchronizing Year from another date would overwrite legitimate independent metadata and is explicitly rejected.
- Treating the engine’s default PropertyMap names as the compatibility authority would reintroduce known content-group and publisher disagreements.
- Copying external editor labels into canonical keys conflates display names with storage semantics and user-configurable mappings.
- Following native specification labels alone fails to account for established cross-tool use of the primary Date slot.
- Writing all aliases maximizes duplication and risks contradictory metadata; explicit alias resolution is required instead.

## Consequences

The refactor must introduce precision-aware dates and edit intents, revise the package registry, version exchange schemas, preserve old draft provenance and update conflicting tests. There is no background file conversion. Complete conformance requires per-field/per-format evidence rather than an extension-level writable flag. Existing safety boundaries and maintainer-owned interactive acceptance remain in force.

## Verification

The shared specification defines preferred native targets, conformance tests, migrations and release gates. `ITUNESADVISORY` distinguishes absence from 0 (Not Explicit), 1 (Explicit), and 2 (Clean). The [metadata mapping table](../../Reference/METADATA_FIELD_MAPPING_TABLE.md) tracks the current registry inventory, and [Dependency Limitations](../../Reference/DEPENDENCY_LIMITATIONS.md) describes the 0.8.2 pin and its verified restrictions.
