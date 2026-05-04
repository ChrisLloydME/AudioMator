import SwiftUI
import PhotosUI

let inspectorRowContentHeight: CGFloat = 20
let inspectorRowVerticalPadding: CGFloat = 6
let artworkActionButtonHeight: CGFloat = 28
let artworkActionButtonCornerRadius: CGFloat = 14

enum ArtworkImportTarget {
    case file(AudioFile)
    case files([AudioFile])
}

struct InspectorPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState
    @Binding var isInspectorVisible: Bool

    @State private var inspectorQuickLabel: String = ""
    @State private var inspectorQuickText: String = ""
    @State private var inspectorQuickBinding: Binding<String>? = nil
    @State private var isInspectorQuickPresented: Bool = false
    @State private var photoLibraryArtworkTarget: ArtworkImportTarget?
    @State private var isPhotoLibraryArtworkPickerPresented: Bool = false
    @State private var selectedPhotoLibraryArtworkItem: PhotosPickerItem?

    private var artworkLookupSessionBinding: Binding<ArtworkLookupSession?> {
        Binding<ArtworkLookupSession?>(
            get: { viewModel.artworkLookupSession },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissArtworkLookup()
                }
            }
        )
    }

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

    private var previewFont: PlatformFont {
        PlatformFont(name: "Menlo-Regular", size: 13) ??
            PlatformFont.monospacedSystemFont(ofSize: 13, weight: .regular)
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

    private func trackNumberFieldBinding(for file: AudioFile) -> Binding<String> {
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

    private func trackTotalFieldBinding(for file: AudioFile) -> Binding<String> {
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

    private func discNumberFieldBinding(for file: AudioFile) -> Binding<String> {
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

    private func discTotalFieldBinding(for file: AudioFile) -> Binding<String> {
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

    private func multiBinding(for field: MultiFileEditableTextField) -> Binding<String> {
        Binding<String>(
            get: {
                viewModel.multiEdit?.text(for: field) ?? ""
            },
            set: { newValue in
                guard var current = viewModel.multiEdit else { return }
                current.setText(newValue, for: field)
                viewModel.multiEdit = current
            }
        )
    }

    private var multiExplicitBinding: Binding<MultiFileExplicitEditState> {
        Binding<MultiFileExplicitEditState>(
            get: {
                viewModel.multiEdit?.explicitEditState ?? .keepExisting
            },
            set: { newValue in
                guard var current = viewModel.multiEdit else { return }
                current.explicitEditState = newValue
                viewModel.multiEdit = current
            }
        )
    }

    private func displayedArtwork(for file: AudioFile) -> PlatformImage? {
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

    private func artworkLookupDisabledReason(for file: AudioFile) -> String? {
        viewModel.artworkLookupDisabledReason(for: file)
    }

    private var multiDisplayedArtwork: PlatformImage? {
        viewModel.multiEdit?.displayedArtwork
    }

    private var multiArtworkSummary: String {
        viewModel.multiEdit?.artworkSummary ?? "Selected files use different artwork"
    }

    private var multiArtworkPlaceholderSymbolName: String {
        viewModel.multiEdit?.artworkPlaceholderSymbolName ?? "photo.on.rectangle.angled"
    }

    private var canClearMultiArtwork: Bool {
        viewModel.multiEdit?.canClearArtwork ?? false
    }

    private var hasPendingMultiArtworkChange: Bool {
        viewModel.multiEdit?.hasPendingArtworkChange ?? false
    }

    private func artworkLookupDisabledReason(for files: [AudioFile]) -> String? {
        viewModel.artworkLookupDisabledReason(for: files)
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        multiSelectionSection(selectedFiles)
                        multiArtworkSection(selectedFiles)
                        multiMetadataSection(selectedFiles)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Select a File",
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

                    Text("Edit the original text on the left. Preview hidden characters on the right.")
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
                                Text("Type or paste text")
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
                                textColor: .audiomatorLabel
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
        .sheet(item: artworkLookupSessionBinding) { _ in
            AlbumArtworkLookupSheet(viewModel: viewModel)
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

    private func pickArtworkFromFinder(for target: ArtworkImportTarget) {
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

    @ViewBuilder
    private func chooseArtworkMenu(
        for target: ArtworkImportTarget,
        width: CGFloat
    ) -> some View {
        Menu {
            Button("Finder") {
                pickArtworkFromFinder(for: target)
            }

            Button("Photo Library") {
                presentPhotoLibraryArtworkPicker(for: target)
            }
        } label: {
            artworkActionLabel("Choose Artwork…", width: width)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .controlSize(.large)
        .frame(width: width)
    }

    private func artworkActionButton(
        _ title: String,
        width: CGFloat,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            artworkActionLabel(
                title,
                width: width,
                isDestructive: role == .destructive,
                isEnabled: isEnabled
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help ?? "")
    }

    private func artworkActionLabel(
        _ title: String,
        width: CGFloat,
        isDestructive: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        Text(title)
            .font(.body.weight(isDestructive ? .semibold : .regular))
            .foregroundStyle(artworkActionForeground(isDestructive: isDestructive, isEnabled: isEnabled))
            .frame(width: width, height: artworkActionButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: artworkActionButtonCornerRadius, style: .continuous)
                    .fill(artworkActionBackground(isDestructive: isDestructive, isEnabled: isEnabled))
            )
            .contentShape(RoundedRectangle(cornerRadius: artworkActionButtonCornerRadius, style: .continuous))
    }

    private func artworkActionForeground(isDestructive: Bool, isEnabled: Bool) -> Color {
        if isDestructive {
            return .white.opacity(isEnabled ? 1 : 0.45)
        }

        return isEnabled ? .primary : .secondary.opacity(0.55)
    }

    private func artworkActionBackground(isDestructive: Bool, isEnabled: Bool) -> Color {
        if isDestructive {
            return .red.opacity(isEnabled ? 0.82 : 0.35)
        }

        return .secondary.opacity(isEnabled ? 0.16 : 0.10)
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

    @ViewBuilder
    private func fileSection(_ file: AudioFile) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(file.url.lastPathComponent)
                    .font(.headline)
                #if os(macOS)
                Text(file.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            inspectorSectionLabel("File", systemImage: "doc.text")
        }
    }

    @ViewBuilder
    private func multiSelectionSection(_ files: [AudioFile]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(files.count) files selected")
                    .font(.headline)

                Text("Edits apply to all selected files. Fields you leave untouched stay as they are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            inspectorSectionLabel("Selection", systemImage: "checklist")
        }
    }

    @ViewBuilder
    private func artworkSection(_ file: AudioFile) -> some View {
        let artworkControlWidth: CGFloat = 220
        let lookupDisabledReason = artworkLookupDisabledReason(for: file)

        GroupBox {
            VStack(spacing: 16) {
                if let image = displayedArtwork(for: file) {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: artworkControlWidth, maxHeight: artworkControlWidth)
                        .cornerRadius(8)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: artworkControlWidth, height: artworkControlWidth)
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 10) {
                    chooseArtworkMenu(for: .file(file), width: artworkControlWidth)

                    artworkActionButton(
                        "Fetch Online…",
                        width: artworkControlWidth,
                        isEnabled: lookupDisabledReason == nil,
                        help: lookupDisabledReason ?? "Search iTunes artwork using the selected file metadata."
                    ) {
                        viewModel.findOnlineArtwork(for: file)
                    }

                    artworkActionButton(
                        "Clear Artwork",
                        width: artworkControlWidth,
                        role: .destructive,
                        isEnabled: hasArtwork(for: file)
                    ) {
                        viewModel.clearArtwork(for: file)
                    }
                }

                Text("Double-click the cover to add or replace artwork.")
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
                Button("Choose from Finder") {
                    viewModel.pickArtwork(for: file)
                }

                Button("Choose from Photo Library") {
                    presentPhotoLibraryArtworkPicker(for: .file(file))
                }

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
    private func multiArtworkSection(_ files: [AudioFile]) -> some View {
        let artworkControlWidth: CGFloat = 220
        let lookupDisabledReason = artworkLookupDisabledReason(for: files)

        GroupBox {
            VStack(spacing: 16) {
                Group {
                    if let image = multiDisplayedArtwork {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: artworkControlWidth, maxHeight: artworkControlWidth)
                            .cornerRadius(8)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: artworkControlWidth, height: artworkControlWidth)

                            VStack(spacing: 10) {
                                Image(systemName: multiArtworkPlaceholderSymbolName)
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)

                                Text(multiArtworkSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    chooseArtworkMenu(for: .files(files), width: artworkControlWidth)

                    artworkActionButton(
                        "Fetch Online…",
                        width: artworkControlWidth,
                        isEnabled: lookupDisabledReason == nil,
                        help: lookupDisabledReason ?? "Search iTunes artwork for the shared album metadata."
                    ) {
                        viewModel.findOnlineArtwork(for: files)
                    }

                    artworkActionButton(
                        "Clear All",
                        width: artworkControlWidth,
                        role: .destructive,
                        isEnabled: canClearMultiArtwork
                    ) {
                        viewModel.clearArtwork(for: files)
                    }
                }
                .frame(width: artworkControlWidth)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                viewModel.pickArtwork(for: files)
            }
            .contextMenu {
                Button("Choose from Finder") {
                    viewModel.pickArtwork(for: files)
                }

                Button("Choose from Photo Library") {
                    presentPhotoLibraryArtworkPicker(for: .files(files))
                }

                Button("Import from Clipboard") {
                    viewModel.importArtworkFromClipboard(for: files)
                }

                Button("Clear All Artwork") {
                    viewModel.clearArtwork(for: files)
                }
                .disabled(!canClearMultiArtwork)

                Button("Keep Current Artwork") {
                    viewModel.keepArtwork(for: files)
                }
                .disabled(!hasPendingMultiArtworkChange)
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
                editableRow(label: "Track Number", text: trackNumberFieldBinding(for: file))
                Divider()
                editableRow(label: "Total Tracks", text: trackTotalFieldBinding(for: file))
                Divider()
                editableRow(label: "Disc Number", text: discNumberFieldBinding(for: file))
                Divider()
                editableRow(label: "Total Discs", text: discTotalFieldBinding(for: file))
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
            .padding(.vertical, 3)
        } label: {
            inspectorSectionLabel("Metadata", systemImage: "tag")
        }
    }

    @ViewBuilder
    private func multiMetadataSection(_ files: [AudioFile]) -> some View {
        let merged = MergedAudioFile(files: files)

        GroupBox {
            if viewModel.multiEdit != nil {
                VStack(spacing: 6) {
                    editableRow(
                        label: "Title",
                        text: multiBinding(for: .title),
                        placeholder: viewModel.multiEdit?.placeholder(for: .title)
                    )
                    Divider()
                    editableRow(
                        label: "Artist",
                        text: multiBinding(for: .artist),
                        placeholder: viewModel.multiEdit?.placeholder(for: .artist)
                    )
                    Divider()
                    editableRow(
                        label: "Album",
                        text: multiBinding(for: .album),
                        placeholder: viewModel.multiEdit?.placeholder(for: .album)
                    )
                    Divider()
                    editableRow(
                        label: "Composer",
                        text: multiBinding(for: .composer),
                        placeholder: viewModel.multiEdit?.placeholder(for: .composer)
                    )
                    Divider()
                    editableRow(
                        label: "Genre",
                        text: multiBinding(for: .genre),
                        placeholder: viewModel.multiEdit?.placeholder(for: .genre)
                    )
                    Divider()
                    editableRow(
                        label: "Year",
                        text: multiBinding(for: .year),
                        placeholder: viewModel.multiEdit?.placeholder(for: .year)
                    )
                    Divider()
                    editableRow(
                        label: "Track Number",
                        text: multiBinding(for: .trackNumber),
                        placeholder: viewModel.multiEdit?.placeholder(for: .trackNumber)
                    )
                    Divider()
                    editableRow(
                        label: "Total Tracks",
                        text: multiBinding(for: .trackTotal),
                        placeholder: viewModel.multiEdit?.placeholder(for: .trackTotal)
                    )
                    Divider()
                    editableRow(
                        label: "Disc Number",
                        text: multiBinding(for: .discNumber),
                        placeholder: viewModel.multiEdit?.placeholder(for: .discNumber)
                    )
                    Divider()
                    editableRow(
                        label: "Total Discs",
                        text: multiBinding(for: .discTotal),
                        placeholder: viewModel.multiEdit?.placeholder(for: .discTotal)
                    )
                    Divider()
                    editableRow(
                        label: "Comment",
                        text: multiBinding(for: .comment),
                        placeholder: viewModel.multiEdit?.placeholder(for: .comment)
                    )
                    Divider()
                    editableRow(
                        label: "Album Artist",
                        text: multiBinding(for: .albumArtist),
                        placeholder: viewModel.multiEdit?.placeholder(for: .albumArtist)
                    )
                    Divider()
                    editableRow(
                        label: "Release Date",
                        text: multiBinding(for: .releaseDate),
                        placeholder: viewModel.multiEdit?.placeholder(for: .releaseDate)
                    )
                    Divider()
                    editableRow(
                        label: "Publisher",
                        text: multiBinding(for: .publisher),
                        placeholder: viewModel.multiEdit?.placeholder(for: .publisher)
                    )
                    Divider()
                    editableRow(
                        label: "Copyright",
                        text: multiBinding(for: .copyright),
                        placeholder: viewModel.multiEdit?.placeholder(for: .copyright)
                    )
                    Divider()
                    multiExplicitRow(
                        label: "Explicit",
                        selection: multiExplicitBinding,
                        currentValueDescription: viewModel.multiEdit?.explicitCurrentValueDescription ?? "Values differ"
                    )
                    Divider()
                    metadataRow(label: "Credits", value: merged.credits)
                }
                .padding(.vertical, 3)
            }
        } label: {
            inspectorSectionLabel("Metadata", systemImage: "tag")
        }
    }

    @ViewBuilder
    private func technicalSection(_ file: AudioFile) -> some View {
        GroupBox {
            VStack(spacing: 6) {
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
            .padding(.vertical, 3)
        } label: {
            inspectorSectionLabel("Technical Info", systemImage: "waveform")
        }
    }

    private func inspectorSectionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.10))
                )

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(.secondary)
        }
        .textCase(.uppercase)
        .symbolRenderingMode(.monochrome)
    }

    @ViewBuilder
    private func metadataRow(
        label: String,
        value: String?
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            FlexibleScrollableInspectorValueText(text: value ?? "—")
                .frame(maxWidth: .infinity, minHeight: inspectorRowContentHeight, alignment: .trailing)
        }
        .padding(.vertical, inspectorRowVerticalPadding)
    }

    @ViewBuilder
    private func editableRow(
        label: String,
        text: Binding<String>,
        placeholder: String? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            InspectorEditableValueField(text: text, placeholder: placeholder) {
                inspectorQuickLabel = label
                inspectorQuickText = text.wrappedValue
                inspectorQuickBinding = text
                isInspectorQuickPresented = true
            }
            .frame(maxWidth: .infinity, minHeight: inspectorRowContentHeight, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            inspectorQuickLabel = label
            inspectorQuickText = text.wrappedValue
            inspectorQuickBinding = text
            isInspectorQuickPresented = true
        }
        .padding(.vertical, inspectorRowVerticalPadding)
    }

    @ViewBuilder
    private func multiExplicitRow(
        label: String,
        selection: Binding<MultiFileExplicitEditState>,
        currentValueDescription: String
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.headline)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Picker("", selection: selection) {
                    Text("Leave As Is").tag(MultiFileExplicitEditState.keepExisting)
                    Text("Mark Explicit").tag(MultiFileExplicitEditState.markExplicit)
                    Text("Mark Clean").tag(MultiFileExplicitEditState.markClean)
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Text(currentValueDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, inspectorRowVerticalPadding)
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
        .padding(.vertical, inspectorRowVerticalPadding)
    }
}

 #if os(macOS)
struct ScrollableInspectorValueText: NSViewRepresentable {
    let text: String
    let width: CGFloat

    func makeNSView(context: Context) -> InspectorValueScrollView {
        let scrollView = InspectorValueScrollView()
        updateScrollView(scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: InspectorValueScrollView, context: Context) {
        updateScrollView(nsView)
    }

    private func updateScrollView(_ scrollView: InspectorValueScrollView) {
        scrollView.update(
            text: text,
            width: width,
            font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            textColor: .secondaryLabelColor
        )
    }
}
#else
struct ScrollableInspectorValueText: View {
    let text: String
    let width: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(minWidth: width, alignment: .trailing)
        }
    }
}
#endif

struct FlexibleScrollableInspectorValueText: View {
    let text: String

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(proxy.size.width, 1)

            ScrollableInspectorValueText(text: text, width: availableWidth)
                .frame(width: availableWidth, height: inspectorRowContentHeight, alignment: .trailing)
        }
        .frame(height: inspectorRowContentHeight)
    }
}

struct InspectorEditableValueField: View {
    @Binding var text: String
    var placeholder: String? = nil
    let onDoubleClick: () -> Void

    @FocusState private var isFocused: Bool
    @State private var isEditing = false

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $text, prompt: placeholder.map(Text.init))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .focused($isFocused)
                    .onAppear {
                        isFocused = true
                    }
                    .onSubmit {
                        isEditing = false
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            isEditing = false
                        }
                    }
            } else {
                FlexibleScrollableInspectorValueText(text: displayText)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditing = true
                    }
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                onDoubleClick()
                            }
                    )
            }
        }
    }

    private var displayText: String {
        if !text.isEmpty {
            return text
        }

        if let placeholder, !placeholder.isEmpty {
            return placeholder
        }

        return "—"
    }
}

 #if os(macOS)
