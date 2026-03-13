import SwiftUI
import AppKit

struct InspectorPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState
    @Binding var isInspectorVisible: Bool

    @State private var inspectorQuickLabel: String = ""
    @State private var inspectorQuickText: String = ""
    @State private var inspectorQuickBinding: Binding<String>? = nil
    @State private var isInspectorQuickPresented: Bool = false

    private var selectedFiles: [AudioFile] {
        viewModel.files.filter { state.selectedAudioIDs.contains($0.id) }
    }

    private var inspectorQuickPreview: String {
        renderedPreview(from: inspectorQuickText)
    }

    private var inspectorQuickCharacterCount: Int {
        inspectorQuickText.count
    }

    private var inspectorQuickLineCount: Int {
        max(inspectorQuickText.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
    }

    private var previewFont: NSFont {
        NSFont(name: "Menlo-Regular", size: 13) ??
            NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    private func renderedPreview(from text: String) -> String {
        guard !text.isEmpty else { return "" }

        var rendered = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case " ":
                rendered.append("·")
            case "\t":
                rendered.append("⇥")
            case "\n":
                rendered.append("↩")
                rendered.append("\n")
            case "\r":
                rendered.append("␍")
            case "\u{00A0}":
                rendered.append("⍽")
            default:
                rendered.unicodeScalars.append(scalar)
            }
        }

        return rendered
    }

    private func binding(
        for file: AudioFile,
        keyPath: WritableKeyPath<SingleFileEditModel, String>
    ) -> Binding<String> {
        Binding<String>(
            get: {
                viewModel.edit?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                if var current = viewModel.edit {
                    current[keyPath: keyPath] = newValue
                    viewModel.edit = current
                } else {
                    var model = SingleFileEditModel(from: file)
                    model[keyPath: keyPath] = newValue
                    viewModel.edit = model
                }
            }
        )
    }

    private func boolBinding(
        for file: AudioFile,
        keyPath: WritableKeyPath<SingleFileEditModel, Bool>
    ) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                viewModel.edit?[keyPath: keyPath] ?? false
            },
            set: { newValue in
                if var current = viewModel.edit {
                    current[keyPath: keyPath] = newValue
                    viewModel.edit = current
                } else {
                    var model = SingleFileEditModel(from: file)
                    model[keyPath: keyPath] = newValue
                    viewModel.edit = model
                }
            }
        )
    }

    private func displayedArtwork(for file: AudioFile) -> NSImage? {
        switch viewModel.edit?.artworkEditAction ?? .unchanged {
        case .unchanged:
            return file.artwork
        case .replace(let artwork):
            return artwork.image
        case .remove:
            return nil
        }
    }

    private func hasArtwork(for file: AudioFile) -> Bool {
        displayedArtwork(for: file) != nil
    }

    var body: some View {
        Group {
            if selectedFiles.count == 1, let file = selectedFiles.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        fileSection(file)
                        artworkSection(file)
                        metadataSection(file)
                        technicalSection(file)
                    }
                    .padding()
                }
            } else if selectedFiles.count > 1 {
                let merged = MergedAudioFile(files: selectedFiles)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        MergedMetadataSectionView(merged: merged)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Select an Audio File",
                    systemImage: "music.quarternote.3"
                )
            }
        }
        .sheet(isPresented: $isInspectorQuickPresented) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Edit \(inspectorQuickLabel)")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("The left side keeps the original input unchanged, while the right side shows a real-time preview using a clearer monospaced font and highlights hidden characters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Source", systemImage: "square.and.pencil")
                                .font(.headline)

                            Spacer()

                            Text("\(inspectorQuickCharacterCount) chars · \(inspectorQuickLineCount) lines")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.035))

                            TextEditor(text: $inspectorQuickText)
                                .scrollContentBackground(.hidden)
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.82))
                                .padding(10)

                            if inspectorQuickText.isEmpty {
                                Text("Enter text…")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Preview", systemImage: "text.magnifyingglass")
                                .font(.headline)

                            Spacer()

                            Text("· space  ⇥ tab  ↩ newline  ⍽ nbsp")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(0.12),
                                            Color.primary.opacity(0.06)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            ReadOnlyMonospacedTextView(
                                text: inspectorQuickPreview,
                                font: previewFont,
                                textColor: .labelColor
                            )
                            .padding(1)

                            if inspectorQuickText.isEmpty {
                                Text("Preview updates as you type.")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        isInspectorQuickPresented = false
                    }
                    Button("Save") {
                        inspectorQuickBinding?.wrappedValue = inspectorQuickText
                        isInspectorQuickPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 860, height: 420)
        }
    }

    @ViewBuilder
    private func fileSection(_ file: AudioFile) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(file.url.lastPathComponent)
                    .font(.headline)
                Text(file.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            inspectorSectionLabel("File", systemImage: "doc.text")
        }
    }

    @ViewBuilder
    private func artworkSection(_ file: AudioFile) -> some View {
        GroupBox {
            VStack {
                if let image = displayedArtwork(for: file) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .cornerRadius(8)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 200, height: 200)
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Double-click to replace or add artwork")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                viewModel.pickArtwork(for: file)
            }
            .contextMenu {
                Button("Import from Clipboard") {
                    viewModel.importArtworkFromClipboard(for: file)
                }

                Button("Clear Artwork") {
                    viewModel.clearArtwork(for: file)
                }
                .disabled(!hasArtwork(for: file))
            }
        } label: {
            inspectorSectionLabel("Artwork", systemImage: "photo.on.rectangle.angled")
        }
    }

    @ViewBuilder
    private func metadataSection(_ file: AudioFile) -> some View {
        GroupBox {
            VStack(spacing: 6) {
                editableRow(label: "Title", text: binding(for: file, keyPath: \.title))
                Divider()
                editableRow(label: "Artist", text: binding(for: file, keyPath: \.artist))
                Divider()
                editableRow(label: "Album", text: binding(for: file, keyPath: \.album))
                Divider()
                editableRow(label: "Composer", text: binding(for: file, keyPath: \.composer))
                Divider()
                editableRow(label: "Genre", text: binding(for: file, keyPath: \.genre))
                Divider()
                editableRow(label: "Year", text: binding(for: file, keyPath: \.year))
                Divider()
                editableRow(label: "Track Number", text: binding(for: file, keyPath: \.trackNumberText))
                Divider()
                editableRow(label: "Disc Number", text: binding(for: file, keyPath: \.discNumberText))
                Divider()
                editableRow(label: "Comment", text: binding(for: file, keyPath: \.comment))
                Divider()
                editableRow(label: "Album Artist", text: binding(for: file, keyPath: \.albumArtist))
                Divider()
                editableRow(label: "Release Date", text: binding(for: file, keyPath: \.releaseDate))
                Divider()
                editableRow(label: "Publisher", text: binding(for: file, keyPath: \.publisher))
                Divider()
                editableRow(label: "Copyright", text: binding(for: file, keyPath: \.copyright))
                Divider()
                explicitRow(label: "Explicit", isOn: boolBinding(for: file, keyPath: \.isExplicit))
                Divider()
                metadataRow(label: "Credits", value: file.credits)
            }
            .padding(.vertical, 4)
        } label: {
            inspectorSectionLabel("Metadata", systemImage: "tag")
        }
    }

    @ViewBuilder
    private func technicalSection(_ file: AudioFile) -> some View {
        GroupBox {
            VStack(spacing: 0) {
                metadataRow(label: "Duration", value: formatDuration(file.duration), valueWidth: 120, keepsLabelOnOneLine: true)
                Divider()
                metadataRow(label: "Bitrate", value: "\(file.bitrate) kbps", valueWidth: 120, keepsLabelOnOneLine: true)
                Divider()
                metadataRow(label: "Sample Rate", value: "\(Int(file.sampleRate)) Hz", valueWidth: 120, keepsLabelOnOneLine: true)
                Divider()
                metadataRow(label: "Channels", value: "\(file.channels)", valueWidth: 120, keepsLabelOnOneLine: true)
                Divider()
                metadataRow(label: "Format", value: file.format, valueWidth: 120, keepsLabelOnOneLine: true)
            }
            .padding(.vertical, 4)
        } label: {
            inspectorSectionLabel("Technical Info", systemImage: "waveform")
        }
    }

    private func inspectorSectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title3.weight(.bold))
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
    }

    @ViewBuilder
    private func metadataRow(
        label: String,
        value: String?,
        valueWidth: CGFloat = 220,
        keepsLabelOnOneLine: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.headline)
                .lineLimit(keepsLabelOnOneLine ? 1 : nil)
                .fixedSize(horizontal: keepsLabelOnOneLine, vertical: false)
            Spacer()
            Text(value ?? "—")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: valueWidth, alignment: .trailing)
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func editableRow(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.headline)
            Spacer()
            TextField("", text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 220, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            inspectorQuickLabel = label
            inspectorQuickText = text.wrappedValue
            inspectorQuickBinding = text
            isInspectorQuickPresented = true
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func explicitRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.headline)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
        }
        .padding(.vertical, 14)
    }
}
