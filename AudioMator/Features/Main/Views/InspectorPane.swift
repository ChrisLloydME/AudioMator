import SwiftUI
import PhotosUI
import AppKit
import TagLibAudioMetadata

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
    let onHideInspector: () -> Void

    @State private var inspectorQuickLabel: String = ""
    @State private var inspectorQuickText: String = ""
    @State private var inspectorQuickBinding: Binding<String>? = nil
    @State private var inspectorQuickStartedMixed: Bool = false
    @State private var inspectorQuickDraftScope: InspectorActiveDraftScope? = nil
    @State private var isInspectorQuickPresented: Bool = false
    @State private var photoLibraryArtworkTarget: ArtworkImportTarget?
    @State private var photoLibraryArtworkIntent: ArtworkTransferIntent?
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
        viewModel.selectedFiles
    }

    private func currentEdit(for file: AudioFile) -> SingleFileEditModel? {
        viewModel.editSourceFileID == file.id ? viewModel.edit : nil
    }

    private func updateEdit(
        for file: AudioFile,
        mutate: (inout SingleFileEditModel) -> Void
    ) {
        var model = currentEdit(for: file) ?? SingleFileEditModel(from: file)
        mutate(&model)
        viewModel.edit = model
        if viewModel.editSourceFileID != file.id {
            viewModel.editSourceFileID = file.id
        }
    }

    private func binding(
        for file: AudioFile,
        keyPath: WritableKeyPath<SingleFileEditModel, String>
    ) -> Binding<String> {
        Binding<String>(
            get: {
                currentEdit(for: file)?[keyPath: keyPath] ?? SingleFileEditModel(from: file)[keyPath: keyPath]
            },
            set: { newValue in
                let currentValue = currentEdit(for: file)?[keyPath: keyPath] ?? SingleFileEditModel(from: file)[keyPath: keyPath]
                guard newValue != currentValue else { return }
                updateEdit(for: file) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func explicitSelectionBinding(for file: AudioFile) -> Binding<ExplicitInspectorSelection> {
        Binding<ExplicitInspectorSelection>(
            get: {
                if let edit = currentEdit(for: file) {
                    return ExplicitInspectorSelection(
                        contentAdvisory: edit.contentAdvisory,
                        rawValue: file.advisoryRawValue
                    )
                }
                return ExplicitInspectorSelection(
                    contentAdvisory: file.contentAdvisory,
                    rawValue: file.advisoryRawValue
                )
            },
            set: { newValue in
                // Selecting a preserved unknown native code is not an edit.
                guard case .unknown = newValue else {
                    updateEdit(for: file) { model in
                        model.contentAdvisory = newValue.contentAdvisory
                        model.clearsUnknownAdvisory =
                            newValue == .unset && file.advisoryRawValue != nil
                    }
                    return
                }
            }
        )
    }

    private func trackNumberFieldBinding(for file: AudioFile) -> Binding<String> {
        Binding(
            get: { currentEdit(for: file)?.trackNumberFieldText ?? SingleFileEditModel(from: file).trackNumberFieldText },
            set: { newValue in
                let currentValue = currentEdit(for: file)?.trackNumberFieldText ?? SingleFileEditModel(from: file).trackNumberFieldText
                guard newValue != currentValue else { return }
                updateEdit(for: file) { $0.setTrackNumberFieldText(newValue) }
            }
        )
    }

    private func trackTotalFieldBinding(for file: AudioFile) -> Binding<String> {
        Binding(
            get: { currentEdit(for: file)?.trackTotalFieldText ?? SingleFileEditModel(from: file).trackTotalFieldText },
            set: { newValue in
                let currentValue = currentEdit(for: file)?.trackTotalFieldText ?? SingleFileEditModel(from: file).trackTotalFieldText
                guard newValue != currentValue else { return }
                updateEdit(for: file) { $0.setTrackTotalFieldText(newValue) }
            }
        )
    }

    private func discNumberFieldBinding(for file: AudioFile) -> Binding<String> {
        Binding(
            get: { currentEdit(for: file)?.discNumberFieldText ?? SingleFileEditModel(from: file).discNumberFieldText },
            set: { newValue in
                let currentValue = currentEdit(for: file)?.discNumberFieldText ?? SingleFileEditModel(from: file).discNumberFieldText
                guard newValue != currentValue else { return }
                updateEdit(for: file) { $0.setDiscNumberFieldText(newValue) }
            }
        )
    }

    private func discTotalFieldBinding(for file: AudioFile) -> Binding<String> {
        Binding(
            get: { currentEdit(for: file)?.discTotalFieldText ?? SingleFileEditModel(from: file).discTotalFieldText },
            set: { newValue in
                let currentValue = currentEdit(for: file)?.discTotalFieldText ?? SingleFileEditModel(from: file).discTotalFieldText
                guard newValue != currentValue else { return }
                updateEdit(for: file) { $0.setDiscTotalFieldText(newValue) }
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
                guard Self.shouldApplyMultiEditText(newValue, for: field, in: current) else { return }
                current.setText(newValue, for: field)
                viewModel.multiEdit = current
            }
        )
    }

    static func shouldApplyMultiEditText(
        _ newValue: String,
        for field: MultiFileEditableTextField,
        in current: MultiFileEditModel
    ) -> Bool {
        let isUntouchedMixed = current.isUntouchedMixedTextField(field)
        return isUntouchedMixed || newValue != current.text(for: field)
    }

    enum QuickEditCommitDecision: Equatable {
        case apply(String)
        case skipUntouchedMixedClear
        case discardStaleScope
    }

    static func quickEditCommitDecision(
        startedMixed: Bool,
        text: String,
        allowClearingUntouchedMixed: Bool,
        expectedScope: InspectorActiveDraftScope?,
        currentScope: InspectorActiveDraftScope?
    ) -> QuickEditCommitDecision {
        guard let expectedScope, currentScope == expectedScope else {
            return .discardStaleScope
        }
        if startedMixed && text.isEmpty && !allowClearingUntouchedMixed {
            return .skipUntouchedMixedClear
        }
        return .apply(text)
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

    private func hasArtwork(for file: AudioFile) -> Bool {
        switch currentEdit(for: file)?.artworkEditAction ?? .unchanged {
        case .unchanged: return file.artworkData != nil
        case .replace: return true
        case .remove: return false
        }
    }

    private func artworkLookupDisabledReason(for file: AudioFile) -> String? {
        viewModel.artworkLookupDisabledReason(for: file)
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
        let selectedFiles = self.selectedFiles
        Group {
            if let pendingReview = viewModel.inspectorPendingReview {
                pendingReviewSection(pendingReview)
            } else if selectedFiles.count == 1, let file = selectedFiles.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        fileSection(file)
                        artworkSection(file)
                        metadataSection(file)
                        technicalSection(file)
                    }
                    .padding()
                }
                .audiomatorScrollEdgeEffect(.soft, for: .vertical)
            } else if selectedFiles.count > 1 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        multiSelectionSection(selectedFiles)
                        multiArtworkSection(selectedFiles)
                        multiMetadataSection(selectedFiles)
                    }
                    .padding()
                }
                .audiomatorScrollEdgeEffect(.soft, for: .vertical)
            } else {
                ContentUnavailableView(
                    "Select a File",
                    systemImage: "music.quarternote.3"
                )
            }
        }
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if state.visibleToolbarButtons.contains(.cancelEdits) {
                    Button("Cancel", action: viewModel.cancelEditing)
                        .disabled(viewModel.selectedAudioIDs.isEmpty && !viewModel.hasInspectorPendingReview)
                }

                if state.visibleToolbarButtons.contains(.saveEdits) {
                    Button("Save", action: viewModel.saveInspectorEdits)
                        .disabled(
                            viewModel.selectedAudioIDs.isEmpty
                                || viewModel.metadataSaveProgress != nil
                                || viewModel.isInspectorSaveSuspended
                        )
                }

                Button(action: onHideInspector) {
                    Label("Hide Inspector", systemImage: "sidebar.right")
                        .labelStyle(.iconOnly)
                }
                .help("Hide Inspector")
            }
        }
        .sheet(isPresented: $isInspectorQuickPresented) {
            inspectorQuickEditSheet
        }
        .onChange(of: viewModel.activeInspectorDraftScope) { _, newScope in
            if isInspectorQuickPresented, newScope != inspectorQuickDraftScope {
                dismissInspectorQuickEdit()
            }
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

    private var inspectorQuickEditSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Edit Metadata Field")
                    .font(.title3)
                    .fontWeight(.semibold)

                if selectedFiles.count > 1 {
                    Text("Update the selected metadata field for every file in the current selection.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Field")
                    .font(.headline)

                Text(inspectorQuickLabel)
                    .font(.system(size: 13, weight: .medium))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(inspectorQuickLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Value")
                    .font(.headline)

                MetadataFieldValueEditor(
                    text: $inspectorQuickText,
                    placeholder: L10n.string("Enter the metadata value")
                )
                .accessibilityLabel("Metadata Value")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack(spacing: 8) {
                if inspectorQuickStartedMixed && inspectorQuickText.isEmpty {
                    Button("Clear for Selected Files", role: .destructive) {
                        commitInspectorQuickEdit(allowClearingUntouchedMixed: true)
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismissInspectorQuickEdit()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    commitInspectorQuickEdit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(inspectorQuickStartedMixed && inspectorQuickText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 860, height: 540)
    }

    private func presentInspectorQuickEdit(
        label: String,
        text: Binding<String>,
        isUntouchedMixed: Bool
    ) {
        guard !isInspectorQuickPresented,
              let activeScope = viewModel.activeInspectorDraftScope else {
            return
        }
        inspectorQuickLabel = label
        inspectorQuickText = text.wrappedValue
        inspectorQuickBinding = text
        inspectorQuickStartedMixed = isUntouchedMixed
        inspectorQuickDraftScope = activeScope
        isInspectorQuickPresented = true
    }

    private func dismissInspectorQuickEdit() {
        isInspectorQuickPresented = false
        inspectorQuickBinding = nil
        inspectorQuickStartedMixed = false
        inspectorQuickDraftScope = nil
    }

    private func commitInspectorQuickEdit(allowClearingUntouchedMixed: Bool = false) {
        let decision = Self.quickEditCommitDecision(
            startedMixed: inspectorQuickStartedMixed,
            text: inspectorQuickText,
            allowClearingUntouchedMixed: allowClearingUntouchedMixed,
            expectedScope: inspectorQuickDraftScope,
            currentScope: viewModel.activeInspectorDraftScope
        )
        if case .apply(let value) = decision {
            inspectorQuickBinding?.wrappedValue = value
        }
        dismissInspectorQuickEdit()
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
        // Validate artwork write support upfront (matching Finder/Clipboard)
        // before opening PhotosPicker or normalizing image bytes.
        switch target {
        case .file(let file):
            guard viewModel.validateArtworkEditingSupport(for: file) else { return }
        case .files(let files):
            guard viewModel.validateArtworkEditingSupport(for: files) else { return }
        }

        // The destination draft is authorized before the picker is presented;
        // the intent crosses the PhotosPicker/loadTransferable suspension
        // untouched and is revalidated at commit.
        let intent: ArtworkTransferIntent?
        switch target {
        case .file(let file):
            intent = viewModel.beginPhotoLibraryArtworkImport(for: file)
        case .files(let files):
            intent = viewModel.beginPhotoLibraryArtworkImport(for: files)
        }

        guard let intent else {
            switch target {
            case .file(let file):
                viewModel.presentArtworkTransferNoDestination(for: [file])
            case .files(let files):
                viewModel.presentArtworkTransferNoDestination(for: files)
            }
            return
        }

        photoLibraryArtworkTarget = target
        photoLibraryArtworkIntent = intent

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
        guard let item, let intent = photoLibraryArtworkIntent else { return }
        selectedPhotoLibraryArtworkItem = nil
        photoLibraryArtworkTarget = nil
        photoLibraryArtworkIntent = nil

        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                // Only the newest captured intent may stage; an older
                // completion is inert because the view model revalidates it.
                viewModel.finishPhotoLibraryArtworkImport(data: data, intent: intent)
            }
        }
    }

    // MARK: - Pending review (F3-b)

    @ViewBuilder
    private func pendingReviewSection(_ review: InspectorPendingReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Unsaved Edits Need Review")
                    .font(.headline)

                Text(String(localized: "This draft captured files that are no longer available. The captured values are kept; Save is suspended until every file is available again and you resume editing, or you discard the edits."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(Array(viewModel.inspectorPendingReviewCapturedSummaries().enumerated()), id: \.offset) { _, summary in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(summary.fileName)
                                .font(.subheadline.weight(.semibold))
                            if summary.values.isEmpty {
                                Text(String(localized: "No inspectable field changes."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(summary.values, id: \.self) { value in
                                    Text(value)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: 10) {
                    Button(String(localized: "Resume Editing")) {
                        _ = viewModel.resumeInspectorPendingReview()
                    }
                    .disabled(!viewModel.isInspectorPendingReviewResumable)

                    Button(String(localized: "Discard Edits"), role: .destructive) {
                        viewModel.discardInspectorPendingReview()
                    }
                }

                if !viewModel.isInspectorPendingReviewResumable {
                    Text(String(localized: "Re-import or restore every captured file, then resume editing. Values are not transferred to other files."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
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
                InspectorArtworkPreviewView(preview: viewModel.inspectorArtworkPreview) {
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
                InspectorArtworkPreviewView(preview: viewModel.inspectorArtworkPreview) {
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
        let fields = visibleInspectorMetadataFields

        GroupBox {
            VStack(spacing: 6) {
                ForEach(Array(fields.enumerated()), id: \.element) { index, field in
                    if index > 0 {
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        metadataFieldRow(field, file: file)
                        if let reason = viewModel.metadataFieldUnsupportedReason(field, in: [file]) {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(viewModel.metadataFieldUnsupportedReason(field, in: [file]) != nil)
                }


            }
            .padding(.vertical, 3)
        } label: {
            inspectorSectionLabel("Metadata", systemImage: "tag")
        }
    }

    @ViewBuilder
    private func multiMetadataSection(_ files: [AudioFile]) -> some View {
        let merged = MergedAudioFile(files: files)
        let fields = visibleInspectorMetadataFields

        GroupBox {
            if viewModel.multiEdit != nil {
                VStack(spacing: 6) {
                    ForEach(Array(fields.enumerated()), id: \.element) { index, field in
                        if index > 0 {
                            Divider()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            multiMetadataFieldRow(field, merged: merged)
                            if let reason = viewModel.metadataFieldUnsupportedReason(field, in: files) {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(viewModel.metadataFieldUnsupportedReason(field, in: files) != nil)
                    }
                }
                .padding(.vertical, 3)
            }
        } label: {
            inspectorSectionLabel("Metadata", systemImage: "tag")
        }
    }

    private var visibleInspectorMetadataFields: [InspectorMetadataField] {
        state.orderedVisibleInspectorMetadataFields
    }

    @ViewBuilder
    private func metadataFieldRow(_ field: InspectorMetadataField, file: AudioFile) -> some View {
        switch field {
        case .title:
            editableRow(label: field.displayName, text: binding(for: file, keyPath: \.title))
        case .artist:
            editableRow(label: field.displayName, text: binding(for: file, keyPath: \.artist))
        case .album:
            editableRow(label: field.displayName, text: binding(for: file, keyPath: \.album))
        case .composer:
            editableRow(label: field.displayName, text: binding(for: file, keyPath: \.composer))
        case .genre:
            editableRow(label: field.displayName, text: binding(for: file, keyPath: \.genre))
        case .year:
            editableRow(
                label: field.displayName, text: binding(for: file, keyPath: \.year), dateField: field
            )
        case .date:
            editableRow(
                label: field.displayName, text: binding(for: file, keyPath: \.date), dateField: field
            )
        case .releaseDate:
            editableRow(
                label: field.displayName, text: binding(for: file, keyPath: \.releaseDate), dateField: field
            )
        case .originalReleaseDate:
            editableRow(
                label: field.displayName, text: binding(for: file, keyPath: \.originalReleaseDate), dateField: field
            )
        case .trackNumber:
            editableRow(
                label: field.displayName,
                text: trackNumberFieldBinding(for: file),
                captureRevertSnapshot: trackPairRevertSnapshot(for: file)
            )
        case .totalTracks:
            editableRow(
                label: field.displayName,
                text: trackTotalFieldBinding(for: file),
                captureRevertSnapshot: trackPairRevertSnapshot(for: file)
            )
        case .discNumber:
            editableRow(
                label: field.displayName,
                text: discNumberFieldBinding(for: file),
                captureRevertSnapshot: discPairRevertSnapshot(for: file)
            )
        case .totalDiscs:
            editableRow(
                label: field.displayName,
                text: discTotalFieldBinding(for: file),
                captureRevertSnapshot: discPairRevertSnapshot(for: file)
            )
        case .comment:
            editableRow(label: field.displayName, text: binding(for: file, keyPath: \.comment))
        case .albumArtist:
            editableRow(label: field.displayName, text: binding(for: file, keyPath: \.albumArtist))
        case .contentGroup:
            editableRow(label: field.displayName, text: binding(for: file, keyPath: \.contentGroup))
        case .grouping:
            editableRow(label: field.displayName, text: binding(for: file, keyPath: \.grouping))
        case .work:
            editableRow(label: field.displayName, text: binding(for: file, keyPath: \.work))
        case .publisher:
            editableRow(label: field.displayName, text: binding(for: file, keyPath: \.publisher))
        case .copyright:
            editableRow(label: field.displayName, text: binding(for: file, keyPath: \.copyright))
        case .explicit:
            explicitRow(
                label: field.displayName,
                selection: explicitSelectionBinding(for: file),
                identity: file.id
            )
        case .credits:
            metadataRow(label: field.displayName, value: file.credits)
        }
    }

    private func trackPairRevertSnapshot(for file: AudioFile) -> () -> (() -> Void) {
        {
            let snapshot = (currentEdit(for: file) ?? SingleFileEditModel(from: file)).trackPairSnapshot
            return {
                updateEdit(for: file) { $0.restoreTrackPair(snapshot) }
            }
        }
    }

    private func discPairRevertSnapshot(for file: AudioFile) -> () -> (() -> Void) {
        {
            let snapshot = (currentEdit(for: file) ?? SingleFileEditModel(from: file)).discPairSnapshot
            return {
                updateEdit(for: file) { $0.restoreDiscPair(snapshot) }
            }
        }
    }

    @ViewBuilder
    private func multiEditableRow(
        label: String,
        field: MultiFileEditableTextField,
        dateField: InspectorMetadataField? = nil
    ) -> some View {
        editableRow(
            label: label,
            text: multiBinding(for: field),
            placeholder: viewModel.multiEdit?.placeholder(for: field),
            isUntouchedMixed: viewModel.multiEdit?.isUntouchedMixedTextField(field) ?? false,
            dateField: dateField,
            captureRevertSnapshot: {
                let snapshot = viewModel.multiEdit?.textFieldRevertSnapshot(for: field)
                return {
                    guard let snapshot, var current = viewModel.multiEdit else { return }
                    current.restoreTextField(snapshot)
                    viewModel.multiEdit = current
                }
            }
        )
    }

    @ViewBuilder
    private func multiMetadataFieldRow(_ field: InspectorMetadataField, merged: MergedAudioFile) -> some View {
        switch field {
        case .title:
            multiEditableRow(label: field.displayName, field: .title)
        case .artist:
            multiEditableRow(label: field.displayName, field: .artist)
        case .album:
            multiEditableRow(label: field.displayName, field: .album)
        case .composer:
            multiEditableRow(label: field.displayName, field: .composer)
        case .genre:
            multiEditableRow(label: field.displayName, field: .genre)
        case .year:
            multiEditableRow(label: field.displayName, field: .year, dateField: field)
        case .date:
            multiEditableRow(label: field.displayName, field: .date, dateField: field)
        case .releaseDate:
            multiEditableRow(label: field.displayName, field: .releaseDate, dateField: field)
        case .originalReleaseDate:
            multiEditableRow(label: field.displayName, field: .originalReleaseDate, dateField: field)
        case .trackNumber:
            multiEditableRow(label: field.displayName, field: .trackNumber)
        case .totalTracks:
            multiEditableRow(label: field.displayName, field: .trackTotal)
        case .discNumber:
            multiEditableRow(label: field.displayName, field: .discNumber)
        case .totalDiscs:
            multiEditableRow(label: field.displayName, field: .discTotal)
        case .comment:
            multiEditableRow(label: field.displayName, field: .comment)
        case .albumArtist:
            multiEditableRow(label: field.displayName, field: .albumArtist)
        case .contentGroup:
            multiEditableRow(label: field.displayName, field: .contentGroup)
        case .grouping:
            multiEditableRow(label: field.displayName, field: .grouping)
        case .work:
            multiEditableRow(label: field.displayName, field: .work)
        case .publisher:
            multiEditableRow(label: field.displayName, field: .publisher)
        case .copyright:
            multiEditableRow(label: field.displayName, field: .copyright)
        case .explicit:
            multiExplicitRow(
                label: field.displayName,
                selection: multiExplicitBinding,
                currentValueDescription: viewModel.multiEdit?.explicitCurrentValueDescription ?? "Values differ"
            )
        case .credits:
            metadataRow(label: field.displayName, value: merged.credits)
        }
    }

    @ViewBuilder
    private func technicalSection(_ file: AudioFile) -> some View {
        GroupBox {
            VStack(spacing: 6) {
                metadataRow(label: MetadataFieldGuide.displayName(forReadOnlyField: "duration"), value: formatDuration(file.duration))
                Divider()
                metadataRow(label: MetadataFieldGuide.displayName(forReadOnlyField: "bitrate"), value: "\(file.bitrate) kbps")
                Divider()
                metadataRow(label: MetadataFieldGuide.displayName(forReadOnlyField: "sampleRate"), value: formatSampleRate(file.sampleRate))
                Divider()
                metadataRow(label: MetadataFieldGuide.displayName(forReadOnlyField: "channels"), value: "\(file.channels)")
                Divider()
                metadataRow(label: MetadataFieldGuide.displayName(forReadOnlyField: "format"), value: file.format)
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
    private func dateButton(for field: InspectorMetadataField, text: Binding<String>) -> some View {
        if let key = field.metadataFieldKey,
           let eligibility = MetadataDatePickerEligibilityResolver.inspectorEligibility(for: key, files: selectedFiles) {
            MetadataDatePickerButton(
                scope: viewModel.currentInspectorDatePickerScope(),
                title: field.displayName,
                value: text.wrappedValue,
                format: eligibility.destinationFormat,
                onApply: { scope, value in
                    viewModel.applyInspectorDatePickerValue(
                        value,
                        for: field,
                        expectedScope: scope,
                        expectedEligibility: eligibility
                    )
                }
            ) {
                Image(systemName: "calendar")
                    .frame(minWidth: 20, minHeight: inspectorRowContentHeight)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Choose \(field.displayName)"))
            .accessibilityLabel(Text("Choose \(field.displayName)"))
        }
    }

    @ViewBuilder
    private func editableRow(
        label: String,
        text: Binding<String>,
        placeholder: String? = nil,
        isUntouchedMixed: Bool = false,
        dateField: InspectorMetadataField? = nil,
        captureRevertSnapshot: (() -> (() -> Void))? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            InspectorEditableValueField(
                text: text,
                placeholder: placeholder,
                activeScope: viewModel.activeInspectorDraftScope,
                captureRevertSnapshot: captureRevertSnapshot
            ) {
                presentInspectorQuickEdit(
                    label: label,
                    text: text,
                    isUntouchedMixed: isUntouchedMixed
                )
            }
            .frame(maxWidth: .infinity, minHeight: inspectorRowContentHeight, alignment: .trailing)
            if let dateField {
                dateButton(for: dateField, text: text)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            presentInspectorQuickEdit(
                label: label,
                text: text,
                isUntouchedMixed: isUntouchedMixed
            )
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
            VStack(alignment: .trailing, spacing: 6) {
                Picker("", selection: selection) {
                    Text(keepExistingExplicitDisplayName(currentValueDescription))
                        .tag(MultiFileExplicitEditState.keepExisting)
                    Text(L10n.string("Unset"))
                        .tag(MultiFileExplicitEditState.set(nil))
                    ForEach(ContentAdvisory.inspectorSelectionOrder) { advisory in
                        Text(advisory.displayName)
                            .tag(MultiFileExplicitEditState.set(advisory))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 120, alignment: .trailing)
                .id("multi-explicit-\(selection.wrappedValue.id)-\(currentValueDescription)")

                Text(currentValueDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, inspectorRowVerticalPadding)
    }

    private func keepExistingExplicitDisplayName(_ currentValueDescription: String) -> String {
        for advisory in ContentAdvisory.allCases where currentValueDescription == advisory.currentValueDescription {
            return advisory.displayName
        }
        if currentValueDescription == L10n.string("Current value: Unset") {
            return L10n.string("Unset")
        }
        return currentValueDescription
    }

    @ViewBuilder
    private func explicitRow(
        label: String,
        selection: Binding<ExplicitInspectorSelection>,
        identity: AudioFile.ID
    ) -> some View {
        HStack {
            Text(label)
                .font(.headline)
            Spacer()
            Picker("", selection: selection) {
                if case .unknown(let rawValue) = selection.wrappedValue {
                    Text(ExplicitInspectorSelection.unknown(rawValue).displayName)
                        .tag(ExplicitInspectorSelection.unknown(rawValue))
                }
                ForEach(ExplicitInspectorSelection.inspectorSelectionOrder) { option in
                    Text(option.displayName)
                        .tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 120, alignment: .trailing)
            .id("explicit-\(identity)-\(selection.wrappedValue.id)")
        }
        .padding(.vertical, inspectorRowVerticalPadding)
    }
}

struct ScrollableInspectorValueText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> InspectorValueScrollView {
        let scrollView = InspectorValueScrollView()
        updateScrollView(scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: InspectorValueScrollView, context: Context) {
        updateScrollView(nsView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: InspectorValueScrollView, context: Context) -> CGSize? {
        let width: CGFloat
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            width = max(proposedWidth, 1)
        } else {
            width = max(nsView.measuredTextWidth, 1)
        }
        return CGSize(width: width, height: inspectorRowContentHeight)
    }

    private func updateScrollView(_ scrollView: InspectorValueScrollView) {
        scrollView.update(
            text: text,
            font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            textColor: .secondaryLabelColor
        )
    }
}

struct FlexibleScrollableInspectorValueText: View {
    let text: String

    var body: some View {
        ScrollableInspectorValueText(text: text)
            .frame(
                maxWidth: .infinity,
                minHeight: inspectorRowContentHeight,
                maxHeight: inspectorRowContentHeight,
                alignment: .trailing
            )
    }
}

struct InspectorInlineDoubleClickHandoff: Equatable {
    struct Anchor: Equatable {
        let timestamp: TimeInterval
        let windowNumber: Int
        let locationInWindow: CGPoint
    }

    private(set) var anchor: Anchor?

    static let maximumDistance: CGFloat = 6

    mutating func begin(
        at timestamp: TimeInterval,
        windowNumber: Int,
        locationInWindow: CGPoint
    ) {
        anchor = Anchor(
            timestamp: timestamp,
            windowNumber: windowNumber,
            locationInWindow: locationInWindow
        )
    }

    mutating func reset() {
        anchor = nil
    }

    /// Evaluates a subsequent left-mouse-down while inline editing is active
    /// and untouched. Always disarms once evaluated.
    mutating func consumeLeftMouseDown(
        clickCount: Int,
        timestamp: TimeInterval,
        windowNumber: Int,
        locationInWindow: CGPoint,
        doubleClickInterval: TimeInterval,
        hasMutated: Bool
    ) -> Bool {
        defer { anchor = nil }
        guard !hasMutated,
              let anchor,
              clickCount >= 2,
              windowNumber == anchor.windowNumber else {
            return false
        }

        let elapsed = timestamp - anchor.timestamp
        guard elapsed >= 0, elapsed <= doubleClickInterval else {
            return false
        }

        let distance = hypot(
            locationInWindow.x - anchor.locationInWindow.x,
            locationInWindow.y - anchor.locationInWindow.y
        )
        return distance <= Self.maximumDistance
    }
}

struct InspectorEditableValueField: View {
    @Binding var text: String
    var placeholder: String? = nil
    var activeScope: InspectorActiveDraftScope? = nil
    var captureRevertSnapshot: (() -> (() -> Void))? = nil
    let onDoubleClick: () -> Void

    @FocusState private var isFocused: Bool
    @State private var isEditing = false
    @State private var editingScope: InspectorActiveDraftScope? = nil
    @State private var revertInlineEdit: (() -> Void)? = nil
    @State private var hasMutatedDuringSession = false
    @State private var doubleClickHandoff = InspectorInlineDoubleClickHandoff()
    @State private var doubleClickMonitor: Any? = nil

    var body: some View {
        ZStack(alignment: .trailing) {
            FlexibleScrollableInspectorValueText(text: displayText)
                .opacity(isEditing ? 0 : 1)
                .allowsHitTesting(!isEditing)
                .contentShape(Rectangle())
                .onTapGesture {
                    beginInlineEditing()
                }

            if isEditing {
                TextField("", text: inlineTextBinding, prompt: placeholder.map(Text.init))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: inspectorRowContentHeight,
                        maxHeight: inspectorRowContentHeight,
                        alignment: .trailing
                    )
                    .focused($isFocused)
                    .onAppear {
                        isFocused = true
                    }
                    .onSubmit {
                        finishEditing()
                    }
                    .onExitCommand {
                        cancelInlineEditing()
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            finishEditing()
                        }
                    }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: inspectorRowContentHeight,
            maxHeight: inspectorRowContentHeight,
            alignment: .trailing
        )
        .onChange(of: activeScope) { _, newScope in
            if isEditing, let editingScope, newScope != editingScope {
                finishEditing()
            }
        }
        .onDisappear {
            teardownDoubleClickMonitor()
        }
    }

    private var inlineTextBinding: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                guard isEditing else { return }
                if let editingScope, activeScope != editingScope {
                    finishEditing()
                    return
                }
                guard newValue != text else { return }
                hasMutatedDuringSession = true
                teardownDoubleClickMonitor()
                text = newValue
            }
        )
    }

    private func beginInlineEditing() {
        guard !isEditing else { return }
        if activeScope == nil && captureRevertSnapshot != nil {
            return
        }

        editingScope = activeScope
        hasMutatedDuringSession = false
        if let captureRevertSnapshot {
            revertInlineEdit = captureRevertSnapshot()
        } else {
            let initialText = text
            revertInlineEdit = {
                text = initialText
            }
        }
        isEditing = true
        armDoubleClickHandoff()
    }

    private func armDoubleClickHandoff() {
        teardownDoubleClickMonitor()
        guard let event = NSApp.currentEvent else { return }
        doubleClickHandoff.begin(
            at: event.timestamp,
            windowNumber: event.windowNumber,
            locationInWindow: event.locationInWindow
        )

        doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { incomingEvent in
            if incomingEvent.type == .keyDown {
                teardownDoubleClickMonitor()
                return incomingEvent
            }

            let shouldPromote = doubleClickHandoff.consumeLeftMouseDown(
                clickCount: incomingEvent.clickCount,
                timestamp: incomingEvent.timestamp,
                windowNumber: incomingEvent.windowNumber,
                locationInWindow: incomingEvent.locationInWindow,
                doubleClickInterval: NSEvent.doubleClickInterval,
                hasMutated: hasMutatedDuringSession
            )
            teardownDoubleClickMonitor()
            guard shouldPromote, isEditing else {
                return incomingEvent
            }

            let scopeMatches = editingScope == nil || activeScope == editingScope
            finishEditing()
            if scopeMatches {
                onDoubleClick()
            }
            return nil
        }
    }

    private func teardownDoubleClickMonitor() {
        doubleClickHandoff.reset()
        if let monitor = doubleClickMonitor {
            NSEvent.removeMonitor(monitor)
            doubleClickMonitor = nil
        }
    }

    private func cancelInlineEditing() {
        guard isEditing else { return }
        if editingScope == nil || activeScope == editingScope {
            revertInlineEdit?()
        }
        finishEditing()
    }

    private func finishEditing() {
        teardownDoubleClickMonitor()
        revertInlineEdit = nil
        editingScope = nil
        hasMutatedDuringSession = false
        isFocused = false
        isEditing = false
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

struct InspectorValueScrollInput: Equatable {
    let deltaX: CGFloat
    let deltaY: CGFloat
    let hasPreciseScrollingDeltas: Bool
    let phase: NSEvent.Phase
    let momentumPhase: NSEvent.Phase
    let currentOffsetX: CGFloat
    let maxOffsetX: CGFloat
}

enum InspectorValueScrollAction: Equatable {
    case forwardToParent
    case scrollHorizontal(to: CGFloat)
    case consume
}

struct InspectorValueScrollRouter {
    enum AxisLatch: Equatable {
        case undecided
        case horizontal
        case vertical
    }

    private(set) var axisLatch: AxisLatch = .undecided
    private(set) var didForwardPreciseBeginToParent = false
    private var hasActiveMayBegin = false
    private var undecidedDelta: CGSize = .zero

    private static let deltaThreshold: CGFloat = 0.01
    private static let axisLatchThreshold: CGFloat = 2.0
    private static let nonPreciseScale: CGFloat = 12

    mutating func handle(_ input: InspectorValueScrollInput) -> InspectorValueScrollAction {
        if !input.hasPreciseScrollingDeltas {
            resetGestureState()
            return handleDiscreteWheel(input)
        }

        return handlePreciseScroll(input)
    }

    private mutating func resetGestureState() {
        axisLatch = .undecided
        didForwardPreciseBeginToParent = false
        hasActiveMayBegin = false
        undecidedDelta = .zero
    }

    private func handleDiscreteWheel(_ input: InspectorValueScrollInput) -> InspectorValueScrollAction {
        guard input.maxOffsetX > 0 else {
            return .forwardToParent
        }

        let hasHorizontalDelta = abs(input.deltaX) > Self.deltaThreshold
        let hasVerticalDelta = abs(input.deltaY) > Self.deltaThreshold

        if hasHorizontalDelta {
            let proposed = input.currentOffsetX - (input.deltaX * Self.nonPreciseScale)
            let clamped = min(max(proposed, 0), input.maxOffsetX)
            if clamped != input.currentOffsetX {
                return .scrollHorizontal(to: clamped)
            }
            return hasVerticalDelta ? .forwardToParent : .consume
        }

        guard hasVerticalDelta else {
            return .forwardToParent
        }

        // Preserve mouse-wheel horizontal navigation over overflowing values;
        // once clamped at either edge, hand off directly to the outer vertical ScrollView.
        let proposed = input.currentOffsetX - (input.deltaY * Self.nonPreciseScale)
        let clamped = min(max(proposed, 0), input.maxOffsetX)
        guard clamped != input.currentOffsetX else {
            return .forwardToParent
        }

        return .scrollHorizontal(to: clamped)
    }

    private mutating func handlePreciseScroll(_ input: InspectorValueScrollInput) -> InspectorValueScrollAction {
        let isPhaseless = input.phase.isEmpty && input.momentumPhase.isEmpty
        if isPhaseless {
            resetGestureState()
        }

        let isMayBegin = input.phase.contains(.mayBegin)
        let isBegan = input.phase.contains(.began)
        let isNewGesture = isMayBegin || isBegan

        if isMayBegin {
            resetGestureState()
            hasActiveMayBegin = true
        } else if isBegan {
            axisLatch = .undecided
            undecidedDelta = .zero
            if hasActiveMayBegin {
                // Continue balancing the preceding .mayBegin already forwarded to the parent.
                hasActiveMayBegin = false
            } else {
                didForwardPreciseBeginToParent = false
            }
        } else {
            hasActiveMayBegin = false
        }

        let isGestureCancelled = input.phase.contains(.cancelled)
        let isMomentumEnding = input.momentumPhase.contains(.ended) || input.momentumPhase.contains(.cancelled)

        guard input.maxOffsetX > 0 else {
            if input.phase.contains(.ended) || isGestureCancelled || isMomentumEnding {
                resetGestureState()
            } else if isNewGesture {
                didForwardPreciseBeginToParent = true
            }
            return .forwardToParent
        }

        let absX = abs(input.deltaX)
        let absY = abs(input.deltaY)

        if axisLatch == .undecided {
            if isPhaseless {
                if absX > Self.deltaThreshold || absY > Self.deltaThreshold {
                    axisLatch = absX > absY ? .horizontal : .vertical
                } else {
                    return .forwardToParent
                }
            } else {
                undecidedDelta.width += input.deltaX
                undecidedDelta.height += input.deltaY
                let absAccumX = abs(undecidedDelta.width)
                let absAccumY = abs(undecidedDelta.height)
                if max(absAccumX, absAccumY) >= Self.axisLatchThreshold {
                    axisLatch = absAccumX > absAccumY ? .horizontal : .vertical
                    undecidedDelta = .zero
                } else {
                    if isNewGesture {
                        didForwardPreciseBeginToParent = true
                    } else if input.phase.contains(.ended) || isGestureCancelled || isMomentumEnding {
                        resetGestureState()
                    }
                    return .forwardToParent
                }
            }
        }

        switch axisLatch {
        case .vertical:
            if isGestureCancelled || isMomentumEnding {
                resetGestureState()
            }
            return .forwardToParent

        case .horizontal:
            if isGestureCancelled {
                let shouldCloseParentBegin = didForwardPreciseBeginToParent
                resetGestureState()
                return shouldCloseParentBegin ? .forwardToParent : .consume
            }

            if isMomentumEnding {
                resetGestureState()
                return .consume
            }

            if input.phase.contains(.ended) && input.momentumPhase.isEmpty {
                // Balance an earlier zero-delta .mayBegin/.began forwarded to the parent while
                // keeping axisLatch == .horizontal for any following momentumPhase.
                if didForwardPreciseBeginToParent {
                    didForwardPreciseBeginToParent = false
                    return .forwardToParent
                }
                return .consume
            }

            guard absX > Self.deltaThreshold else {
                return .consume
            }

            let proposed = input.currentOffsetX - input.deltaX
            let clamped = min(max(proposed, 0), input.maxOffsetX)
            guard clamped != input.currentOffsetX else {
                return .consume
            }

            return .scrollHorizontal(to: clamped)

        case .undecided:
            return .forwardToParent
        }
    }
}

final class InspectorValueScrollView: NSScrollView {
    private let containerView = WheelForwardingStackView()
    private let spacerView = NSView(frame: .zero)
    private let textField = WheelForwardingLabel(labelWithString: "")

    private var lastText: String?
    private var lastFont: NSFont?
    private var lastTextColor: NSColor?
    private(set) var measuredTextWidth: CGFloat = 0
    private var lastLaidOutWidth: CGFloat = 0
    private var pendingScrollToTrailingEdge = false
    private var scrollRouter = InspectorValueScrollRouter()
    private(set) var textMeasurementCount = 0

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
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
        documentView = containerView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var maximumHorizontalOffset: CGFloat {
        guard let documentView else { return 0 }
        return max(documentView.frame.width - contentView.bounds.width, 0)
    }

    var currentHorizontalOffset: CGFloat {
        contentView.bounds.origin.x
    }

    func update(text: String, font: NSFont, textColor: NSColor) {
        let textDidChange = lastText != text
        let fontDidChange = lastFont != font
        let colorDidChange = lastTextColor != textColor

        guard textDidChange || fontDidChange || colorDidChange else {
            return
        }

        lastText = text
        lastFont = font
        lastTextColor = textColor

        if textDidChange {
            textField.stringValue = text
            pendingScrollToTrailingEdge = true
        }

        if fontDidChange {
            textField.font = font
        }

        if colorDidChange {
            textField.textColor = textColor
        }

        if textDidChange || fontDidChange {
            textField.sizeToFit()
            measuredTextWidth = ceil(textField.fittingSize.width)
            textMeasurementCount += 1
            applyContentLayout(forAvailableWidth: bounds.width, force: true)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyContentLayout(forAvailableWidth: bounds.width, force: false)
    }

    override func layout() {
        super.layout()
        applyContentLayout(forAvailableWidth: bounds.width, force: false)
    }

    func scrollHorizontal(to targetOffsetX: CGFloat) {
        let clamped = min(max(targetOffsetX, 0), maximumHorizontalOffset)
        if abs(contentView.bounds.origin.x - clamped) > 0.01 || contentView.bounds.origin.y != 0 {
            contentView.scroll(to: NSPoint(x: clamped, y: 0))
            reflectScrolledClipView(contentView)
        }
    }

    private func applyContentLayout(forAvailableWidth rawWidth: CGFloat, force: Bool) {
        let availableWidth = max(rawWidth, 0)
        guard availableWidth > 0 else { return }
        guard force || abs(availableWidth - lastLaidOutWidth) > 0.01 || pendingScrollToTrailingEdge else {
            return
        }

        lastLaidOutWidth = availableWidth
        let contentWidth = max(availableWidth, measuredTextWidth)
        let contentHeight = inspectorRowContentHeight
        let desiredFrame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)

        if containerView.frame != desiredFrame {
            containerView.frame = desiredFrame
        }

        let maxOffsetX = max(contentWidth - availableWidth, 0)
        let targetOffsetX = pendingScrollToTrailingEdge
            ? maxOffsetX
            : min(max(contentView.bounds.origin.x, 0), maxOffsetX)
        pendingScrollToTrailingEdge = false

        if abs(contentView.bounds.origin.x - targetOffsetX) > 0.01 || contentView.bounds.origin.y != 0 {
            contentView.scroll(to: NSPoint(x: targetOffsetX, y: 0))
            reflectScrolledClipView(contentView)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let action = scrollRouter.handle(
            InspectorValueScrollInput(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
                phase: event.phase,
                momentumPhase: event.momentumPhase,
                currentOffsetX: contentView.bounds.origin.x,
                maxOffsetX: maximumHorizontalOffset
            )
        )

        switch action {
        case .forwardToParent:
            nextResponder?.scrollWheel(with: event)
        case .scrollHorizontal(let targetOffsetX):
            scrollHorizontal(to: targetOffsetX)
        case .consume:
            break
        }
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
