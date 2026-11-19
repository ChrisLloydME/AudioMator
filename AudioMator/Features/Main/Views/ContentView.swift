//
//  ContentView.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import SwiftUI
import AVFoundation
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState
    @ObservedObject var onlineMetadataBrowserStore: MusicBrainzBrowserStore
    @ObservedObject var lrclibLyricsBrowserStore: LRCLIBLyricsBrowserStore
    @ObservedObject var metadataFilenameToolStore: MetadataFilenameToolStore
    @ObservedObject var metadataEditorStore: MetadataEditorStore
    let metadataPipeline: any AudioMetadataPipeline
    @Environment(\.openWindow) private var openWindow

    @AppStorage(WelcomeSplashProgress.completionKey, store: AudioMatorTestHost.preferences) private var hasCompletedWelcomeSplash: Bool = false
    @AppStorage(WelcomeSplashProgress.completedVersionKey, store: AudioMatorTestHost.preferences) private var completedWelcomeSplashVersion: Int = 0
    @AppStorage("suppressesUnsavedInspectorDiscardWarning", store: AudioMatorTestHost.preferences) private var suppressesUnsavedInspectorDiscardWarning: Bool = false
    @State private var isInspectorVisible: Bool = true
    @State private var isWelcomeSplashPresented: Bool = false

    // Full metadata dump (user-facing feature)
    @State private var isMetadataDumpPresented: Bool = false
    @State private var metadataDumpText: String = ""

    // Track renumbering (by middle-list order)
    @State private var isTrackRenumberPresented: Bool = false
    @State private var trackRenumberOptions: TrackRenumberOptions = .init()
    @State private var trackRenumberStartText: String = "1"
    @State private var isTrackRenumberRunning: Bool = false
    @State private var trackRenumberResult: TrackRenumberResult = .empty

    private var guardedSelection: Binding<Set<AudioFile.ID>> {
        Binding(
            get: { viewModel.selectedAudioIDs },
            set: { newSelection in
                attemptSelectionChange(to: newSelection)
            }
        )
    }

    var body: some View {
        rootContent
            .sheet(isPresented: $isMetadataDumpPresented) {
                MetadataDumpSheet(
                    metadataDumpText: metadataDumpText,
                    onClose: { isMetadataDumpPresented = false }
                )
            }
            .sheet(isPresented: $isTrackRenumberPresented) {
                TrackRenumberSheet(
                    viewModel: viewModel,
                    state: state,
                    isPresented: $isTrackRenumberPresented,
                    trackRenumberOptions: $trackRenumberOptions,
                    trackRenumberStartText: $trackRenumberStartText,
                    isTrackRenumberRunning: $isTrackRenumberRunning,
                    trackRenumberResult: $trackRenumberResult
                )
            }
            .sheet(isPresented: $isWelcomeSplashPresented) {
                WelcomeSplashView(
                    onQuit: quitApplication,
                    onContinue: dismissWelcomeSplash,
                    initialFileAccessGrantPath: viewModel.primaryFileAccessGrantPath,
                    onAuthorizeFileAccess: viewModel.authorizeDefaultFileAccessFolder
                )
            }
            .background(MetadataWriteHUDScreenPresenter(hud: viewModel.metadataWriteHUD))
            .overlay {
                if let progress = viewModel.metadataSaveProgress {
                    MetadataSaveProgressOverlay(progress: progress)
                }
            }
            .onAppear {
                viewModel.setSidebarSelection(state.selectedSidebarItem)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await viewModel.refreshSelectedFilesAfterActivation() }
            }
            .task {
                guard shouldPresentWelcomeSplashOnLaunch, !isWelcomeSplashPresented else { return }
                isWelcomeSplashPresented = true
            }
            .onChange(of: state.selectedSidebarItem) { _, newSelection in
                viewModel.setSidebarSelection(newSelection)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showWelcomeSplash)) { _ in
                guard !isWelcomeSplashPresented else { return }
                isWelcomeSplashPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestMetadataDump)) { _ in
                guard !viewModel.selectedAudioIDs.isEmpty else { return }
                presentMetadataDump()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestTrackRenumber)) { _ in
                guard !viewModel.files.isEmpty else { return }
                openTrackRenumberSheet()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestOnlineMetadataBrowser)) { _ in
                openOnlineMetadataBrowser()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestSelectAllTracks)) { _ in
                attemptSelectionChange(to: Set(viewModel.files.map(\.id)))
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestSidebarSelectionChange)) { notification in
                guard let selection = notification.object as? SidebarSelection else { return }
                attemptSidebarSelectionChange(to: selection)
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestToggleInspector)) { _ in
                toggleInspector()
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        NavigationSplitView {
            SidebarPane(
                viewModel: viewModel,
                state: state,
                onSelectSidebarItem: attemptSidebarSelectionChange,
                onRemoveWatchedFolder: attemptWatchedFolderRemoval
            )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            contentPane
        }
        .navigationSplitViewStyle(.balanced)
        // Use SwiftUI's full-height Inspector with its own toolbar section.
        .inspector(isPresented: $isInspectorVisible) {
            InspectorPane(
                viewModel: viewModel,
                state: state,
                onHideInspector: toggleInspector
            )
            .inspectorColumnWidth(min: 340, ideal: 380, max: 480)
        }
    }

    private var contentPane: some View {
        ContentPane(
            viewModel: viewModel,
            state: state,
            selection: guardedSelection,
            onAddFiles: viewModel.addFiles,
            onShowMetadataDump: presentMetadataDump,
            onOpenOnlineMetadataBrowser: openOnlineMetadataBrowser,
            onOpenMetadataFilenameTool: openMetadataFilenameTool,
            onOpenMetadataEditor: openMetadataEditor,
            onFindSelectedFileInMusicBrainz: findSelectedFileInMusicBrainz,
            onOpenTrackRenumber: openTrackRenumberSheet,
            isInspectorVisible: isInspectorVisible,
            onShowInspector: toggleInspector
        )
    }

    private func openTrackRenumberSheet() {
        // Seed the approved default start each time the sheet opens. The transient
        // options value is only ever set from a validated plan.
        trackRenumberStartText = String(trackRenumberOptions.startNumber)
        trackRenumberResult = .empty
        isTrackRenumberPresented = true
    }

    private func openOnlineMetadataBrowser() {
        onlineMetadataBrowserStore.apply(seed: currentMusicBrainzMatchSeed())
        seedLRCLIBLyricsBrowser()
        openWindow(id: OnlineMetadataBrowserView.windowID)

        if onlineMetadataBrowserStore.hasSearchText {
            onlineMetadataBrowserStore.search()
        }
    }

    private func findSelectedFileInMusicBrainz() {
        guard let seed = currentMusicBrainzMatchSeed() else { return }

        onlineMetadataBrowserStore.apply(seed: seed)
        seedLRCLIBLyricsBrowser()
        openWindow(id: OnlineMetadataBrowserView.windowID)
        onlineMetadataBrowserStore.search()
    }

    private func openMetadataFilenameTool(targetFileIDs: [AudioFile.ID]) {
        guard !targetFileIDs.isEmpty else { return }
        metadataFilenameToolStore.present(targetFileIDs: targetFileIDs)
        openWindow(id: MetadataFilenameWindowView.windowID)
    }

    private func openMetadataEditor(targetFileIDs: [AudioFile.ID]) {
        guard !targetFileIDs.isEmpty else { return }

        let filesByID = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0) })
        let targets = targetFileIDs.compactMap { filesByID[$0] }
        guard !targets.isEmpty else { return }

        let targetCount = targets.count
        let decision = metadataEditorStore.openDecision(for: targets.map(\.id))
        Task { @MainActor in
            let outcome = await MetadataEditorOpener.open(
                store: metadataEditorStore,
                targetFiles: targets,
                decision: decision,
                confirmDiscard: { _ in
                    await confirmDiscardingMetadataEditorDraft(targetCount: targetCount)
                }
            )
            switch outcome {
            case .focusExisting, .presentedNew, .presentedWhileDraining:
                openWindow(id: MetadataEditorWindowView.windowID)
            case .discardDeclined:
                break
            case .staleConfirmation:
                viewModel.presentMetadataWriteHUD(
                    style: .warning,
                    title: String(localized: "Metadata Editor Changed"),
                    subtitle: String(localized: "The Metadata Editor changed before it could open these files. Choose Metadata Editor… again.")
                )
            }
        }
    }

    /// Localized discard decision for a raw Metadata Editor draft when a
    /// different target selection is requested. The response is only a claim
    /// about the session that was current when the alert was requested;
    /// `MetadataEditorOpener` revalidates it through the store before discarding.
    @MainActor
    private func confirmDiscardingMetadataEditorDraft(targetCount: Int) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Discard Metadata Editor Changes?")
        alert.informativeText = targetCount == 1
            ? String(localized: "The Metadata Editor has unsaved changes. Opening the selected file discards them.")
            : String(localized: "The Metadata Editor has unsaved changes. Opening the selected files discards them.")
        alert.addButton(withTitle: String(localized: "Discard and Open"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
            }
        }

        return alert.runModal() == .alertFirstButtonReturn
    }

    private func dismissWelcomeSplash() {
        hasCompletedWelcomeSplash = true
        completedWelcomeSplashVersion = WelcomeSplashProgress.currentVersion
        isWelcomeSplashPresented = false
    }

    private var shouldPresentWelcomeSplashOnLaunch: Bool {
        WelcomeSplashProgress.shouldPresent(
            hasCompleted: hasCompletedWelcomeSplash,
            completedVersion: completedWelcomeSplashVersion
        )
    }

    private func quitApplication() {
        isWelcomeSplashPresented = false

        Task { @MainActor in
            await Task.yield()
            MacApplication.terminate()
        }
    }

    private func attemptSelectionChange(to newSelection: Set<AudioFile.ID>) {
        guard newSelection != viewModel.selectedAudioIDs else { return }

        confirmDiscardUnsavedInspectorEditsIfNeeded {
            viewModel.setSelectedAudioIDs(newSelection)
        }
    }

    private func attemptSidebarSelectionChange(to newSelection: SidebarSelection?) {
        guard newSelection != state.selectedSidebarItem else { return }

        Self.performSidebarSelectionChange(
            hasUnsavedInspectorChanges: viewModel.hasUnsavedInspectorChanges,
            suppressesDiscardWarning: suppressesUnsavedInspectorDiscardWarning,
            requestDiscardConfirmation: presentUnsavedInspectorDiscardAlert,
            discardInspectorEdits: discardInspectorEditsIfNeeded
        ) {
            state.selectedSidebarItem = newSelection
        }
    }

    static func performSidebarSelectionChange(
        hasUnsavedInspectorChanges: Bool,
        suppressesDiscardWarning: Bool,
        requestDiscardConfirmation: (@escaping () -> Void) -> Void,
        discardInspectorEdits: @escaping () -> Void,
        commitSelection: @escaping () -> Void
    ) {
        guard hasUnsavedInspectorChanges else {
            commitSelection()
            return
        }

        let continueAction = {
            discardInspectorEdits()
            commitSelection()
        }

        if suppressesDiscardWarning {
            continueAction()
        } else {
            requestDiscardConfirmation(continueAction)
        }
    }

    private func attemptWatchedFolderRemoval(_ folder: WatchedFolder) {
        guard watchedFolderRemovalCanAffectInspectorSelection(folder) else {
            removeWatchedFolderAndUpdateSelection(id: folder.id)
            return
        }

        confirmDiscardUnsavedInspectorEditsIfNeeded {
            removeWatchedFolderAndUpdateSelection(id: folder.id)
        }
    }

    private func watchedFolderRemovalCanAffectInspectorSelection(_ folder: WatchedFolder) -> Bool {
        switch state.selectedSidebarItem {
        case .watchedFolder(let id):
            return id == folder.id
        case .watchedLibrary:
            return viewModel.files.contains { file in
                guard viewModel.selectedAudioIDs.contains(file.id) else { return false }
                return FileSystemPathSemantics.isSameOrDescendant(file.url, of: folder.url)
            }
        case .quickImport, .none:
            return false
        }
    }

    private func removeWatchedFolderAndUpdateSelection(id: UUID) {
        viewModel.removeWatchedFolder(id: id)

        if state.selectedSidebarItem == .watchedFolder(id) {
            state.selectedSidebarItem = viewModel.watchedFolders.isEmpty ? .quickImport : .watchedLibrary
        }
    }

    private func discardInspectorEditsIfNeeded() {
        guard viewModel.hasUnsavedInspectorChanges else { return }
        viewModel.cancelEditing()
    }

    private func confirmDiscardUnsavedInspectorEditsIfNeeded(_ action: @escaping () -> Void) {
        guard viewModel.hasUnsavedInspectorChanges else {
            action()
            return
        }

        let continueAction = {
            discardInspectorEditsIfNeeded()
            action()
        }

        guard !suppressesUnsavedInspectorDiscardWarning else {
            continueAction()
            return
        }

        presentUnsavedInspectorDiscardAlert(onContinue: continueAction)
    }

    private func presentUnsavedInspectorDiscardAlert(onContinue: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard Inspector Edits?"
        alert.informativeText = "To continue, discard your unsaved inspector edits."
        alert.addButton(withTitle: "Discard Edits")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }

            if alert.suppressionButton?.state == .on {
                suppressesUnsavedInspectorDiscardWarning = true
            }

            onContinue()
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            let response = alert.runModal()
            handleResponse(response)
        }
    }

    private func setInspectorVisibility(_ isVisible: Bool) {
        withAnimation(.easeInOut(duration: 0.18)) {
            isInspectorVisible = isVisible
        }
    }

    private func currentMusicBrainzMatchSeed() -> MusicBrainzSearchSeed? {
        let selectedFiles = viewModel.files.filter { viewModel.selectedAudioIDs.contains($0.id) }
        let fileInputs = musicBrainzFileInputs(from: selectedFiles)
        guard let selectedFile = selectedFiles.first, let selectedInput = fileInputs.first else { return nil }

        return MusicBrainzSearchSeed(
            mode: .file,
            title: selectedInput.title,
            artist: selectedInput.artist,
            albumArtist: selectedInput.albumArtist,
            album: selectedInput.album,
            trackNumber: selectedInput.trackNumber,
            trackTotal: selectedFile.trackTotal,
            durationMilliseconds: AudioNumericConversion.positiveDurationMilliseconds(selectedFile.duration),
            releaseDate: selectedInput.releaseDate,
            isrc: selectedFile.isrc,
            barcode: selectedFile.barcode,
            musicBrainzAlbumID: selectedFile.musicBrainzAlbumID,
            musicBrainzTrackID: selectedFile.musicBrainzTrackID,
            fileInputs: fileInputs,
            link: "",
            sourceDescription: selectedFiles.count == 1
                ? "From the selected file metadata, filename, and path."
                : "From \(selectedFiles.count) selected files, with filename and path fallback."
        )
    }

    private func musicBrainzFileInputs(from files: [AudioFile]) -> [MusicBrainzFileSearchInput] {
        files.map { MusicBrainzFilenameFallbackResolver.makeSearchInput(for: $0) }
    }

    private func seedLRCLIBLyricsBrowser() {
        let selectedFiles = viewModel.files.filter { viewModel.selectedAudioIDs.contains($0.id) }
        lrclibLyricsBrowserStore.seed(from: selectedFiles)
    }

    private func toggleInspector() {
        if isInspectorVisible {
            confirmDiscardUnsavedInspectorEditsIfNeeded {
                setInspectorVisibility(false)
            }
        } else {
            setInspectorVisibility(true)
        }
    }

}

