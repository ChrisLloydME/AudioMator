import Foundation
import Combine

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
    case ignore

    var id: String { placeholderName }

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
        case .ignore:
            return "Ignore"
        }
    }

    var placeholderName: String {
        switch self {
        case .title:
            return "title"
        case .artist:
            return "artist"
        case .album:
            return "album"
        case .albumArtist:
            return "albumArtist"
        case .composer:
            return "composer"
        case .genre:
            return "genre"
        case .year:
            return "year"
        case .trackNumberText:
            return "trackNumber"
        case .discNumberText:
            return "discNumber"
        case .comment:
            return "comment"
        case .releaseDate:
            return "releaseDate"
        case .publisher:
            return "publisher"
        case .copyright:
            return "copyright"
        case .credits:
            return "credits"
        case .ignore:
            return "_ignore"
        }
    }

    var token: String {
        "{{\(placeholderName)}}"
    }

    static func field(forPlaceholderName placeholderName: String) -> Self? {
        allCases.first { $0.placeholderName == placeholderName }
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

func makeFileRenamePlan(template: String, targetFiles: [AudioFile]) -> FileRenamePlan {
    let document = FileRenameTemplateDocument(rawValue: template)

    guard !document.isVisuallyEmpty, !targetFiles.isEmpty else {
        return FileRenamePlan(template: template, rows: [], operations: [])
    }

    let builder = FileRenamePlanBuilder()
    return builder.makePlan(document: document, targetFiles: targetFiles)
}

enum FileRenameTemplateSegment: Equatable {
    case literal(String)
    case field(FileRenameMetadataField)
}

struct FileRenameTemplateDocument: Equatable {
    let rawValue: String
    let segments: [FileRenameTemplateSegment]

    init(rawValue: String) {
        self.rawValue = rawValue
        self.segments = FileRenameTemplateParser.parse(rawValue)
    }

    var isVisuallyEmpty: Bool {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var containsFieldSegments: Bool {
        segments.contains { segment in
            if case .field = segment {
                return true
            }

            return false
        }
    }
}

private enum FileRenameTemplateParser {
    static func parse(_ rawValue: String) -> [FileRenameTemplateSegment] {
        guard !rawValue.isEmpty else { return [] }

        var segments: [FileRenameTemplateSegment] = []
        var searchStart = rawValue.startIndex
        var literalStart = rawValue.startIndex

        while searchStart < rawValue.endIndex,
              let openingRange = rawValue[searchStart...].range(of: "{{") {
            if openingRange.lowerBound > literalStart {
                appendLiteral(String(rawValue[literalStart..<openingRange.lowerBound]), to: &segments)
            }

            guard let closingRange = rawValue[openingRange.upperBound...].range(of: "}}") else {
                literalStart = openingRange.lowerBound
                searchStart = rawValue.endIndex
                break
            }

            let placeholderName = String(rawValue[openingRange.upperBound..<closingRange.lowerBound])
            if let field = FileRenameMetadataField.field(forPlaceholderName: placeholderName) {
                segments.append(.field(field))
            } else {
                let unmatchedPlaceholder = String(rawValue[openingRange.lowerBound..<closingRange.upperBound])
                appendLiteral(unmatchedPlaceholder, to: &segments)
            }

            searchStart = closingRange.upperBound
            literalStart = searchStart
        }

        if literalStart < rawValue.endIndex {
            appendLiteral(String(rawValue[literalStart...]), to: &segments)
        }

        return segments
    }

    private static func appendLiteral(_ literal: String, to segments: inout [FileRenameTemplateSegment]) {
        guard !literal.isEmpty else { return }

        if case .literal(let existing)? = segments.last {
            segments[segments.count - 1] = .literal(existing + literal)
        } else {
            segments.append(.literal(literal))
        }
    }
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

private struct FileRenameCompatibilityOptions {
    let directorySeparatorReplacement: Character
    let colonReplacement: Character
    let invalidScalarReplacement: Character
    let controlCharacterReplacement: Character

    static let currentDefaults = FileRenameCompatibilityOptions(
        directorySeparatorReplacement: "-",
        colonReplacement: "-",
        invalidScalarReplacement: "-",
        controlCharacterReplacement: " "
    )
}

private struct FileRenameSanitizer {
    let options: FileRenameCompatibilityOptions

    init(options: FileRenameCompatibilityOptions = .currentDefaults) {
        self.options = options
    }

    func sanitizeBaseName(_ baseName: String) -> String? {
        let invalidScalars = CharacterSet(charactersIn: "/:\u{0000}")
        let controlCharacters = CharacterSet.controlCharacters

        let sanitized = String(baseName.unicodeScalars.map { scalar -> Character in
            if invalidScalars.contains(scalar) {
                switch scalar {
                case "/":
                    return options.directorySeparatorReplacement
                case ":":
                    return options.colonReplacement
                default:
                    return options.invalidScalarReplacement
                }
            }

            if controlCharacters.contains(scalar) {
                return options.controlCharacterReplacement
            }

            return Character(scalar)
        })
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? nil : sanitized
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

        let duplicateKeySet = duplicateDestinationKeys(in: drafts)
        let activeReadyIDs = resolveReadyIDs(from: drafts, duplicateKeySet: duplicateKeySet)
        let rows = finalizeRows(from: drafts, duplicateKeySet: duplicateKeySet, activeReadyIDs: activeReadyIDs)
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

    private func duplicateDestinationKeys(in drafts: [FileRenameDraftRow]) -> Set<String> {
        var destinationCounts: [String: Int] = [:]

        for draft in drafts {
            guard draft.row.status == .ready, let destinationKey = draft.destinationKey else { continue }
            destinationCounts[destinationKey, default: 0] += 1
        }

        return Set(
            destinationCounts.compactMap { entry in
                entry.value > 1 ? entry.key : nil
            }
        )
    }

    private func resolveReadyIDs(
        from drafts: [FileRenameDraftRow],
        duplicateKeySet: Set<String>
    ) -> Set<AudioFile.ID> {
        let renamableDrafts = drafts.filter { draft in
            guard draft.row.status == .ready, let destinationKey = draft.destinationKey else { return false }
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

        return activeReadyIDs
    }

    private func finalizeRows(
        from drafts: [FileRenameDraftRow],
        duplicateKeySet: Set<String>,
        activeReadyIDs: Set<AudioFile.ID>
    ) -> [FileRenamePreviewRow] {
        drafts.map { draft in
            if
                draft.row.status == .ready,
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

            if draft.row.status == .ready, !activeReadyIDs.contains(draft.row.id) {
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
