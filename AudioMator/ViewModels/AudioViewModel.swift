//
//  AudioViewModel.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

private let metadataWriteSuccessHUDDuration: Duration = .seconds(2.3)

enum MetadataWriteHUDStyle: Equatable {
    case success
    case warning
    case failure
}

struct MetadataWriteHUD: Identifiable, Equatable {
    let id = UUID()
    let style: MetadataWriteHUDStyle
    let title: String
    let subtitle: String
}

struct MetadataSaveProgress: Equatable {
    let title: String
    let subtitle: String
    let completedUnitCount: Int
    let totalUnitCount: Int

    var fractionCompleted: Double {
        guard totalUnitCount > 0 else { return 0 }
        return min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
    }

    var progressLabel: String {
        "\(completedUnitCount) / \(totalUnitCount)"
    }
}

@MainActor
final class AudioViewModel: ObservableObject {
    nonisolated private static let readableAudioExtensions: Set<String> = Set(
        TagLibMetadataExtractor.supportedExtensions().map { $0.lowercased() }
    )

    // All audio files currently loaded into the middle list.
    @Published var files: [AudioFile] = []
    @Published private(set) var watchedFolders: [WatchedFolder] = []
    // Current selection in the middle list. Single-file and multi-file inspector editing both use this selection.
    @Published var selectedAudioIDs: Set<UUID> = []
    // Inspector edit models bound to the right-side inspector.
    @Published var edit: SingleFileEditModel?
    @Published var multiEdit: MultiFileEditModel?
    @Published var metadataWriteHUD: MetadataWriteHUD?
    @Published var artworkLookupSession: ArtworkLookupSession?
    @Published var metadataSaveProgress: MetadataSaveProgress?

    private let watchedFolderStore: WatchedFolderStore
    let iTunesArtworkService = ITunesArtworkService()
    private var metadataWriteHUDDismissTask: Task<Void, Never>?
    var artworkLookupTask: Task<Void, Never>?
    private var pendingMetadataWriteHUDs: [MetadataWriteHUD] = []
    private var quickImportFiles: [AudioFile] = []
    private var watchedFolderFiles: [UUID: [AudioFile]] = [:]
    private var activeSidebarSelection: SidebarSelection = .quickImport
    private var fileIDsByKey: [String: UUID] = [:]
    private var folderRescanTasks: [UUID: Task<Void, Never>] = [:]
    private var folderDirectoryMonitors: [UUID: [String: DirectoryMonitor]] = [:]
    private var securityScopedFolderURLs: [UUID: URL] = [:]
    private var securityScopedQuickImportFileURLs: [String: URL] = [:]
    private var securityScopedQuickImportDirectoryURLs: [String: URL] = [:]
    private var securityScopedQuickImportRenameDirectoryURLs: [String: URL] = [:]
    private var folderScanTokens: [UUID: UUID] = [:]

    convenience init() {
        self.init(watchedFolderStore: WatchedFolderStore())
    }

    init(watchedFolderStore: WatchedFolderStore) {
        self.watchedFolderStore = watchedFolderStore

        #if os(macOS)
        let restoredFolders = watchedFolderStore.loadFolders()
        self.watchedFolders = restoredFolders

        for folder in restoredFolders {
            beginAccessingWatchedFolder(folder)
            updateDirectoryMonitors(for: folder.id, directories: [folder.url])
            scheduleWatchedFolderRescan(for: folder.id, debounceMilliseconds: 0)
        }
        #endif

        rebuildVisibleFiles()
    }

