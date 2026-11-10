# AudioMator metadata mapping implementation prompt

Copy the instructions below into the agent attached to the AudioMator project in Xcode Code Intelligence. This is an implementation task, not a request for another design proposal.

## Objective and completion boundary

Implement AudioMator's adoption of TagLibAudioMetadata **0.7.0** and mapping contract **AM-TLAM-MAPPING-2.2**. Complete the application pipeline, models, editing surfaces, previews, providers, exchange workflows, conflicts, tests, and current documentation. Do not stop after upgrading the dependency or fixing Year in the Inspector.

You have access to **AudioMator only**. The package is an external, released dependency. Do not enter, modify, build independently from, commit in, or copy a sibling package checkout. Do not patch resolved package sources or caches. Normal dependency resolution and compilation as part of the AudioMator build are authorized. Inspect public declarations through Xcode's module/generated interface and the published, tag-pinned documentation. Do not depend on unpublished APIs.

Read `AGENTS.md` before changing anything. Preserve existing uncommitted changes. Use stable `/Applications/Xcode.app`, project `AudioMator.xcodeproj`, scheme `AudioMator`, macOS 15.0+, Swift 5 language mode with complete strict concurrency and MainActor default isolation. Do not suppress concurrency diagnostics or relax build settings to make the upgrade compile.

The only requested product work is this mapping refactor. Do not change app release numbers, unrelated UI, update feeds, network behavior, or deployment targets. Do not push, open/merge a PR, tag, or publish without a separate maintainer request. Local implementation and verification should proceed without repeated approval questions.

## Released dependency facts: use these exact identities

| Item | Required value |
| --- | --- |
| Repository | `https://github.com/ChrisLloydME/TagLibAudioMetadata.git` |
| Dependency requirement | Exact version `0.7.0` |
| Resolved source revision | `0f89fbe83c8fb029a9b6d640d57e397686986930` |
| Mapping contract | `AM-TLAM-MAPPING-2.2` |
| Swift tools required by dependency | 6.4; use the stable installed Xcode toolchain |
| Product | `TagLibAudioMetadata`; preserve the existing product boundary |
| Native binary | Existing checksum-pinned TagLib 2.3.1 revision 2; unchanged by 0.7.0 |

Release: <https://github.com/ChrisLloydME/TagLibAudioMetadata/releases/tag/0.7.0>.

Read these published references when checking API signatures and native behavior:

- <https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/0.7.0/docs/operations/MIGRATION.md>
- <https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/0.7.0/docs/reference/API.md>
- <https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/0.7.0/docs/reference/MODELS.md>
- <https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/0.7.0/docs/reference/FIELDS.md>
- <https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/0.7.0/docs/reference/MAPPING_MATRIX.md>
- <https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/0.7.0/docs/reference/MAPPING_SPEC.md>

Do not assume the local target specification is an identical copy of the released package documentation. Its native matrix is design context; its application integration requirements remain relevant. Do not change the shared normative contract, increment its ID, or claim cross-repository synchronization. Record discrepancies in the application implementation ledger. The published 0.7.0 API defines what can actually be called. If a required operation is genuinely unavailable, fail safely and report a minimal package issue rather than silently redefining the requirement or implementing a native codec in the app.

## Non-negotiable behavior

### Independent dates

| App semantic identity | Package typed field | Intent |
| --- | --- | --- |
| `year` | `.year` | YEAR, complete stored text |
| `date` | `.standaloneDate` | Independent DATE |
| `releaseDate` | `.releaseDate` | Independent RELEASEDATE |
| `originalReleaseDate` | `.originalReleaseDate` | Independent ORIGINALDATE |

The package's legacy `.date` case is an alias of YEAR. It is **not** the new app Date field. New semantic application writes must use `.year` for Year. Never submit both `.date` and `.year` in a patch. Do not globally replace raw keys or raw editor entries: a TagLib PropertyMap key named `DATE` can still project the native YEAR slot.

