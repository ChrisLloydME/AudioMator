# Metadata Field Guide

Choose **Help → Metadata Field Guide** to open the bundled, reusable reference window. The guide is available without opening a file or connecting to a service. It covers all 100 `TagLibAudioMetadata` package metadata fields plus Credits and five technical display values (Duration, Bitrate, Sample Rate, Channels, Format).

Search by a field name, a word in its explanation, or a storage name such as `©day` or `TDRL`. Choose a result to read what the field is for. **Where This Field Is Stored** shows a padded, two-column table of tag formats, storage locations and availability for package metadata fields; the app-only Credits and technical entries have no storage table. **Learn More** opens a fixed primary reference in the default browser only when selected.

The guide uses system appearance, a standard resizable window, a searchable list, split-view selection and native GroupBox/Grid table controls. It uses system text styles, selectable text and descriptive link labels. Technical mappings follow the explanation and remain visible without a disclosure control. It is a reference, not another editor: it does not select music files, create drafts or change metadata. Inspector visibility remains controlled by Settings → Interface.

## Meaning and mapping

Explanations are editorial paraphrases of ID3.org, Xiph.Org, Apple Developer, TagLib, MusicBrainz/Picard and AcoustID references. The [complete developer table](../Reference/METADATA_FIELD_MAPPING_TABLE.md) includes purposes, sources and cross-layer identities. Other editors and standards may use different names. AudioMator-specific date separation, grouping ownership and advisory choices are explicitly distinguished from the references.

Descriptions are bundled in `MetadataFieldGuide`; mappings are read from the installed package registry, not duplicated in the help content or downloaded from the web. A registered location does not guarantee every operation on every file. Read-only locations, unavailable role codecs and planned Matroska targets are labeled accordingly. Opaque playback values are described for recognition, not as instructions to manufacture an encoding.

The reference layout follows Apple's [Offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help) and [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) guidance: task-related help, a standard independent window, readable explanations and optional detail. Visual and keyboard interaction acceptance remain maintainer work; no interactive launch is implied by automated verification.

## Shared field names in Metadata Editor

The guide and Metadata Editor use the same AudioMator labels. The Add Field list shows the label first, then its purpose, without a Native or PropertyMap key. Choosing a suggestion displays its friendly name while retaining its mapping identity separately. The Field table column and Edit Field sheet use friendly names; hovering a table field reveals its exact raw key. Custom names are preserved, and role/language/description suffixes remain distinguishable.

This is presentation, not whole-file canonicalisation. Existing raw keys and exact value arrays remain separate draft identities, even when two keys share a label. Explicit uppercase raw input remains raw; a friendly `Date` selection resolves to `STANDALONEDATE`, whereas existing raw `DATE` is not silently rewritten as `YEAR`. A DATE row is named according to the supported tag-family dialect (Year for ID3/MP4 engine DATE, Date for Xiph/APE literal DATE); a mixed-family row uses Year / Date rather than implying one meaning for all targets. Editing still uses the original raw key. The RELEASETIME display alias is shown as Release Date without renaming its stored key.

## Settings and Inspector labels

Settings → Interface, single/batch Inspector rows, batch edit labels, technical information and list column labels use the same AudioMator name source as the guide and Metadata Editor. Track and Disc list headers say Track Number and Disc Number; their existing number/total display is unchanged. Stored preference identifiers, curated defaults, selection, order, visibility and native write targets are not changed by the display naming.

The field list's preferred width is measured from the longest localized field name at the system body font size, including space for insets and a scrollbar. The list can be resized, and labels wrap when narrowed. The reference window opens wider to retain useful detail space alongside the list.

The detail pane contains the field name and purpose, its storage table (for package metadata fields), and official reference links. There is no separate "Using This Field" section.
