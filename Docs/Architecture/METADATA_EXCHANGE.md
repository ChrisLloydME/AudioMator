# Metadata Exchange

The Filename & Metadata tool converts between metadata and filenames, plain
text, CSV, and other metadata fields. This document describes its planning and
write model.

The feature is split by responsibility:

- `Domain/Rename/FileRenameTemplateCore.swift` — filename template parsing and
  base-name sanitization.
- `Domain/Rename/FilenameMetadataExtractionCore.swift` — filename-to-metadata
  matching.
- `Domain/MetadataExchange/MetadataExchangeTemplateSyntax.swift` — Foundation-only
  `{{placeholder}}` tokenizer.
- `Domain/MetadataExchange/MetadataExchangeTemplate.swift` — maps placeholders to
  typed fields, preserving unknown placeholders as literals.
- `Domain/MetadataExchange/MetadataExchangeModels.swift` — converter modes and
  field schema.
- `Domain/MetadataExchange/MetadataExchangeCSV.swift` — bounded CSV parsing,
  serialization, locator indexing, and export budgeting.
- `Domain/MetadataExchange/MetadataExchangePlanning.swift` — export/import plans,
  record matching, and validation.
- `Features/MetadataFilenameTool/` — the window, previews, template editors, and
  apply actions.

## Modes

| Mode | Result |
| --- | --- |
| Metadata to Filename | Rename plan; template output becomes the base name, extension preserved |
| Filename to Metadata | Write plan; template captures values from the filename stem |
| Metadata to Text | One rendered record per selected file/line |
| Text to Metadata | Parse one record per line and write matched fields |
| Metadata to CSV | Header plus one row per file |
| CSV to Metadata | Parse columns and write matched fields |
| Copy or Cut Metadata Fields | Per-file field-to-field transfer |

## Template Syntax

Templates are literal text with `{{field}}` placeholders.

- Unknown placeholders are preserved as literal text and reported separately.
- An unterminated `{{` is reported and preserved.
- Adjacent placeholders are permitted.
- Plain-text templates have no escaping syntax for separators or newlines.
- CSV is the recommended format when values can contain line breaks or the
  template's literal separators.

Filename templates support:
`title`, `artist`, `album`, `albumArtist`, `composer`, `genre`, `year`,
`trackNumber`, `discNumber`, `comment`, `releaseDate`, `publisher`, `copyright`,
`credits`, and `_ignore`.

## Planning

All modes produce a preview plan before writing:

- `MetadataTextExportPlan`,
- `MetadataCSVExportPlan`,
- `MetadataExchangeImportPlan` with preview rows,
- `FilenameMetadataPlan`,
- `FileRenamePlan`.

Preview rows classify each target as ready, unchanged, invalid/parse error,
ambiguous, unmatched, source unavailable, or duplicate. The plan carries each
target's expected file fingerprint and, where applicable, metadata version.

### Import matching

Imports with one or more locator columns match each record to selected files
using all supplied locators:

- File Name,
- Base Name,
- Path,
- Relative Path,
- Index.

Imports without a locator match records to selected files by selection order.
The following fail closed and are not written:

- ambiguous locator matches,
- duplicate records for one file,
- missing or extra records where a one-to-one mapping is required,
- invalid typed values,
- files changed since preview,
- unsupported destination fields.

Blank imported values are ignored unless the clear-empty-values option is
enabled.

### Number fields

Text/CSV pair imports treat `Track Number`/`Total Tracks` and
`Disc Number`/`Total Discs` as structured pairs. Field-transfer mode treats them
as independent fields.

An operation that would leave a total without a number is blocked because the
current package patch API cannot reliably round-trip that state.

## CSV Rules

Supported delimiters: comma, semicolon, pipe, and tab. The parser detects the
delimiter outside quotes.

- Quoted fields, doubled quotes, embedded delimiters, and embedded newlines are
  supported.
- An optional header row is supported.
- Unquoted imports are trimmed; quoted blanks are preserved.
- Export quotes only when required and uses CRLF line endings.
- Leading formula characters are neutralized reversibly on export to avoid
  spreadsheet execution.
- Imported text encodings: UTF-8, UTF-16, Windows-1252, and Mac Roman. Export is
  UTF-8.

Resource limits (`MetadataExchangeResourceLimits`):

| Limit | Value |
| --- | --- |
| Files/records | 100,000 |
| Source or generated document | 32 MiB UTF-8 |
| Plain-text record | 256 KiB UTF-8 |
| CSV field | 1 MiB UTF-8 |

The exporter also uses a byte budget that counts separators and fails closed
rather than producing a truncated document.

## Field Transfer

**Copy or Cut Metadata Fields** chooses one writable source field and one
writable destination field.

- Each file uses its own source value.
- Copy keeps the source; Cut clears it in the same write.
- Empty sources are skipped.
- Source and destination must differ and both must be writable.
- Destination values are validated before writing.
- The preview applies the same whitespace trimming as the writer, so a
  whitespace-only source cannot erase a destination.
- Invalid destinations and files whose revision cannot be verified are skipped.
- Total-without-number results are blocked.

## Applying a Plan

Apply paths construct a `SingleFileEditModel` per target, apply the planned
values, and call the shared `persistMetadataEdit` path. Therefore:

- format-capability preflight runs,
- conflict policy and expected versions apply,
- the file mutation reservation serializes with other operations,
- a post-write reload updates the snapshot,
- results are reported per file.

Writes are **not** a group transaction. A summary may contain successes and
failures.

## Extension Points

- Add a new converter mode in `MetadataConverterMode` and implement its plan type
  in the planner.
- Add a field in `MetadataExchangeField`, including display name, placeholder,
  value projection, and import validation.
- Reuse `MetadataExchangeTemplateSyntaxParser` for any new template surface.

## Known Gaps

- The full planner depends on app-only `AudioFile` models and is compiled only in
  the app-hosted test target. The SwiftPM fast target covers the syntax, CSV,
  locator index, and budget cores.
- Plain text intentionally has no escaping; it is not a lossless format for
  arbitrary values.
- Export/import handles metadata represented in the app's field schema; unknown
  raw PropertyMap keys are outside these modes.
- Positive tests for some container-specific number edge cases depend on
  temporary fixture copies and the external package.

## Related Documents

- [Rename and Renumbering](RENAME_AND_RENUMBERING.md)
- [Metadata Pipeline](METADATA_PIPELINE.md)
- [Testing](../Development/TESTING.md)
- [ADR 0004](Decisions/0004-metadata-exchange-responsibility-boundaries.md)