All four fields need separate values, edit intents, dirty tracking, merged-selection state, capabilities, preview rows, and clear actions. Different years are valid. Required example: YEAR=`2004`, DATE=`2008-03-04`, RELEASEDATE=`2017-06-09`, ORIGINALDATE=`1999-11-12`.

No inference, synchronization, year-component editing, cross-date equality validation, automatic completion, or cross-field clearing is permitted. Retain complete YEAR text such as `2004-07-15`; do not read or write only its first four characters. Retain supported precision/timezone text without inventing January 1 or midnight. Validate only the explicitly edited field against its own shape and destination support. Preserve unedited malformed or multi-valued native data.

On MP4, `©day` is YEAR. Independent DATE and RELEASEDATE are separate freeforms. Do not copy an old `©day` into RELEASEDATE, infer historical provenance, or migrate files during import/reload/scan. Providers supply RELEASEDATE only; they must not set YEAR, DATE, or ORIGINALDATE unless those are independently supplied and explicitly selected. A derived year used solely for search/display ranking must never become a stored Year value or edit intent.

### Native numbering and private provenance

Track Number, Total Tracks, Disc Number, and Total Discs remain distinct user intents. Internally, track and disc each share a native pair on ID3/MP4. Changing one component preserves the untouched component; untouched disc data must not block a track-only edit or be cleaned as a side effect.

Use the package's numbering inventory and its `absent`, `native`, `recoveredLegacy`, `ambiguous`, and `invalid` states. Do not hide unresolved state behind a default integer zero. A sole valid historical total may be recovered; conflicting or malformed candidates require explicit resolution. Preserve exact native/alias/private identities and source values for preview.

The private descriptions `AUDIOMATOR_TRACKNUMBER_TEXT`, `AUDIOMATOR_DISCNUMBER_TEXT`, `TAGLIBAUDIOMETADATA_TRACKNUMBER_TEXT`, and `TAGLIBAUDIOMETADATA_DISCNUMBER_TEXT` are legacy provenance. Do not create, rename, or automatically remove them. They remain visible in low-level inspection and survive unrelated edits. Ordinary Xiph/APE total keys are legitimate native storage, not private garbage.

A user-requested cleanup must use the released `numberingInventory(at:)`, `planNumberNormalization(at:policy:groups:)`, and `applyNumberNormalization(_:to:expectedVersion:)` APIs through the application pipeline. Confirm their exact public signatures first. The preview must show source values/identities, selected group, native destination, resolved values, removals, and warnings. Execute the **same captured plan**. Never regenerate the plan during Apply, replace its captured version, widen its groups, or resolve ambiguity by picking the first candidate. A changed file invalidates the plan and requires a fresh preview.

Support `.useNative`, `.useLegacy`, and explicit `.replace(number:total:)` as deliberate choices, with visible data-loss implications where a choice discards candidates. Use a focused action in the existing inspection/editing flow, not a background migration. Run cleanup as a separate explicit operation; do not perform cleanup and a draft save as two commits presented as one atomic save. Require outstanding drafts to be saved or discarded through existing behavior before cleanup. Refresh the model after a successful cleanup.

MP4 pair components are bounded by 65535. Total-only storage is supported on MP4 and ID3-backed formats and separate-key Xiph/APE layouts; ASF total-only remains unsupported. Let package validation reject unsupported layouts before mutation. Text padding normalization is a warning when numeric intent persists, not a failed save. Do not restore exact MP4 padding with new private atoms.

### Advisory and container-exclusive fields

Advisory semantics are: absent/unset, `0` = Not Explicit, `1` = Explicit, `2` = Clean. Zero is present. Preserve unknown existing native codes as unknown, with their original value/provenance. An unrelated save must not turn an unknown code into absence, false, Clean, or zero. Mixed selection is separate from absent and unknown. Never use the Boolean projection as the authoritative edit model.

