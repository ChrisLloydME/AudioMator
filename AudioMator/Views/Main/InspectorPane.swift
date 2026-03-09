import SwiftUI

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
        let text = inspectorQuickText
        if text.isEmpty {
            return " "
        }
        return text.replacingOccurrences(of: " ", with: "·")
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
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit \(inspectorQuickLabel)")
                    .font(.title2)
                    .fontWeight(.semibold)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $inspectorQuickText)
                        .font(.system(.body, design: .monospaced))
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .frame(minHeight: 80, idealHeight: 140)

                    if inspectorQuickText.isEmpty {
                        Text("Enter text…")
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview:")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(inspectorQuickPreview)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
            .padding()
            .frame(width: 480)
        }
    }

    @ViewBuilder
    private func fileSection(_ file: AudioFile) -> some View {
        GroupBox("File") {
            VStack(alignment: .leading, spacing: 8) {
                Text(file.url.lastPathComponent)
                    .font(.headline)
                Text(file.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func artworkSection(_ file: AudioFile) -> some View {
        GroupBox("Artwork") {
            VStack {
                if let image = file.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200)
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
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func metadataSection(_ file: AudioFile) -> some View {
        GroupBox("Metadata") {
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
        }
    }

    @ViewBuilder
    private func technicalSection(_ file: AudioFile) -> some View {
        GroupBox("Technical Info") {
            VStack(spacing: 0) {
                metadataRow(label: "Duration", value: formatDuration(file.duration))
                Divider()
                metadataRow(label: "Bitrate", value: "\(file.bitrate) kbps")
                Divider()
                metadataRow(label: "Sample Rate", value: "\(Int(file.sampleRate)) Hz")
                Divider()
                metadataRow(label: "Channels", value: "\(file.channels)")
                Divider()
                metadataRow(label: "Format", value: file.format)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.headline)
            Spacer()
            Text(value ?? "—")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 220, alignment: .trailing)
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
