import SwiftUI
import AppKit
import TagLibAudioMetadata

struct MetadataFieldGuideView: View {
    static let windowID = "metadata-field-guide"
    /// Use the actual localized labels at the system body size, including row
    /// insets and the scrollbar, rather than guessing from character counts.
    static var preferredSidebarWidth: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let longest = MetadataFieldGuide.entries.map {
            ($0.title as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        return max(320, ceil(longest) + 64)
    }

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
                    Text(entry.title)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .tag(entry.id)
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: Self.preferredSidebarWidth, max: max(520, Self.preferredSidebarWidth))
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
        .frame(minWidth: 840, minHeight: 480)
    }

    private func detail(_ entry: MetadataFieldGuide.Entry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.title).font(.largeTitle).accessibilityAddTraits(.isHeader)
                    Text(entry.purpose).font(.body)
                }

                if let guidance = entry.valueGuidance {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Format and Examples").font(.headline).accessibilityAddTraits(.isHeader)
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(guidance.examples.enumerated()), id: \.element.id) { index, example in
                                    if index > 0 {
                                        Divider()
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(example.value)
                                            .font(.system(.body, design: .monospaced))
                                        Text(example.note)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(8)
                        }
                        Text(guidance.formatNote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Editing in AudioMator").font(.headline).accessibilityAddTraits(.isHeader)
                        Text(guidance.editingSummary)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(guidance.pickerAvailabilityNote)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(guidance.sharedEditingNote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if entry.key != nil {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Where This Field Is Stored").font(.headline).accessibilityAddTraits(.isHeader)
                        Text("Find your tag format to see what you can save. To clear a text field in the Inspector, leave it empty. In Metadata Editor, choose Delete Field.")
                            .foregroundStyle(.secondary)
                        if let note = entry.numberingSavingNote {
                            Text(note).fixedSize(horizontal: false, vertical: true)
                        }
                        GroupBox {
                            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                                GridRow {
                                    Text("Tag Format").font(.headline)
                                    Text("Stored Field and How to Edit").font(.headline)
                                }
                                Divider().gridCellColumns(2)
                                ForEach(MetadataNativeFamily.allCases, id: \.self) { family in
                                    GridRow(alignment: .top) {
                                        Text(familyTitle(family)).fontWeight(.medium)
                                        VStack(alignment: .leading, spacing: 4) {
                                            let targets = entry.schema?.targets(for: family) ?? []
                                            ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                                                Text(nativeName(target)).font(.system(.body, design: .monospaced))
                                            }
                                            Text(entry.savingNote(for: family) ?? availability(entry, family: family))
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    }
                                    if family != MetadataNativeFamily.allCases.last {
                                        Divider().gridCellColumns(2)
                                    }
                                }
                                if let note = entry.trackerSavingNote {
                                    Divider().gridCellColumns(2)
                                    GridRow(alignment: .top) {
                                        Text("Tracker Modules").fontWeight(.medium)
                                        Text(note)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(8)
                        }
                        Text("MP3 and some WAV, AIFF and DSD files use ID3 tags. FLAC and supported Ogg files use Vorbis comments; WMA uses ASF. A WAV file can contain both ID3 and RIFF INFO. These are tag formats, not guarantees based on a filename.")
                            .foregroundStyle(.secondary)
                    }
                }

                let resolvedSources = entry.resolvedSources
                VStack(alignment: .leading, spacing: 8) {
                    Text("Learn More").font(.headline).accessibilityAddTraits(.isHeader)
                    Text(
                        resolvedSources.count > 1
                            ? "The explanation and format guidance draw on the official references below. AudioMator’s storage and editing choices are described above."
                            : "The explanation draws on the official reference below. AudioMator’s storage and editing choices are described above."
                    )
                        .foregroundStyle(.secondary)
                    ForEach(resolvedSources) { source in
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
        guard entry.schema?.targets(for: family).isEmpty == false else {
            return String(localized: "AudioMator has no standard way to save this field in this tag format.")
        }
        return String(localized: "Editing depends on the tag in the file.")
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
            Button {
                openWindow(id: MetadataFieldGuideView.windowID)
            } label: {
                Label("Metadata Field Guide", systemImage: "text.book.closed")
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}
