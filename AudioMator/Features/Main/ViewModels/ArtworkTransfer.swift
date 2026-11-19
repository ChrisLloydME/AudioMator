import Foundation

/// Async preparation seam used by the local artwork handoffs. The live value
/// runs the production ImageIO normalization on the concurrent executor; tests
/// substitute a gated closure so the guard between capture and staging is
/// exercised deterministically.
typealias ArtworkDataNormalizer = @Sendable (Data) async throws -> Data

nonisolated enum ArtworkTransferNormalization {
    static let live: ArtworkDataNormalizer = { data in
        try await ArtworkImageNormalizer.normalizedPNGDataInBackground(from: data)
    }
}

/// Where an asynchronous artwork handoff was authorized.
enum ArtworkTransferSource: Equatable, Sendable {
    case onlineLookup(sessionID: UUID)
    case finder
    case photoLibrary
    case clipboard
    case clear
    case keep
}

/// Captured before the first suspension of an artwork command. It carries the
/// F3-owned draft command token (session ID, artwork generation, ordered target
/// IDs), an N4 attempt/transfer identity, the source context, and a diagnostic
/// selection label for localized rejection messages.
struct ArtworkTransferIntent: Equatable, Sendable {
    let id: UUID
    let command: ArtworkCommandToken
    let source: ArtworkTransferSource
    let selectionTitle: String
    let targetNames: [AudioFile.ID: String]

    var targetIDs: [AudioFile.ID] {
        command.targetIDs
    }

    init(
        id: UUID = UUID(),
        command: ArtworkCommandToken,
        source: ArtworkTransferSource,
        selectionTitle: String,
        targetNames: [AudioFile.ID: String]
    ) {
        self.id = id
        self.command = command
        self.source = source
        self.selectionTitle = selectionTitle
        self.targetNames = targetNames
    }
}

enum ArtworkTransferRejection: Equatable, Sendable {
    case noDestination(message: String)
    case draftChanged(message: String)
    case targetUnavailable(ids: [AudioFile.ID], message: String)
    case superseded(message: String)

    var message: String {
        switch self {
        case .noDestination(let message),
             .draftChanged(let message),
             .targetUnavailable(_, let message),
             .superseded(let message):
            return message
        }
    }

    var isSuperseded: Bool {
        if case .superseded = self { return true }
        return false
    }
}

enum ArtworkTransferOutcome: Equatable, Sendable {
    case staged
    case rejected(ArtworkTransferRejection)
}

extension AudioViewModel {
    // MARK: - Intent capture

    /// Captures the destination-draft authority for an artwork command before
    /// the first suspension. Returns nil when the current draft cannot authorize
    /// the command; callers treat that as preview-only / no destination.
    func captureArtworkTransfer(
        targetIDs: [AudioFile.ID],
        source: ArtworkTransferSource
    ) -> ArtworkTransferIntent? {
        guard let command = beginArtworkCommand(for: targetIDs) else { return nil }
        return makeArtworkTransferIntent(command: command, source: source)
    }

    /// Starts a new local artwork command and cancels any older local
    /// normalization. The returned intent must travel with the async completion.
    func beginArtworkImport(
        for file: AudioFile,
        source: ArtworkTransferSource
    ) -> ArtworkTransferIntent? {
        beginArtworkImport(targetIDs: [file.id], source: source)
    }

    func beginArtworkImport(
        for files: [AudioFile],
        source: ArtworkTransferSource
    ) -> ArtworkTransferIntent? {
        beginArtworkImport(targetIDs: files.map(\.id), source: source)
    }

    func beginPhotoLibraryArtworkImport(for file: AudioFile) -> ArtworkTransferIntent? {
        beginArtworkImport(for: file, source: .photoLibrary)
    }

    func beginPhotoLibraryArtworkImport(for files: [AudioFile]) -> ArtworkTransferIntent? {
        beginArtworkImport(for: files, source: .photoLibrary)
    }

    private func beginArtworkImport(
        targetIDs: [AudioFile.ID],
        source: ArtworkTransferSource
    ) -> ArtworkTransferIntent? {
        guard let intent = captureArtworkTransfer(targetIDs: targetIDs, source: source) else {
            return nil
        }
        artworkImportTask?.cancel()
        return intent
    }

    func makeArtworkTransferIntent(
        command: ArtworkCommandToken,
        source: ArtworkTransferSource
    ) -> ArtworkTransferIntent {
        let names = capturedArtworkTargetNames(for: command.targetIDs)
        let orderedNames = command.targetIDs.compactMap { names[$0] }
        let selectionTitle: String
        if orderedNames.count == 1, let name = orderedNames.first {
            selectionTitle = name
        } else {
            selectionTitle = String(
                localized: "\(command.targetIDs.count) selected files"
            )
        }
        return ArtworkTransferIntent(
            command: command,
            source: source,
            selectionTitle: selectionTitle,
            targetNames: names
        )
    }

