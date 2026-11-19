import Foundation

extension FileRenameMetadataField {
    func currentMetadataValue(from file: AudioFile) -> String {
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
        case .date:
            return file.date
        case .originalReleaseDate:
            return file.originalReleaseDate
        case .trackNumberText:
            return file.trackNumberText
        case .discNumberText:
            return file.discNumberText
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

    func applyExtractedValue(_ value: String, to edit: inout SingleFileEditModel) {
        switch self {
        case .title:
            edit.title = value
        case .artist:
            edit.artist = value
        case .album:
            edit.album = value
        case .albumArtist:
            edit.albumArtist = value
        case .composer:
            edit.composer = value
        case .genre:
            edit.genre = value
        case .year:
            edit.year = value
        case .date:
            edit.date = value
        case .originalReleaseDate:
            edit.originalReleaseDate = value
        case .trackNumberText:
            edit.setTrackNumberText(value)
        case .discNumberText:
            edit.setDiscNumberText(value)
        case .comment:
            edit.comment = value
        case .releaseDate:
            edit.releaseDate = value
        case .publisher:
            edit.publisher = value
        case .copyright:
            edit.copyright = value
        case .credits, .ignore:
            break
        }
    }
}

enum FilenameMetadataFieldChangeStatus: Equatable {
    case same
    case different
}

struct FilenameMetadataFieldChange: Identifiable {
    let field: FileRenameMetadataField
    let currentValue: String
    let extractedValue: String
    let status: FilenameMetadataFieldChangeStatus
    let willWrite: Bool

    var id: String { field.placeholderName }
}

enum FilenameMetadataPreviewStatus: Equatable {
    case ready
    case unchanged
    case noMatch
    case sourceUnavailable
    case noWritableFields
    /// The extracted values are valid, but the destination format cannot save one
    /// or more of them. The row is rejected before any write.
    case unsupported

    var title: String {
        switch self {
        case .ready:
            return L10n.string("Ready")
        case .unchanged:
            return L10n.string("Unchanged")
        case .noMatch:
            return L10n.string("No Match Found")
        case .sourceUnavailable:
            return L10n.string("Couldn't Check File")
        case .noWritableFields:
            return L10n.string("No Editable Fields")
        case .unsupported:
            return L10n.string("Can’t Save Here")
        }
    }

    var message: String {
        switch self {
        case .ready:
            return L10n.string("The filename matched and extracted metadata can be written.")
        case .unchanged:
            return L10n.string("The extracted metadata already matches the file's current tags.")
        case .noMatch:
            return L10n.string("The filename doesn't fully match the template. Check the field order and fixed text, leaving out the file extension.")
        case .sourceUnavailable:
            return L10n.string("The file couldn’t be checked for changes. Choose Reload from Disk from its context menu before continuing.")
        case .noWritableFields:
            return L10n.string("The filename matches, but the template didn't extract any editable metadata. Add an editable field to the template.")
        case .unsupported:
            return L10n.string("This file format can’t save some of the fields extracted from the filename. Choose a different template or convert the file.")
        }
    }

    var isError: Bool {
        switch self {
        case .noMatch, .sourceUnavailable, .unsupported:
            return true
        case .ready, .unchanged, .noWritableFields:
            return false
        }
    }
}

struct FilenameMetadataWriteEntry: Identifiable {
    let fileName: String
    /// Frozen reviewed write captured from the reviewed file during planning.
    let write: ReviewedMetadataWrite
    /// Presentation-only extracted values for previews/tests. Never used to build
    /// a commit.
    let previewValues: [FileRenameMetadataField: String]

    var id: UUID { write.target.id }
    var fileID: UUID { write.target.id }

    var frozenPayload: MetadataEditPayload? {
        guard case .semantic(let payload) = write.intent else { return nil }
        return payload
    }

    var frozenProjection: MetadataWriteProjection { write.projection }
    var frozenTarget: ReviewedMetadataTarget { write.target }
}

struct FilenameMetadataPreviewRow: Identifiable {
    let id: AudioFile.ID
    let currentName: String
    let sourceBaseName: String
    let status: FilenameMetadataPreviewStatus
    let changes: [FilenameMetadataFieldChange]
    let issueMessage: String?
    let writeEntry: FilenameMetadataWriteEntry?
}

struct FilenameMetadataPlan {
    let template: String
    let replaceUnderscoresWithSpaces: Bool
    let validationMessage: String?
    let rows: [FilenameMetadataPreviewRow]

    var writeEntries: [FilenameMetadataWriteEntry] {
        rows.compactMap(\.writeEntry)
    }

    var readyCount: Int {
        writeEntries.count
    }

    var unchangedCount: Int {
        rows.filter { $0.status == .unchanged }.count
    }

    var noWritableCount: Int {
        rows.filter { $0.status == .noWritableFields }.count
    }

    var noMatchCount: Int {
        rows.filter { $0.status == .noMatch }.count
    }

    var issueCount: Int {
        let rowIssues = rows.filter { $0.status.isError }.count
        return rowIssues + (validationMessage == nil ? 0 : 1)
    }

    var hasIssues: Bool {
        issueCount > 0
    }

    var canApply: Bool {
        validationMessage == nil && !writeEntries.isEmpty
    }
}

func makeFilenameMetadataPlan(
    template: String,
    targetFiles: [AudioFile],
    replaceUnderscoresWithSpaces: Bool,
    projector: (any AudioMetadataPipeline)? = nil
) -> FilenameMetadataPlan {
    guard template.utf8.count <= maximumFileRenameTemplateUTF8ByteCount else {
        return FilenameMetadataPlan(
            template: template,
            replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces,
            validationMessage: L10n.string("This filename template is too long. Shorten it before continuing."),
            rows: []
        )
    }

    let document = FileRenameTemplateDocument(rawValue: template)

    guard !document.isVisuallyEmpty, !targetFiles.isEmpty else {
        return FilenameMetadataPlan(
            template: template,
            replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces,
            validationMessage: nil,
            rows: []
        )
    }

    let builder = FilenameMetadataPlanBuilder(
        replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces,
        projector: projector
    )
    return builder.makePlan(document: document, targetFiles: targetFiles)
}

private struct FilenameMetadataPlanBuilder {
    let replaceUnderscoresWithSpaces: Bool
    let projector: (any AudioMetadataPipeline)?