Use the package registry to expose supported semantic fields and their shapes. Do not duplicate the native mapping table in AudioMator. Expose independent `contentGroup`, `grouping`, and `work` semantics. Cover the full registered MP4-exclusive set through appropriate semantic field editing and preview; not every field needs a permanent Inspector row. Store IDs remain exact identifiers, TV numbers remain numeric, and present-false values remain present.

MP4 `RATE` is read-only: `writeSupport(for: .rate)` returns `.unsupported`. Preserve and display existing data, disable typed editing with a reason, and never invent a scale. Media-kind codes round-trip as integers, including unknown codes; do not invent a label-to-code vocabulary. The two Matroska TV registrations are gated and unsupported; they do not authorize adding MKV file support. MP4-exclusive Basic properties are readable but Basic replacement does not write them; use supported typed patches/structured operations through Infrastructure, never a legacy Basic fallback.

### Architecture and safety

All semantic entry points must converge on one application intent/planning policy: Inspector, single/multi editor, CSV/text, filename extraction, field transfer, renumbering, MusicBrainz, and iTunes. Raw editing remains an explicit low-level exception with its own raw delta and exact baseline; do not route unsupported semantic writes through it.

Keep `AudioViewModel` as selection owner. Keep models/intent/conflicts under Domain, package calls under Infrastructure, and UI/state under Features. Honor the existing Domain exception in `AGENTS.md`; do not spread manager calls into Domain or views. Pass package-specific normalization plans behind the pipeline/Infrastructure boundary rather than creating a new dependency exception.

All disk mutations must remain under `FileMutationCoordinator` and existing directory/security-scope handling. Retain exact expected file versions, audio-content guards where available, same-entry checks, and final version checks. Never clear a version token, retry a failed commit, substitute a similar-looking file, or write after cancellation before commit. Cancellation after commit begins must account for the real outcome. Preserve committed-but-durability-uncertain and refresh-failed outcomes.

Per-file semantic operations are all-or-nothing: one unsupported requested field must reject the file's operation without writing its supported subset. Existing batch summaries can still report different outcomes for different files. No silent field dropping. Every requested removal needs the same preflight as a set. Capability checks remain advisory until concrete-file validation runs.

## Starting map: inspect these files before edits

| Area | Starting points |
| --- | --- |
| Contract | `Docs/Architecture/METADATA_MAPPING_SPEC.md`, ADR `0005-metadata-mapping-compatibility-contract.md`, `METADATA_PIPELINE.md`, `STATE_AND_MUTATION_MODEL.md`, `FILE_REVISION_AND_RELOAD.md` |
| Dependency/legal | `AudioMator.xcodeproj/project.pbxproj`, workspace `Package.resolved`, `Core/Legal/LicenseDisclosure.swift`, `Resources/Licenses`, notices/privacy docs, `AGENTS.md` dependency notes |
| Models | `Domain/AudioFiles/AudioFile.swift`, `MergedAudioFile.swift`, `SingleFileEditModel.swift`, `SingleFileEditModel+MetadataPipeline.swift` |
| Pipeline/conflicts | `Domain/MetadataEditing/AudioMetadataPipeline.swift`, `MetadataConflictBaseline.swift`, `Infrastructure/TagLib/TagLibAudioMetadataPipeline.swift`, `MetadataConflictResolver.swift` |
| Editing UI | `Features/Main/State/InspectorMetadataField.swift`, `Features/Main/Views/InspectorPane.swift`, `Features/Main/ViewModels/AudioViewModel+MetadataWriteSupport.swift`, `Features/MetadataEditor`, `Features/MetadataInspector` |
| Orchestration | `AudioViewModel+MetadataWrite.swift`, `+MetadataPlanWrite.swift`, `+MetadataFieldImportWrite.swift`, `+ProviderTaggingWrite.swift`, `+RawMetadataWrite.swift`, `Features/Main/Application/MetadataFileMutationExecutor.swift` |
| Exchange/rename | `Domain/MetadataExchange/*`, `Domain/Rename/*`, `Domain/TrackRenumber/*`, `Features/MetadataFilenameTool/*` |
| Providers | `Infrastructure/iTunes/iTunesProviderCore.swift`, `Infrastructure/MusicBrainz/MusicBrainzProviderCore.swift`, `Infrastructure/OnlineMetadata/OnlineMetadataSelectionCore.swift`, provider comparison builders and plan builders |
| Tests | `AudioMatorTests/Application/MetadataEditing`, `Application/MetadataExchange`, `Application/Rename`, `Integration/TagLib`, `Unit/Presentation`, `Tests/AudioMatorCoreLogicTests` |

