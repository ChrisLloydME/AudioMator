import Foundation
import AppKit

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
        guard var session = artworkLookupSession,
              session.canSelectCandidate,
              session.results.contains(where: { $0.id == id }) else {
            return
        }

        session.selectedResultID = id
        if let fault = session.downloadFault,
           fault.isRetryable,
           fault.candidateID != id {
            // A retryable candidate fault is replaced by choosing another
            // candidate; search and destination-draft faults are never cleared
            // by selecting.
            session.downloadFault = nil
        }
        artworkLookupSession = session
    }

    func applySelectedArtworkLookupResult() {
        guard var session = artworkLookupSession,
              session.canApplySelectedResult,
              let selectedResult = session.selectedResult else {
            return
        }

        let attempt = ArtworkLookupDownloadAttempt(id: UUID(), candidateID: selectedResult.id)
        session.download = attempt
        session.downloadFault = nil
        artworkLookupSession = session

        startArtworkDownload(
            sessionID: session.id,
            searchAttemptID: session.searchAttemptID,
            attempt: attempt,
            candidate: selectedResult
        )
    }

    /// Explicit Stop for the one in-flight download. The attempt identity is
    /// removed before the task is cancelled, so its late cancellation handler
    /// cannot publish state or clear a newer attempt.
    func cancelSelectedArtworkDownload() {
        guard var session = artworkLookupSession, let attempt = session.download else { return }

        session.download = nil
        session.downloadFault = .cancelled(
            candidateID: attempt.candidateID,
            message: String(localized: "Artwork download cancelled.")
        )
        artworkLookupSession = session

        artworkLookupTask?.cancel()
        artworkLookupTask = nil
    }

    /// Switches the active storefront for the open artwork lookup sheet, remembers
    /// the choice for later sessions, cancels any in-flight search, and starts a
    /// fresh search in the newly chosen region while preserving the captured draft
    /// transfer (and any terminal destination-draft fault).
    func selectArtworkLookupStorefront(_ storefront: iTunesStorefront) {
        guard var session = artworkLookupSession,
              session.canChangeStorefront,
              session.storefront != storefront else {
            return
        }

        artworkLookupStorefront = storefront

        let searchAttemptID = UUID()
        session.storefront = storefront
        session.searchAttemptID = searchAttemptID
        session.searchState = .searching
        session.results = []
        session.selectedResultID = nil
        if session.downloadFault?.isTransferFault != true {
            session.downloadFault = nil
        }
        session.emptyMessage = nil
        artworkLookupSession = session

        startArtworkSearch(
            sessionID: session.id,
            searchAttemptID: searchAttemptID,
            request: session.request,
            storefront: storefront
        )
    }

    /// Search-level retry inside the same sheet session, preserving the captured
    /// target/request context and active storefront. Only a failed search is retryable.
    func retryArtworkSearch() {
        guard var session = artworkLookupSession,
              session.showsSearchRetry,
              session.download == nil else {
            return
        }

        let searchAttemptID = UUID()
        session.searchAttemptID = searchAttemptID
        session.searchState = .searching
        session.results = []
        session.selectedResultID = nil
        session.download = nil
        if session.downloadFault?.isTransferFault != true {
            session.downloadFault = nil
        }
        session.emptyMessage = nil
        artworkLookupSession = session

        startArtworkSearch(
            sessionID: session.id,
            searchAttemptID: searchAttemptID,
            request: session.request,
            storefront: session.storefront
        )
    }

    private func startArtworkLookup(
        fileIDs: [AudioFile.ID],
        selectionTitle: String,
        request: ArtworkLookupRequestDescriptor
    ) {
        artworkLookupTask?.cancel()

        // Capture destination-draft authority before the first suspension. The
        // resolved ordered target set is the draft's captured target set, not
        // the visible projection passed by the caller.
        let command = beginArtworkCommand(for: fileIDs)
        let resolvedFileIDs = command?.targetIDs ?? fileIDs
        let storefront = artworkLookupStorefront
        let searchAttemptID = UUID()
        var session = ArtworkLookupSession(
            fileIDs: resolvedFileIDs,
            selectionTitle: selectionTitle,
            request: request,
            storefront: storefront,
            searchAttemptID: searchAttemptID
        )
        if let command {
            session.transfer = makeArtworkTransferIntent(
                command: command,
                source: .onlineLookup(sessionID: session.id)
            )
        }
        artworkLookupSession = session

        startArtworkSearch(
            sessionID: session.id,
            searchAttemptID: searchAttemptID,
            request: request,
            storefront: storefront
        )
    }

    private func startArtworkSearch(
        sessionID: UUID,
        searchAttemptID: UUID,
        request: ArtworkLookupRequestDescriptor,
        storefront: iTunesStorefront
    ) {
        let service = artworkLookupService
        let operationTimeout = artworkLookupOperationTimeout

        artworkLookupTask?.cancel()
        artworkLookupTask = Task { [weak self, service] in
            let outcome: Result<[iTunesArtworkSearchResult], Error>
            do {
                let searchRequest = iTunesArtworkSearchRequest(
                    query: request.query,
                    entity: request.entity,
                    country: storefront.countryCode
                )
                let results = try await withAsyncTimeout(
                    operationTimeout,
                    operationName: String(localized: "Searching iTunes for artwork")
                ) {
                    try await service.search(searchRequest)
                }
                try Task.checkCancellation()
                outcome = .success(results)
            } catch is CancellationError {
                outcome = .failure(CancellationError())
            } catch {
                outcome = .failure(error)
            }

            guard let self else { return }
            guard var currentSession = self.artworkLookupSession,
                  currentSession.id == sessionID,
                  currentSession.searchAttemptID == searchAttemptID,
                  currentSession.storefront == storefront else {
                return
            }

            switch outcome {
            case .success(let results):
                currentSession.searchState = .results
                currentSession.results = results
                currentSession.selectedResultID = results.first?.id
                currentSession.emptyMessage = results.isEmpty
                    ? String(localized: "No artwork matches this search in the \(storefront.displayName) storefront. Try another storefront, or check the album or artist name.")
                    : nil
            case .failure(let error):
                if error is CancellationError {
                    currentSession.searchState = .cancelled(message: String(localized: "Artwork search cancelled."))
                } else {
                    currentSession.searchState = .failed(message: (error as NSError).localizedDescription)
                }
                currentSession.emptyMessage = nil
            }

            self.artworkLookupSession = currentSession
            self.artworkLookupTask = nil
        }
    }

    private func startArtworkDownload(
        sessionID: UUID,
        searchAttemptID: UUID?,
        attempt: ArtworkLookupDownloadAttempt,
        candidate: iTunesArtworkSearchResult
    ) {
        let service = artworkLookupService
        let operationTimeout = artworkLookupOperationTimeout

        artworkLookupTask?.cancel()
        artworkLookupTask = Task { [weak self, service] in
            let outcome: Result<Data, Error>
            do {
                let downloadedArtwork = try await withAsyncTimeout(
                    operationTimeout,
                    operationName: String(localized: "Downloading artwork from iTunes")
                ) {
                    try await service.downloadArtworkData(for: candidate)
                }
                try Task.checkCancellation()
                outcome = .success(downloadedArtwork.pngData)
            } catch is CancellationError {
                outcome = .failure(CancellationError())
            } catch {
                outcome = .failure(error)
            }

            guard let self else { return }
            // This single check owns publication for the attempt: a stale
            // search/download handler must not publish an image, fault, or
            // progress state, nor clear the task handle of a newer attempt.
            guard var currentSession = self.artworkLookupSession,
                  currentSession.id == sessionID,
                  currentSession.searchAttemptID == searchAttemptID,
                  currentSession.download?.id == attempt.id else {
                return
            }

            switch outcome {
            case .success(let pngData):
                guard let intent = currentSession.transfer else {
                    currentSession.download = nil
                    currentSession.downloadFault = .staleSelection(
                        message: String(localized: "This artwork lookup isn’t connected to an editable Inspector draft, so the artwork wasn’t applied. Nothing was written. Select the intended files in the Inspector and use Fetch Online… again.")
                    )
                    self.artworkLookupSession = currentSession
                    self.artworkLookupTask = nil
                    return
                }

                // The guarded commit revalidates the captured draft session,
                // command generation and full ordered target set before staging.
                // A failure keeps the sheet open with results for reference.
                let pendingArtwork = PendingArtwork(data: pngData, mimeType: "image/png")
                switch self.commitArtworkTransfer(intent, action: .replace(pendingArtwork)) {
                case .staged:
                    self.artworkLookupSession = nil
                    self.artworkLookupTask = nil
                case .rejected(let rejection):
                    currentSession.download = nil
                    currentSession.downloadFault = self.artworkTransferRejectionForLookup(rejection)
                    self.artworkLookupSession = currentSession
                    self.artworkLookupTask = nil
                }
            case .failure(let error):
                currentSession.download = nil
                if error is CancellationError {
                    currentSession.downloadFault = .cancelled(
                        candidateID: attempt.candidateID,
                        message: String(localized: "Artwork download cancelled.")
                    )
                } else {
                    currentSession.downloadFault = .failed(
                        candidateID: attempt.candidateID,
                        message: (error as NSError).localizedDescription
                    )
                }
                self.artworkLookupSession = currentSession
                self.artworkLookupTask = nil
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