struct MetadataSaveProgressOverlay: View {
    let progress: MetadataSaveProgress

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.10))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(progress.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                VStack(alignment: .trailing, spacing: 7) {
                    ProgressView(value: progress.fractionCompleted)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)

                    Text(progress.progressLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(20)
            .frame(width: 380)
            .audiomatorRegularGlassRoundedRectangle(cornerRadius: 26)
            .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 18)
            .allowsHitTesting(true)
        }
        .ignoresSafeArea()
    }
}

private struct MetadataWriteHUDView: View {
    @Environment(\.colorScheme) private var colorScheme

    let hud: MetadataWriteHUD
    private let cornerRadius: CGFloat = 24

    var body: some View {
        VStack(spacing: 16) {
            MetadataWriteHUDIcon(style: hud.style, colorScheme: colorScheme)

            VStack(spacing: 7) {
                Text(hud.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if !hud.summary.isEmpty {
                    Text(hud.summary)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(hud.style == .success ? 2 : 4)
                        .fixedSize(horizontal: false, vertical: true)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.center)
                }
            }

            if !hud.details.isEmpty {
                Divider()
                Text(hud.detailPreview)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if hud.hasOmittedDetails {
                Text(hud.omissionNotice)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .truncationMode(.tail)
            }
        }
        .frame(width: 372)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.55)
    }
}