Some filenames above are relative to `AudioMator/`; verify current paths with repository search. This is a navigation map, not permission to omit other call sites. Search for `.date`, `year`, `prefix(4)`, date formatters, `releaseDate`, `ContentAdvisory`, `numberText`, private descriptions, capability checks, and schema/profile headers. Classify matches by meaning before changing them.

## Execution phases: implement in this order

### Phase 0 — Baseline and work ledger

1. Read project instructions and relevant documentation, inspect Git status and preserve current work. If creating a branch, use `codex/audiomator-mapping-070` from the current intended base; do not reset or move someone else's branch/worktree.
2. Record current pin, build settings, dirty changes, and a baseline build/test result using the available tools. Record pre-existing failures as failures, not passes. Do not assume historical test counts are current.
3. Create `Docs/Engineering/AUDIOMATOR_MAPPING_070_IMPLEMENTATION.md` as a dated implementation ledger: requirement ID, affected routes, implementation status, tests/evidence, and remaining limitations. Add a row for each acceptance criterion below. An untested row is not complete.
4. Inventory semantic vs raw routes, all Year/date projections, provider writes, CSV profiles, number handling, raw/private fields, snapshots, reloads, and conflict comparisons. Record every route before refactoring it.

Gate: ledger and baseline exist; no unresolved uncertainty about which routes must migrate. Continue implementation rather than returning only this inventory.

### Phase 1 — Adopt the release

1. Change the Xcode remote package requirement to exact `0.7.0`. Resolve with Xcode's package tools/build integration, not by manually fabricating the resolved file's hashes. Verify version and source revision match the table above.
2. Update dependency disclosures and current dependency instructions consistently. Keep TagLib binary/license identities unchanged unless the released dependency proves otherwise. Do not remove attribution or rewrite license texts just to update a version number.
3. Inspect the released public interfaces. Record how the app obtains independent date values and original values from full snapshots, including native provenance when Basic projections are insufficient. Do not guess property names or read dates by splitting a flattened string.
4. Build the app target, fix compilation at the adapter/model boundaries, and add a dependency contract regression for exact pin/disclosure and mapping capabilities.

Gate: the app compiles against the released package; no local path dependency, cache patch, or old pin remains in current executable configuration.

### Phase 2 — Application semantic model and shared planning

1. Add independent Date and Original Release Date across file models, edit models, merged models, initializers/copy helpers, equality/hashing, baselines, selection refresh, dirty fields, payloads, and patch generation. Keep YEAR's full text.
2. Replace semantic Year `.date` uses with `.year`. Map app Date to `.standaloneDate`. Preserve intentional raw PropertyMap DATE behavior and label its dialect explicitly.
3. Represent unchanged/set/remove independently of display defaults and mixed values. Retain the complete snapshot/provenance baseline; do not replay a flattened projection during an unrelated save.
4. Centralize canonical identity, value shape, and per-destination support handling. Use registry declarations, not a second native table. Prepare a single intent plan that previews and executes the same requested fields/values under the same baseline.
5. Load numbering inventory and advisory provenance without manufacturing resolved values. Preserve ambiguous states through drafts/previews. Extend existing pipeline fakes and test builders together with production interfaces.

