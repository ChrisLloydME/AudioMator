import Foundation
import UniformTypeIdentifiers
import AppKit

extension AudioViewModel {
    // MARK: - File Import

    func addFiles() {
        guard currentFileSourceMode == .quickImport else { return }
        MacDocumentPicker.pickAudioFiles { [weak self] urls in
            guard !urls.isEmpty else { return }
            Task { @MainActor in
                self?.importQuickFiles(from: urls)
            }
        }
    }

    func presentArtworkPreparationFailure(for fileName: String, reason: String) {
        presentMetadataWriteHUD(
            style: .failure,
            title: String(localized: "Artwork Couldn’t Be Updated"),
            subtitle: fileName + "\n" + reason,
            summary: fileName,
            details: reason
        )
    }

    // MARK: - Finder artwork handoffs

    func pickArtwork(for file: AudioFile) {
        guard validateArtworkEditingSupport(for: file) else { return }
        guard let intent = beginArtworkImport(for: file, source: .finder) else {
            presentArtworkTransferNoDestination(for: [file])
            return
        }

        MacDocumentPicker.pickImage { [weak self] url in
            guard let self, let url else { return }
            guard self.isArtworkTransferCurrent(intent) else { return }
            self.artworkImportTask?.cancel()
            self.artworkImportTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.finishPickedArtworkImport(url: url, intent: intent)
            }
        }
    }

    func pickArtwork(for files: [AudioFile]) {
        guard validateArtworkEditingSupport(for: files) else { return }
        guard let intent = beginArtworkImport(for: files, source: .finder) else {
            presentArtworkTransferNoDestination(for: files)
            return
        }

        MacDocumentPicker.pickImage { [weak self] url in
            guard let self, let url else { return }
            guard self.isArtworkTransferCurrent(intent) else { return }
            self.artworkImportTask?.cancel()
            self.artworkImportTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.finishPickedArtworkImport(url: url, intent: intent)
            }
        }
    }

    // MARK: - Clipboard artwork handoffs

    func importArtworkFromClipboard(for file: AudioFile) {
        guard validateArtworkEditingSupport(for: file) else { return }
        guard let intent = beginArtworkImport(for: file, source: .clipboard) else {
            presentArtworkTransferNoDestination(for: [file])
            return
        }
        guard let data = MacPasteboard.imageData else {
            guard isArtworkTransferCurrent(intent) else { return }
            presentArtworkPreparationFailure(
                for: file.url.lastPathComponent,
                reason: String(localized: "The clipboard doesn't contain an image. Copy an image, then paste again.")
            )
            return
        }

        artworkImportTask?.cancel()
        artworkImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.finishArtworkImport(imageData: data, intent: intent)
        }
    }

    func importArtworkFromClipboard(for files: [AudioFile]) {
        guard validateArtworkEditingSupport(for: files) else { return }
        guard let intent = beginArtworkImport(for: files, source: .clipboard) else {
            presentArtworkTransferNoDestination(for: files)
            return
        }
        guard let data = MacPasteboard.imageData else {
            guard isArtworkTransferCurrent(intent) else { return }
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Artwork Couldn’t Be Updated"),
                subtitle: String(localized: "The clipboard doesn't contain an image. Copy an image, then paste again.")
            )
            return
        }

        artworkImportTask?.cancel()
        artworkImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.finishArtworkImport(imageData: data, intent: intent)
        }
    }

    // MARK: - Synchronous artwork commands

    func clearArtwork(for file: AudioFile) {
        guard validateArtworkEditingSupport(for: file) else { return }
        guard let intent = captureArtworkTransfer(targetIDs: [file.id], source: .clear) else {
            presentArtworkTransferNoDestination(for: [file])
            return
        }
        artworkImportTask?.cancel()
        commitSynchronousArtworkTransfer(intent, action: .remove)
    }

    func clearArtwork(for files: [AudioFile]) {
        guard validateArtworkEditingSupport(for: files) else { return }
        guard let intent = captureArtworkTransfer(targetIDs: files.map(\.id), source: .clear) else {
            presentArtworkTransferNoDestination(for: files)
            return
        }
        artworkImportTask?.cancel()
        commitSynchronousArtworkTransfer(intent, action: .remove)
    }

    func keepArtwork(for files: [AudioFile]) {
        guard !files.isEmpty else { return }
        guard let intent = captureArtworkTransfer(targetIDs: files.map(\.id), source: .keep) else {
            presentArtworkTransferNoDestination(for: files)
            return
        }
        artworkImportTask?.cancel()
        commitSynchronousArtworkTransfer(intent, action: .unchanged)
    }

    private func commitSynchronousArtworkTransfer(
        _ intent: ArtworkTransferIntent,
        action: ArtworkEditAction
    ) {
        // Clear/Keep run in one MainActor turn; the live draft always passes.
        // A rejection means the command was superseded immediately and the user
        // still sees why nothing changed.
        if case .rejected(let rejection) = commitArtworkTransfer(intent, action: action) {
            presentArtworkTransferRejection(rejection)
        }
    }

    // MARK: - Validation

    func validateArtworkEditingSupport(for file: AudioFile) -> Bool {
        guard isArtworkWriteSupportedExtension(file.url.pathExtension) else {
            presentArtworkPreparationFailure(
                for: file.url.lastPathComponent,
                reason: String(localized: "This file format doesn't support saving embedded artwork in AudioMator.")
            )
            return false
        }

        return true
    }

    func validateArtworkEditingSupport(for files: [AudioFile]) -> Bool {
        let unsupportedFiles = files.filter { !isArtworkWriteSupportedExtension($0.url.pathExtension) }
        guard unsupportedFiles.isEmpty else {
            let fileNames = unsupportedFiles.prefix(3).map(\.url.lastPathComponent)
            var lines = [String(localized: "Artwork can't be saved to every selected file. Select only files with supported formats before continuing.")]
            lines.append(contentsOf: fileNames)
            if unsupportedFiles.count > fileNames.count {
                lines.append(String(localized: "Additional unsupported files: \(unsupportedFiles.count - fileNames.count)."))
            }

            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Can't Edit Artwork for This Selection"),
                subtitle: lines.joined(separator: "\n")
            )
            return false
        }

        return true
    }
}