private struct MetadataWriteHUDScreenPresenter: NSViewRepresentable {
    let hud: MetadataWriteHUD?

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(hud: hud)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var panel: NSPanel?
        private var hostingController: NSHostingController<MetadataWriteHUDScreenRoot>?
        private var presentedHUDID: UUID?
        private var presentationGeneration = UUID()

        @MainActor
        func update(hud: MetadataWriteHUD?) {
            guard let hud else {
                dismissPanel()
                return
            }

            presentationGeneration = UUID()
            if panel == nil {
                createPanel()
            }

            guard let panel, let hostingController else { return }

            hostingController.rootView = MetadataWriteHUDScreenRoot(hud: hud)
            hostingController.view.layoutSubtreeIfNeeded()
            resizeAndPosition(panel: panel, for: hostingController)

            if presentedHUDID != hud.id || !panel.isVisible {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    panel.animator().alphaValue = 1
                }
            }

            presentedHUDID = hud.id
        }

        @MainActor
        private func createPanel() {
            let hostingController = NSHostingController(rootView: MetadataWriteHUDScreenRoot.empty)
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
            hostingController.view.layer?.isOpaque = false

            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.contentViewController = hostingController
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.isMovable = false
            panel.isOpaque = false
            panel.level = .statusBar
            panel.isReleasedWhenClosed = false

            self.hostingController = hostingController
            self.panel = panel
        }

        @MainActor
        private func resizeAndPosition(
            panel: NSPanel,
            for hostingController: NSHostingController<MetadataWriteHUDScreenRoot>
        ) {
            let fittingSize = hostingController.view.fittingSize
            let width = max(fittingSize.width, 456)
            let height = max(fittingSize.height, 180)
            let screenFrame = targetScreen()?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let lowerHalfCenterY = screenFrame.minY + screenFrame.height * 0.35
            let origin = NSPoint(
                x: screenFrame.midX - width / 2,
                y: lowerHalfCenterY - height / 2
            )

            panel.setFrame(
                NSRect(origin: origin, size: NSSize(width: width, height: height)),
                display: true
            )
        }

        @MainActor
        private func dismissPanel() {
            guard let panel else {
                presentedHUDID = nil
                return
            }

            presentedHUDID = nil
            let generation = UUID()
            presentationGeneration = generation

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor [weak self] in
                    guard let self, self.presentationGeneration == generation,
                          self.presentedHUDID == nil else { return }
                    panel.orderOut(nil)
                }
            }
        }

        @MainActor
        private func targetScreen() -> NSScreen? {
            NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main
        }
    }
}