Gate: unit/contract tests prove four independent date intents, unknown advisory preservation, number component preservation, and no mutation for an empty intent.

### Phase 3 — Inspector, semantic editor, and capability UI

1. Add separate Inspector Date and Original Release Date controls and independent clear actions. Keep Year editable on MP4 under its correct mapping. Preserve the normal single/multi-selection behavior.
2. Provide semantic editors for the registry fields needed by this contract, including MP4 exclusives. Keep the existing raw editor identifiable as raw. Do not relabel raw `DATE` as standalone Date or pretend raw scalar editing is semantic conformance.
3. Derive text/integer/Boolean/advisory/identifier editors from field shape. Preserve present zero and false. Show read-only/unsupported reasons before Save. For mixed formats, preview support per file and do not write a subset of requested fields within any file.
4. Add explicit numbering recovery/cleanup preview and Apply through the existing mutation/pipeline architecture. Keep opaque package plan ownership in Infrastructure. Handle stale plans by invalidating preview and requiring rebuild, without retrying writes.
5. Localize user-facing strings using the repository convention and update string catalogs. Do not show native implementation details in routine flows; show exact native identities where a recovery/raw preview needs them.

Gate: model/view-model/presentation tests cover distinct date controls/state, mixed vs absent vs unknown, unsupported disabled state, explicit clears, and scoped cleanup. Interactive UI verification remains with the maintainer.

### Phase 4 — Providers, exchange, filename, transfer, and renumber

1. Migrate provider plan generation, comparisons, selection defaults, overwrite policy, and execution together. Provider RELEASEDATE edits never set/remove Year or Date. Keep existing no-live-network testing and cancellation semantics.
2. Introduce an explicit versioned AudioMator exchange profile carrying YEAR, DATE, RELEASEDATE, ORIGINALDATE as independent columns. Version both export and import parsing; account for the existing CSV delimiter/header parser rather than inserting an unparseable metadata line.
3. Keep an explicit legacy reader for existing unversioned AudioMator files. Omitted column = unchanged. Define and test explicit removal syntax separately from omitted/empty/mixed state. Old header identities and values must not be silently reinterpreted under the new mapping. When provenance is insufficient, require an explicit profile/remap preview before mutation; no guessing from date prefixes. Reject unknown profile versions before writes.
4. Round-trip unknown advisory codes in export/import without presenting them as one of the four known states. Preserve identifier text and repeated values where the selected profile supports them; preview/reject unrepresentable loss. Do not flatten arrays silently.
5. Add separate filename/template tokens and field-transfer identities for the four dates. Existing year token means stored YEAR. Date formatting or extraction only edits the explicitly targeted field, with precision/loss shown in preview. Preserve old template interpretation through explicit compatibility handling.
6. Renumbering changes only requested number components, retains totals and untouched group provenance, handles ambiguity visibly, and never performs private cleanup implicitly.

Gate: tests execute previews and actual saves for every route, not only parser assertions. Full canonical identity survives preview → payload → package patch → reload.

### Phase 5 — Conflict, reload, and preservation audit

1. Update snapshot comparison to compare actual touched native storage. Four independent date fields must not be one blanket conflict group. Track and its total share one physical pair; disc has its own group. Raw aliases and private provenance still matter when the chosen operation touches them.
2. Metadata-only rebase remains possible only under existing verified file/audio identity rules. Unsupported audio identity requires explicit reload. Do not add retries or relax same-inode replacement detection.
3. Invalidate old drafts and preview plans whose mapping/profile identity or baseline no longer applies. Preserve dirty intent for explicit rebuild/review rather than silently replaying against different native slots.
4. Verify reload, batch summaries, no-op, cancellation, post-commit refresh failure, and uncertain durability still describe the actual outcome. Confirm untouched dates, totals, aliases, custom metadata, artwork, comments/lyrics, and unknown values survive.

Gate: existing conflict/replacement/cancellation regressions pass, plus new native-field independence and stale normalization-plan cases.

