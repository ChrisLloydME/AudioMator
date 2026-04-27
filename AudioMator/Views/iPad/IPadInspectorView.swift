#if os(iOS)
import SwiftUI
import UIKit

struct IPadInspectorView: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState
    let onCancelEdits: () -> Void
    let onSaveEdits: () -> Void

    private var selectedFiles: [AudioFile] {
        viewModel.files.filter { state.selectedAudioIDs.contains($0.id) }
    }

    private var artworkLookupSessionBinding: Binding<ArtworkLookupSession?> {
        Binding(
            get: { viewModel.artworkLookupSession },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissArtworkLookup()
                }
            }
        )
    }

    var body: some View {
        Group {
            if selectedFiles.count == 1, let file = selectedFiles.first {
                singleFileInspector(file)
            } else if selectedFiles.count > 1 {
                multiFileInspector(selectedFiles)
            } else {
                ContentUnavailableView(
                    "Select a File",
                    systemImage: "slider.horizontal.3",
                    description: Text("Choose one or more tracks to edit their metadata.")
                )
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            if !selectedFiles.isEmpty {
                actionBar
            }
        }
        .sheet(item: artworkLookupSessionBinding) { _ in
            IPadDismissibleSheet(
                title: "Online Album Artwork",
                isCloseDisabled: viewModel.artworkLookupSession?.isApplying == true
            ) {
                AlbumArtworkLookupSheet(viewModel: viewModel)
            }
        }
    }

    private func singleFileInspector(_ file: AudioFile) -> some View {
        Form {
            Section("File") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(file.url.lastPathComponent)
                        .font(.headline)
                    Text(file.format)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Artwork") {
                artworkSection(file)
            }

            Section("Core Tags") {
                fieldRow("Title", text: binding(for: file, keyPath: \.title))
                fieldRow("Artist", text: binding(for: file, keyPath: \.artist))
                fieldRow("Album", text: binding(for: file, keyPath: \.album))
                fieldRow("Album Artist", text: binding(for: file, keyPath: \.albumArtist))
                fieldRow("Composer", text: binding(for: file, keyPath: \.composer))
                fieldRow("Genre", text: binding(for: file, keyPath: \.genre))
                fieldRow("Year", text: binding(for: file, keyPath: \.year), keyboardType: .numberPad)
                fieldRow("Release Date", text: binding(for: file, keyPath: \.releaseDate), keyboardType: .numbersAndPunctuation)
            }

            Section("Track & Disc") {
                compactNumberGrid(
                    trackNumber: trackNumberFieldBinding(for: file),
                    trackTotal: trackTotalFieldBinding(for: file),
                    discNumber: discNumberFieldBinding(for: file),
                    discTotal: discTotalFieldBinding(for: file)
                )
            }

            Section("Publishing") {
                fieldRow("Publisher", text: binding(for: file, keyPath: \.publisher))
                fieldRow("Copyright", text: binding(for: file, keyPath: \.copyright))
                Toggle("Explicit", isOn: boolBinding(for: file, keyPath: \.isExplicit))
            }

            Section("Comment") {
                textEditorRow("Comment", text: binding(for: file, keyPath: \.comment), minHeight: 110)
            }

            Section("Technical") {
                readOnlyRow("Duration", value: formatDuration(file.duration))
                readOnlyRow("Bitrate", value: "\(file.bitrate) kbps")
                readOnlyRow("Sample Rate", value: "\(Int(file.sampleRate)) Hz")
                readOnlyRow("Channels", value: "\(file.channels)")
                readOnlyRow("Format", value: file.format)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func multiFileInspector(_ files: [AudioFile]) -> some View {
        Form {
            Section("Selection") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(files.count) files selected")
                        .font(.headline)
                    Text("Changes apply to every selected file. Fields left untouched keep their current values.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Artwork") {
                multiArtworkSection(files)
            }

            Section("Core Tags") {
                multiFieldRow("Title", field: .title)
                multiFieldRow("Artist", field: .artist)
                multiFieldRow("Album", field: .album)
                multiFieldRow("Album Artist", field: .albumArtist)
                multiFieldRow("Composer", field: .composer)
                multiFieldRow("Genre", field: .genre)
                multiFieldRow("Year", field: .year, keyboardType: .numberPad)
                multiFieldRow("Release Date", field: .releaseDate, keyboardType: .numbersAndPunctuation)
            }

            Section("Track & Disc") {
                compactNumberGrid(
                    trackNumber: multiBinding(for: .trackNumber),
                    trackTotal: multiBinding(for: .trackTotal),
                    discNumber: multiBinding(for: .discNumber),
                    discTotal: multiBinding(for: .discTotal),
                    trackNumberPlaceholder: viewModel.multiEdit?.placeholder(for: .trackNumber),
                    trackTotalPlaceholder: viewModel.multiEdit?.placeholder(for: .trackTotal),
                    discNumberPlaceholder: viewModel.multiEdit?.placeholder(for: .discNumber),
                    discTotalPlaceholder: viewModel.multiEdit?.placeholder(for: .discTotal)
                )
            }

            Section("Publishing") {
                multiFieldRow("Publisher", field: .publisher)
                multiFieldRow("Copyright", field: .copyright)
                Picker("Explicit", selection: multiExplicitBinding) {
                    Text("Keep Existing").tag(MultiFileExplicitEditState.keepExisting)
                    Text("Explicit").tag(MultiFileExplicitEditState.markExplicit)
                    Text("Clean").tag(MultiFileExplicitEditState.markClean)
                }
                .pickerStyle(.menu)

                Text(viewModel.multiEdit?.explicitCurrentValueDescription ?? "Current values differ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Comment") {
                textEditorRow(
                    "Comment",
                    text: multiBinding(for: .comment),
                    placeholder: viewModel.multiEdit?.placeholder(for: .comment),
                    minHeight: 110
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.hasUnsavedInspectorChanges ? "Unsaved Changes" : "No Pending Changes")
                    .font(.subheadline.weight(.semibold))
                Text(actionBarSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Cancel", action: onCancelEdits)
                .disabled(!viewModel.hasUnsavedInspectorChanges)

            Button("Save", action: onSaveEdits)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasUnsavedInspectorChanges || viewModel.metadataSaveProgress != nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var actionBarSubtitle: String {
        if selectedFiles.count == 1, let file = selectedFiles.first {
            return file.url.lastPathComponent
        }
        return "\(selectedFiles.count) files"
    }
}

private extension IPadInspectorView {
    func binding(
        for file: AudioFile,
        keyPath: WritableKeyPath<SingleFileEditModel, String>
    ) -> Binding<String> {
        Binding(
            get: { viewModel.edit?[keyPath: keyPath] ?? "" },
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

    func boolBinding(
        for file: AudioFile,
        keyPath: WritableKeyPath<SingleFileEditModel, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { viewModel.edit?[keyPath: keyPath] ?? false },
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

    func trackNumberFieldBinding(for file: AudioFile) -> Binding<String> {
        Binding(
            get: { viewModel.edit?.trackNumberFieldText ?? SingleFileEditModel(from: file).trackNumberFieldText },
            set: { newValue in
                if var current = viewModel.edit {
                    current.setTrackNumberFieldText(newValue)
                    viewModel.edit = current
                } else {
                    var model = SingleFileEditModel(from: file)
                    model.setTrackNumberFieldText(newValue)
                    viewModel.edit = model
                }
            }
        )
    }

    func trackTotalFieldBinding(for file: AudioFile) -> Binding<String> {
        Binding(
            get: { viewModel.edit?.trackTotalFieldText ?? SingleFileEditModel(from: file).trackTotalFieldText },
            set: { newValue in
                if var current = viewModel.edit {
                    current.setTrackTotalFieldText(newValue)
                    viewModel.edit = current
                } else {
                    var model = SingleFileEditModel(from: file)
                    model.setTrackTotalFieldText(newValue)
                    viewModel.edit = model
                }
            }
        )
    }

    func discNumberFieldBinding(for file: AudioFile) -> Binding<String> {
        Binding(
            get: { viewModel.edit?.discNumberFieldText ?? SingleFileEditModel(from: file).discNumberFieldText },
            set: { newValue in
                if var current = viewModel.edit {
                    current.setDiscNumberFieldText(newValue)
                    viewModel.edit = current
                } else {
                    var model = SingleFileEditModel(from: file)
                    model.setDiscNumberFieldText(newValue)
                    viewModel.edit = model
                }
            }
        )
    }

    func discTotalFieldBinding(for file: AudioFile) -> Binding<String> {
        Binding(
            get: { viewModel.edit?.discTotalFieldText ?? SingleFileEditModel(from: file).discTotalFieldText },
            set: { newValue in
                if var current = viewModel.edit {
                    current.setDiscTotalFieldText(newValue)
                    viewModel.edit = current
                } else {
                    var model = SingleFileEditModel(from: file)
                    model.setDiscTotalFieldText(newValue)
                    viewModel.edit = model
                }
            }
        )
    }

    func multiBinding(for field: MultiFileEditableTextField) -> Binding<String> {
        Binding(
            get: { viewModel.multiEdit?.text(for: field) ?? "" },
            set: { newValue in
                guard var current = viewModel.multiEdit else { return }
                current.setText(newValue, for: field)
                viewModel.multiEdit = current
            }
        )
    }

    var multiExplicitBinding: Binding<MultiFileExplicitEditState> {
        Binding(
            get: { viewModel.multiEdit?.explicitEditState ?? .keepExisting },
            set: { newValue in
                guard var current = viewModel.multiEdit else { return }
                current.explicitEditState = newValue
                viewModel.multiEdit = current
            }
        )
    }

    func displayedArtwork(for file: AudioFile) -> PlatformImage? {
        switch viewModel.edit?.artworkEditAction ?? .unchanged {
        case .unchanged:
            return file.artwork
        case .replace(let artwork):
            return artwork.image
        case .remove:
            return nil
        }
    }

    func hasArtwork(for file: AudioFile) -> Bool {
        displayedArtwork(for: file) != nil
    }

    var multiDisplayedArtwork: PlatformImage? {
        viewModel.multiEdit?.displayedArtwork
    }

    var multiArtworkSummary: String {
        viewModel.multiEdit?.artworkSummary ?? "Selected files use different artwork"
    }

    var multiArtworkPlaceholderSymbolName: String {
        viewModel.multiEdit?.artworkPlaceholderSymbolName ?? "photo.on.rectangle.angled"
    }

    var canClearMultiArtwork: Bool {
        viewModel.multiEdit?.canClearArtwork ?? false
    }

    func artworkSection(_ file: AudioFile) -> some View {
        let disabledReason = viewModel.artworkLookupDisabledReason(for: file)

        return VStack(alignment: .leading, spacing: 14) {
            artworkPreview(displayedArtwork(for: file), placeholderSymbol: "photo")

            HStack(spacing: 10) {
                Button("Choose Artwork…") {
                    viewModel.pickArtwork(for: file)
                }
                .buttonStyle(.bordered)

                Button("Fetch Online…") {
                    viewModel.findOnlineArtwork(for: file)
                }
                .buttonStyle(.bordered)
                .disabled(disabledReason != nil)

                Button("Clear", role: .destructive) {
                    viewModel.clearArtwork(for: file)
                }
                .buttonStyle(.bordered)
                .disabled(!hasArtwork(for: file))
            }

            if let disabledReason {
                Text(disabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    func multiArtworkSection(_ files: [AudioFile]) -> some View {
        let disabledReason = viewModel.artworkLookupDisabledReason(for: files)

        return VStack(alignment: .leading, spacing: 14) {
            artworkPreview(multiDisplayedArtwork, placeholderSymbol: multiArtworkPlaceholderSymbolName, subtitle: multiArtworkSummary)

            HStack(spacing: 10) {
                Button("Choose Artwork…") {
                    viewModel.pickArtwork(for: files)
                }
                .buttonStyle(.bordered)

                Button("Fetch Online…") {
                    viewModel.findOnlineArtwork(for: files)
                }
                .buttonStyle(.bordered)
                .disabled(disabledReason != nil)

                Button("Keep Current") {
                    viewModel.keepArtwork(for: files)
                }
                .buttonStyle(.bordered)

                Button("Clear", role: .destructive) {
                    viewModel.clearArtwork(for: files)
                }
                .buttonStyle(.bordered)
                .disabled(!canClearMultiArtwork)
            }

            if let disabledReason {
                Text(disabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    func artworkPreview(
        _ image: PlatformImage?,
        placeholderSymbol: String,
        subtitle: String? = nil
    ) -> some View {
        HStack(spacing: 16) {
            Group {
                if let image {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .overlay {
                            Image(systemName: placeholderSymbol)
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(image == nil ? "No Artwork" : "Embedded Artwork")
                    .font(.headline)

                Text(subtitle ?? "Artwork changes stay pending until you tap Save.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func compactNumberGrid(
        trackNumber: Binding<String>,
        trackTotal: Binding<String>,
        discNumber: Binding<String>,
        discTotal: Binding<String>,
        trackNumberPlaceholder: String? = nil,
        trackTotalPlaceholder: String? = nil,
        discNumberPlaceholder: String? = nil,
        discTotalPlaceholder: String? = nil
    ) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            compactField("Track Number", text: trackNumber, placeholder: trackNumberPlaceholder)
            compactField("Total Tracks", text: trackTotal, placeholder: trackTotalPlaceholder)
            compactField("Disc Number", text: discNumber, placeholder: discNumberPlaceholder)
            compactField("Total Discs", text: discTotal, placeholder: discTotalPlaceholder)
        }
        .padding(.vertical, 4)
    }

    func compactField(_ title: String, text: Binding<String>, placeholder: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder ?? title, text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
        }
    }

    func fieldRow(
        _ title: String,
        text: Binding<String>,
        placeholder: String? = nil,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            TextField(placeholder ?? title, text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(keyboardType)
        }
        .padding(.vertical, 2)
    }

    func multiFieldRow(
        _ title: String,
        field: MultiFileEditableTextField,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        fieldRow(
            title,
            text: multiBinding(for: field),
            placeholder: viewModel.multiEdit?.placeholder(for: field),
            keyboardType: keyboardType
        )
    }

    func textEditorRow(
        _ title: String,
        text: Binding<String>,
        placeholder: String? = nil,
        minHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))

                TextEditor(text: text)
                    .frame(minHeight: minHeight)
                    .padding(6)

                if text.wrappedValue.isEmpty, let placeholder {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.vertical, 2)
    }

    func readOnlyRow(_ title: String, value: String) -> some View {
        LabeledContent(title, value: value.isEmpty ? "—" : value)
    }
}
#endif