private struct MetadataWriteHUDScreenRoot: View {
    let hud: MetadataWriteHUD?

    static let empty = MetadataWriteHUDScreenRoot(hud: nil)

    var body: some View {
        ZStack {
            if let hud {
                MetadataWriteHUDView(hud: hud)
                    .id(hud.id)
                    .padding(18)
            }
        }
        .fixedSize()
        .background(Color.clear)
    }
}

private struct MetadataWriteHUDIcon: View {
    let style: MetadataWriteHUDStyle
    let colorScheme: ColorScheme

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 60, weight: .semibold))
            .foregroundStyle(symbolColor)
        .frame(width: 64, height: 64)
    }

    private var symbolColor: Color {
        switch style {
        case .success:
            return Color.green.opacity(colorScheme == .dark ? 0.92 : 0.86)
        case .warning:
            return colorScheme == .dark ? Color.orange.opacity(0.92) : Color.orange.opacity(0.86)
        case .failure:
            return colorScheme == .dark ? Color.red.opacity(0.92) : Color.red.opacity(0.86)
        }
    }

    private var symbolName: String {
        switch style {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failure:
            return "xmark.circle.fill"
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(
            viewModel: AudioViewModel(),
            state: SharedState(),
            onlineMetadataBrowserStore: MusicBrainzBrowserStore(),
            lrclibLyricsBrowserStore: LRCLIBLyricsBrowserStore(),
            metadataFilenameToolStore: MetadataFilenameToolStore(),
            metadataEditorStore: MetadataEditorStore(metadataPipeline: TagLibAudioMetadataPipeline()),
            metadataPipeline: TagLibAudioMetadataPipeline()
        )
    }
}

