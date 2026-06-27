//
//  ContentView.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    private enum PendingDiscardAction {
        case selection(Set<AudioFile.ID>)
        case hideInspector
    }

    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState
    @ObservedObject var musicBrainzBrowserStore: MusicBrainzBrowserStore
    @ObservedObject var lrclibLyricsBrowserStore: LRCLIBLyricsBrowserStore
    @ObservedObject var metadataFilenameToolStore: MetadataFilenameToolStore
    @ObservedObject var metadataEditorStore: MetadataEditorStore
    let metadataPipeline: any AudioMetadataPipeline
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @AppStorage(WelcomeSplashProgress.completionKey) private var hasCompletedWelcomeSplash: Bool = false
    @AppStorage(WelcomeSplashProgress.completedVersionKey) private var completedWelcomeSplashVersion: Int = 0
    @AppStorage("suppressesUnsavedInspectorDiscardWarning") private var suppressesUnsavedInspectorDiscardWarning: Bool = false
    @State private var isInspectorVisible: Bool = true
    @State private var isWelcomeSplashPresented: Bool = false
    @State private var isMusicBrainzBrowserPresented: Bool = false
    @State private var isMetadataFilenameToolPresented: Bool = false
    @State private var isMetadataEditorPresented: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var isDiscardInspectorAlertPresented: Bool = false
    @State private var pendingDiscardAction: PendingDiscardAction?

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
            get: { state.selectedAudioIDs },
            set: { newSelection in
                attemptSelectionChange(to: newSelection)
            }
        )
    }

    var body: some View {
        rootContent
            .sheet(isPresented: $isMetadataDumpPresented) {
                #if os(iOS)
                IPadDismissibleSheet(title: AppWindowTitle.rawMetadata) {
                    MetadataDumpSheet(
                        metadataDumpText: metadataDumpText,
                        onClose: { isMetadataDumpPresented = false }
                    )
                }
                #else
                MetadataDumpSheet(
                    metadataDumpText: metadataDumpText,
                    onClose: { isMetadataDumpPresented = false }
                )
                #endif
            }
            .sheet(isPresented: $isTrackRenumberPresented) {
                #if os(iOS)
                IPadDismissibleSheet(title: AppWindowTitle.renumberTracks, isCloseDisabled: isTrackRenumberRunning) {
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
                #else
                TrackRenumberSheet(
                    viewModel: viewModel,
                    state: state,
                    isPresented: $isTrackRenumberPresented,
                    trackRenumberOptions: $trackRenumberOptions,
                    trackRenumberStartText: $trackRenumberStartText,
                    isTrackRenumberRunning: $isTrackRenumberRunning,
                    trackRenumberResult: $trackRenumberResult
                )
                #endif
            }
            .sheet(isPresented: $isWelcomeSplashPresented) {
                WelcomeSplashView(
                    onQuit: quitApplication,
                    onContinue: dismissWelcomeSplash
                )
            }
            #if os(iOS)
            .sheet(isPresented: $isMusicBrainzBrowserPresented) {
                MusicBrainzBrowserView(
                    store: musicBrainzBrowserStore,
                    lrclibStore: lrclibLyricsBrowserStore,
                    viewModel: viewModel
                )
            }
            .sheet(isPresented: $isMetadataFilenameToolPresented) {
                MetadataFilenameWindowView(
                    viewModel: viewModel,
                    store: metadataFilenameToolStore
                )
            }
            .sheet(isPresented: $isMetadataEditorPresented) {
                MetadataEditorWindowView(
                    viewModel: viewModel,
                    store: metadataEditorStore
                )
            }
            .sheet(isPresented: $isSettingsPresented) {
                IPadDismissibleSheet(title: AppWindowTitle.settings) {
                    IPadSettingsView(sharedState: state)
                }
            }
            .confirmationDialog(
                "Discard Inspector Edits?",
                isPresented: $isDiscardInspectorAlertPresented,
                titleVisibility: .visible
            ) {
                Button("Discard Edits", role: .destructive) {
                    performPendingDiscardAction()
                }
                Button("Always Discard Without Asking", role: .destructive) {
                    suppressesUnsavedInspectorDiscardWarning = true
                    performPendingDiscardAction()
                }
                Button("Cancel", role: .cancel) {
                    pendingDiscardAction = nil
                }
            } message: {
                Text("To continue, AudioMator needs to discard your unsaved inspector edits.")
            }
            #endif
            #if os(macOS)
            .background(MetadataWriteHUDScreenPresenter(hud: viewModel.metadataWriteHUD))
            #else
            .overlay(alignment: .bottom) {
                if let hud = viewModel.metadataWriteHUD {
                    MetadataWriteHUDView(hud: hud)
                        .id(hud.id)
                        .padding(.bottom, 40)
                }
            }
            #endif
            .overlay {
                if let progress = viewModel.metadataSaveProgress {
                    MetadataSaveProgressOverlay(progress: progress)
                }
            }
            .onAppear {
                viewModel.setSidebarSelection(state.selectedSidebarItem)
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
                guard !state.selectedAudioIDs.isEmpty else { return }
                presentMetadataDump()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestTrackRenumber)) { _ in
                guard !viewModel.files.isEmpty else { return }
                openTrackRenumberSheet()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestMusicBrainzBrowser)) { _ in
                openMusicBrainzBrowser()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestSelectAllTracks)) { _ in
                attemptSelectionChange(to: Set(viewModel.files.map(\.id)))
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestToggleInspector)) { _ in
                toggleInspector()
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if os(macOS)
        NavigationSplitView {
            SidebarPane(viewModel: viewModel, state: state)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            contentPane
                .inspector(isPresented: $isInspectorVisible) {
                    InspectorPane(
                        viewModel: viewModel,
                        state: state,
                        isInspectorVisible: $isInspectorVisible
                    )
                    .inspectorColumnWidth(min: 340, ideal: 380, max: 480)
                }
        }
        .navigationSplitViewStyle(.balanced)
        #else
        IPadWorkspaceView(
            viewModel: viewModel,
            state: state,
            selection: guardedSelection,
            onAddFiles: viewModel.addFiles,
            onShowMetadataDump: presentMetadataDump,
            onOpenMusicBrainzBrowser: openMusicBrainzBrowser,
            onOpenMetadataFilenameTool: openMetadataFilenameTool,
            onOpenMetadataEditor: openMetadataEditor,
            onFindSelectedFileInMusicBrainz: findSelectedFileInMusicBrainz,
            onOpenTrackRenumber: openTrackRenumberSheet,
            onOpenSettings: openSettings,
            onCancelEdits: viewModel.cancelEditing,
            onSaveEdits: viewModel.saveInspectorEdits
        )
        #endif
    }

    private var contentPane: some View {
        ContentPane(
            viewModel: viewModel,
            state: state,
            selection: guardedSelection,
            onAddFiles: viewModel.addFiles,
            onShowMetadataDump: presentMetadataDump,
            onOpenMusicBrainzBrowser: openMusicBrainzBrowser,
            onOpenMetadataFilenameTool: openMetadataFilenameTool,
            onOpenMetadataEditor: openMetadataEditor,
            onFindSelectedFileInMusicBrainz: findSelectedFileInMusicBrainz,
            onOpenTrackRenumber: openTrackRenumberSheet,
            onCancelEdits: viewModel.cancelEditing,
            onSaveEdits: viewModel.saveInspectorEdits,
            isInspectorVisible: isInspectorVisible,
            onToggleInspector: toggleInspector
        )
    }

    private func openTrackRenumberSheet() {
        // Seed defaults each time the sheet opens
        trackRenumberStartText = String(max(1, trackRenumberOptions.startNumber))
        trackRenumberResult = .empty
        isTrackRenumberPresented = true
    }

    private func openMusicBrainzBrowser() {
        let seed = currentMusicBrainzMatchSeed() ?? currentMusicBrainzSearchSeed()
        musicBrainzBrowserStore.apply(seed: seed)
        seedLRCLIBLyricsBrowser()
        #if os(macOS)
        openWindow(id: MusicBrainzBrowserView.windowID)
        #else
        isMusicBrainzBrowserPresented = true
        #endif

        if musicBrainzBrowserStore.hasSearchText {
            musicBrainzBrowserStore.search()
        }
    }

    private func findSelectedFileInMusicBrainz() {
        guard let seed = currentMusicBrainzMatchSeed() else { return }

        musicBrainzBrowserStore.apply(seed: seed)
        seedLRCLIBLyricsBrowser()
        #if os(macOS)
        openWindow(id: MusicBrainzBrowserView.windowID)
        #else
        isMusicBrainzBrowserPresented = true
        #endif
        musicBrainzBrowserStore.search()
    }

    private func openMetadataFilenameTool(targetFileIDs: [AudioFile.ID]) {
        guard !targetFileIDs.isEmpty else { return }
        metadataFilenameToolStore.present(targetFileIDs: targetFileIDs)
        #if os(macOS)
        openWindow(id: MetadataFilenameWindowView.windowID)
        #else
        isMetadataFilenameToolPresented = true
        #endif
    }

    private func openMetadataEditor(targetFileIDs: [AudioFile.ID]) {
        guard !targetFileIDs.isEmpty else { return }

        let filesByID = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0) })
        let targets = targetFileIDs.compactMap { filesByID[$0] }
        guard !targets.isEmpty else { return }

        metadataEditorStore.present(targetFiles: targets)
        #if os(macOS)
        openWindow(id: MetadataEditorWindowView.windowID)
        #else
        isMetadataEditorPresented = true
        #endif
    }

    #if os(iOS)
    private func openSettings() {
        isSettingsPresented = true
    }
    #endif

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
            PlatformApplication.terminate()
        }
    }

    private func attemptSelectionChange(to newSelection: Set<AudioFile.ID>) {
        guard newSelection != state.selectedAudioIDs else { return }

        confirmDiscardUnsavedInspectorEditsIfNeeded(pendingAction: .selection(newSelection)) {
            state.selectedAudioIDs = newSelection
        }
    }

    private func discardInspectorEditsIfNeeded() {
        guard viewModel.hasUnsavedInspectorChanges else { return }
        viewModel.cancelEditing()
    }

    private func confirmDiscardUnsavedInspectorEditsIfNeeded(
        pendingAction: PendingDiscardAction,
        _ action: @escaping () -> Void
    ) {
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

        #if os(macOS)
        presentUnsavedInspectorDiscardAlert(onContinue: continueAction)
        #else
        pendingDiscardAction = pendingAction
        isDiscardInspectorAlertPresented = true
        #endif
    }

    #if os(macOS)
    private func presentUnsavedInspectorDiscardAlert(onContinue: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard Inspector Edits?"
        alert.informativeText = "To switch files, discard your unsaved inspector edits."
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
    #endif

    private func setInspectorVisibility(_ isVisible: Bool) {
        withAnimation(.easeInOut(duration: 0.18)) {
            isInspectorVisible = isVisible
        }
    }

    private func currentMusicBrainzSearchSeed() -> MusicBrainzSearchSeed? {
        let selectedFiles = viewModel.files.filter { state.selectedAudioIDs.contains($0.id) }
        let fileInputs = musicBrainzFileInputs(from: selectedFiles)
        guard let selectedInput = fileInputs.first else { return nil }

        if selectedFiles.count == 1,
           let selectedFile = selectedFiles.first,
           viewModel.editSourceFileID == selectedFile.id,
           let edit = viewModel.edit {
            return MusicBrainzSearchSeed(
                mode: .track,
                title: preferredMusicBrainzSeedValue(edit.title, fallback: selectedInput.title),
                artist: preferredMusicBrainzSeedValue(edit.artist, fallback: selectedInput.artist),
                albumArtist: preferredMusicBrainzSeedValue(edit.albumArtist, fallback: selectedInput.albumArtist),
                album: preferredMusicBrainzSeedValue(edit.album, fallback: selectedInput.album),
                trackNumber: preferredMusicBrainzSeedValue(edit.trackNumberText, fallback: selectedInput.trackNumber),
                trackTotal: 0,
                durationMilliseconds: nil,
                releaseDate: "",
                isrc: "",
                barcode: "",
                musicBrainzAlbumID: "",
                musicBrainzTrackID: "",
                fileInputs: fileInputs,
                link: "",
                sourceDescription: "From the current inspector fields, with filename and path fallback for blanks."
            )
        }

        let sourceDescription: String
        if selectedFiles.count == 1 {
            sourceDescription = "From the selected file metadata, filename, and path."
        } else {
            sourceDescription = "From the first of \(selectedFiles.count) selected files, with filename and path fallback."
        }

        return MusicBrainzSearchSeed(
            mode: .track,
            title: selectedInput.title,
            artist: selectedInput.artist,
            albumArtist: selectedInput.albumArtist,
            album: selectedInput.album,
            trackNumber: selectedInput.trackNumber,
            trackTotal: 0,
            durationMilliseconds: nil,
            releaseDate: "",
            isrc: "",
            barcode: "",
            musicBrainzAlbumID: "",
            musicBrainzTrackID: "",
            fileInputs: fileInputs,
            link: "",
            sourceDescription: sourceDescription
        )
    }

    private func currentMusicBrainzMatchSeed() -> MusicBrainzSearchSeed? {
        let selectedFiles = viewModel.files.filter { state.selectedAudioIDs.contains($0.id) }
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
            durationMilliseconds: selectedFile.duration.isFinite && selectedFile.duration > 0
                ? Int((selectedFile.duration * 1000).rounded())
                : nil,
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
        let selectedFiles = viewModel.files.filter { state.selectedAudioIDs.contains($0.id) }
        lrclibLyricsBrowserStore.seed(from: selectedFiles)
    }

    private func preferredMusicBrainzSeedValue(_ primary: String, fallback: String) -> String {
        let trimmedPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrimary.isEmpty {
            return trimmedPrimary
        }

        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggleInspector() {
        if isInspectorVisible {
            confirmDiscardUnsavedInspectorEditsIfNeeded(pendingAction: .hideInspector) {
                setInspectorVisibility(false)
            }
        } else {
            setInspectorVisibility(true)
        }
    }

    private func performPendingDiscardAction() {
        defer { pendingDiscardAction = nil }

        discardInspectorEditsIfNeeded()

        guard let pendingDiscardAction else { return }
        switch pendingDiscardAction {
        case .selection(let newSelection):
            state.selectedAudioIDs = newSelection
        case .hideInspector:
            setInspectorVisibility(false)
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
            .glassEffect(.regular, in: .rect(cornerRadius: 26.0))
            .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 18)
            .allowsHitTesting(true)
        }
        .ignoresSafeArea()
    }
}

private struct MetadataWriteHUDView: View {
    @Environment(\.colorScheme) private var colorScheme

    let hud: MetadataWriteHUD
    private let cornerRadius: CGFloat = 26

    var body: some View {
        VStack(spacing: 12) {
            MetadataWriteHUDIcon(style: hud.style, colorScheme: colorScheme)

            VStack(spacing: 4) {
                Text(hud.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(hud.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 320)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.55)
    }
}

#if os(macOS)
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

        @MainActor
        func update(hud: MetadataWriteHUD?) {
            guard let hud else {
                dismissPanel()
                return
            }

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
            let width = max(fittingSize.width, 364)
            let height = max(fittingSize.height, 150)
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

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
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
#endif

private struct MetadataWriteHUDIcon: View {
    let style: MetadataWriteHUDStyle
    let colorScheme: ColorScheme

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 54, weight: .semibold))
            .foregroundStyle(symbolColor)
        .frame(width: 54, height: 54)
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
            musicBrainzBrowserStore: MusicBrainzBrowserStore(),
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
        let selected = viewModel.files.filter { state.selectedAudioIDs.contains($0.id) }
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