    deinit {
        artworkLookupTask?.cancel()
        metadataWriteHUDDismissTask?.cancel()
        folderRescanTasks.values.forEach { $0.cancel() }
        folderDirectoryMonitors.removeAll()
        securityScopedFolderURLs.values.forEach { $0.stopAccessingSecurityScopedResource() }
        securityScopedQuickImportFileURLs.values.forEach { $0.stopAccessingSecurityScopedResource() }
        securityScopedQuickImportDirectoryURLs.values.forEach { $0.stopAccessingSecurityScopedResource() }
        securityScopedQuickImportRenameDirectoryURLs.values.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    var currentFileSourceMode: FileSourceMode {
        normalizedSidebarSelection(activeSidebarSelection).sourceMode
    }

    var hasUnsavedInspectorChanges: Bool {
        if selectedAudioIDs.count > 1 {
            return multiEdit?.hasUnsavedChanges ?? false
        }

        guard
            selectedAudioIDs.count == 1,
            let id = selectedAudioIDs.first,
            let file = files.first(where: { $0.id == id }),
            let edit
        else {
            return false
        }

        return edit.hasUnsavedChanges(comparedTo: file)
    }

    func setSidebarSelection(_ selection: SidebarSelection?) {
        activeSidebarSelection = normalizedSidebarSelection(selection ?? .quickImport)
        rebuildVisibleFiles()
    }

    // MARK: - Selection and Edit Sync

    /// Called when the middle-list selection changes to keep the inspector in sync with the current file.
    func updateEditForSelection() {
        guard !selectedAudioIDs.isEmpty else {
            edit = nil
            multiEdit = nil
            return
        }

        if selectedAudioIDs.count == 1,
           let selectedID = selectedAudioIDs.first,
           let selectedFile = files.first(where: { $0.id == selectedID }) {
            edit = SingleFileEditModel(from: selectedFile)
            multiEdit = nil
            return
        }

        let selectedFiles = files.filter { selectedAudioIDs.contains($0.id) }
        guard !selectedFiles.isEmpty else {
            edit = nil
            multiEdit = nil
            return
        }

        edit = nil
        multiEdit = MultiFileEditModel(files: selectedFiles)
    }

    /// Discard the current edits and restore the latest tags from disk.
    func cancelEditing() {
        updateEditForSelection()
    }

    func presentMetadataWriteHUD(
        style: MetadataWriteHUDStyle,
        title: String,
        subtitle: String
    ) {
        enqueueMetadataWriteHUD(
            style: style,
            title: title,
            subtitle: subtitle
        )
    }

    func presentMetadataWriteSuccess(for fileName: String) {
        presentMetadataWriteHUD(
            style: .success,
            title: "Saved to Disk",
            subtitle: fileName
        )
    }

    func presentMetadataWriteWarning(title: String, subtitle: String) {
        presentMetadataWriteHUD(
            style: .warning,
            title: title,
            subtitle: subtitle
        )
    }

    func presentMetadataWriteFailure(for fileName: String, reason: String) {
        presentMetadataWriteHUD(
            style: .failure,
            title: "Save Failed",
            subtitle: [fileName, reason]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        )
    }

    private func enqueueMetadataWriteHUD(
        style: MetadataWriteHUDStyle,
        title: String,
        subtitle: String
    ) {
        let hud = MetadataWriteHUD(
            style: style,
            title: title,
            subtitle: subtitle
        )
        pendingMetadataWriteHUDs.append(hud)

        guard metadataWriteHUD == nil else { return }
        showNextMetadataWriteHUD()
    }

    private func showNextMetadataWriteHUD() {
        guard metadataWriteHUD == nil, !pendingMetadataWriteHUDs.isEmpty else { return }

        metadataWriteHUDDismissTask?.cancel()

        let hud = pendingMetadataWriteHUDs.removeFirst()
        metadataWriteHUD = hud

        metadataWriteHUDDismissTask = Task { [weak self, hudID = hud.id] in
            try? await Task.sleep(for: metadataWriteSuccessHUDDuration)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.metadataWriteHUD?.id == hudID else { return }
                self.metadataWriteHUD = nil
            }

            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.showNextMetadataWriteHUD()
            }
        }
    }

    @discardableResult
    func addWatchedFolders() -> SidebarSelection? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.title = "Choose Folders to Watch"
        panel.prompt = "Watch"
        panel.message = "AudioMator will keep these folders in the sidebar and refresh them when their contents change."

        guard panel.runModal() == .OK else { return nil }

        var addedFolders: [WatchedFolder] = []
        var duplicateSelection: SidebarSelection?
        var seenFolderKeys = Set<String>()
        let existingFoldersByKey = Dictionary(
            uniqueKeysWithValues: watchedFolders.map { (Self.urlKey(for: $0.url), $0) }
        )

        for url in panel.urls {
            let key = Self.urlKey(for: url)
            guard seenFolderKeys.insert(key).inserted else { continue }

            if let existingFolder = existingFoldersByKey[key] {
                duplicateSelection = .watchedFolder(existingFolder.id)
                continue
            }

            do {
                let folder = try watchedFolderStore.makeFolder(from: url)
                addedFolders.append(folder)
            } catch {
                print("Failed to create watched folder bookmark for \(url.path): \(error)")
            }
        }

        guard !addedFolders.isEmpty else {
            return duplicateSelection ?? .watchedLibrary
        }

        watchedFolders.append(contentsOf: addedFolders)
        persistWatchedFolders()

        for folder in addedFolders {
            beginAccessingWatchedFolder(folder)
            updateDirectoryMonitors(for: folder.id, directories: [folder.url])
            scheduleWatchedFolderRescan(for: folder.id, debounceMilliseconds: 0)
        }

        rebuildVisibleFiles()

        if addedFolders.count == 1, let folder = addedFolders.first {
            return .watchedFolder(folder.id)
        }

        return .watchedLibrary
        #else
        return nil
        #endif
    }

    func removeWatchedFolder(id: UUID) {
        guard watchedFolders.contains(where: { $0.id == id }) else { return }

        stopWatchingFolder(id: id)
        watchedFolders.removeAll { $0.id == id }
        watchedFolderFiles[id] = nil
        folderScanTokens[id] = nil

        persistWatchedFolders()

        activeSidebarSelection = normalizedSidebarSelection(activeSidebarSelection)
        rebuildVisibleFiles()
    }

    func mergeQuickImportFiles(_ incoming: [AudioFile]) {
        quickImportFiles = mergeFilesPreservingExistingOrder(existing: quickImportFiles, incoming: incoming)
        syncQuickImportSecurityScopedResources()
        rebuildVisibleFiles()
    }

    func importQuickFiles(from urls: [URL]) {
        let candidateURLs = Self.uniqueSortedURLs(urls)
        beginAccessingQuickImportResources(for: candidateURLs)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let fileIDsByKey = await MainActor.run {
                self.prepareStableIDs(for: candidateURLs)
            }

            _ = await Self.loadAudioFiles(
                from: candidateURLs,
                fileIDsByKey: fileIDsByKey,
                onBatchLoaded: { batch in
                    guard !batch.isEmpty else { return }
                    await MainActor.run {
                        self.mergeQuickImportFiles(batch)
                    }
                }
            )
        }
    }

    func clearQuickImportFiles() {
        quickImportFiles.removeAll()
        syncQuickImportSecurityScopedResources()
        activeSidebarSelection = normalizedSidebarSelection(activeSidebarSelection)
        rebuildVisibleFiles()
    }

    func removeQuickImportFile(id: UUID) {
        quickImportFiles.removeAll { $0.id == id }
        syncQuickImportSecurityScopedResources()
        rebuildVisibleFiles()
    }

    func replaceLoadedFile(_ reloaded: AudioFile) {
        if let index = quickImportFiles.firstIndex(where: { $0.id == reloaded.id }) {
            quickImportFiles[index] = reloaded
        }

        for folderID in watchedFolderFiles.keys {
            guard var folderFiles = watchedFolderFiles[folderID] else { continue }
            guard let index = folderFiles.firstIndex(where: { $0.id == reloaded.id }) else { continue }
            folderFiles[index] = reloaded
            watchedFolderFiles[folderID] = folderFiles
        }

        rebuildVisibleFiles()
    }

    func replaceLoadedFiles(_ reloadedFiles: [AudioFile]) {
        guard !reloadedFiles.isEmpty else { return }

        let reloadedByID = Dictionary(uniqueKeysWithValues: reloadedFiles.map { ($0.id, $0) })

        quickImportFiles = quickImportFiles.map { reloadedByID[$0.id] ?? $0 }

        for folderID in watchedFolderFiles.keys {
            guard let folderFiles = watchedFolderFiles[folderID] else { continue }
            watchedFolderFiles[folderID] = folderFiles.map { reloadedByID[$0.id] ?? $0 }
        }

        rebuildVisibleFiles()
    }

    func applyMovedFiles(_ changes: [(id: UUID, newURL: URL)]) {
        guard !changes.isEmpty else { return }

        let urlsByID = Dictionary(uniqueKeysWithValues: changes.map { ($0.id, $0.newURL) })

        quickImportFiles = quickImportFiles.map { file in
            guard let newURL = urlsByID[file.id] else { return file }
            return file.withUpdatedURL(newURL)
        }
        syncQuickImportSecurityScopedResources()

        for folderID in watchedFolderFiles.keys {
            guard let folderFiles = watchedFolderFiles[folderID] else { continue }
            watchedFolderFiles[folderID] = folderFiles.map { file in
                guard let newURL = urlsByID[file.id] else { return file }
                return file.withUpdatedURL(newURL)
            }
        }

        rebuildVisibleFiles()
    }

    func withSecurityScopedAccessForQuickImportURLs<T>(
        _ urls: [URL],
        perform body: () throws -> T
    ) rethrows -> T {
        var accessedURLs: [URL] = []
        let fileURLs = Self.urlsByKey(urls).values
        let directoryURLs = Self.parentDirectoryURLsByKey(for: urls).values

        for url in fileURLs {
            if url.startAccessingSecurityScopedResource() {
                accessedURLs.append(url)
            }
        }

        for directoryURL in directoryURLs {
            if directoryURL.startAccessingSecurityScopedResource() {
                accessedURLs.append(directoryURL)
            }
        }

        defer {
            for accessedURL in accessedURLs.reversed() {
                accessedURL.stopAccessingSecurityScopedResource()
            }
        }

        return try body()
    }

    func ensureRenameDirectoryAccess(for urls: [URL]) -> String? {
        guard currentFileSourceMode == .quickImport else { return nil }

        let directoryURLs = Self.parentDirectoryURLsByKey(for: urls).values.sorted(by: Self.compareURLs)
        for directoryURL in directoryURLs {
            if hasRenameDirectoryAccess(for: directoryURL) {
                continue
            }

            if let failure = requestRenameDirectoryAccess(for: directoryURL) {
                return failure
            }
        }

        return nil
    }

    func registerMovedFiles(_ changes: [(id: UUID, oldURL: URL, newURL: URL)]) {
        guard !changes.isEmpty else { return }

        let oldKeys = Set(changes.map { Self.urlKey(for: $0.oldURL) })
        for oldKey in oldKeys {
            fileIDsByKey.removeValue(forKey: oldKey)
        }

        for change in changes {
            fileIDsByKey[Self.urlKey(for: change.newURL)] = change.id
        }
    }

    func scheduleWatchedFolderRescan(for id: UUID, debounceMilliseconds: UInt64 = 350) {
        folderRescanTasks[id]?.cancel()

        folderRescanTasks[id] = Task { [weak self] in
            guard let self else { return }

            if debounceMilliseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceMilliseconds * 1_000_000)
            }

            guard !Task.isCancelled else { return }
            await self.rescanWatchedFolder(id: id)
        }
    }

    private func rescanWatchedFolder(id: UUID) async {
        guard let folder = watchedFolders.first(where: { $0.id == id }) else { return }

        let scanToken = UUID()
        folderScanTokens[id] = scanToken

        let snapshot = await Task.detached(priority: .utility) {
            Self.scanFolderSnapshot(for: folder.url)
        }.value

        let fileIDsByKey = prepareStableIDs(for: snapshot.audioURLs)

        let loadedFiles = await Task.detached(priority: .userInitiated) {
            await Self.loadAudioFiles(from: snapshot.audioURLs, fileIDsByKey: fileIDsByKey)
        }.value

        guard folderScanTokens[id] == scanToken else { return }

        watchedFolderFiles[id] = loadedFiles
        updateDirectoryMonitors(for: id, directories: snapshot.directoryURLs)
        rebuildVisibleFiles()
    }

    private func rebuildVisibleFiles() {
        let selection = normalizedSidebarSelection(activeSidebarSelection)
        activeSidebarSelection = selection

        switch selection {
        case .quickImport:
            files = quickImportFiles
        case .watchedLibrary:
            files = mergedWatchedFiles()
        case .watchedFolder(let id):
            files = watchedFolderFiles[id] ?? []
        }
    }

    private func normalizedSidebarSelection(_ selection: SidebarSelection) -> SidebarSelection {
        #if !os(macOS)
        return .quickImport
        #else
        switch selection {
        case .watchedFolder(let folderID):
            if watchedFolders.contains(where: { $0.id == folderID }) {
                return selection
            }
            return .watchedLibrary
        case .watchedLibrary:
            return .watchedLibrary
        case .quickImport:
            return .quickImport
        }
        #endif
    }

    private func mergedWatchedFiles() -> [AudioFile] {
        var seenKeys = Set<String>()
        var result: [AudioFile] = []

        for folder in watchedFolders {
            for file in watchedFolderFiles[folder.id] ?? [] {
                let key = Self.urlKey(for: file.url)
                guard seenKeys.insert(key).inserted else { continue }
                result.append(file)
            }
        }

        return result.sorted(by: Self.compareAudioFiles)
    }

    private func prepareStableIDs(for urls: [URL]) -> [String: UUID] {
        var ids: [String: UUID] = [:]

        for url in urls {
            let key = Self.urlKey(for: url)

            if let existingID = fileIDsByKey[key] {
                ids[key] = existingID
                continue
            }

            let id = UUID()
            fileIDsByKey[key] = id
            ids[key] = id
        }

        return ids
    }

    private func mergeFilesPreservingExistingOrder(existing: [AudioFile], incoming: [AudioFile]) -> [AudioFile] {
        var merged = existing
        var indicesByKey = Dictionary(
            uniqueKeysWithValues: existing.enumerated().map { (Self.urlKey(for: $0.element.url), $0.offset) }
        )

        for file in incoming {
            let key = Self.urlKey(for: file.url)

            if let index = indicesByKey[key] {
                merged[index] = file
            } else {
                indicesByKey[key] = merged.count
                merged.append(file)
            }
        }

        return merged
    }

    private func beginAccessingWatchedFolder(_ folder: WatchedFolder) {
        guard securityScopedFolderURLs[folder.id] == nil else { return }

        if folder.url.startAccessingSecurityScopedResource() {
            securityScopedFolderURLs[folder.id] = folder.url
        }
    }

    private func stopAccessingWatchedFolder(_ id: UUID) {
        guard let url = securityScopedFolderURLs.removeValue(forKey: id) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    private func stopWatchingFolder(id: UUID) {
        folderRescanTasks[id]?.cancel()
        folderRescanTasks[id] = nil

        folderDirectoryMonitors[id]?.values.forEach { $0.stop() }
        folderDirectoryMonitors[id] = nil

        stopAccessingWatchedFolder(id)
    }

    private func syncQuickImportSecurityScopedResources() {
        let quickImportURLs = quickImportFiles.map(\.url)
        let desiredFileURLsByKey = Self.urlsByKey(quickImportURLs)
        let desiredDirectoryURLsByKey = Self.parentDirectoryURLsByKey(for: quickImportURLs)

        for key in Array(securityScopedQuickImportFileURLs.keys) where desiredFileURLsByKey[key] == nil {
            securityScopedQuickImportFileURLs[key]?.stopAccessingSecurityScopedResource()
            securityScopedQuickImportFileURLs[key] = nil
        }

        for (key, url) in desiredFileURLsByKey where securityScopedQuickImportFileURLs[key] == nil {
            if url.startAccessingSecurityScopedResource() {
                securityScopedQuickImportFileURLs[key] = url
            }
        }

        for key in Array(securityScopedQuickImportDirectoryURLs.keys) where desiredDirectoryURLsByKey[key] == nil {
            securityScopedQuickImportDirectoryURLs[key]?.stopAccessingSecurityScopedResource()
            securityScopedQuickImportDirectoryURLs[key] = nil
        }

        for (key, url) in desiredDirectoryURLsByKey where securityScopedQuickImportDirectoryURLs[key] == nil {
            if url.startAccessingSecurityScopedResource() {
                securityScopedQuickImportDirectoryURLs[key] = url
            }
        }
    }

    private func beginAccessingQuickImportResources(for urls: [URL]) {
        let fileURLsByKey = Self.urlsByKey(urls)
        let directoryURLsByKey = Self.parentDirectoryURLsByKey(for: urls)

        for (key, url) in fileURLsByKey where securityScopedQuickImportFileURLs[key] == nil {
            if url.startAccessingSecurityScopedResource() {
                securityScopedQuickImportFileURLs[key] = url
            }
        }

        for (key, url) in directoryURLsByKey where securityScopedQuickImportDirectoryURLs[key] == nil {
            if url.startAccessingSecurityScopedResource() {
                securityScopedQuickImportDirectoryURLs[key] = url
            }
        }
    }

    private func hasRenameDirectoryAccess(for directoryURL: URL) -> Bool {
        let key = Self.urlKey(for: directoryURL)
        if securityScopedQuickImportRenameDirectoryURLs[key] != nil {
            return true
        }

        if securityScopedQuickImportDirectoryURLs[key] != nil {
            return true
        }

        return securityScopedFolderURLs.values.contains { folderURL in
            Self.isSameOrDescendant(directoryURL, of: folderURL)
        }
    }

    private func requestRenameDirectoryAccess(for directoryURL: URL) -> String? {
        #if os(macOS)
        let displayName = FileManager.default.displayName(atPath: directoryURL.path)
        let key = Self.urlKey(for: directoryURL)

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.directoryURL = directoryURL.deletingLastPathComponent()
        panel.title = "Allow Folder Access"
        panel.prompt = "Allow"
        panel.message = "To rename imported files, select the folder “\(displayName)”."

        guard panel.runModal() == .OK, let selectedURL = panel.url?.standardizedFileURL else {
            return "Renaming requires folder access for “\(displayName)”."
        }

        guard Self.urlKey(for: selectedURL) == key else {
            return "Select the exact folder “\(displayName)” to continue renaming."
        }

        guard selectedURL.startAccessingSecurityScopedResource() else {
            return "AudioMator couldn't access “\(displayName)” after you selected it."
        }

        securityScopedQuickImportRenameDirectoryURLs[key] = selectedURL
        return nil
        #else
        let displayName = FileManager.default.displayName(atPath: directoryURL.path)
        return "Renaming requires folder access for “\(displayName)”."
        #endif
    }

    private func updateDirectoryMonitors(for folderID: UUID, directories: [URL]) {
        #if os(macOS)
        let normalizedDirectories = Self.urlsByKey(directories)

        var monitors = folderDirectoryMonitors[folderID] ?? [:]

        for key in Array(monitors.keys) where normalizedDirectories[key] == nil {
            monitors[key]?.stop()
            monitors[key] = nil
        }

        for (key, directoryURL) in normalizedDirectories where monitors[key] == nil {
            guard let monitor = DirectoryMonitor(url: directoryURL, eventHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleWatchedFolderRescan(for: folderID)
                }
            }) else { continue }

            monitor.start()
            monitors[key] = monitor
        }

        folderDirectoryMonitors[folderID] = monitors
        #endif
    }

    private func persistWatchedFolders() {
        watchedFolderStore.saveFolders(watchedFolders)
    }

    nonisolated private static func loadAudioFiles(
        from urls: [URL],
        fileIDsByKey: [String: UUID],
        onBatchLoaded: (@Sendable ([AudioFile]) async -> Void)? = nil
    ) async -> [AudioFile] {
        let inputs: [(index: Int, url: URL, id: UUID)] = urls.enumerated().compactMap { offset, url in
            let key = urlKey(for: url)
            guard let id = fileIDsByKey[key] else { return nil }
            return (offset, url, id)
        }

        guard !inputs.isEmpty else { return [] }

        // Audio metadata reads are mostly I/O-bound. Allow higher parallelism than the
        // earlier fixed value so first import becomes interactive faster on larger drops.
        let maxConcurrentLoads = min(
            max(ProcessInfo.processInfo.activeProcessorCount * 2, 6),
            min(12, inputs.count)
        )
        let partialBatchSize = 24
        let forceFlushBatchSize = 48
        let minimumFlushInterval: TimeInterval = 0.2
        var nextInputIndex = maxConcurrentLoads
        var completedByIndex: [Int: AudioFile] = [:]
        completedByIndex.reserveCapacity(inputs.count)
        var loadedByIndex: [(Int, AudioFile)] = []
        loadedByIndex.reserveCapacity(inputs.count)
        var nextContiguousIndex = 0
        var pendingBatch: [AudioFile] = []
        pendingBatch.reserveCapacity(partialBatchSize)
        var lastFlushTime = Date.timeIntervalSinceReferenceDate

        await withTaskGroup(of: (Int, AudioFile?).self) { group in
            for input in inputs.prefix(maxConcurrentLoads) {
                group.addTask {
                    (
                        input.index,
                        try? await AudioFile(url: input.url, id: input.id)
                    )
                }
            }

            while let (index, file) = await group.next() {
                if let file {
                    completedByIndex[index] = file
                    loadedByIndex.append((index, file))

                    while let nextFile = completedByIndex.removeValue(forKey: nextContiguousIndex) {
                        pendingBatch.append(nextFile)
                        nextContiguousIndex += 1

                        let now = Date.timeIntervalSinceReferenceDate
                        let shouldFlush =
                            pendingBatch.count >= forceFlushBatchSize ||
                            (
                                pendingBatch.count >= partialBatchSize &&
                                now - lastFlushTime >= minimumFlushInterval
                            )

                        if shouldFlush, let onBatchLoaded {
                            await onBatchLoaded(pendingBatch)
                            pendingBatch.removeAll(keepingCapacity: true)
                            lastFlushTime = now
                        }
                    }
                }

                guard nextInputIndex < inputs.count else { continue }
                let input = inputs[nextInputIndex]
                nextInputIndex += 1

                group.addTask {
                    (
                        input.index,
                        try? await AudioFile(url: input.url, id: input.id)
                    )
                }
            }
        }

        if !pendingBatch.isEmpty, let onBatchLoaded {
            await onBatchLoaded(pendingBatch)
        }

        loadedByIndex.sort { $0.0 < $1.0 }
        return loadedByIndex.map(\.1)
    }

    nonisolated private static func scanFolderSnapshot(for folderURL: URL) -> FolderScanSnapshot {
        var audioURLs: [URL] = []
        var directoryURLs: [URL] = [folderURL.standardizedFileURL]
        var seenAudioKeys = Set<String>()
        var seenDirectoryKeys = Set([urlKey(for: folderURL)])

        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options
        ) else {
            return FolderScanSnapshot(audioURLs: audioURLs, directoryURLs: directoryURLs)
        }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: resourceKeys) else { continue }

            if values.isDirectory == true {
                let key = urlKey(for: url)
                if seenDirectoryKeys.insert(key).inserted {
                    directoryURLs.append(url.standardizedFileURL)
                }
                continue
            }

            guard values.isRegularFile == true else { continue }
            guard readableAudioExtensions.contains(url.pathExtension.lowercased()) else { continue }

            let key = urlKey(for: url)
            guard seenAudioKeys.insert(key).inserted else { continue }
            audioURLs.append(url.standardizedFileURL)
        }

        audioURLs.sort(by: compareURLs)
        directoryURLs.sort(by: compareURLs)

        return FolderScanSnapshot(audioURLs: audioURLs, directoryURLs: directoryURLs)
    }

    nonisolated private static func uniqueSortedURLs(_ urls: [URL]) -> [URL] {
        urlsByKey(urls).values.sorted(by: compareURLs)
    }

    nonisolated private static func urlsByKey(_ urls: [URL]) -> [String: URL] {
        var urlsByKey: [String: URL] = [:]

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            urlsByKey[urlKey(for: standardizedURL)] = standardizedURL
        }

        return urlsByKey
    }

    nonisolated private static func parentDirectoryURLsByKey(for urls: [URL]) -> [String: URL] {
        var directoryURLsByKey: [String: URL] = [:]

        for url in urls {
            let directoryURL = url.standardizedFileURL.deletingLastPathComponent()
            directoryURLsByKey[urlKey(for: directoryURL)] = directoryURL
        }

        return directoryURLsByKey
    }

    nonisolated private static func isSameOrDescendant(_ url: URL, of ancestorURL: URL) -> Bool {
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath().path
        let normalizedAncestorURL = ancestorURL.standardizedFileURL.resolvingSymlinksInPath().path

        if normalizedURL == normalizedAncestorURL {
            return true
        }

        let ancestorPrefix = normalizedAncestorURL == "/" ? "/" : normalizedAncestorURL + "/"
        return normalizedURL.hasPrefix(ancestorPrefix)
    }

    nonisolated private static func urlKey(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    nonisolated private static func compareAudioFiles(_ lhs: AudioFile, _ rhs: AudioFile) -> Bool {
        compareURLs(lhs.url, rhs.url)
    }

    nonisolated private static func compareURLs(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsName = lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent)
        if lhsName != .orderedSame {
            return lhsName == .orderedAscending
        }

        return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }
}

private struct FolderScanSnapshot {
    let audioURLs: [URL]
    let directoryURLs: [URL]
}
