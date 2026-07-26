import Foundation

nonisolated struct MusicBrainzMetadataComparisonRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let localValue: String
    let remoteValue: String
    let status: MusicBrainzMetadataComparisonStatus
    let monospaced: Bool
}

nonisolated struct MusicBrainzMetadataComparisonGroup: Identifiable, Sendable {
    let id: String
    let assignment: MusicBrainzReleaseMatchAssignment
    let rows: [MusicBrainzMetadataComparisonRow]
}

nonisolated enum MusicBrainzMetadataComparisonStatus: Equatable, Sendable {
    case same
    case different
    case missingLocal
    case missingRemote
}

nonisolated struct MusicBrainzReleaseMetadataPresentation: Sendable {
    let preview: MusicBrainzReleaseMatchPreview?
    let comparisonGroups: [MusicBrainzMetadataComparisonGroup]
}

nonisolated enum MusicBrainzMetadataComparisonBuilder {
    static func presentation(
        for release: MusicBrainzReleaseDetail,
        fallbackFiles: [MusicBrainzFileSearchInput]
    ) -> MusicBrainzReleaseMetadataPresentation {
        let preview = release.selectionMatchPreview
            ?? MusicBrainzTaggingPreviewBuilder.makePreview(files: fallbackFiles, release: release)
        let groups = preview?.matchedAssignments.map { assignment in
            MusicBrainzMetadataComparisonGroup(
                id: assignment.id,
                assignment: assignment,
                rows: rows(for: assignment, release: release)
            )
        } ?? []

        return MusicBrainzReleaseMetadataPresentation(
            preview: preview,
            comparisonGroups: groups
        )
    }

    static func rows(
        for assignment: MusicBrainzReleaseMatchAssignment,
        release: MusicBrainzReleaseDetail
    ) -> [MusicBrainzMetadataComparisonRow] {
        [
            row("title", "Title", local: assignment.file.title, remote: assignment.track.title),
            row(
                "artist",
                "Artist",
                local: assignment.file.artist,
                remote: assignment.track.artistCredit.isEmpty ? release.artistCredit : assignment.track.artistCredit
            ),
            row("album-artist", "Album Artist", local: assignment.file.albumArtist, remote: release.artistCredit),
            row("album", "Album", local: assignment.file.album, remote: release.title),
            row("track-number", "Track Number", local: assignment.file.trackNumber, remote: assignment.track.number, monospaced: true),
            row(
                "disc-number",
                "Disc Number",
                local: assignment.file.discNumber,
                remote: assignment.track.mediumPosition > 0 ? String(assignment.track.mediumPosition) : "",
                monospaced: true
            ),
            row("release-date", "Release Date", local: assignment.file.releaseDate, remote: release.date),
            row(
                "isrc",
                "ISRC",
                local: assignment.file.isrc,
                remote: assignment.track.isrcs.joined(separator: ", "),
                monospaced: true
            ),
            row("barcode", "Barcode", local: assignment.file.barcode, remote: release.barcode, monospaced: true)
        ].compactMap { $0 }
    }

    static func row(
        _ id: String,
        _ title: String,
        local: String,
        remote: String,
        monospaced: Bool = false
    ) -> MusicBrainzMetadataComparisonRow? {
        let localValue = local.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteValue = remote.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !localValue.isEmpty || !remoteValue.isEmpty else { return nil }

        let status: MusicBrainzMetadataComparisonStatus
        if localValue.isEmpty {
            status = .missingLocal
        } else if remoteValue.isEmpty {
            status = .missingRemote
        } else if normalizedValue(localValue) == normalizedValue(remoteValue) {
            status = .same
        } else {
            status = .different
        }

        return MusicBrainzMetadataComparisonRow(
            id: id,
            title: title,
            localValue: localValue,
            remoteValue: remoteValue,
            status: status,
            monospaced: monospaced
        )
    }

    private static func normalizedValue(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
