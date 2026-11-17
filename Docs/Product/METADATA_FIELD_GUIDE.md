# Metadata Field Guide

Choose **Help → Metadata Field Guide** to open a separate, reusable reference window. The guide is available without opening a file or connecting to a service. It covers all 100 package metadata fields plus Credits and five technical display values.

Search by a field name, a word in its explanation or a storage name such as `©day` or `TDRL`. Choose a result to read what the field is for and where to find it in AudioMator. Expand **Where This Field Is Stored** for format-specific locations. **Learn More** opens a primary reference in the default browser only when selected.

The guide follows the system appearance and standard resizable window, searchable list, split-view selection and disclosure controls. It uses system text styles, selectable text and descriptive link labels. Technical mappings are secondary to the explanation. It is a reference, not another editor: it does not select music files, create drafts or change metadata. Inspector visibility remains controlled by Settings.

## Meaning and mapping

Explanations are editorial paraphrases of ID3.org, Xiph.Org, Apple Developer, TagLib, MusicBrainz/Picard and AcoustID references. The [complete developer table](../Reference/METADATA_FIELD_MAPPING_TABLE.md) includes purposes, sources and cross-layer identities. Other editors and standards may use different names. AudioMator-specific date separation, grouping ownership and advisory choices are explicitly distinguished from the references.

Descriptions are bundled in `MetadataFieldGuide`; mappings are read from the installed package registry, not duplicated in the help content or downloaded from the web. A registered location does not guarantee every operation on every file. Read-only dates, unavailable role codecs, ratings and planned Matroska targets are labeled accordingly. Opaque playback values are described for recognition, not as instructions to manufacture an encoding. There is no new metadata codec, mapping change or capability expansion.

The reference layout follows Apple's [Offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help) and [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) guidance: task-related help, a standard independent window, readable explanations and optional detail. Visual and keyboard interaction acceptance remain maintainer work; no interactive launch is implied by automated verification.

## Shared field names in Metadata Editor

The guide and Metadata Editor use the same AudioMator labels. The Add Field list shows the label first, then the actual PropertyMap key and purpose. Choosing a suggestion displays its friendly name while retaining its mapping identity separately. The Field table column and Edit Field sheet use friendly names; hovering a table field reveals its exact raw key. Custom names are preserved, and role/language/description suffixes remain distinguishable.

This is presentation, not whole-file canonicalisation. Existing raw keys and exact value arrays remain separate draft identities, even when two keys share a label. Explicit uppercase raw input remains raw; a friendly `Date` selection resolves to `STANDALONEDATE`, whereas existing raw `DATE` is not silently rewritten as `YEAR`. A DATE row is named according to the supported tag-family dialect (Year for ID3/MP4 engine DATE, Date for Xiph/APE literal DATE); a mixed-family row uses Year / Date rather than implying one meaning for all targets. Editing still uses the original raw key. The RELEASETIME display alias is shown as Release Date without renaming its stored key.

## Settings and Inspector labels

Settings → Interface, single/batch Inspector rows, batch edit labels, technical information and list column labels use the same AudioMator name source as the guide and Metadata Editor. Track and Disc list headers now say Track Number and Disc Number; their existing number/total display remains unchanged. Stored preference identifiers, curated defaults, selection, order, visibility and native write targets do not change.