// MARK: - Full metadata dump (user-facing)
extension ContentView {
    private func presentMetadataDump() {
        let selected = viewModel.files.filter { viewModel.selectedAudioIDs.contains($0.id) }
        metadataDumpText = "Loading metadata…"
        isMetadataDumpPresented = true

        Task {
            let text = await buildMetadataDump(for: selected)
            await MainActor.run {
                guard isMetadataDumpPresented else { return }
                metadataDumpText = text
            }
        }
    }

    /// Produces a best-effort raw metadata dump for the selected files.
    ///
    /// This intentionally bypasses the normalized right-inspector model and instead
    /// re-reads metadata directly from the file through multiple backends.
    private func buildMetadataDump(for files: [AudioFile]) async -> String {
        guard !files.isEmpty else { return "(No selection)" }

        if files.count == 1, let file = files.first {
            return await buildMetadataDump(for: file.url)
        }

        var dumps: [String] = []
        dumps.reserveCapacity(files.count)

        for file in files {
            dumps.append(await buildMetadataDump(for: file.url))
        }

        return dumps.joined(separator: "\n\n")
    }

    private func buildMetadataDump(for url: URL) async -> String {
        var sections: [String] = []

        let tagLibText = await rawMetadataDumpTextOffMainActor(for: url)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !tagLibText.isEmpty {
            sections.append(tagLibText)
        }

        if let avFoundationText = await buildAVFoundationMetadataDump(for: url) {
            sections.append(avFoundationText)
        }

        if !sections.isEmpty {
            return sections.joined(separator: "\n\n")
        }

        return """
        File: \(url.lastPathComponent)
        Path: \(url.path)

        (No metadata could be read by either TagLib or AVFoundation.)
        """
    }

