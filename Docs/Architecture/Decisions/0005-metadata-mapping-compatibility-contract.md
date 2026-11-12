# ADR 0005: Adopt a versioned native metadata interoperability mapping contract

- Status: Accepted (implemented by published TagLibAudioMetadata 0.7.3)
- Date: 2026-11-09

## Context

Current AudioMator sends Year to `.date` and Release Date to `.releaseDate`. Package 0.6.0 disallows typed MP4 `.date` and assigns `.releaseDate` to ©day. This differs from upstream TagLib's DATE mapping and the declared interoperable YEAR location. A year-only model also loses complete date precision when written as a replacement. Other registry entries disagree over work/grouping, encoder fields and native store identifiers. The package checkout inspected for this decision is exact 0.6.0, revision c135fe0a3c52ba76054731e2afe3e56b83f6d40e.

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

The shared specification enumerates all 79 current package enum cases plus five planned additions, across seven native family/version columns, and the application integration routes. Dedicated tables additionally cover all 26 MP4-exclusive entries and both MKV-exclusive entries (including overlap with the core matrix). ITUNESADVISORY is absent/unset, 0=not Explicit, 1=Explicit, 2=Clean; present zero must never collapse to absence. It defines conformance tests, migration cases and release gates. Published package 0.7.3 and the recorded application gate implement the contract; [Dependency Limitations](../../Reference/DEPENDENCY_LIMITATIONS.md) states the remaining current capability restrictions.
