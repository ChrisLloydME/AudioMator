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
    nonisolated private static let readableAudioExtensions = AudioFormatSupport.readableExtensions
    nonisolated private static let maximumDirectoryMonitorsPerFolder = 128

    // All audio files currently loaded into the middle list.
    @Published var files: [AudioFile] = []
    @Published private(set) var watchedFolders: [WatchedFolder] = []
    // Current selection in the middle list. Single-file and multi-file inspector editing both use this selection.
    @Published var selectedAudioIDs: Set<UUID> = []
    // Inspector edit models bound to the right-side inspector.
    @Published var editSourceFileID: UUID?
    @Published var edit: SingleFileEditModel? {
        didSet {
            if edit == nil {
                editSourceFileID = nil
            }
        }
    }
    @Published var multiEdit: MultiFileEditModel?
    @Published var metadataWriteHUD: MetadataWriteHUD?
    @Published var artworkLookupSession: ArtworkLookupSession?
    @Published var metadataSaveProgress: MetadataSaveProgress?
    @Published private(set) var directoryMonitoringStatuses: [UUID: DirectoryMonitoringStatus] = [:]

    private let watchedFolderStore: WatchedFolderStore
    let metadataPipeline: any AudioMetadataPipeline
    let saveIssueLogStore: SaveIssueLogStore
    let fileMutationCoordinator = FileMutationCoordinator()
    let artworkLookupService = iTunesArtworkService()
    private var metadataWriteHUDDismissTask: Task<Void, Never>?
    var artworkLookupTask: Task<Void, Never>?
    private var pendingMetadataWriteHUDs: [MetadataWriteHUD] = []
    private var quickImportFiles: [AudioFile] = []
    private var quickImportGeneration: UInt64 = 0
    private var quickImportTasks: [UUID: Task<Void, Never>] = [:]
    private var quickImportLoadingURLs: [UUID: [URL]] = [:]
    private var watchedFolderFiles: [UUID: [AudioFile]] = [:]
    private var activeSidebarSelection: SidebarSelection = .quickImport
    private var fileIDsByKey: [String: UUID] = [:]
    private var folderRescanTasks: [UUID: Task<Void, Never>] = [:]
    private var folderDirectoryMonitors: [UUID: [String: DirectoryMonitor]] = [:]
    private var watchedFolderScanFailureCounts: [UUID: Int] = [:]
    private var watchedFolderMetadataReadFailureCounts: [UUID: Int] = [:]
    private var securityScopedFolderURLs: [UUID: URL] = [:]
    private var securityScopedQuickImportFileURLs: [String: URL] = [:]
    private var securityScopedQuickImportDirectoryURLs: [String: URL] = [:]
    private var securityScopedQuickImportRenameDirectoryURLs: [String: URL] = [:]
    private var folderScanTokens: [UUID: UUID] = [:]

    convenience init() {
        self.init(
            watchedFolderStore: WatchedFolderStore(),
            metadataPipeline: TagLibAudioMetadataPipeline(),
            saveIssueLogStore: SaveIssueLogStore()
        )
    }

    convenience init(metadataPipeline: any AudioMetadataPipeline) {
        self.init(
            watchedFolderStore: WatchedFolderStore(),
            metadataPipeline: metadataPipeline,
            saveIssueLogStore: SaveIssueLogStore()
        )
    }

    convenience init(
        metadataPipeline: any AudioMetadataPipeline,
        saveIssueLogStore: SaveIssueLogStore
    ) {
        self.init(
            watchedFolderStore: WatchedFolderStore(),
            metadataPipeline: metadataPipeline,
            saveIssueLogStore: saveIssueLogStore
        )
    }

    init(
        watchedFolderStore: WatchedFolderStore,
        metadataPipeline: any AudioMetadataPipeline,
        saveIssueLogStore: SaveIssueLogStore
    ) {
        self.watchedFolderStore = watchedFolderStore
        self.metadataPipeline = metadataPipeline
        self.saveIssueLogStore = saveIssueLogStore

        let restoredFolders = PlatformApplication.supportsWatchedFolders
            ? watchedFolderStore.loadFolders()
            : []
        self.watchedFolders = restoredFolders

        for folder in restoredFolders {
            beginAccessingWatchedFolder(folder)
            updateDirectoryMonitors(for: folder.id, directories: [folder.url])
            scheduleWatchedFolderRescan(for: folder.id, debounceMilliseconds: 0)
        }

        rebuildVisibleFiles()
    }

    deinit {
        artworkLookupTask?.cancel()
        metadataWriteHUDDismissTask?.cancel()
        quickImportTasks.values.forEach { $0.cancel() }
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
            let edit,
            editSourceFileID == id
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
            editSourceFileID = nil
            multiEdit = nil
            return
        }

        if selectedAudioIDs.count == 1,
           let selectedID = selectedAudioIDs.first,
           let selectedFile = files.first(where: { $0.id == selectedID }) {
            edit = SingleFileEditModel(from: selectedFile)
            editSourceFileID = selectedID
            multiEdit = nil
            return
        }

        let selectedFiles = files.filter { selectedAudioIDs.contains($0.id) }
        guard !selectedFiles.isEmpty else {
            edit = nil
            editSourceFileID = nil
            multiEdit = nil
            return
        }

        edit = nil
        editSourceFileID = nil
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

    func presentMetadataWriteWarning(
        title: String,
        subtitle: String,
        operation: BatchMetadataOperationKind = .write
    ) {
        let lines = subtitle.components(separatedBy: .newlines)
        let fileName = lines.first ?? ""
        let messages = Array(lines.dropFirst())
        saveIssueLogStore.recordSingleIssue(
            title: title,
            subtitle: subtitle,
            fileName: fileName,
            messages: messages.isEmpty ? [subtitle] : messages,
            severity: .warning,
            operation: operation
        )

        presentMetadataWriteHUD(
            style: .warning,
            title: title,
            subtitle: subtitle
        )
    }

    func presentMetadataWriteFailure(for fileName: String, reason: String) {
        let subtitle = [fileName, reason]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        saveIssueLogStore.recordSingleIssue(
            title: "Save Failed",
            subtitle: subtitle,
            fileName: fileName,
            messages: [reason],
            severity: .failure
        )

        presentMetadataWriteHUD(
            style: .failure,
            title: "Save Failed",
            subtitle: subtitle
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
        guard PlatformApplication.supportsWatchedFolders else { return nil }

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
        var failedFolderNames: [String] = []
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
                failedFolderNames.append(FileManager.default.displayName(atPath: url.path))
            }
        }

        if !failedFolderNames.isEmpty {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "Folder Not Added"),
                subtitle: Self.watchedFolderAccessFailureMessage(for: failedFolderNames)
            )
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

    nonisolated static func watchedFolderAccessFailureMessage(for displayNames: [String]) -> String {
        guard let firstName = displayNames.first else { return "" }
        if displayNames.count == 1 {
            return String(localized: "AudioMator couldn't save access to “\(firstName)”.")
        }
        return String(localized: "AudioMator couldn't save access to \(displayNames.count) selected folders.")
    }

    func removeWatchedFolder(id: UUID) {
        guard watchedFolders.contains(where: { $0.id == id }) else { return }

        stopWatchingFolder(id: id)
        watchedFolders.removeAll { $0.id == id }
        watchedFolderFiles[id] = nil
        watchedFolderScanFailureCounts[id] = nil
        watchedFolderMetadataReadFailureCounts[id] = nil
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
        guard !candidateURLs.isEmpty else { return }

        let taskID = UUID()
        let generation = quickImportGeneration
        quickImportLoadingURLs[taskID] = candidateURLs
        beginAccessingQuickImportResources(for: candidateURLs)

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let context: (fileIDsByKey: [String: UUID], metadataPipeline: any AudioMetadataPipeline)? = await MainActor.run { [weak self] in
                guard let self, self.quickImportGeneration == generation else { return nil }
                return (
                    fileIDsByKey: self.prepareStableIDs(for: candidateURLs),
                    metadataPipeline: self.metadataPipeline
                )
            }

            guard let context, !Task.isCancelled else {
                await MainActor.run { [weak self] in
                    self?.finishQuickImportTask(taskID)
                }
                return
            }

            let loadResult = await Self.loadAudioFiles(
                from: candidateURLs,
                fileIDsByKey: context.fileIDsByKey,
                metadataPipeline: context.metadataPipeline,
                onBatchLoaded: { [weak self] batch in
                    guard !batch.isEmpty, !Task.isCancelled else { return }
                    await MainActor.run { [weak self] in
                        guard let self, self.quickImportGeneration == generation else { return }
                        self.mergeQuickImportFiles(batch)
                    }
                }
            )

            let shouldReportFailures = !Task.isCancelled
            await MainActor.run { [weak self] in
                guard let self else { return }
                if shouldReportFailures, self.quickImportGeneration == generation {
                    self.mergeQuickImportFiles(loadResult.files)
                }
                self.finishQuickImportTask(taskID)
                if shouldReportFailures, self.quickImportGeneration == generation {
                    self.presentQuickImportFailures(loadResult.failures)
                }
            }
        }
        quickImportTasks[taskID] = task
    }

    func clearQuickImportFiles() {
        quickImportGeneration &+= 1
        quickImportTasks.values.forEach { $0.cancel() }
        quickImportTasks.removeAll()
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
        perform body: () async throws -> T
    ) async rethrows -> T {
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

        return try await body()
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

        let scanTask = Task.detached(priority: .utility) {
            Self.scanFolderSnapshot(for: folder.url)
        }
        let snapshot = await withTaskCancellationHandler {
            await scanTask.value
        } onCancel: {
            scanTask.cancel()
        }
        guard !Task.isCancelled else { return }
        guard folderScanTokens[id] == scanToken else { return }

        if snapshot.scanFailureCount > 0 {
            watchedFolderScanFailureCounts[id] = snapshot.scanFailureCount
            let retainedMonitorKeys = folderDirectoryMonitors[id].map { Array($0.keys) } ?? []
            let retainedMonitorURLs = retainedMonitorKeys.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            updateDirectoryMonitors(
                for: id,
                directories: snapshot.directoryURLs + retainedMonitorURLs
            )
            rebuildVisibleFiles()
            return
        }

        watchedFolderScanFailureCounts[id] = 0

        let fileIDsByKey = prepareStableIDs(for: snapshot.audioURLs)
        let metadataPipeline = self.metadataPipeline

        let loadTask = Task.detached(priority: .userInitiated) {
            await Self.loadAudioFiles(
                from: snapshot.audioURLs,
                fileIDsByKey: fileIDsByKey,
                metadataPipeline: metadataPipeline
            )
        }
        let loadResult = await withTaskCancellationHandler {
            await loadTask.value
        } onCancel: {
            loadTask.cancel()
        }

        guard !Task.isCancelled else { return }
        guard folderScanTokens[id] == scanToken else { return }

        let previousFilesByKey = Dictionary(
            uniqueKeysWithValues: (watchedFolderFiles[id] ?? []).map { (Self.urlKey(for: $0.url), $0) }
        )
        var refreshedFilesByKey = Dictionary(
            uniqueKeysWithValues: loadResult.files.map { (Self.urlKey(for: $0.url), $0) }
        )
        for failure in loadResult.failures {
            let key = Self.urlKey(for: failure.url)
            if let previousFile = previousFilesByKey[key] {
                refreshedFilesByKey[key] = previousFile
            }
        }

        watchedFolderFiles[id] = snapshot.audioURLs.compactMap { url in
            refreshedFilesByKey[Self.urlKey(for: url)]
        }
        watchedFolderMetadataReadFailureCounts[id] = loadResult.failures.count
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
        directoryMonitoringStatuses[id] = nil

        stopAccessingWatchedFolder(id)
    }

    private func syncQuickImportSecurityScopedResources() {
        let quickImportURLs = quickImportFiles.map(\.url) + quickImportLoadingURLs.values.flatMap { $0 }
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

    private func finishQuickImportTask(_ taskID: UUID) {
        quickImportTasks[taskID] = nil
        quickImportLoadingURLs[taskID] = nil
        syncQuickImportSecurityScopedResources()
    }

    private func presentQuickImportFailures(_ failures: [AudioFileLoadFailure]) {
        guard !failures.isEmpty else { return }

        var lines = failures.prefix(3).map { failure in
            let fileName = failure.url.lastPathComponent
            let reason = failure.reason.replacingOccurrences(of: failure.url.path, with: fileName)
            return "\(fileName): \(reason)"
        }
        if failures.count > lines.count {
            lines.append("...and \(failures.count - lines.count) more")
        }

        presentMetadataWriteHUD(
            style: .warning,
            title: failures.count == 1 ? "File Not Imported" : "Some Files Were Not Imported",
            subtitle: lines.joined(separator: "\n")
        )
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
        let displayName = FileManager.default.displayName(atPath: directoryURL.path)
        let key = Self.urlKey(for: directoryURL)

        #if os(macOS)
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
        if directoryURL.startAccessingSecurityScopedResource() {
            securityScopedQuickImportRenameDirectoryURLs[key] = directoryURL
            return nil
        }

        return "iPadOS can't request extra folder access here. Keep renamed files inside the imported session scope."
        #endif
    }

    private func updateDirectoryMonitors(for folderID: UUID, directories: [URL]) {
        guard let rootURL = watchedFolders.first(where: { $0.id == folderID })?.url else { return }
        let plan = DirectoryMonitoringPlan.make(
            directories: directories,
            rootURL: rootURL,
            limit: Self.maximumDirectoryMonitorsPerFolder
        )
        let normalizedDirectories = Self.urlsByKey(plan.monitoredURLs)

        var monitors = folderDirectoryMonitors[folderID] ?? [:]
        var failedToOpenCount = 0

        for key in Array(monitors.keys) where normalizedDirectories[key] == nil {
            monitors[key]?.stop()
            monitors[key] = nil
        }

        for (key, directoryURL) in normalizedDirectories where monitors[key] == nil {
            guard let monitor = DirectoryMonitor(url: directoryURL, eventHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleWatchedFolderRescan(for: folderID)
                }
            }) else {
                failedToOpenCount += 1
                continue
            }

            monitor.start()
            monitors[key] = monitor
        }

        folderDirectoryMonitors[folderID] = monitors
        directoryMonitoringStatuses[folderID] = DirectoryMonitoringStatus(
            totalDirectoryCount: plan.totalDirectoryCount,
            monitoredDirectoryCount: monitors.count,
            omittedByLimitCount: plan.omittedByLimitCount,
            failedToOpenCount: failedToOpenCount,
            scanFailureCount: watchedFolderScanFailureCounts[folderID] ?? 0,
            metadataReadFailureCount: watchedFolderMetadataReadFailureCounts[folderID] ?? 0
        )
    }

    private func persistWatchedFolders() {
        watchedFolderStore.saveFolders(watchedFolders)
    }

    nonisolated private static func loadAudioFiles(
        from urls: [URL],
        fileIDsByKey: [String: UUID],
        metadataPipeline: any AudioMetadataPipeline,
        onBatchLoaded: (@Sendable ([AudioFile]) async -> Void)? = nil
    ) async -> AudioFileLoadResult {
        let inputs: [(index: Int, url: URL, id: UUID)] = urls.enumerated().compactMap { offset, url in
            let key = urlKey(for: url)
            guard let id = fileIDsByKey[key] else { return nil }
            return (offset, url, id)
        }

        guard !inputs.isEmpty else { return AudioFileLoadResult(files: [], failures: []) }
        guard !Task.isCancelled else { return AudioFileLoadResult(files: [], failures: []) }

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
        var failuresByIndex: [(Int, AudioFileLoadFailure)] = []
        var nextContiguousIndex = 0
        var pendingBatch: [AudioFile] = []
        pendingBatch.reserveCapacity(partialBatchSize)
        var lastFlushTime = Date.timeIntervalSinceReferenceDate

        await withTaskGroup(of: (Int, URL, AudioFile?, String?).self) { group in
            for input in inputs.prefix(maxConcurrentLoads) {
                group.addTask {
                    guard !Task.isCancelled else { return (input.index, input.url, nil, nil) }
                    do {
                        return (
                            input.index,
                            input.url,
                            try await metadataPipeline.loadAudioFile(at: input.url, id: input.id),
                            nil
                        )
                    } catch is CancellationError {
                        return (input.index, input.url, nil, nil)
                    } catch {
                        return (input.index, input.url, nil, (error as NSError).localizedDescription)
                    }
                }
            }

            while let (index, url, file, failureReason) = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

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

                        if shouldFlush, let onBatchLoaded, !Task.isCancelled {
                            await onBatchLoaded(pendingBatch)
                            pendingBatch.removeAll(keepingCapacity: true)
                            lastFlushTime = now
                        }
                    }
                } else if let failureReason {
                    failuresByIndex.append(
                        (
                            index,
                            AudioFileLoadFailure(
                                url: url,
                                reason: failureReason
                            )
                        )
                    )
                }

                guard nextInputIndex < inputs.count else { continue }
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                let input = inputs[nextInputIndex]
                nextInputIndex += 1

                group.addTask {
                    guard !Task.isCancelled else { return (input.index, input.url, nil, nil) }
                    do {
                        return (
                            input.index,
                            input.url,
                            try await metadataPipeline.loadAudioFile(at: input.url, id: input.id),
                            nil
                        )
                    } catch is CancellationError {
                        return (input.index, input.url, nil, nil)
                    } catch {
                        return (input.index, input.url, nil, (error as NSError).localizedDescription)
                    }
                }
            }
        }

        if !pendingBatch.isEmpty, let onBatchLoaded, !Task.isCancelled {
            await onBatchLoaded(pendingBatch)
        }

        loadedByIndex.sort { $0.0 < $1.0 }
        failuresByIndex.sort { $0.0 < $1.0 }
        return AudioFileLoadResult(
            files: loadedByIndex.map(\.1),
            failures: failuresByIndex.map(\.1)
        )
    }

    nonisolated private static func scanFolderSnapshot(for folderURL: URL) -> FolderScanSnapshot {
        var audioURLs: [URL] = []
        var directoryURLs: [URL] = [folderURL.standardizedFileURL]
        var scanFailureCount = 0
        var seenAudioKeys = Set<String>()
        var seenDirectoryKeys = Set([urlKey(for: folderURL)])

        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options,
            errorHandler: { _, _ in
                scanFailureCount += 1
                return true
            }
        ) else {
            return FolderScanSnapshot(
                audioURLs: audioURLs,
                directoryURLs: directoryURLs,
                scanFailureCount: 1
            )
        }

        for case let url as URL in enumerator {
            guard !Task.isCancelled else { break }
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: resourceKeys)
            } catch {
                scanFailureCount += 1
                continue
            }

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

        return FolderScanSnapshot(
            audioURLs: audioURLs,
            directoryURLs: directoryURLs,
            scanFailureCount: scanFailureCount
        )
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
    let scanFailureCount: Int
}

private struct AudioFileLoadFailure: Sendable {
    let url: URL
    let reason: String
}

private struct AudioFileLoadResult: Sendable {
    let files: [AudioFile]
    let failures: [AudioFileLoadFailure]
}