    /// True while the captured command still belongs to the live draft session
    /// with the same ordered target set. Used to silence stale failures and to
    /// skip work whose destination is already gone; the full eligibility check
    /// still runs inside `commitArtworkTransfer`.
    func isArtworkTransferCurrent(_ intent: ArtworkTransferIntent) -> Bool {
        guard isCurrentArtworkCommand(intent.command) else { return false }
        guard let session = inspectorDraft, session.targetIDs == intent.command.targetIDs else {
            return false
        }
        return !intent.command.targetIDs.isEmpty
    }

    // MARK: - Guarded commit

    /// The only asynchronous artwork staging boundary. Every check runs before
    /// the first (and only) synchronous stage; a rejection mutates no draft.
    func commitArtworkTransfer(
        _ intent: ArtworkTransferIntent,
        action: ArtworkEditAction
    ) -> ArtworkTransferOutcome {
        guard isCurrentArtworkCommand(intent.command) else {
            return .rejected(artworkTransferStaleRejection(for: intent))
        }

        guard let session = inspectorDraft,
              session.targetIDs == intent.command.targetIDs else {
            return .rejected(artworkTransferStaleRejection(for: intent))
        }

        let capturedIDs = Set(intent.command.targetIDs)
        guard selectedAudioIDs == capturedIDs else {
            return .rejected(
                artworkTransferSelectionChangedRejection(for: intent)
            )
        }

        // Every captured target must still be present in source membership,
        // writable for artwork, and not blocked by recovery. No subset staging.
        var unavailableIDs: [AudioFile.ID] = []
        for targetID in intent.command.targetIDs {
            guard let file = committedFile(withID: targetID),
                  isArtworkWriteSupportedExtension(file.url.pathExtension),
                  !file.requiresMetadataRefreshBeforeWriting else {
                unavailableIDs.append(targetID)
                continue
            }
        }
        guard unavailableIDs.isEmpty else {
            return .rejected(
                .targetUnavailable(
                    ids: unavailableIDs,
                    message: String(
                        localized: "Some files from \(intent.selectionTitle) are no longer available, so the artwork wasn’t applied to any file. Nothing was written. Select the intended files again and choose the artwork again."
                    )
                )
            )
        }

        // Stage on the existing draft only. Never create or steal a draft.
        if intent.command.targetIDs.count == 1 {
            guard selectedAudioIDs.count == 1,
                  let targetID = intent.command.targetIDs.first,
                  editSourceFileID == targetID,
                  edit != nil else {
                return .rejected(artworkTransferSelectionChangedRejection(for: intent))
            }
        } else {
            guard multiEdit != nil else {
                return .rejected(artworkTransferSelectionChangedRejection(for: intent))
            }
        }

        guard completeArtworkHandoff(intent.command, action: action) else {
            return .rejected(
                .superseded(
                    message: String(
                        localized: "A newer artwork command replaced the unfinished one for \(intent.selectionTitle), so the older artwork wasn’t applied. Nothing was written."
                    )
                )
            )
        }
        return .staged
    }

    // MARK: - Completion helpers

    /// Normalizes and commits a completed local artwork command. A superseded
    /// intent is silent; a genuine decode failure is reported only while the
    /// intent is still current.
    @discardableResult
    func finishArtworkImport(
        imageData: Data,
        intent: ArtworkTransferIntent,
        normalize: ArtworkDataNormalizer = ArtworkTransferNormalization.live
    ) async -> ArtworkTransferOutcome? {
        guard isArtworkTransferCurrent(intent) else { return nil }

        let normalizedData: Data
        do {
            normalizedData = try await normalize(imageData)
            try Task.checkCancellation()
        } catch is CancellationError {
            return nil
        } catch {
            guard isArtworkTransferCurrent(intent) else { return nil }
            presentArtworkPreparationFailure(
                for: intent.selectionTitle,
                reason: (error as NSError).localizedDescription
            )
            return nil
        }

        return publishArtworkTransfer(
            intent,
            action: .replace(PendingArtwork(data: normalizedData, mimeType: "image/png"))
        )
    }

    /// Finder variant: the picked file is read under security scope, then
    /// normalized and committed through the same guarded boundary.
    @discardableResult
    func finishPickedArtworkImport(
        url: URL,
        intent: ArtworkTransferIntent,
        normalize: ArtworkDataNormalizer = ArtworkTransferNormalization.live
    ) async -> ArtworkTransferOutcome? {
        guard isArtworkTransferCurrent(intent) else { return nil }

        let data: Data
        do {
            data = try SecurityScopedResourceAccess.withAccess(to: url) {
                try Data(contentsOf: url, options: .mappedIfSafe)
            }
        } catch {
            guard isArtworkTransferCurrent(intent) else { return nil }
            presentArtworkPreparationFailure(
                for: intent.selectionTitle,
                reason: (error as NSError).localizedDescription
            )
            return nil
        }

        return await finishArtworkImport(
            imageData: data,
            intent: intent,
            normalize: normalize
        )
    }

