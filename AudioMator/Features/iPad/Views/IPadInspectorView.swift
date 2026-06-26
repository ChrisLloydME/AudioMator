#if os(iOS)
import PhotosUI
import SwiftUI
import UIKit

struct IPadInspectorView: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState
    let onCancelEdits: () -> Void
    let onSaveEdits: () -> Void

    @State private var photoLibraryArtworkTarget: ArtworkImportTarget?
    @State private var isPhotoLibraryArtworkPickerPresented: Bool = false
    @State private var selectedPhotoLibraryArtworkItem: PhotosPickerItem?

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
        .photosPicker(
            isPresented: $isPhotoLibraryArtworkPickerPresented,
            selection: $selectedPhotoLibraryArtworkItem,
            matching: .images
        )
        .onChange(of: selectedPhotoLibraryArtworkItem) { _, newItem in
            importSelectedPhotoLibraryArtwork(newItem)
        }
    }

    private func pickArtworkFromFiles(for target: ArtworkImportTarget) {
        switch target {
        case .file(let file):
            viewModel.pickArtwork(for: file)
        case .files(let files):
            viewModel.pickArtwork(for: files)
        }
    }

    private func presentPhotoLibraryArtworkPicker(for target: ArtworkImportTarget) {
        photoLibraryArtworkTarget = target

        Task { @MainActor in
            await Task.yield()
            isPhotoLibraryArtworkPickerPresented = true
        }
    }

    private func importSelectedPhotoLibraryArtwork(_ item: PhotosPickerItem?) {
        guard let item, let target = photoLibraryArtworkTarget else { return }
        selectedPhotoLibraryArtworkItem = nil
        photoLibraryArtworkTarget = nil

        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                switch target {
                case .file(let file):
                    viewModel.importArtworkFromPhotoLibrary(data, for: file)
                case .files(let files):
                    viewModel.importArtworkFromPhotoLibrary(data, for: files)
                }
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
                Picker("Explicit", selection: contentAdvisoryBinding(for: file)) {
                    Text("Unset").tag(nil as ContentAdvisory?)
                    Text(ContentAdvisory.notExplicit.displayName).tag(ContentAdvisory.notExplicit as ContentAdvisory?)
                    Text(ContentAdvisory.explicit.displayName).tag(ContentAdvisory.explicit as ContentAdvisory?)
                    Text(ContentAdvisory.clean.displayName).tag(ContentAdvisory.clean as ContentAdvisory?)
                }
                .pickerStyle(.menu)
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
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
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
                    Text(MultiFileExplicitEditState.keepExisting.displayName).tag(MultiFileExplicitEditState.keepExisting)
                    Text("Unset").tag(MultiFileExplicitEditState.set(nil))
                    Text(ContentAdvisory.notExplicit.displayName).tag(MultiFileExplicitEditState.set(.notExplicit))
                    Text(ContentAdvisory.explicit.displayName).tag(MultiFileExplicitEditState.set(.explicit))
                    Text(ContentAdvisory.clean.displayName).tag(MultiFileExplicitEditState.set(.clean))
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
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
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
                .buttonStyle(IPadGlassActionButtonStyle())
                .disabled(!viewModel.hasUnsavedInspectorChanges)

            Button("Save", action: onSaveEdits)
                .buttonStyle(IPadGlassActionButtonStyle(isProminent: true))
                .disabled(!viewModel.hasUnsavedInspectorChanges || viewModel.metadataSaveProgress != nil)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 0.5)
        }
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

    func contentAdvisoryBinding(for file: AudioFile) -> Binding<ContentAdvisory?> {
        Binding(
            get: { viewModel.edit?.contentAdvisory ?? file.contentAdvisory },
            set: { newValue in
                if var current = viewModel.edit {
                    current.contentAdvisory = newValue
                    viewModel.edit = current
                } else {
                    var model = SingleFileEditModel(from: file)
                    model.contentAdvisory = newValue
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

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    artworkSourceMenu(for: .file(file))

                    artworkButton("Fetch Online", systemImage: "icloud.and.arrow.down") {
                        viewModel.findOnlineArtwork(for: file)
                    }
                    .disabled(disabledReason != nil)
                }

                GridRow {
                    artworkButton("Clear", systemImage: "trash", role: .destructive, isDestructive: true) {
                        viewModel.clearArtwork(for: file)
                    }
                    .disabled(!hasArtwork(for: file))
                    .gridCellColumns(2)
                }
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

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    artworkSourceMenu(for: .files(files))

                    artworkButton("Fetch Online", systemImage: "icloud.and.arrow.down") {
                        viewModel.findOnlineArtwork(for: files)
                    }
                    .disabled(disabledReason != nil)
                }

                GridRow {
                    artworkButton("Keep Current", systemImage: "checkmark.seal") {
                        viewModel.keepArtwork(for: files)
                    }

                    artworkButton("Clear", systemImage: "trash", role: .destructive, isDestructive: true) {
                        viewModel.clearArtwork(for: files)
                    }
                    .disabled(!canClearMultiArtwork)
                }
            }

            if let disabledReason {
                Text(disabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    func artworkSourceMenu(for target: ArtworkImportTarget) -> some View {
        Menu {
            Button("Files") {
                pickArtworkFromFiles(for: target)
            }

            Button("Photo Library") {
                presentPhotoLibraryArtworkPicker(for: target)
            }
        } label: {
            Label("Choose", systemImage: "photo.badge.plus")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 38)
        }
        .menuIndicator(.hidden)
        .menuStyle(.button)
        .buttonStyle(IPadArtworkButtonStyle())
        .controlSize(.regular)
    }

    func artworkButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(IPadArtworkButtonStyle(isDestructive: isDestructive))
        .controlSize(.regular)
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

private struct IPadArtworkButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(background(configuration: configuration))
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        isDestructive ? .white : .primary
    }

    @ViewBuilder
    private func background(configuration: Configuration) -> some View {
        if isDestructive {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(configuration.isPressed ? 0.78 : 0.92))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(configuration.isPressed ? 0.68 : 0.86))
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private var border: some View {
        if isDestructive {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct IPadGlassActionButtonStyle: ButtonStyle {
    var isProminent: Bool = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .frame(minWidth: 86)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(background(configuration: configuration))
            .overlay(border(configuration: configuration))
            .clipShape(Capsule(style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        isProminent ? .white : .primary
    }

    @ViewBuilder
    private func background(configuration: Configuration) -> some View {
        if isProminent {
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(configuration.isPressed ? 0.72 : 0.88))
                .background(.thinMaterial, in: Capsule(style: .continuous))
        } else {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .opacity(configuration.isPressed ? 0.82 : 1)
        }
    }

    @ViewBuilder
    private func border(configuration: Configuration) -> some View {
        Capsule(style: .continuous)
            .strokeBorder(
                isProminent
                    ? Color.white.opacity(configuration.isPressed ? 0.16 : 0.28)
                    : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.16),
                lineWidth: 1
            )
    }
}
#endif