final class InspectorValueScrollView: NSScrollView {
    private let containerView = WheelForwardingStackView()
    private let spacerView = NSView(frame: .zero)
    private let textField = WheelForwardingLabel(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        containerView.orientation = .horizontal
        containerView.alignment = .centerY
        containerView.distribution = .fill
        containerView.spacing = 0

        spacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.setContentHuggingPriority(.required, for: .horizontal)
        textField.setContentCompressionResistancePriority(.required, for: .horizontal)

        if let cell = textField.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.usesSingleLineMode = true
            cell.lineBreakMode = .byClipping
        }

        containerView.addArrangedSubview(spacerView)
        containerView.addArrangedSubview(textField)

        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = false
        hasHorizontalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .automatic
        verticalScrollElasticity = .none
        documentView = containerView
        horizontalScroller?.alphaValue = 0.001
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String, width: CGFloat, font: NSFont, textColor: NSColor) {
        horizontalScroller?.alphaValue = 0.001

        let textDidChange = textField.stringValue != text

        if textField.stringValue != text {
            textField.stringValue = text
        }

        if textField.font != font {
            textField.font = font
        }

        if textField.textColor != textColor {
            textField.textColor = textColor
        }

        textField.sizeToFit()

        let contentWidth = max(width, ceil(textField.fittingSize.width))
        let contentHeight = inspectorRowContentHeight

        containerView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        frame.size = NSSize(width: width, height: contentHeight)

        let maxOffsetX = max(contentWidth - width, 0)
        let currentOffsetX = textDidChange ? maxOffsetX : min(contentView.bounds.origin.x, maxOffsetX)
        contentView.scroll(to: NSPoint(x: currentOffsetX, y: 0))
        reflectScrolledClipView(contentView)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let documentView else {
            super.scrollWheel(with: event)
            return
        }

        let maxOffsetX = max(documentView.frame.width - contentView.bounds.width, 0)
        guard maxOffsetX > 0 else {
            super.scrollWheel(with: event)
            return
        }

        let preciseScale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        let horizontalDelta = abs(deltaX) > 0.01 ? deltaX : deltaY

        guard abs(horizontalDelta) > 0.01 else {
            super.scrollWheel(with: event)
            return
        }

        let currentOffsetX = contentView.bounds.origin.x
        let proposedOffsetX = currentOffsetX - (horizontalDelta * preciseScale)
        let clampedOffsetX = min(max(proposedOffsetX, 0), maxOffsetX)

        guard clampedOffsetX != currentOffsetX else {
            super.scrollWheel(with: event)
            return
        }

        contentView.scroll(to: NSPoint(x: clampedOffsetX, y: 0))
        reflectScrolledClipView(contentView)
    }
}

final class WheelForwardingStackView: NSStackView {
    override func scrollWheel(with event: NSEvent) {
        enclosingScrollView?.scrollWheel(with: event)
    }
}

final class WheelForwardingLabel: NSTextField {
    override func scrollWheel(with event: NSEvent) {
        enclosingScrollView?.scrollWheel(with: event)
    }
}
 #endif
