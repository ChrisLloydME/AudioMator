import Foundation

enum FileRenameMetadataField: CaseIterable, Hashable, Identifiable {
    case title
    case artist
    case album
    case albumArtist
    case composer
    case genre
    case year
    case trackNumberText
    case discNumberText
    case comment
    case releaseDate
    case publisher
    case copyright
    case credits

    var id: String { token }

    var displayName: String {
        switch self {
        case .title:
            return "Title"
        case .artist:
            return "Artist"
        case .album:
            return "Album"
        case .albumArtist:
            return "Album Artist"
        case .composer:
            return "Composer"
        case .genre:
            return "Genre"
        case .year:
            return "Year"
        case .trackNumberText:
            return "Track Number"
        case .discNumberText:
            return "Disc Number"
        case .comment:
            return "Comment"
        case .releaseDate:
            return "Release Date"
        case .publisher:
            return "Publisher"
        case .copyright:
            return "Copyright"
        case .credits:
            return "Credits"
        }
    }

    var token: String {
        switch self {
        case .title:
            return "{{title}}"
        case .artist:
            return "{{artist}}"
        case .album:
            return "{{album}}"
        case .albumArtist:
            return "{{albumArtist}}"
        case .composer:
            return "{{composer}}"
        case .genre:
            return "{{genre}}"
        case .year:
            return "{{year}}"
        case .trackNumberText:
            return "{{trackNumber}}"
        case .discNumberText:
            return "{{discNumber}}"
        case .comment:
            return "{{comment}}"
        case .releaseDate:
            return "{{releaseDate}}"
        case .publisher:
            return "{{publisher}}"
        case .copyright:
            return "{{copyright}}"
        case .credits:
            return "{{credits}}"
        }
    }

    func value(from file: AudioFile) -> String {
        switch self {
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
            return "Ready"
        case .unchanged:
            return "Unchanged"
        case .emptyName:
            return "Empty Name"
        case .duplicateTarget:
            return "Duplicate Target"
        case .existingFile:
            return "File Exists"
        }
    }

    var message: String {
        switch self {
        case .ready:
            return "This file can be renamed."
        case .unchanged:
            return "The generated filename already matches the current file."
        case .emptyName:
            return "This template resolves to an empty filename for the file."
        case .duplicateTarget:
            return "Multiple selected files would end up with the same filename."
        case .existingFile:
            return "A different file already exists at the target path."
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

private struct FileRenameDraftRow {
    let row: FileRenamePreviewRow
    let sourceKey: String?
    let destinationKey: String?
    let destinationExists: Bool
}

func makeFileRenamePlan(template: String, targetFiles: [AudioFile]) -> FileRenamePlan {
    let normalizedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !normalizedTemplate.isEmpty, !targetFiles.isEmpty else {
        return FileRenamePlan(template: template, rows: [], operations: [])
    }

    let fileManager = FileManager.default

    var drafts: [FileRenameDraftRow] = []
    drafts.reserveCapacity(targetFiles.count)

    for file in targetFiles {
        let renderedBaseName = renderFileRenameTemplate(template, for: file)

        guard let sanitizedBaseName = sanitizeRenamedFileBaseName(renderedBaseName) else {
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

        let status: FileRenamePreviewStatus
        if sourcePath == destinationPath {
            status = .unchanged
        } else {
            status = .ready
        }

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

    var destinationCounts: [String: Int] = [:]
    for draft in drafts {
        guard draft.row.status == FileRenamePreviewStatus.ready,
              let destinationKey = draft.destinationKey else { continue }
        destinationCounts[destinationKey, default: 0] += 1
    }

    let duplicateKeySet = Set(
        destinationCounts.compactMap { entry -> String? in
            entry.value > 1 ? entry.key : nil
        }
    )

    let renamableDrafts: [FileRenameDraftRow] = drafts.filter { draft in
        guard draft.row.status == FileRenamePreviewStatus.ready,
              let destinationKey = draft.destinationKey else { return false }
        return !duplicateKeySet.contains(destinationKey)
    }

    var activeReadyIDs = Set(renamableDrafts.map { $0.row.id })
    var didChange = true

    while didChange {
        didChange = false
        let readySourceKeys = Set(
            renamableDrafts.compactMap { draft in
                activeReadyIDs.contains(draft.row.id) ? draft.sourceKey : nil
            }
        )

        for draft in renamableDrafts {
            guard activeReadyIDs.contains(draft.row.id) else { continue }
            guard
                let sourceKey = draft.sourceKey,
                let destinationKey = draft.destinationKey
            else {
                continue
            }

            let isBlockedByExistingFile =
                draft.destinationExists &&
                destinationKey != sourceKey &&
                !readySourceKeys.contains(destinationKey)

            if isBlockedByExistingFile {
                activeReadyIDs.remove(draft.row.id)
                didChange = true
            }
        }
    }

    let rows = drafts.map { draft -> FileRenamePreviewRow in
        if
            draft.row.status == FileRenamePreviewStatus.ready,
            let destinationKey = draft.destinationKey,
            duplicateKeySet.contains(destinationKey)
        {
            return FileRenamePreviewRow(
                id: draft.row.id,
                currentName: draft.row.currentName,
                previewName: draft.row.previewName,
                sourceURL: draft.row.sourceURL,
                destinationURL: draft.row.destinationURL,
                status: .duplicateTarget
            )
        }

        if draft.row.status == FileRenamePreviewStatus.ready, !activeReadyIDs.contains(draft.row.id) {
            return FileRenamePreviewRow(
                id: draft.row.id,
                currentName: draft.row.currentName,
                previewName: draft.row.previewName,
                sourceURL: draft.row.sourceURL,
                destinationURL: draft.row.destinationURL,
                status: .existingFile
            )
        }

        return draft.row
    }

    let operations = rows.compactMap { row -> FileRenameOperation? in
        guard
            row.status == FileRenamePreviewStatus.ready,
            let destinationURL = row.destinationURL
        else {
            return nil
        }

        return FileRenameOperation(
            id: row.id,
            sourceURL: row.sourceURL,
            destinationURL: destinationURL
        )
    }

    return FileRenamePlan(template: template, rows: rows, operations: operations)
}

private func renderFileRenameTemplate(_ template: String, for file: AudioFile) -> String {
    FileRenameMetadataField.allCases.reduce(template) { partial, field in
        partial.replacingOccurrences(of: field.token, with: field.value(from: file))
    }
}

private func sanitizeRenamedFileBaseName(_ baseName: String) -> String? {
    let invalidScalars = CharacterSet(charactersIn: "/:\u{0000}")
    let controlCharacters = CharacterSet.controlCharacters

    let sanitized = String(baseName.unicodeScalars.map { scalar -> Character in
        if invalidScalars.contains(scalar) {
            return "-"
        }

        if controlCharacters.contains(scalar) {
            return " "
        }

        return Character(scalar)
    })
    .trimmingCharacters(in: .whitespacesAndNewlines)

    return sanitized.isEmpty ? nil : sanitized
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
