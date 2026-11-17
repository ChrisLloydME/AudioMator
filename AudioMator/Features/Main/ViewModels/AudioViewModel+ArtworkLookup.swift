import Foundation
import AppKit

enum ArtworkLookupSource: String {
    case iTunesAlbumID = "iTunes Album ID"
    case album = "Album"
    case trackTitle = "Track Title"
}

struct ArtworkLookupRequestDescriptor {
    let query: String
    let entity: iTunesArtworkSearchEntity
    let source: ArtworkLookupSource

    var summary: String {
        "\(source.rawValue): \(query)"
    }
}

struct ArtworkLookupSession: Identifiable {
    let id = UUID()
    let fileIDs: [AudioFile.ID]
    let selectionTitle: String
    let request: ArtworkLookupRequestDescriptor
    var isLoading: Bool = true
    var isApplying: Bool = false
    var results: [iTunesArtworkSearchResult] = []
    var selectedResultID: iTunesArtworkSearchResult.ID?
    var errorMessage: String?
    var emptyMessage: String?
    var cancellationMessage: String?

    var isMultiSelection: Bool {
        fileIDs.count > 1
    }

    var selectedResult: iTunesArtworkSearchResult? {
        guard let selectedResultID else { return nil }
        return results.first { $0.id == selectedResultID }
    }
}

extension AudioViewModel {
    func artworkLookupDisabledReason(for file: AudioFile) -> String? {
        guard isArtworkWriteSupportedExtension(file.url.pathExtension) else {
            return L10n.string("This file format doesn't support saving embedded artwork in AudioMator.")
        }

        return makeArtworkLookupRequest(for: file) == nil
            ? "No iTunes Album ID, Album, or Track Title metadata is available for this file."
            : nil
    }

    func artworkLookupDisabledReason(for files: [AudioFile]) -> String? {
        let unsupportedFiles = files.filter { !isArtworkWriteSupportedExtension($0.url.pathExtension) }
        guard unsupportedFiles.isEmpty else {
            return L10n.string("Some selected files use formats that don't support saving embedded artwork in AudioMator.")
        }

        if makeArtworkLookupRequest(for: files) != nil {
            return nil
        }

        let hasAnyAlbumSignal = files.contains {
            !trimmedArtworkLookupValue($0.itunesAlbumID).isEmpty ||
            !trimmedArtworkLookupValue($0.album).isEmpty
        }

        if hasAnyAlbumSignal {
            return L10n.string("Online artwork lookup for multiple files is only available when all selected tracks belong to the same album.")
        }

        return L10n.string("To look up artwork for several files together, select files with the same iTunes Album ID or the same Album value.")
    }

    func findOnlineArtwork(for file: AudioFile) {
        if let reason = artworkLookupDisabledReason(for: file) {
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Can't Look Up Artwork for This Selection"),
                subtitle: reason
            )
            return
        }

        guard let request = makeArtworkLookupRequest(for: file) else { return }