    func makePlan(
        document: FileRenameTemplateDocument,
        targetFiles: [AudioFile]
    ) -> FilenameMetadataPlan {
        if let validationMessage = validate(document: document) {
            return FilenameMetadataPlan(
                template: document.rawValue,
                replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces,
                validationMessage: validationMessage,
                rows: []
            )
        }

        let matcher = FilenameMetadataTemplateMatcher(
            document: document,
            replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces
        )

        let rows = targetFiles.map { file in
            makeRow(for: file, matcher: matcher, document: document)
        }

        return FilenameMetadataPlan(
            template: document.rawValue,
            replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces,
            validationMessage: nil,
            rows: rows
        )
    }

    private func validate(document: FileRenameTemplateDocument) -> String? {
        if let validationMessage = fileRenameTemplateSyntaxValidationMessage(document) {
            return validationMessage
        }

        let hasExtractionField = document.segments.contains { segment in
            guard case .field(let field) = segment else { return false }
            return !field.isHiddenExtractionField
        }

        guard hasExtractionField else {
            return L10n.string("Add at least one metadata field to extract from the filename.")
        }

        for index in document.segments.indices.dropLast() {
            guard case .field = document.segments[index] else { continue }
            guard case .field = document.segments[index + 1] else { continue }
            return L10n.string("Add text between adjacent fields so AudioMator can tell where each value starts and ends.")
        }

        return nil
    }

    private func makeRow(
        for file: AudioFile,
        matcher: FilenameMetadataTemplateMatcher,
        document: FileRenameTemplateDocument
    ) -> FilenameMetadataPreviewRow {
        let sourceBaseName = file.url.deletingPathExtension().lastPathComponent

        guard let extractedValues = matcher.match(sourceBaseName) else {
            return FilenameMetadataPreviewRow(
                id: file.id,
                currentName: file.url.lastPathComponent,
                sourceBaseName: sourceBaseName,
                status: .noMatch,
                changes: [],
                issueMessage: FilenameMetadataPreviewStatus.noMatch.message,
                writeEntry: nil
            )
        }

        let orderedFields = uniqueOrderedFields(from: document)
        let changes = orderedFields.compactMap { field -> FilenameMetadataFieldChange? in
            guard !field.isHiddenExtractionField else { return nil }
            guard let extractedValue = extractedValues[field] else { return nil }

            let currentValue = field.currentMetadataValue(from: file)
            let status: FilenameMetadataFieldChangeStatus = currentValue == extractedValue ? .same : .different
            let willWrite = field.supportsFilenameToMetadataWriting && status == .different

            return FilenameMetadataFieldChange(
                field: field,
                currentValue: currentValue,
                extractedValue: extractedValue,
                status: status,
                willWrite: willWrite
            )
        }

        let writeValues = Dictionary(
            uniqueKeysWithValues: changes
                .filter(\.willWrite)
                .map { ($0.field, $0.extractedValue) }
        )

        let capturedWritableFieldCount = changes.filter { $0.field.supportsFilenameToMetadataWriting }.count
        var status: FilenameMetadataPreviewStatus
        var issueMessage: String?

        if capturedWritableFieldCount == 0 {
            status = .noWritableFields
            issueMessage = FilenameMetadataPreviewStatus.noWritableFields.message
        } else if writeValues.isEmpty {
            status = .unchanged
            issueMessage = nil
        } else if file.fileFingerprint == nil {
            status = .sourceUnavailable
            issueMessage = FilenameMetadataPreviewStatus.sourceUnavailable.message
        } else {
            status = .ready
            issueMessage = nil
        }

        var writeEntry: FilenameMetadataWriteEntry?
        if status == .ready, let expectedFileFingerprint = file.fileFingerprint {
            var edit = SingleFileEditModel(from: file)
            for field in FileRenameMetadataField.allCases {
                guard let value = writeValues[field] else { continue }
                field.applyExtractedValue(value, to: &edit)
            }
            switch ExchangeWriteTranslator.makeFrozenWrite(
                from: file,
                edit: edit,
                projector: projector
            ) {
            case .executable(let frozen):
                writeEntry = FilenameMetadataWriteEntry(
                    fileName: file.url.lastPathComponent,
                    write: frozen.reviewedWrite,
                    previewValues: writeValues
                )
            case .unchanged:
                status = .unchanged
                writeEntry = nil
            case .rejected(let message), .unavailable(let message):
                status = .unsupported
                issueMessage = message
                writeEntry = nil
            }
        }

        return FilenameMetadataPreviewRow(
            id: file.id,
            currentName: file.url.lastPathComponent,
            sourceBaseName: sourceBaseName,
            status: status,
            changes: changes,
            issueMessage: issueMessage,
            writeEntry: writeEntry
        )
    }

    private func uniqueOrderedFields(from document: FileRenameTemplateDocument) -> [FileRenameMetadataField] {
        var orderedFields: [FileRenameMetadataField] = []
        var seen = Set<FileRenameMetadataField>()

        for segment in document.segments {
            guard case .field(let field) = segment else { continue }
            guard !seen.contains(field) else { continue }
            seen.insert(field)
            orderedFields.append(field)
        }

        return orderedFields
    }
}