    private func rawMetadataDumpTextOffMainActor(for url: URL) async -> String? {
        let metadataPipeline = metadataPipeline

        return await Task.detached(priority: .userInitiated) {
            metadataPipeline.rawMetadataDumpText(for: url)
        }.value
    }

    private func buildAVFoundationMetadataDump(for url: URL) async -> String? {
        let asset = AVURLAsset(url: url)

        let metadataItems: [AVMetadataItem]
        do {
            metadataItems = try await asset.load(.metadata)
        } catch {
            return """
            File: \(url.lastPathComponent)
            Path: \(url.path)

            [AVFoundation Metadata]
            (failed to load metadata: \((error as NSError).localizedDescription))
            """
        }

        guard !metadataItems.isEmpty else { return nil }

        var lines: [String] = [
            "File: \(url.lastPathComponent)",
            "Path: \(url.path)",
            "",
            "[AVFoundation Metadata]"
        ]

        for item in metadataItems {
            let keySpace = item.keySpace?.rawValue ?? "unknown"

            let keyName: String = {
                if let identifier = item.identifier?.rawValue, !identifier.isEmpty {
                    return identifier
                }
                if let commonKey = item.commonKey?.rawValue, !commonKey.isEmpty {
                    return commonKey
                }
                if let key = item.key {
                    return String(describing: key)
                }
                return "(unknown key)"
            }()

            let valueDescription = await describeAVMetadataValue(item)
            lines.append("[\(keySpace)] \(keyName) = \(valueDescription)")
        }

        return lines.joined(separator: "\n")
    }