### Phase 6 — Documentation, final verification, and handoff

Update current guidance using `Docs/Development/DOCUMENTATION.md`: pipeline, exchange, rename/renumber, providers, dependency limitations, configuration/build, testing, disclosures, and user-facing guidance where behavior changed. Update app implementation status separately from the shared native contract; do not claim every format is fixture-verified. Link the implementation ledger from `Docs/README.md`.

Review the complete diff for accidental native mapping duplication, private atom creation, Boolean advisory flattening, semantic `.date` uses, cross-date inference, silent unsupported-field filtering, and bypasses of mutation/version guards. Search results are audit aids, not substitutes for runtime tests.

Do not stop with a red app-hosted suite just because SwiftPM core tests passed. A package defect cannot be repaired in this repository: report the API, observed/expected behavior, minimal AudioMator reproduction, unchanged-file evidence, and the test/fix the package owner needs. Continue all independent work, but mark affected acceptance rows blocked rather than complete.

## Required acceptance tests

Use temporary fixture copies only. Test the real adapter through app payloads and reload models; use structured/native snapshot values as the oracle so two identically wrong app projections cannot make a round-trip test pass. For pre-mutation rejection, compare file bytes and relevant identity/version. Test fixtures must actually contain the independent or conflicting values under test.

| ID | Required proof |
| --- | --- |
| A01 | Exact 0.7.0 pin, expected revision and disclosure consistency; declared contract/capability matches the release; no path override. |
| A02 | On the six committed formats (MP3, M4A, FLAC, Ogg, AAC and WAV), seed distinct date values in each supported native layout. Include an ID3v2.4 case supporting the complete example and ID3v2.3-specific Date shape/rejection cases; do not assume the same Date syntax works in both versions. Setting and clearing each supported field changes only that field. YEAR and RELEASEDATE remaining different is accepted. For version-specific unsupported precision, assert rejection and unchanged bytes rather than coercion. |
| A03 | Full YEAR text such as `2004-07-15` survives read, selection/model copy, unrelated edit, export and reload without four-character truncation. No-op preserves the file. |
| A04 | Inspector and multi-edit track unchanged/set/remove/mixed separately for all four dates. MP4 Year is editable; a failed mixed-format request writes no supported subset within a rejected file. |
| A05 | MusicBrainz and iTunes application change only selected RELEASEDATE and other explicitly selected fields, leaving YEAR/DATE/ORIGINALDATE intact. Verify through execution and reload using mocked provider data. |
| A06 | Versioned CSV/text round-trip four dates and distinct advisory states; omitted vs remove differs; legacy profile/remap behavior is explicit; unknown profile rejects; preview matches save. Filename extraction and field transfer alter only their chosen date identity. |
| A07 | Number-only edits retain totals, total-only edits retain numbers, removing a number retains supported total-only representation, disc-only/track-only edits preserve the other group. Exercise all six committed audio formats where supported; unsupported layouts reject unchanged. |
| A08 | Native vs legacy total conflicts are surfaced; an ambiguous disc does not block unrelated track/title edits. Both private prefixes, private-only `03/12`, total-only `/12`, duplicate/malformed candidates, ordinary Xiph/APE totals, and foreign-namespace lookalikes are handled without guessing or broad removal. Where the app lacks a committed format fixture, report that coverage gap rather than claim it passed. |
| A09 | Cleanup preview/apply uses the same captured plan; track cleanup preserves disc aliases/private data; explicit disc replacement affects disc; stale plan rejects even if a newer expected token is available; unrelated save/import/scan does not create, rename, or retire private fields. |
| A10 | Advisory absent/0/1/2 are distinct; existing unknown code (for example MP4 4) survives unrelated save and export. Mixed and unknown never silently become unset/Clean. Explicit replacement/removal works. |
| A11 | MP4 exclusive editing uses correct typed shapes and capabilities. Exercise representative integer ID, integer TV value including zero, Boolean false, text and unknown media-kind code through the app. Assert every registered exclusive field has a deliberate UI/capability classification. RATE stays readable/read-only and MKV is not advertised writable. |
| A12 | `contentGroup`, `grouping`, and `work` remain independent where supported. Raw DATE retains its PropertyMap meaning; standalone semantic Date uses its own field. Unknown/custom arrays, native comment/lyrics identity, and artwork survive unrelated semantic edits. |
| A13 | Existing stale-version, same-inode replacement, audio-identity, cancellation, refresh-required, and uncertain-durability behavior remains correct. Independent date changes do not create blanket conflicts; shared native number pair conflicts remain protected. |
| A14 | App Debug/Release builds, Foundation-only tests, relevant focused app-hosted tests, and full serial app-hosted suite pass. No newly skipped/expected-failing tests or weakened assertions conceal mapping regressions. Documentation describes implemented behavior and precise remaining coverage gaps. |

