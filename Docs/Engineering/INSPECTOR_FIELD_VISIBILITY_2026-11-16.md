# Inspector common-field visibility restoration — 2026-11-16

## Product contract and implementation

The right Inspector is a curated common-metadata editor. Settings → Interface → Inspector Metadata Fields controls all single/multi-selection metadata rows. The former unconditional MP4 Container Fields sections and their bindings/support-only helper are removed. Advanced PropertyMap edits remain in Metadata Editor; Tag Inspector remains the native inspection surface.

`configurableFields` explicitly defines the 22 optional Inspector rows; `defaultVisibleFields` explicitly restores the pre-mapping 17-field common set. Date, Original Release Date, Content Group, Grouping and Work remain independently selectable but are not new-install defaults. Year and all date identities retain their independent mappings. Existing nonempty preferences, including optional fields already enabled, are preserved. Empty or unrecognized-only preferences recover to common defaults; the existing at-least-one-row policy remains.

Both selection modes render `SharedState.orderedVisibleInspectorMetadataFields`. Settings uses the same curated catalog. Capabilities only disable unsupported edits. Visibility never clears metadata or drafts; Save includes pending edits entered before hiding their rows. No write pipeline, package, dependency, raw mapping or conflict policy is changed.

## Regression evidence

Five configuration tests cover defaults, optional independent dates, exact persisted choices, old/empty preferences, single/multi draft preservation and the absence of an uncontrolled Inspector render route. A real-file save journey checks both single and batch hidden drafts and preservation of untouched common/date/store fields. The visibility/route/persistence and real-save contracts are mandatory critical gate identities.

Focused configuration/dirty-state/Inspector-editor tests passed. The final six configuration/save tests and 13 Python gate policies passed. Complete release acceptance is recorded below after execution. No interactive app launch or UI automation is performed; visual acceptance remains manual.

## Final verification

Tested implementation: `86e156fb` on `codex/restore-inspector-field-design`. Evidence: `.deriveddata-codex/Validation/20261116-165959-40611/`.

- 13 Python policies passed.
- 62/62 core tests passed with accepted named evidence.
- 586/586 serial app-hosted tests passed with accepted exact source inventory; no missing/unexpected tests, failures, skips or expected failures.
- New preference/visibility tests, Inspector dirty-state/editor workflows and real single/batch hidden-field save journeys passed.
- The already-running unsigned Release build and artifact checks completed successfully before the user's instruction to skip Release was processed. No additional Release build or archive is requested or run after that instruction.

The working package dependency is unchanged. No interactive UI launch or visual acceptance is claimed. This final update records evidence only; implementation and test source remain unchanged after the tested commit.
