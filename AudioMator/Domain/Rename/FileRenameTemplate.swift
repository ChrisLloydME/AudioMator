import Foundation
import Combine

extension FileRenameMetadataField {
    var displayName: String {
        switch self {
        case .title:
            return L10n.string("Title")
        case .artist:
            return L10n.string("Artist")
        case .album:
            return L10n.string("Album")
        case .albumArtist:
            return L10n.string("Album Artist")
        case .composer:
            return L10n.string("Composer")
        case .genre:
            return L10n.string("Genre")
        case .year:
            return L10n.string("Year")
        case .trackNumberText:
            return L10n.string("Track Number")
        case .discNumberText:
            return L10n.string("Disc Number")
        case .comment:
            return L10n.string("Comment")
        case .releaseDate:
            return L10n.string("Release Date")
        case .publisher:
            return L10n.string("Publisher")
        case .copyright:
            return L10n.string("Copyright")
        case .credits:
            return L10n.string("Credits")
        case .ignore:
            return L10n.string("Ignore")
        }
    }
}

enum FileRenamePreviewStatus: Equatable {
    case ready
    case unchanged
    case emptyName
    case duplicateTarget
    case existingFile

    var title: String {
        switch self {
        case .ready:
            return L10n.string("Ready")
        case .unchanged:
            return L10n.string("Unchanged")
        case .emptyName:
            return L10n.string("Empty Name")
        case .duplicateTarget:
            return L10n.string("Duplicate Target")
        case .existingFile:
            return L10n.string("File Exists")
        }
    }

    var message: String {
        switch self {
        case .ready:
            return L10n.string("This file can be renamed.")
        case .unchanged:
            return L10n.string("The generated filename already matches the current file.")
        case .emptyName:
            return L10n.string("This template resolves to an empty filename for the file.")
        case .duplicateTarget:
            return L10n.string("Multiple selected files would end up with the same filename.")
        case .existingFile:
            return L10n.string("A different file already exists at the target path.")
        }
    }

    var isError: Bool {
        switch self {
        case .ready, .unchanged:
            return false
        case .emptyName, .duplicateTarget, .existingFile:
            return true
        }
    }
}

struct FileRenamePreviewRow: Identifiable {
    let id: AudioFile.ID
    let currentName: String
    let previewName: String
    let sourceURL: URL
    let destinationURL: URL?
    let status: FileRenamePreviewStatus
}

struct FileRenameOperation: Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL
    let destinationURL: URL
}

struct FileRenamePlan {
    let template: String
    let rows: [FileRenamePreviewRow]
    let operations: [FileRenameOperation]

    var totalTargets: Int {
        rows.count
    }

    var readyCount: Int {
        operations.count
    }

    var unchangedCount: Int {
        rows.filter { $0.status == .unchanged }.count
    }

    var issueCount: Int {
        rows.filter { $0.status.isError }.count
    }

    var hasIssues: Bool {
        issueCount > 0
    }

    var canApply: Bool {
        readyCount > 0
    }
}

func makeFileRenamePlan(template: String, targetFiles: [AudioFile]) -> FileRenamePlan {
    let document = FileRenameTemplateDocument(rawValue: template)

    guard !document.isVisuallyEmpty, !targetFiles.isEmpty else {
        return FileRenamePlan(template: template, rows: [], operations: [])
    }

    let builder = FileRenamePlanBuilder()
    return builder.makePlan(document: document, targetFiles: targetFiles)
}

private struct FileRenameFieldValueResolver {
    func resolve(_ field: FileRenameMetadataField, for file: AudioFile) -> String {
        switch field {
        case .title:
            return file.title
        case .artist:
            return file.artist
        case .album:
            return file.album
        case .albumArtist:
            return file.albumArtist
        case .composer:
            return file.composer
        case .genre:
            return file.genre
        case .year:
            return file.year
        case .trackNumberText:
            return file.trackNumberText.isEmpty
                ? formatTrackIndex(file.track, total: file.trackTotal)
                : file.trackNumberText
        case .discNumberText:
            return file.discNumberText.isEmpty
                ? formatTrackIndex(file.disc, total: file.discTotal)
                : file.discNumberText
        case .comment:
            return file.comment
        case .releaseDate:
            return file.releaseDate
        case .publisher:
            return file.publisher
        case .copyright:
            return file.copyright
        case .credits:
            return file.credits
        case .ignore:
            return ""
        }
    }
}

private struct FileRenameRenderer {
    let resolver = FileRenameFieldValueResolver()

    func render(document: FileRenameTemplateDocument, for file: AudioFile) -> String {
        var rendered = ""
        rendered.reserveCapacity(document.rawValue.count)

        for segment in document.segments {
            switch segment {
            case .literal(let literal):
                rendered += literal
            case .field(let field):
                rendered += resolver.resolve(field, for: file)
            }
        }

        return rendered
    }
}

private struct FileRenameDraftRow {
    let row: FileRenamePreviewRow
    let sourceKey: String?
    let destinationKey: String?
    let destinationExists: Bool
}