Add app regressions near existing `TagLibReadWriteIntegrationTests`, `TagLibUpgradeContractTests`, `NumberTextDependencyContractTests`, pipeline/Inspector/editor workflow tests, provider execution/cancellation tests, exchange/field-transfer/filename/renumber tests, and conflict strategy/revision/replacement tests. Extend existing test builders deliberately; do not merely change expected strings until tests turn green. Update obsolete 0.6.0 assertions only alongside a test proving the new native contract; historical records remain historical.

## Build and test procedure inside Xcode Code Intelligence

Use available Xcode-internal tools to inspect diagnostics, build the selected AudioMator scheme, run focused tests, and run the serial suite. Discover the actual available ACP tools; do not invent tool names. Check the full result, failure details, test target, configuration, and actual test counts. A tool saying the request was accepted is not evidence of a completed successful build/test. Ensure final app-hosted tests run serially; use the shell fallback if internal tooling cannot establish that.

The CLI fallback, when shell tools are available, is:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --filter AudioMatorCoreLogicTests
bash scripts/codex-build.sh
xcodebuild \
  -project AudioMator.xcodeproj \
  -scheme AudioMator \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  test
xcodebuild \
  -project AudioMator.xcodeproj \
  -scheme AudioMator \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  build
```

Use `.deriveddata-codex` for any agent-controlled Xcode build path; do not create alternate roots or change the user's global Xcode settings. Follow repository signing guidance; if signing alone blocks a local unsigned build, use the documented signing override and state it in evidence. Cache permission failures are environment failures; obtain the tool's appropriate access rather than diagnosing them as code defects. If no tool can run a required check, mark it not run and explain the exact missing capability.

The SwiftPM target compiles a selected Foundation-only subset. It must not acquire TagLib/AppKit/SwiftUI dependencies just to host these tests. App-hosted integration tests remain in `AudioMatorTests`. Never run `scripts/build-taglib-bridge-smoke.sh`; it crosses the package boundary. Do not manually launch `AudioMator.app`, use UI automation, AppleScript, accessibility tooling, or screenshots for interactive testing. Automated app-hosted test execution is allowed; interactive acceptance belongs to the maintainer.

## Final report format

Provide a concise summary, followed by:

1. Dependency version/revision and Git branch/worktree status.
2. Acceptance table A01–A14 with pass/fail/blocked/not-run, test names, and result artifacts or reproducible commands. Separate code completion from empirical coverage.
3. Actual Debug/Release build and test results, counts/skips/failures, toolchain, serial setting, and any environment overrides. Do not reuse historical results as current evidence.
4. Migration behavior for dates, legacy CSV/templates, numbering/private cleanup, advisory unknown values, and MP4 capabilities.
5. Remaining package limitations and maintainer UI checks, without claiming release readiness or cross-repository conformance.

You are done only when all implementation requirements are satisfied and required checks pass, or a concrete external blocker is documented. A partially wired editor, a dependency bump alone, a green core-only suite, or a TODO list is not completion.
