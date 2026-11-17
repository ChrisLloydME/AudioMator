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

    func pickArtwork(for file: AudioFile) {
        guard validateArtworkEditingSupport(for: file) else { return }
        MacDocumentPicker.pickImage { [weak self] url in
            guard let self, let url else { return }

            self.artworkImportTask?.cancel()
            self.artworkImportTask = Task { @MainActor in
                do {
                    let pendingArtwork = try await Self.loadPendingArtwork(from: url)
                    try Task.checkCancellation()
                    self.applyArtworkEditAction(.replace(pendingArtwork), to: file)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    self.presentMetadataWriteFailure(
                        for: file.url.lastPathComponent,
                        reason: (error as NSError).localizedDescription
                    )
                }
            }
        }
    }

    func canImportArtwork(for file: AudioFile) -> Bool {
        validateArtworkEditingSupport(for: file)
    }

    func importArtworkFromPhotoLibrary(_ data: Data?, for file: AudioFile) {
        guard validateArtworkEditingSupport(for: file) else { return }

        guard let data else {
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent,
                reason: String(localized: "AudioMator couldn't load this photo. Choose another photo or import an image file.")
            )
            return
        }

        artworkImportTask?.cancel()
        artworkImportTask = Task { @MainActor in
            do {
                let pendingArtwork = try await Self.loadPendingArtwork(fromImageData: data)
                try Task.checkCancellation()
                applyArtworkEditAction(.replace(pendingArtwork), to: file)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                presentMetadataWriteFailure(
                    for: file.url.lastPathComponent,
                    reason: (error as NSError).localizedDescription
                )
            }
        }
    }

    func importArtworkFromClipboard(for file: AudioFile) {
        guard validateArtworkEditingSupport(for: file) else { return }

        guard let data = MacPasteboard.imageData else {
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent,
                reason: String(localized: "The clipboard doesn't contain an image. Copy an image, then paste again.")
            )
            return
        }

        artworkImportTask?.cancel()
        artworkImportTask = Task { @MainActor in
            do {
                let pendingArtwork = try await Self.loadPendingArtwork(fromImageData: data)
                try Task.checkCancellation()
                applyArtworkEditAction(.replace(pendingArtwork), to: file)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                presentMetadataWriteFailure(
                    for: file.url.lastPathComponent,
                    reason: (error as NSError).localizedDescription
                )
            }
        }
    }

    func clearArtwork(for file: AudioFile) {
        artworkImportTask?.cancel()
        guard validateArtworkEditingSupport(for: file) else { return }
        applyArtworkEditAction(.remove, to: file)
    }

    func pickArtwork(for files: [AudioFile]) {
        guard validateArtworkEditingSupport(for: files) else { return }
        MacDocumentPicker.pickImage { [weak self] url in
            guard let self, let url else { return }

            self.artworkImportTask?.cancel()
            self.artworkImportTask = Task { @MainActor in
                do {
                    let pendingArtwork = try await Self.loadPendingArtwork(from: url)
                    try Task.checkCancellation()
                    self.applyArtworkEditAction(.replace(pendingArtwork), to: files)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    self.presentMetadataWriteHUD(
                        style: .failure,
                        title: String(localized: "Artwork Couldn’t Be Updated"),
                        subtitle: (error as NSError).localizedDescription
                    )
                }
            }
        }
    }

    func canImportArtwork(for files: [AudioFile]) -> Bool {
        validateArtworkEditingSupport(for: files)
    }

    func importArtworkFromPhotoLibrary(_ data: Data?, for files: [AudioFile]) {
        guard validateArtworkEditingSupport(for: files) else { return }

        guard let data else {
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Artwork Couldn’t Be Updated"),
                subtitle: String(localized: "AudioMator couldn't load this photo. Choose another photo or import an image file.")
            )
            return
        }

        artworkImportTask?.cancel()
        artworkImportTask = Task { @MainActor in
            do {
                let pendingArtwork = try await Self.loadPendingArtwork(fromImageData: data)
                try Task.checkCancellation()
                applyArtworkEditAction(.replace(pendingArtwork), to: files)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                presentMetadataWriteHUD(
                    style: .failure,
                    title: String(localized: "Artwork Couldn’t Be Updated"),
                    subtitle: (error as NSError).localizedDescription
                )
            }
        }
    }

    func importArtworkFromClipboard(for files: [AudioFile]) {
        guard validateArtworkEditingSupport(for: files) else { return }

        guard let data = MacPasteboard.imageData else {
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Artwork Couldn’t Be Updated"),
                subtitle: String(localized: "The clipboard doesn't contain an image. Copy an image, then paste again.")
            )
            return
        }

        artworkImportTask?.cancel()
        artworkImportTask = Task { @MainActor in
            do {
                let pendingArtwork = try await Self.loadPendingArtwork(fromImageData: data)
                try Task.checkCancellation()
                applyArtworkEditAction(.replace(pendingArtwork), to: files)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                presentMetadataWriteHUD(
                    style: .failure,
                    title: String(localized: "Artwork Couldn’t Be Updated"),
                    subtitle: (error as NSError).localizedDescription
                )
            }
        }
    }

    func clearArtwork(for files: [AudioFile]) {
        artworkImportTask?.cancel()
        guard validateArtworkEditingSupport(for: files) else { return }
        applyArtworkEditAction(.remove, to: files)
    }

    func keepArtwork(for files: [AudioFile]) {
        artworkImportTask?.cancel()
        guard !files.isEmpty else { return }
        applyArtworkEditAction(.unchanged, to: files)
    }

    private func validateArtworkEditingSupport(for file: AudioFile) -> Bool {
        guard isArtworkWriteSupportedExtension(file.url.pathExtension) else {
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent,
                reason: String(localized: "This file format doesn't support saving embedded artwork in AudioMator.")
            )
            return false
        }

        return true
    }

    private func validateArtworkEditingSupport(for files: [AudioFile]) -> Bool {
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

    func applyArtworkEditAction(_ action: ArtworkEditAction, to file: AudioFile) {
        if editSourceFileID == file.id, var current = edit {
            current.artworkEditAction = action
            edit = current
        } else {
            var model = SingleFileEditModel(from: file)
            model.artworkEditAction = action
            edit = model
            editSourceFileID = file.id
        }
    }

    func applyArtworkEditAction(_ action: ArtworkEditAction, to files: [AudioFile]) {
        guard !files.isEmpty else { return }

        if var current = multiEdit {
            current.setArtworkEditAction(action)
            multiEdit = current
        } else {
            var model = MultiFileEditModel(files: files)
            model.setArtworkEditAction(action)
            multiEdit = model
        }
    }

    @concurrent
    private static func loadPendingArtwork(from url: URL) async throws -> PendingArtwork {
        try SecurityScopedResourceAccess.withAccess(to: url) {
            PendingArtwork(data: try ArtworkImageNormalizer.normalizedPNGData(from: url), mimeType: "image/png")
        }
    }

    @concurrent
    private static func loadPendingArtwork(fromImageData data: Data) async throws -> PendingArtwork {
        PendingArtwork(data: try await ArtworkImageNormalizer.normalizedPNGDataInBackground(from: data), mimeType: "image/png")
    }
}