    private func describeAVMetadataValue(_ item: AVMetadataItem) async -> String {
        if let stringValue = try? await item.load(.stringValue),
           !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stringValue
        }

        if let numberValue = try? await item.load(.numberValue) {
            return numberValue.stringValue
        }

        if let dateValue = try? await item.load(.dateValue) {
            return ISO8601DateFormatter().string(from: dateValue)
        }

        if let dataValue = try? await item.load(.dataValue) {
            return "<Data: \(dataValue.count) bytes>"
        }

        if let value = try? await item.load(.value) {
            return String(describing: value)
        }

        return "(unreadable value)"
    }
}

// MARK: - Metadata Editor open routing (F3)

/// Maps the store's raw-editor open decision onto the window side effects.
///
/// The store alone owns presentation identity and revalidates a discard decision;
/// this type only sequences the user confirmation and the resulting store call,
/// so the routing is testable without AppKit window presentation.
@MainActor
enum MetadataEditorOpener {
    enum Outcome: Equatable {
        /// The current presentation owns the window; raise it without resetting.
        case focusExisting
        /// A new presentation was started for the requested targets.
        case presentedNew
        /// A new presentation was started while a closed apply drains; Done is
        /// blocked store-side until the drain completes.
        case presentedWhileDraining
        /// The user declined to discard the live draft.
        case discardDeclined
        /// The live session changed while the discard decision was pending; the
        /// store refused to discard it and no window should open.
        case staleConfirmation
    }

    static func open(
        store: MetadataEditorStore,
        targetFiles: [AudioFile],
        decision: MetadataEditorOpenDecision,
        confirmDiscard: @MainActor (MetadataEditorPresentationID) async -> Bool
    ) async -> Outcome {
        switch decision {
        case .focusExisting:
            return .focusExisting

        case .presentNew:
            store.presentNew(targetFiles: targetFiles)
            return .presentedNew

        case .presentWhileDraining:
            store.presentNew(targetFiles: targetFiles)
            return .presentedWhileDraining

        case .confirmDiscardAndOpen(let presentationID):
            let confirmed = await confirmDiscard(presentationID)
            guard confirmed else { return .discardDeclined }
            guard store.discardAndOpen(
                targetFiles: targetFiles,
                sessionID: presentationID
            ) else {
                return .staleConfirmation
            }
            return .presentedNew
        }
    }
}