        startArtworkLookup(
            fileIDs: [file.id],
            selectionTitle: file.url.lastPathComponent,
            request: request
        )
    }

    func findOnlineArtwork(for files: [AudioFile]) {
        if let reason = artworkLookupDisabledReason(for: files) {
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Can't Look Up Artwork for This Selection"),
                subtitle: reason
            )
            return
        }

        guard let request = makeArtworkLookupRequest(for: files) else { return }

        let selectionTitle: String
        if let sharedAlbum = sharedNonEmptyValue(files.map(\.album), caseInsensitive: true) {
            selectionTitle = sharedAlbum
        } else {
            selectionTitle = "\(files.count) selected files"
        }

        startArtworkLookup(
            fileIDs: files.map(\.id),
            selectionTitle: selectionTitle,
            request: request
        )
    }

    func dismissArtworkLookup() {
        artworkLookupTask?.cancel()
        artworkLookupTask = nil
        artworkLookupSession = nil
    }

    func selectArtworkLookupResult(id: iTunesArtworkSearchResult.ID) {
        guard var session = artworkLookupSession else { return }
        session.selectedResultID = id
        artworkLookupSession = session
    }

    func applySelectedArtworkLookupResult() {
        guard var session = artworkLookupSession,
              let selectedResult = session.selectedResult else {
            return
        }

        session.isApplying = true
        session.errorMessage = nil
        session.cancellationMessage = nil
        artworkLookupSession = session

        let sessionID = session.id
        let targetFileIDs = session.fileIDs
        let service = artworkLookupService
        let operationTimeout = artworkLookupOperationTimeout

        artworkLookupTask?.cancel()
        artworkLookupTask = Task { [weak self, service] in
            do {
                let downloadedArtwork = try await withAsyncTimeout(
                    operationTimeout,
                    operationName: String(localized: "Downloading artwork from iTunes")
                ) {
                    try await service.downloadArtworkData(for: selectedResult)
                }
                try Task.checkCancellation()

                let pendingArtwork = PendingArtwork(
                    data: downloadedArtwork.pngData,
                    mimeType: "image/png"
                )
                guard let self else { return }

                let targetFiles = files.filter { targetFileIDs.contains($0.id) }
                guard !targetFiles.isEmpty else {
                    throw NSError(
                        domain: "AudioMator.ArtworkLookup",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: String(localized: "The files selected for this artwork lookup are no longer available. Select the files again.")
                        ]
                    )
                }

                if targetFiles.count == 1, let targetFile = targetFiles.first {
                    applyArtworkEditAction(.replace(pendingArtwork), to: targetFile)
                } else {
                    applyArtworkEditAction(.replace(pendingArtwork), to: targetFiles)
                }

                guard artworkLookupSession?.id == sessionID else { return }
                artworkLookupSession = nil
                artworkLookupTask = nil
            } catch is CancellationError {
                guard let self else { return }
                guard var currentSession = artworkLookupSession, currentSession.id == sessionID else { return }
                currentSession.isApplying = false
                currentSession.errorMessage = nil
                currentSession.cancellationMessage = String(localized: "Artwork download cancelled.")
                artworkLookupSession = currentSession
                artworkLookupTask = nil
            } catch {
                guard let self else { return }
                guard var currentSession = artworkLookupSession, currentSession.id == sessionID else { return }
                currentSession.isApplying = false
                currentSession.errorMessage = (error as NSError).localizedDescription
                artworkLookupSession = currentSession
                artworkLookupTask = nil
            }
        }
    }

    private func startArtworkLookup(
        fileIDs: [AudioFile.ID],
        selectionTitle: String,
        request: ArtworkLookupRequestDescriptor
    ) {
        artworkLookupTask?.cancel()

        let session = ArtworkLookupSession(
            fileIDs: fileIDs,
            selectionTitle: selectionTitle,
            request: request
        )
        artworkLookupSession = session

        let sessionID = session.id
        let service = artworkLookupService
        let operationTimeout = artworkLookupOperationTimeout

        artworkLookupTask = Task { [weak self, service] in
            do {
                let searchRequest = iTunesArtworkSearchRequest(
                    query: request.query,
                    entity: request.entity
                )
                let results = try await withAsyncTimeout(
                    operationTimeout,
                    operationName: String(localized: "Searching iTunes for artwork")
                ) {
                    try await service.search(searchRequest)
                }
                try Task.checkCancellation()
                guard let self else { return }
                guard var currentSession = artworkLookupSession, currentSession.id == sessionID else { return }

                currentSession.isLoading = false
                currentSession.results = results
                currentSession.selectedResultID = results.first?.id
                currentSession.emptyMessage = results.isEmpty ? String(localized: "No artwork matches this search. Try a different album or artist name.") : nil
                currentSession.errorMessage = nil
                artworkLookupSession = currentSession
                artworkLookupTask = nil
            } catch is CancellationError {
                guard let self else { return }
                guard var currentSession = artworkLookupSession, currentSession.id == sessionID else { return }
                currentSession.isLoading = false
                currentSession.errorMessage = nil
                currentSession.cancellationMessage = String(localized: "Artwork search cancelled.")
                currentSession.emptyMessage = nil
                artworkLookupSession = currentSession
                artworkLookupTask = nil
            } catch {
                guard let self else { return }
                guard var currentSession = artworkLookupSession, currentSession.id == sessionID else { return }
                currentSession.isLoading = false
                currentSession.errorMessage = (error as NSError).localizedDescription
                currentSession.emptyMessage = nil
                artworkLookupSession = currentSession
                artworkLookupTask = nil
            }
        }
    }

    private func makeArtworkLookupRequest(for file: AudioFile) -> ArtworkLookupRequestDescriptor? {
        if let itunesAlbumID = nonEmptyArtworkLookupValue(file.itunesAlbumID) {
            return ArtworkLookupRequestDescriptor(
                query: itunesAlbumID,
                entity: .idAlbum,
                source: .iTunesAlbumID
            )
        }

        if let album = nonEmptyArtworkLookupValue(file.album) {
            return ArtworkLookupRequestDescriptor(
                query: album,
                entity: .album,
                source: .album
            )
        }

        if let trackTitle = nonEmptyArtworkLookupValue(file.title) {
            return ArtworkLookupRequestDescriptor(
                query: trackTitle,
                entity: .album,
                source: .trackTitle
            )
        }

        return nil
    }

    private func makeArtworkLookupRequest(for files: [AudioFile]) -> ArtworkLookupRequestDescriptor? {
        if let sharediTunesAlbumID = sharedNonEmptyValue(files.map(\.itunesAlbumID)) {
            return ArtworkLookupRequestDescriptor(
                query: sharediTunesAlbumID,
                entity: .idAlbum,
                source: .iTunesAlbumID
            )
        }

        if let sharedAlbum = sharedNonEmptyValue(files.map(\.album), caseInsensitive: true) {
            return ArtworkLookupRequestDescriptor(
                query: sharedAlbum,
                entity: .album,
                source: .album
            )
        }

        return nil
    }

    private func sharedNonEmptyValue(_ values: [String], caseInsensitive: Bool = false) -> String? {
        let trimmedValues = values.map(trimmedArtworkLookupValue)
        guard !trimmedValues.isEmpty else { return nil }
        guard let firstValue = trimmedValues.first, !firstValue.isEmpty else { return nil }

        let comparisonBase = caseInsensitive ? firstValue.lowercased() : firstValue
        return trimmedValues.dropFirst().allSatisfy {
            (caseInsensitive ? $0.lowercased() : $0) == comparisonBase
        } ? firstValue : nil
    }

    private func nonEmptyArtworkLookupValue(_ value: String) -> String? {
        let trimmedValue = trimmedArtworkLookupValue(value)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func trimmedArtworkLookupValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