    /// Photo-library completion. `nil` data presents the existing load failure
    /// only when the captured intent is still current.
    func finishPhotoLibraryArtworkImport(data: Data?, intent: ArtworkTransferIntent) {
        guard isArtworkTransferCurrent(intent) else { return }
        guard let data else {
            presentArtworkPreparationFailure(
                for: intent.selectionTitle,
                reason: String(localized: "AudioMator couldn't load this photo. Choose another photo or import an image file.")
            )
            return
        }

        artworkImportTask?.cancel()
        artworkImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.finishArtworkImport(imageData: data, intent: intent)
        }
    }

    // MARK: - Rejection publication

    func presentArtworkTransferNoDestination(for files: [AudioFile]) {
        let label: String
        if files.count == 1, let file = files.first {
            label = file.url.lastPathComponent
        } else {
            label = String(localized: "\(files.count) selected files")
        }
        presentArtworkTransferRejection(
            .noDestination(
                message: String(
                    localized: "This artwork can’t be applied because the Inspector doesn’t have an editable draft for \(label). Nothing was written. Select the intended files in the Inspector and choose the artwork again."
                )
            )
        )
    }

    func presentArtworkTransferRejection(_ rejection: ArtworkTransferRejection) {
        presentMetadataWriteHUD(
            style: .failure,
            title: String(localized: "Artwork Wasn’t Applied"),
            subtitle: rejection.message
        )
    }

    func artworkTransferRejectionForLookup(_ rejection: ArtworkTransferRejection) -> ArtworkLookupDownloadFault {
        switch rejection {
        case .superseded(let message):
            return .superseded(message: message)
        case .noDestination(let message),
             .draftChanged(let message),
             .targetUnavailable(_, let message):
            return .staleSelection(message: message)
        }
    }

    // MARK: - Private

    @discardableResult
    private func publishArtworkTransfer(
        _ intent: ArtworkTransferIntent,
        action: ArtworkEditAction
    ) -> ArtworkTransferOutcome? {
        let outcome = commitArtworkTransfer(intent, action: action)
        if case .rejected(let rejection) = outcome {
            presentArtworkTransferRejection(rejection)
        }
        return outcome
    }

    private func artworkTransferStaleRejection(
        for intent: ArtworkTransferIntent
    ) -> ArtworkTransferRejection {
        guard let session = inspectorDraft else {
            return artworkTransferTargetsGoneWithoutDraftRejection(for: intent)
        }
        if session.id != intent.command.sessionID
            || session.targetIDs != intent.command.targetIDs {
            return artworkTransferDraftChangedRejection(for: intent)
        }
        return .superseded(
            message: String(
                localized: "A newer artwork command replaced the unfinished one for \(intent.selectionTitle), so the older artwork wasn’t applied. Nothing was written."
            )
        )
    }

    private func artworkTransferTargetsGoneWithoutDraftRejection(
        for intent: ArtworkTransferIntent
    ) -> ArtworkTransferRejection {
        .noDestination(
            message: String(
                localized: "This artwork can’t be applied because the Inspector doesn’t have an editable draft for \(intent.selectionTitle). Nothing was written. Select the intended files in the Inspector and choose the artwork again."
            )
        )
    }

    private func artworkTransferDraftChangedRejection(
        for intent: ArtworkTransferIntent
    ) -> ArtworkTransferRejection {
        .draftChanged(
            message: String(
                localized: "The Inspector draft changed before the artwork for \(intent.selectionTitle) finished loading, so nothing was applied. Select the intended files again and choose the artwork again."
            )
        )
    }

    private func artworkTransferSelectionChangedRejection(
        for intent: ArtworkTransferIntent
    ) -> ArtworkTransferRejection {
        .targetUnavailable(
            ids: intent.command.targetIDs,
            message: String(
                localized: "The Inspector selection no longer matches \(intent.selectionTitle), so the artwork wasn’t applied. Nothing was written. Select the intended files again and choose the artwork again."
            )
        )
    }

    private func capturedArtworkTargetNames(
        for targetIDs: [AudioFile.ID]
    ) -> [AudioFile.ID: String] {
        var names: [AudioFile.ID: String] = [:]
        for targetID in targetIDs {
            if let file = inspectorDraft?.baselinesByID[targetID]
                ?? inspectorEditSourceFilesByID[targetID]
                ?? committedFile(withID: targetID) {
                names[targetID] = file.url.lastPathComponent
            } else {
                names[targetID] = String(localized: "Unknown file")
            }
        }
        return names
    }
}
