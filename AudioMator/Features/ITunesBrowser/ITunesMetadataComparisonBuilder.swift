import Foundation

struct ITunesMetadataComparisonRow: Identifiable, Equatable {
    let id: String
    let title: String
    let localValue: String
    let remoteValue: String
    let status: ITunesMetadataComparisonStatus
    let monospaced: Bool
}

struct ITunesMetadataComparisonGroup: Identifiable {
    let id: String
    let assignment: ITunesAlbumMatchAssignment
    let rows: [ITunesMetadataComparisonRow]
}

enum ITunesMetadataComparisonStatus: Equatable {
    case same
    case different
    case missingLocal
    case missingRemote
}

enum ITunesMetadataComparisonBuilder {
    static func groups(
        for preview: ITunesAlbumMatchPreview,
        detail: ITunesAlbumDetail,
        loadedFiles: [AudioFile]
    ) -> [ITunesMetadataComparisonGroup] {
        preview.matchedAssignments.map { assignment in
            ITunesMetadataComparisonGroup(
                id: assignment.id,
                assignment: assignment,
                rows: rows(for: assignment, detail: detail, loadedFiles: loadedFiles)
            )
        }
    }

    static func rows(
        for assignment: ITunesAlbumMatchAssignment,
        detail: ITunesAlbumDetail,
        loadedFiles: [AudioFile]
    ) -> [ITunesMetadataComparisonRow] {
        ITunesTagWriteField.allCases.compactMap { field in
            let localValue: String
            if let fileID = UUID(uuidString: assignment.file.id),
               let loadedFile = loadedFiles.first(where: { $0.id == fileID }) {
                localValue = field.localValue(from: loadedFile)
            } else {
                localValue = fallbackLocalValue(for: field, file: assignment.file)
            }

            return row(
                id: field.id,
                title: field.displayName,
                local: localValue,
                remote: remoteValue(for: field, assignment: assignment, detail: detail),
                monospaced: field.usesMonospacedComparisonValue
            )
        }
    }

    static func row(
        id: String,
        title: String,
        local: String,
        remote: String,
        monospaced: Bool = false
    ) -> ITunesMetadataComparisonRow? {
        let localValue = local.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteValue = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localValue.isEmpty || !remoteValue.isEmpty else { return nil }

        let status: ITunesMetadataComparisonStatus
        if localValue.isEmpty {
            status = .missingLocal
        } else if remoteValue.isEmpty {
            status = .missingRemote
        } else if normalizedComparisonValue(localValue) == normalizedComparisonValue(remoteValue) {
            status = .same
        } else {
            status = .different
        }

        return ITunesMetadataComparisonRow(
            id: id,
            title: title,
            localValue: localValue,
            remoteValue: remoteValue,
            status: status,
            monospaced: monospaced
        )
    }

    static func remoteValue(
        for field: ITunesTagWriteField,
        assignment: ITunesAlbumMatchAssignment,
        detail: ITunesAlbumDetail
    ) -> String {
        let track = assignment.track
        switch field {
        case .title: return track.trackName
        case .artist: return track.artistName
        case .albumArtist: return track.collectionArtistName.isEmpty ? detail.album.artistName : track.collectionArtistName
        case .album: return detail.album.collectionName
        case .genre: return track.primaryGenreName.isEmpty ? detail.album.primaryGenreName : track.primaryGenreName
        case .trackNumber: return track.trackNumber > 0 ? String(track.trackNumber) : ""
        case .trackTotal: return track.trackCount > 0 ? String(track.trackCount) : ""
        case .discNumber: return track.discNumber > 0 ? String(track.discNumber) : ""
        case .discTotal: return track.discCount > 1 ? String(track.discCount) : ""
        case .releaseDate: return track.releaseDate.isEmpty ? detail.album.releaseDate : track.releaseDate
        case .copyright: return track.copyright.isEmpty ? detail.album.copyright : track.copyright
        case .barcode: return assignment.file.barcode
        case .itunesAlbumID: return String(detail.album.collectionID)
        case .itunesArtistID: return track.artistID.map(String.init) ?? detail.album.artistID.map(String.init) ?? ""
        case .itunesCatalogID: return String(track.trackID)
        case .isExplicit: return track.isExplicit || detail.album.isExplicit ? "Yes" : "No"
        }
    }

    static func normalizedComparisonValue(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func fallbackLocalValue(for field: ITunesTagWriteField, file: ITunesFileSearchInput) -> String {
        switch field {
        case .title: return file.title
        case .artist: return file.artist
        case .albumArtist: return file.albumArtist
        case .album: return file.album
        case .trackNumber: return file.trackNumber
        case .trackTotal: return file.trackTotal > 0 ? String(file.trackTotal) : ""
        case .discNumber: return file.discNumber
        case .releaseDate: return file.releaseDate
        case .barcode: return file.barcode
        case .itunesAlbumID: return file.itunesAlbumID
        case .itunesArtistID: return file.itunesArtistID
        case .itunesCatalogID: return file.itunesCatalogID
        case .genre, .discTotal, .copyright, .isExplicit: return ""
        }
    }
}

extension ITunesTagWriteField {
    var usesMonospacedComparisonValue: Bool {
        switch self {
        case .trackNumber, .trackTotal, .discNumber, .discTotal, .barcode,
             .itunesAlbumID, .itunesArtistID, .itunesCatalogID:
            return true
        case .title, .artist, .albumArtist, .album, .genre, .releaseDate, .copyright, .isExplicit:
            return false
        }
    }
}
