# Metadata Field Guide

Choose **Help → Metadata Field Guide** to open the bundled, reusable reference window. The guide is available without opening a file or connecting to a service. It covers all 100 `TagLibAudioMetadata` package metadata fields plus Credits and five technical display values (Duration, Bitrate, Sample Rate, Channels, Format).

Search in the sidebar by a field name, a word in its explanation or editing guidance, or a storage name such as `©day` or `TDRL`. Choose a result to read what the field is for. Date and time entries also show selectable examples, format notes, and AudioMator editing details before the storage table. **Where This Field Is Stored** shows a padded, two-column table of tag formats, storage locations, and editing requirements for package metadata fields. **Learn More** opens fixed official references in the default browser when selected.

The guide uses system appearance, a standard resizable window, a searchable list, split-view selection and native GroupBox/Grid controls. It uses system text styles, accessible section headings, selectable text and examples, and descriptive link labels. Technical mappings follow the explanation and remain visible without a disclosure control. It is a reference, not another editor: it does not select music files, create drafts or change metadata. Inspector visibility remains controlled by Settings → Interface.

## Meaning and mapping

Explanations are editorial paraphrases of ID3.org, Xiph.Org (including XiphWiki), Apple Developer, Microsoft Learn, TagLib, MusicBrainz/Picard, AcoustID, and RFC Editor (RFC 3339) references. The [complete developer table](../Reference/METADATA_FIELD_MAPPING_TABLE.md) includes purposes, sources and cross-layer identities. Other editors and standards may use different names. AudioMator-specific date separation, grouping ownership and advisory choices are explicitly distinguished from the references.

Descriptions and field guidance are bundled in `MetadataFieldGuide`; mappings are read from the installed package registry, not duplicated in the help content or downloaded from the web. A registered location does not guarantee every operation on every file. Read-only locations, unavailable role codecs and planned Matroska targets are labeled accordingly. Opaque playback values are described for recognition, not as instructions to manufacture an encoding.

The reference layout follows Apple's [Offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help), [Writing](https://developer.apple.com/design/human-interface-guidelines/writing) and [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) guidance: task-related help, a standard independent window, plain-language explanations with the field's meaning first, selectable examples, and optional reference links. Visual and keyboard interaction acceptance remain maintainer work; no interactive launch is implied by automated verification.

## iTunes Genre ID lookup

Select **iTunes Genre ID** in the sidebar to see the **iTunes Store Genre IDs** section above **Where This Field Is Stored**. The section explains the numeric Store identifier and its separate text **Genre** field. Use the storage table to check what your tag format accepts if you already have an ID to enter in Metadata Editor.

**Known limitation:** Standard builds omit the optional catalog resource, so this section displays **Genre Catalog Unavailable**. The field explanation, storage table, and official reference remain available.

When a build includes a valid catalog resource, the section shows a grouped list of media types with entry counts. Selecting a media type pushes a two-column list of genre names and IDs into the same detail pane. **Search by genre or ID** filters that media type by exact numeric ID or by words in the name or parent categories. The ID text is selectable for copying. Back returns to the field page, and changing the selected sidebar field clears the media navigation path.

The guide uses native SwiftUI search placement for the field sidebar and the media detail toolbar. It requests soft vertical scroll edge effects on macOS 26 and later. [Apple HIG search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields) · [Apple HIG scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views)

## What you can save

Each supported tag format shows what to enter below the stored field name. Look here for whole-number limits, date tags that are read-only, fields that include a role, and differences such as WMA requiring a track or disc number when you set a total. The guide also explains which tracker modules can save a tracker name. In Metadata Editor, use the stored value and choose **Delete Field** to remove the field.

The guide uses the package’s field types and common ranges. Guidance about individual formats follows the [package’s write validation reference](https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/bc87ad0/docs/reference/WRITE_VALIDATION.md) and AudioMator’s editing behavior. Search includes the editing notes.

## Date and time entries

Five entries — **Year**, **Date**, **Release Date**, **Original Release Date**, and **iTunes Purchase Date** — add **Format and Examples** and **Editing in AudioMator** sections before **Where This Field Is Stored**, while keeping `purpose` concise for Metadata Editor's Add Field suggestions.

Each entry keeps the decision order short and avoids repeating the storage table below:

- **What to enter:** selectable examples and a brief note distinguishing specification-defined syntax (such as ID3v2.4 UTC timestamps without `Z`, ID3v2.3 four-digit years and `DDMM` dates, and RIFF INFO `YYYY-MM-DD`) from practical recommendations where a container leaves syntax unspecified (such as Vorbis comments, MP4 `©day`, text tags using RFC 3339 UTC, and native MP4 `purd`, which is kept separate from text-tag `ITUNESPURCHASEDATE` conventions).
- **Where to edit and field-specific exceptions:** whether the field appears in the Inspector (default, optional in Settings → Interface, or Metadata Editor only for **iTunes Purchase Date**), independence across date fields, and key picker exceptions (such as ID3v2.3, WAV needing a known ID3v2.4 tag, raw `YEAR`/`DATE`/`STANDALONEDATE`/`RELEASETIME`/`ORIGINAL YEAR` differences, mixed-family selections, and no picker for MP4/M4A native `purd`).
- **Shared editing behavior:** a compact note on direct text entry (no format checks, missing-component completion, or time-zone conversion, subject to tag support) and picker behavior (**Year**, **Year & Month**, **Full Date** with optional **Add Time** and **Time Zone**, pure calendar dates vs. UTC in **Tag Value Preview**, and **Apply** staging into the draft until saved).

For the full date and time workflow and per-format eligibility matrix, see [Date and time editing](USER_GUIDE.md#date-and-time-editing) in the User Guide.

## Shared field names in Metadata Editor

The guide and Metadata Editor use the same AudioMator labels. The Add Field list shows the label first, then its purpose, without a Native or PropertyMap key. Choosing a suggestion displays its friendly name while retaining its mapping identity separately. The Field table column and Edit Field sheet use friendly names; hovering a table field reveals its exact raw key. Custom names are preserved, and role/language/description suffixes remain distinguishable.

Existing raw keys and exact value arrays remain separate draft identities, even when two keys share a label. Editing a raw row uses its original key. The editor displays raw `DATE` as **Year** for ID3, MP4 and ASF, as **Date** for Vorbis Comment and APEv2, and as **Year / Date** for mixed owners. For ID3v2.4, raw `DATE` stays text-only. The named **Date** suggestion writes raw `DATE` for verified Vorbis Comment and WavPack targets. Elsewhere it creates the text-only raw `STANDALONEDATE` key, which is separate from the Inspector's semantic **Date** slot. Raw `RELEASETIME` is displayed as **Release Date** and keeps its original key.

## Settings and Inspector labels

Settings → Interface, single/batch Inspector rows, batch edit labels, technical information and list column labels use the same AudioMator name source as the guide and Metadata Editor. Track and Disc list headers say Track Number and Disc Number; their existing number/total display is unchanged. Stored preference identifiers, curated defaults, selection, order, visibility and native write targets are not changed by the display naming.

The field list's preferred width is measured from the longest localized field name at the system body font size, including space for insets and a scrollbar. The list can be resized, and labels wrap when narrowed. The reference window opens wider to retain useful detail space alongside the list.

The detail pane contains the field name and purpose, format examples and AudioMator editing details for the five date and time fields, genre ID guidance for **iTunes Genre ID**, the storage and editing table for package metadata fields, and official reference links.
