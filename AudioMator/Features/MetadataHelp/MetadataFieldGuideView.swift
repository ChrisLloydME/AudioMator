import SwiftUI
import TagLibAudioMetadata

struct MetadataFieldGuideView: View {
    static let windowID = "metadata-field-guide"
    @State private var query = ""
    @State private var selection: String? = MetadataFieldKey.title.rawValue

    private var results: [MetadataFieldGuide.Entry] {
        MetadataFieldGuide.entries.filter { $0.matches(query) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(results) { entry in
                    Text(entry.title).tag(entry.id)
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
            .searchable(text: $query, prompt: Text("Find a field or storage name"))
        } detail: {
            if let entry = results.first(where: { $0.id == selection }) {
                detail(entry)
            } else {
                ContentUnavailableView(
                    "Choose a Field", systemImage: "text.book.closed",
                    description: Text("Find out what a field means and where AudioMator stores it.")
                )
            }
        }
        .onChange(of: query) { _, _ in
            if !results.contains(where: { $0.id == selection }) { selection = results.first?.id }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private func detail(_ entry: MetadataFieldGuide.Entry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.title).font(.largeTitle).accessibilityAddTraits(.isHeader)
                    Text(entry.purpose).font(.body)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Using This Field").font(.headline)
                    if entry.key == nil {
                        Text("This is read-only file information, not an editable metadata field.")
                    } else if let field = InspectorMetadataField.configurableFields.first(where: { $0.metadataFieldKey == entry.key }) {
                        if InspectorMetadataField.defaultVisibleFields.contains(field) {
                            Text("Available in the Inspector. You can choose which fields appear in Settings.")
                        } else {
                            Text("Optional in the Inspector. Turn it on in Settings if you use it.")
                        }
                    } else if entry.key == .artwork {
                        Text("Use the artwork controls to view or change cover images.")
                    } else {
                        Text("Look for this field in Metadata Editor. Its presence and editing support depend on the file format.")
                    }
                    Text("You can leave unused fields empty. A field’s presence here does not mean it can be edited in every format.")
                        .foregroundStyle(.secondary)
                    if let key = entry.key, [MetadataFieldKey.year, .standaloneDate, .releaseDate, .originalReleaseDate].contains(key) {
                        Text("In AudioMator, Year, Date, Release Date and Original Release Date stay independent. For example, Year can be 2004 while Release Date is in 2017. Editing one does not fill or update the others.")
                    }
                    if let key = entry.key, [MetadataFieldKey.contentGroup, .grouping, .work].contains(key) {
                        Text("AudioMator keeps Content Group, Grouping and Work separate. Other editors may give the same storage location a different label.")
                    }
                }

                if entry.key != nil {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("The names below are the storage locations used by AudioMator. They can differ from the names shown by other editors. Availability also depends on the tag version and the individual file.")
                                .foregroundStyle(.secondary)
                            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                                ForEach(MetadataNativeFamily.allCases, id: \.self) { family in
                                    GridRow(alignment: .top) {
                                        Text(familyTitle(family)).fontWeight(.medium)
                                        VStack(alignment: .leading, spacing: 4) {
                                            let targets = entry.schema?.targets(for: family) ?? []
                                            if targets.isEmpty {
                                                Text(entry.key == .trackerName ? "No portable tag; tracker modules use their own headers." : "No mapping in AudioMator")
                                                    .foregroundStyle(.secondary)
                                            } else {
                                                ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                                                    Text(nativeName(target)).font(.system(.body, design: .monospaced))
                                                }
                                                Text(availability(entry, family: family)).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                            Text("MP3 and some WAV, AIFF and DSD files use ID3 tags. FLAC and supported Ogg files use Vorbis comments; WMA uses ASF. A WAV file can contain both ID3 and RIFF INFO. These are tag formats, not guarantees based on a filename.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 12)
                    } label: {
                        Text("Where This Field Is Stored").font(.headline)
                    }

                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Learn More").font(.headline)
                    Text("The explanation draws on the official reference below. AudioMator’s storage and editing choices are described above.")
                        .foregroundStyle(.secondary)
                    if let source = MetadataFieldGuide.sources.first(where: { $0.id == entry.sourceID }) {
                        Link(destination: source.url) {
                            Label(source.title, systemImage: "arrow.up.right.square")
                        }
                        .help("Opens the official reference in your browser")
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: 720, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func nativeName(_ target: MetadataNativeTarget) -> String {
        switch target.storage {
        case .userTextFrame: return "TXXX (\(target.nativeIdentity))"
        case .mp4Freeform: return "----:com.apple.iTunes:\(target.nativeIdentity)"
        default:
            let component = target.numberComponent.map { $0 == .number ? String(localized: "number") : String(localized: "total") }
            return target.nativeIdentity + (component.map { " (\($0))" } ?? "")
        }
    }

    private func availability(_ entry: MetadataFieldGuide.Entry, family: MetadataNativeFamily) -> String {
        if family == .matroska { return String(localized: "Planned mapping; editing is not available.") }
        if entry.schema?.isRoleQualified == true { return String(localized: "These credits cannot be edited as a simple text field.") }
        switch entry.schema?.capability(for: family) {
        case .readOnly: return String(localized: "Read-only in AudioMator.")
        case .conventionalExtension: return String(localized: "Stored as an additional text field; other players may ignore it.")
        default: return String(localized: "Registered storage location; the file must support the requested edit.")
        }
    }

    private func familyTitle(_ family: MetadataNativeFamily) -> String {
        switch family {
        case .id3v23: "ID3v2.3"
        case .id3v24: "ID3v2.4"
        case .mp4: "MP4 / M4A"
        case .vorbisComment: "Vorbis Comment / FLAC"
        case .apev2: "APEv2"
        case .asf: "ASF / WMA"
        case .riffInfo: "RIFF INFO"
        case .matroska: "Matroska"
        }
    }
}

struct MetadataFieldGuideCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Metadata Field Guide") {
                openWindow(id: MetadataFieldGuideView.windowID)
            }
        }
    }
}
