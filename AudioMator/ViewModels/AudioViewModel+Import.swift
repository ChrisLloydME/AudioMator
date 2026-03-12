import Foundation
import AppKit
import UniformTypeIdentifiers

extension AudioViewModel {
    // MARK: - 文件导入

    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.mp3,
            UTType.mpeg4Audio,
            UTType.wav,
            UTType.aiff,
        ]
        panel.title = "选择音频文件"

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls

        Task {
            var loaded: [AudioFile] = []
            for url in urls {
                if let file = try? await AudioFile(url: url) {
                    loaded.append(file)
                }
            }

            await MainActor.run {
                self.files.append(contentsOf: loaded)
            }
        }
    }

    func pickArtwork(for file: AudioFile) {
        guard isArtworkWriteSupportedExtension(file.url.pathExtension) else {
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent,
                reason: "This format does not support embedded artwork writing yet."
            )
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.title = "选择 Artwork 图片"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let pendingArtwork = try loadPendingArtwork(from: url)
            applyPendingArtwork(pendingArtwork, to: file)
        } catch {
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent,
                reason: (error as NSError).localizedDescription
            )
        }
    }

    private func applyPendingArtwork(_ pendingArtwork: PendingArtwork, to file: AudioFile) {
        if var current = edit {
            current.pendingArtwork = pendingArtwork
            edit = current
        } else {
            var model = SingleFileEditModel(from: file)
            model.pendingArtwork = pendingArtwork
            edit = model
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
