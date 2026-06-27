import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension AudioViewModel {
    // MARK: - File Import

    func addFiles() {
        guard currentFileSourceMode == .quickImport else { return }
        PlatformDocumentPicker.pickAudioFiles { [weak self] urls in
            guard !urls.isEmpty else { return }
            Task { @MainActor in
                self?.importQuickFiles(from: urls)
            }
        }
    }

    func pickArtwork(for file: AudioFile) {
        guard validateArtworkEditingSupport(for: file) else { return }
        PlatformDocumentPicker.pickImage { [weak self] url in
            guard let self, let url else { return }

            Task { @MainActor in
                do {
                    let pendingArtwork = try self.loadPendingArtwork(from: url)
                    self.applyArtworkEditAction(.replace(pendingArtwork), to: file)
                } catch {
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
                reason: "The selected photo could not be loaded."
            )
            return
        }

        do {
            let pendingArtwork = try loadPendingArtwork(fromImageData: data)
            applyArtworkEditAction(.replace(pendingArtwork), to: file)
        } catch {
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent,
                reason: (error as NSError).localizedDescription
            )
        }
    }

    func importArtworkFromClipboard(for file: AudioFile) {
        guard validateArtworkEditingSupport(for: file) else { return }

        guard let image = PlatformPasteboard.image else {
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent,
                reason: "No image was found in the clipboard."
            )
            return
        }

        do {
            let pendingArtwork = try loadPendingArtwork(from: image)
            applyArtworkEditAction(.replace(pendingArtwork), to: file)
        } catch {
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent,
                reason: (error as NSError).localizedDescription
            )
        }
    }

    func clearArtwork(for file: AudioFile) {
        guard validateArtworkEditingSupport(for: file) else { return }
        applyArtworkEditAction(.remove, to: file)
    }

    func pickArtwork(for files: [AudioFile]) {
        guard validateArtworkEditingSupport(for: files) else { return }
        PlatformDocumentPicker.pickImage { [weak self] url in
            guard let self, let url else { return }

            Task { @MainActor in
                do {
                    let pendingArtwork = try self.loadPendingArtwork(from: url)
                    self.applyArtworkEditAction(.replace(pendingArtwork), to: files)
                } catch {
                    self.presentMetadataWriteHUD(
                        style: .failure,
                        title: "Artwork Update Failed",
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
                title: "Artwork Update Failed",
                subtitle: "The selected photo could not be loaded."
            )
            return
        }

        do {
            let pendingArtwork = try loadPendingArtwork(fromImageData: data)
            applyArtworkEditAction(.replace(pendingArtwork), to: files)
        } catch {
            presentMetadataWriteHUD(
                style: .failure,
                title: "Artwork Update Failed",
                subtitle: (error as NSError).localizedDescription
            )
        }
    }

    func importArtworkFromClipboard(for files: [AudioFile]) {
        guard validateArtworkEditingSupport(for: files) else { return }

        guard let image = PlatformPasteboard.image else {
            presentMetadataWriteHUD(
                style: .failure,
                title: "Artwork Update Failed",
                subtitle: "No image was found in the clipboard."
            )
            return
        }

        do {
            let pendingArtwork = try loadPendingArtwork(from: image)
            applyArtworkEditAction(.replace(pendingArtwork), to: files)
        } catch {
            presentMetadataWriteHUD(
                style: .failure,
                title: "Artwork Update Failed",
                subtitle: (error as NSError).localizedDescription
            )
        }
    }

    func clearArtwork(for files: [AudioFile]) {
        guard validateArtworkEditingSupport(for: files) else { return }
        applyArtworkEditAction(.remove, to: files)
    }

    func keepArtwork(for files: [AudioFile]) {
        guard !files.isEmpty else { return }
        applyArtworkEditAction(.unchanged, to: files)
    }

    private func validateArtworkEditingSupport(for file: AudioFile) -> Bool {
        guard isArtworkWriteSupportedExtension(file.url.pathExtension) else {
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent,
                reason: "This format does not support embedded artwork writing yet."
            )
            return false
        }

        return true
    }

    private func validateArtworkEditingSupport(for files: [AudioFile]) -> Bool {
        let unsupportedFiles = files.filter { !isArtworkWriteSupportedExtension($0.url.pathExtension) }
        guard unsupportedFiles.isEmpty else {
            let fileNames = unsupportedFiles.prefix(3).map(\.url.lastPathComponent)
            var lines = ["Embedded artwork writing is not supported for all selected files."]
            lines.append(contentsOf: fileNames)
            if unsupportedFiles.count > fileNames.count {
                lines.append("...and \(unsupportedFiles.count - fileNames.count) more")
            }

            presentMetadataWriteHUD(
                style: .failure,
                title: "Artwork Edit Unavailable",
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

    private func loadPendingArtwork(from url: URL) throws -> PendingArtwork {
        guard let image = PlatformImage(contentsOfFile: url.path) else {
            throw NSError(
                domain: "AudioMator.Artwork",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The selected image could not be opened."]
            )
        }

        return try loadPendingArtwork(from: image)
    }

    private func loadPendingArtwork(fromImageData data: Data) throws -> PendingArtwork {
        guard let image = PlatformImage(data: data) else {
            throw NSError(
                domain: "AudioMator.Artwork",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "The selected photo could not be opened."]
            )
        }

        return try loadPendingArtwork(from: image)
    }

    private func loadPendingArtwork(from image: PlatformImage) throws -> PendingArtwork {
        guard let pngData = image.audiomatorPNGData else {
            throw NSError(
                domain: "AudioMator.Artwork",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The selected image could not be converted to PNG."]
            )
        }

        guard let previewImage = PlatformImage(data: pngData) else {
            throw NSError(
                domain: "AudioMator.Artwork",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The converted artwork preview could not be generated."]
            )
        }

        return PendingArtwork(
            image: previewImage,
            data: pngData,
            mimeType: "image/png"
        )
    }
}
