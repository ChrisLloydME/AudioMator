//
//  AudioViewModel.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import Combine
import AppKit

private let metadataWriteSuccessHUDDuration: Duration = .seconds(2.3)
let supportedAudioImportExtensions: Set<String> = [
    "mp3", "aac",
    "m4a", "m4b", "m4p", "mp4",
    "wav", "aiff", "aif",
    "flac"
]

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

@MainActor
final class AudioViewModel: ObservableObject {
    // All audio files currently loaded into the middle list.
    @Published var files: [AudioFile] = []
    @Published private(set) var watchedFolders: [WatchedFolder] = []
    // Current selection in the middle list. Multi-select is supported, but single-file editing uses the first item only.
    @Published var selectedAudioIDs: Set<UUID> = []
    // Single-file edit model bound to the right-side inspector.
    @Published var edit: SingleFileEditModel?
    @Published var metadataWriteHUD: MetadataWriteHUD?

    private let watchedFolderStore: WatchedFolderStore
    private var metadataWriteHUDDismissTask: Task<Void, Never>?
    private var pendingMetadataWriteHUDs: [MetadataWriteHUD] = []
    private var quickImportFiles: [AudioFile] = []
    private var watchedFolderFiles: [UUID: [AudioFile]] = [:]
    private var activeSidebarSelection: SidebarSelection = .quickImport
    private var fileIDsByKey: [String: UUID] = [:]
    private var folderRescanTasks: [UUID: Task<Void, Never>] = [:]
    private var folderDirectoryMonitors: [UUID: [String: DirectoryMonitor]] = [:]
    private var securityScopedFolderURLs: [UUID: URL] = [:]
    private var folderScanTokens: [UUID: UUID] = [:]

    init(watchedFolderStore: WatchedFolderStore = WatchedFolderStore()) {
        self.watchedFolderStore = watchedFolderStore

        let restoredFolders = watchedFolderStore.loadFolders()
        self.watchedFolders = restoredFolders

        for folder in restoredFolders {
            beginAccessingWatchedFolder(folder)
            updateDirectoryMonitors(for: folder.id, directories: [folder.url])
            scheduleWatchedFolderRescan(for: folder.id, debounceMilliseconds: 0)
        }

        rebuildVisibleFiles()
    }

    deinit {
        metadataWriteHUDDismissTask?.cancel()
        folderRescanTasks.values.forEach { $0.cancel() }
        folderDirectoryMonitors.values.flatMap(\.values).forEach { $0.stop() }
        securityScopedFolderURLs.values.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    var currentFileSourceMode: FileSourceMode {
        normalizedSidebarSelection(activeSidebarSelection).sourceMode
    }

    var hasUnsavedInspectorChanges: Bool {
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
        guard
            let id = selectedAudioIDs.first,
            let file = files.first(where: { $0.id == id })
        else {
            edit = nil
            return
        }

        edit = SingleFileEditModel(from: file)
    }

    /// Discard the current edits and restore the latest tags from disk.
    func cancelEditing() {
        updateEditForSelection()
    }

    func presentMetadataWriteSuccess(for fileName: String) {
        enqueueMetadataWriteHUD(
            style: .success,
            title: "Saved to Disk",
            subtitle: fileName
        )
    }

    func presentMetadataWriteWarning(title: String, subtitle: String) {
        enqueueMetadataWriteHUD(
            style: .warning,
            title: title,
            subtitle: subtitle
        )
    }

    func presentMetadataWriteFailure(for fileName: String, reason: String) {
        enqueueMetadataWriteHUD(
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
        rebuildVisibleFiles()
    }

    func importQuickFiles(from urls: [URL]) {
        let candidateURLs = Self.uniqueSortedURLs(urls)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let fileIDsByKey = await MainActor.run {
                self.prepareStableIDs(for: candidateURLs)
            }

            let loadedFiles = await Self.loadAudioFiles(from: candidateURLs, fileIDsByKey: fileIDsByKey)

            await MainActor.run {
                self.mergeQuickImportFiles(loadedFiles)
            }
        }
    }

    func clearQuickImportFiles() {
        quickImportFiles.removeAll()
        activeSidebarSelection = normalizedSidebarSelection(activeSidebarSelection)
        rebuildVisibleFiles()
    }

    func removeQuickImportFile(id: UUID) {
        quickImportFiles.removeAll { $0.id == id }
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

        stopAccessingWatchedFolder(id)
    }

    private func updateDirectoryMonitors(for folderID: UUID, directories: [URL]) {
        let normalizedDirectories = Dictionary(
            uniqueKeysWithValues: directories.map { (Self.urlKey(for: $0), $0.standardizedFileURL) }
        )

        var monitors = folderDirectoryMonitors[folderID] ?? [:]

        for key in monitors.keys where normalizedDirectories[key] == nil {
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
    }

    private func persistWatchedFolders() {
        watchedFolderStore.saveFolders(watchedFolders)
    }

    nonisolated private static func loadAudioFiles(from urls: [URL], fileIDsByKey: [String: UUID]) async -> [AudioFile] {
        var loaded: [AudioFile] = []
        loaded.reserveCapacity(urls.count)

        for url in urls {
            let key = urlKey(for: url)
            guard let id = fileIDsByKey[key] else { continue }

            if let file = try? await AudioFile(url: url, id: id) {
                loaded.append(file)
            }
        }

        return loaded
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
            guard supportedAudioImportExtensions.contains(url.pathExtension.lowercased()) else { continue }

            let key = urlKey(for: url)
            guard seenAudioKeys.insert(key).inserted else { continue }
            audioURLs.append(url.standardizedFileURL)
        }

        audioURLs.sort(by: compareURLs)
        directoryURLs.sort(by: compareURLs)

        return FolderScanSnapshot(audioURLs: audioURLs, directoryURLs: directoryURLs)
    }

    nonisolated private static func uniqueSortedURLs(_ urls: [URL]) -> [URL] {
        var uniqueURLsByKey: [String: URL] = [:]

        for url in urls {
            uniqueURLsByKey[urlKey(for: url)] = url.standardizedFileURL
        }

        return uniqueURLsByKey.values.sorted(by: compareURLs)
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