private struct FileRenamePlanBuilder {
    let renderer = FileRenameRenderer()
    let sanitizer = FileRenameSanitizer()

    func makePlan(document: FileRenameTemplateDocument, targetFiles: [AudioFile]) -> FileRenamePlan {
        let fileManager = FileManager.default
        var drafts: [FileRenameDraftRow] = []
        drafts.reserveCapacity(targetFiles.count)

        for file in targetFiles {
            let renderedBaseName = renderer.render(document: document, for: file)

            guard let sanitizedBaseName = sanitizer.sanitizeBaseName(renderedBaseName) else {
                drafts.append(
                    FileRenameDraftRow(
                        row: FileRenamePreviewRow(
                            id: file.id,
                            currentName: file.url.lastPathComponent,
                            previewName: "Empty filename",
                            sourceURL: file.url,
                            destinationURL: nil,
                            status: .emptyName
                        ),
                        sourceKey: nil,
                        destinationKey: nil,
                        destinationExists: false
                    )
                )
                continue
            }

            let destinationURL = makeRenamedFileURL(from: file.url, baseName: sanitizedBaseName)
            let sourcePath = file.url.standardizedFileURL.resolvingSymlinksInPath().path
            let destinationPath = destinationURL.standardizedFileURL.resolvingSymlinksInPath().path
            let sourceKey = fileRenameCollisionKey(for: file.url)
            let destinationKey = fileRenameCollisionKey(for: destinationURL)
            let destinationExists = fileManager.fileExists(atPath: destinationURL.path)

            let status: FileRenamePreviewStatus = sourcePath == destinationPath ? .unchanged : .ready
            drafts.append(
                FileRenameDraftRow(
                    row: FileRenamePreviewRow(
                        id: file.id,
                        currentName: file.url.lastPathComponent,
                        previewName: destinationURL.lastPathComponent,
                        sourceURL: file.url,
                        destinationURL: destinationURL,
                        status: status
                    ),
                    sourceKey: sourceKey,
                    destinationKey: destinationKey,
                    destinationExists: destinationExists
                )
            )
        }

        let coreDrafts = drafts.map { draft in
            FileRenameCoreDraft(
                id: draft.row.id,
                sourceKey: draft.sourceKey,
                destinationKey: draft.destinationKey,
                destinationExists: draft.destinationExists,
                initialStatus: FileRenameCoreStatus(status: draft.row.status)
            )
        }
        let finalizedStatuses = FileRenameCollisionPolicy.finalizedStatuses(for: coreDrafts)
        let rows = finalizeRows(from: drafts, finalizedStatuses: finalizedStatuses)
        let operations = rows.compactMap { row -> FileRenameOperation? in
            guard row.status == .ready, let destinationURL = row.destinationURL else {
                return nil
            }

            return FileRenameOperation(
                id: row.id,
                sourceURL: row.sourceURL,
                destinationURL: destinationURL
            )
        }

        return FileRenamePlan(template: document.rawValue, rows: rows, operations: operations)
    }

    private func finalizeRows(
        from drafts: [FileRenameDraftRow],
        finalizedStatuses: [AudioFile.ID: FileRenameCoreStatus]
    ) -> [FileRenamePreviewRow] {
        drafts.map { draft in
            guard
                let coreStatus = finalizedStatuses[draft.row.id],
                let status = FileRenamePreviewStatus(coreStatus: coreStatus),
                status != draft.row.status
            else {
                return draft.row
            }

            return FileRenamePreviewRow(
                id: draft.row.id,
                currentName: draft.row.currentName,
                previewName: draft.row.previewName,
                sourceURL: draft.row.sourceURL,
                destinationURL: draft.row.destinationURL,
                status: status
            )
        }
    }
}

private extension FileRenameCoreStatus {
    init(status: FileRenamePreviewStatus) {
        switch status {
        case .ready:
            self = .ready
        case .unchanged:
            self = .unchanged
        case .emptyName:
            self = .emptyName
        case .duplicateTarget:
            self = .duplicateTarget
        case .existingFile:
            self = .existingFile
        }
    }
}

private extension FileRenamePreviewStatus {
    init?(coreStatus: FileRenameCoreStatus) {
        switch coreStatus {
        case .ready:
            self = .ready
        case .unchanged:
            self = .unchanged
        case .emptyName:
            self = .emptyName
        case .duplicateTarget:
            self = .duplicateTarget
        case .existingFile:
            self = .existingFile
        }
    }
}

private func makeRenamedFileURL(from sourceURL: URL, baseName: String) -> URL {
    let directoryURL = sourceURL.deletingLastPathComponent()
    let extensionText = sourceURL.pathExtension

    if extensionText.isEmpty {
        return directoryURL.appendingPathComponent(baseName, isDirectory: false)
    }

    return directoryURL
        .appendingPathComponent(baseName, isDirectory: false)
        .appendingPathExtension(extensionText)
}

private func fileRenameCollisionKey(for url: URL) -> String {
    url.standardizedFileURL
        .resolvingSymlinksInPath()
        .path
        .lowercased()
}
