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
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = AudioFormatSupport.openPanelContentTypes
        panel.title = "Choose Audio Files"

        guard panel.runModal() == .OK else { return }

        importQuickFiles(from: panel.urls)
        #endif
    }

    func pickArtwork(for file: AudioFile) {
        guard validateArtworkEditingSupport(for: file) else { return }
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.title = "Choose Artwork Image"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let pendingArtwork = try loadPendingArtwork(from: url)
            applyArtworkEditAction(.replace(pendingArtwork), to: file)
        } catch {
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent,
                reason: (error as NSError).localizedDescription
            )
        }
        #else
        presentMetadataWriteFailure(
            for: file.url.lastPathComponent,
            reason: "Use drag and drop or clipboard import on iPadOS."
        )
        #endif
    }

    func importArtworkFromClipboard(for file: AudioFile) {
        guard validateArtworkEditingSupport(for: file) else { return }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
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
        #else
        guard let image = UIPasteboard.general.image else {
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
        #endif
    }

    func clearArtwork(for file: AudioFile) {
        guard validateArtworkEditingSupport(for: file) else { return }
        applyArtworkEditAction(.remove, to: file)
    }

    func pickArtwork(for files: [AudioFile]) {
        guard validateArtworkEditingSupport(for: files) else { return }
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.title = "Choose Artwork Image"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let pendingArtwork = try loadPendingArtwork(from: url)
            applyArtworkEditAction(.replace(pendingArtwork), to: files)
        } catch {
            presentMetadataWriteHUD(
                style: .failure,
                title: "Artwork Update Failed",
                subtitle: (error as NSError).localizedDescription
            )
        }
        #else
        presentMetadataWriteHUD(
            style: .failure,
            title: "Artwork Update Failed",
            subtitle: "Artwork picker is unavailable on iPadOS in this build."
        )
        #endif
    }

    func importArtworkFromClipboard(for files: [AudioFile]) {
        guard validateArtworkEditingSupport(for: files) else { return }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
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
        #else
        guard let image = UIPasteboard.general.image else {
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
        #endif
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
        if var current = edit {
            current.artworkEditAction = action
            edit = current
        } else {
            var model = SingleFileEditModel(from: file)
            model.artworkEditAction = action
            edit = model
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
        guard let image = NSImage(contentsOf: url) else {
            throw NSError(
                domain: "AudioMator.Artwork",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The selected image could not be opened."]
            )
        }

        return try loadPendingArtwork(from: image)
    }

    private func loadPendingArtwork(from image: NSImage) throws -> PendingArtwork {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "AudioMator.Artwork",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The selected image could not be converted to PNG."]
            )
        }

        guard let previewImage = NSImage(data: pngData) else {
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
