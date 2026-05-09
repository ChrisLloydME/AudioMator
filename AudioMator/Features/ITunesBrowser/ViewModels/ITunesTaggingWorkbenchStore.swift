import Foundation
import Combine

enum ITunesTagWriteField: String, CaseIterable, Identifiable, Hashable {
    case title
    case artist
    case albumArtist
    case album
    case genre
    case trackNumber
    case trackTotal
    case discNumber
    case discTotal
    case releaseDate
    case copyright
    case barcode
    case itunesAlbumID
    case itunesArtistID
    case itunesCatalogID
    case isExplicit

    var id: String { rawValue }
    var writeOrderIndex: Int { Self.allCases.firstIndex(of: self) ?? Int.max }

    var displayName: String {
        switch self {
        case .title: return L10n.string("Title")
        case .artist: return L10n.string("Artist")
        case .albumArtist: return L10n.string("Album Artist")
        case .album: return L10n.string("Album")
        case .genre: return L10n.string("Genre")
        case .trackNumber: return L10n.string("Track Number")
        case .trackTotal: return L10n.string("Total Tracks")
        case .discNumber: return L10n.string("Disc Number")
        case .discTotal: return L10n.string("Total Discs")
        case .releaseDate: return L10n.string("Release Date")
        case .copyright: return L10n.string("Copyright")
        case .barcode: return L10n.string("Barcode")
        case .itunesAlbumID: return L10n.string("iTunes Album ID")
        case .itunesArtistID: return L10n.string("iTunes Artist ID")
        case .itunesCatalogID: return L10n.string("iTunes Catalog ID")
        case .isExplicit: return L10n.string("Explicit")
        }
    }

    var description: String {
        switch self {
        case .title: return L10n.string("Track title from iTunes.")
        case .artist: return L10n.string("Track artist from iTunes.")
        case .albumArtist: return L10n.string("Album artist from iTunes.")
        case .album: return L10n.string("Album title from iTunes.")
        case .genre: return L10n.string("Primary iTunes genre.")
        case .trackNumber: return L10n.string("Matched track index.")
        case .trackTotal: return L10n.string("Total tracks in the iTunes album.")
        case .discNumber: return L10n.string("Matched disc index.")
        case .discTotal: return L10n.string("Total discs in the iTunes album.")
        case .releaseDate: return L10n.string("Release date from iTunes.")
        case .copyright: return L10n.string("Copyright text from iTunes, when available.")
        case .barcode: return L10n.string("UPC/EAN already known from the selected file lookup.")
        case .itunesAlbumID: return L10n.string("iTunes collection ID.")
        case .itunesArtistID: return L10n.string("iTunes artist ID.")
        case .itunesCatalogID: return L10n.string("iTunes track catalog ID.")
        case .isExplicit: return L10n.string("Explicit content flag from iTunes.")
        }
    }

    var isDefaultSelected: Bool {
        switch self {
        case .copyright, .barcode, .trackTotal, .discTotal:
            return false
        case .title, .artist, .albumArtist, .album, .genre, .trackNumber, .discNumber,
             .releaseDate, .itunesAlbumID, .itunesArtistID, .itunesCatalogID, .isExplicit:
            return true
        }
    }

    func localValue(from file: AudioFile) -> String {
        switch self {
        case .title: return file.title
        case .artist: return file.artist
        case .albumArtist: return file.albumArtist
        case .album: return file.album
        case .genre: return file.genre
        case .trackNumber:
            return AudioTagNumberPair(rawText: file.trackNumberText, number: file.track, total: file.trackTotal).displayedNumberText
        case .trackTotal:
            return AudioTagNumberPair(rawText: file.trackNumberText, number: file.track, total: file.trackTotal).displayedTotalText
        case .discNumber:
            return AudioTagNumberPair(rawText: file.discNumberText, number: file.disc, total: file.discTotal).displayedNumberText
        case .discTotal:
            return AudioTagNumberPair(rawText: file.discNumberText, number: file.disc, total: file.discTotal).displayedTotalText
        case .releaseDate: return file.releaseDate.isEmpty ? file.year : file.releaseDate
        case .copyright: return file.copyright
        case .barcode: return file.barcode
        case .itunesAlbumID: return file.itunesAlbumID
        case .itunesArtistID: return file.itunesArtistID
        case .itunesCatalogID: return file.itunesCatalogID
        case .isExplicit: return file.isExplicit ? "Yes" : "No"
        }
    }

    func apply(_ value: String, to edit: inout SingleFileEditModel) {
        switch self {
        case .title: edit.title = value
        case .artist: edit.artist = value
        case .albumArtist: edit.albumArtist = value
        case .album: edit.album = value
        case .genre: edit.genre = value
        case .trackNumber: edit.setTrackNumberFieldText(value)
        case .trackTotal: edit.setTrackTotalFieldText(value)
        case .discNumber: edit.setDiscNumberFieldText(value)
        case .discTotal: edit.setDiscTotalFieldText(value)
        case .releaseDate: edit.releaseDate = value
        case .copyright: edit.copyright = value
        case .barcode: edit.barcode = value
        case .itunesAlbumID: edit.itunesAlbumID = value
        case .itunesArtistID: edit.itunesArtistID = value
        case .itunesCatalogID: edit.itunesCatalogID = value
        case .isExplicit: edit.isExplicit = value == "Yes"
        }
    }
}

struct ITunesTaggingWriteEntry: Identifiable {
    let fileID: UUID
    let fileName: String
    let values: [ITunesTagWriteField: String]

    var id: UUID { fileID }
}

struct ITunesTaggingFieldChange: Identifiable {
    enum Status: Equatable {
        case same
        case different
        case missingLocal
        case missingRemote
    }

    let field: ITunesTagWriteField
    let localValue: String
    let remoteValue: String
    let status: Status
    let willWrite: Bool

    var id: String { field.rawValue }
}

struct ITunesTaggingPlanRow: Identifiable {
    let fileInput: ITunesFileSearchInput
    let file: AudioFile?
    let track: ITunesTrackResult?
    let changes: [ITunesTaggingFieldChange]
    let issueMessage: String?

    var id: String { fileInput.id }

    var writeEntry: ITunesTaggingWriteEntry? {
        guard let file else { return nil }
        let values = Dictionary(uniqueKeysWithValues: changes.filter(\.willWrite).map { ($0.field, $0.remoteValue) })
        guard !values.isEmpty else { return nil }
        return ITunesTaggingWriteEntry(fileID: file.id, fileName: file.url.lastPathComponent, values: values)
    }
}

struct ITunesTaggingPlan {
    let rows: [ITunesTaggingPlanRow]

    var writeEntries: [ITunesTaggingWriteEntry] { rows.compactMap(\.writeEntry) }
    var changeCount: Int { rows.reduce(0) { $0 + $1.changes.filter(\.willWrite).count } }
    var filesWithChangesCount: Int { writeEntries.count }
    var unresolvedIssueCount: Int { rows.filter { $0.issueMessage != nil }.count }
}

@MainActor
final class ITunesTaggingWorkbenchStore: ObservableObject, Identifiable {
    struct AssignmentDraft: Identifiable, Hashable {
        let fileInput: ITunesFileSearchInput
        let initialTrackID: Int?
        let initialReason: String?
        var selectedTrackID: Int?

        var id: String { fileInput.id }
    }

    let id = UUID()
    let detail: ITunesAlbumDetail

    @Published private(set) var assignments: [AssignmentDraft]
    @Published private(set) var availableTracks: [ITunesTrackResult]
    @Published private(set) var loadedFilesByInputID: [String: AudioFile]
    @Published var selectedFields: Set<ITunesTagWriteField>

    private let barcodeValue: String

    init(detail: ITunesAlbumDetail, preview: ITunesAlbumMatchPreview, loadedFiles: [AudioFile]) {
        self.detail = detail
        self.availableTracks = detail.tracks
        self.loadedFilesByInputID = Dictionary(uniqueKeysWithValues: loadedFiles.map { ($0.id.uuidString, $0) })
        self.selectedFields = Set(ITunesTagWriteField.allCases.filter(\.isDefaultSelected))
        self.barcodeValue = preview.matchedAssignments.first(where: { !$0.file.barcode.isEmpty })?.file.barcode ?? ""

        let autoAssignments = Dictionary(uniqueKeysWithValues: preview.matchedAssignments.map { ($0.file.id, $0) })
        let orderedFiles = preview.matchedAssignments.map(\.file) + preview.unmatchedFiles
        let availableTrackIDs = Set(detail.tracks.map(\.trackID))
        self.assignments = orderedFiles.map { file in
            let auto = autoAssignments[file.id]
            let selectedTrackID = auto?.track.trackID
            return AssignmentDraft(
                fileInput: file,
                initialTrackID: auto?.track.trackID,
                initialReason: auto?.reason,
                selectedTrackID: selectedTrackID.flatMap { availableTrackIDs.contains($0) ? $0 : nil }
            )
        }
    }

    var availableFields: [ITunesTagWriteField] {
        ITunesTagWriteField.allCases.filter(isFieldAvailable)
    }

    var selectedAvailableFields: Set<ITunesTagWriteField> {
        selectedFields.intersection(availableFields)
    }

    var plan: ITunesTaggingPlan {
        ITunesTaggingPlan(rows: assignments.map(buildPlanRow))
    }

    var hasDuplicateTrackAssignments: Bool {
        !duplicateTrackIDs.isEmpty
    }

    var duplicateTrackIDs: Set<Int> {
        let ids = assignments.compactMap(\.selectedTrackID)
        var seen: Set<Int> = []
        var duplicates: Set<Int> = []
        for id in ids {
            if !seen.insert(id).inserted { duplicates.insert(id) }
        }
        return duplicates
    }

    var canApply: Bool {
        !selectedAvailableFields.isEmpty && !hasDuplicateTrackAssignments && !plan.writeEntries.isEmpty
    }

    var applyDisabledReason: String? {
        if selectedAvailableFields.isEmpty { return L10n.string("Choose at least one field to write.") }
        if hasDuplicateTrackAssignments { return L10n.string("Each iTunes track can only be assigned once before writing.") }
        if plan.writeEntries.isEmpty { return L10n.string("No selected fields would change any loaded files.") }
        return nil
    }

    func refreshLoadedFiles(_ files: [AudioFile]) {
        loadedFilesByInputID = Dictionary(uniqueKeysWithValues: files.map { ($0.id.uuidString, $0) })
    }

    func isFieldSelected(_ field: ITunesTagWriteField) -> Bool {
        selectedFields.contains(field)
    }

    func setFieldSelected(_ isSelected: Bool, for field: ITunesTagWriteField) {
        if isSelected {
            selectedFields.insert(field)
        } else {
            selectedFields.remove(field)
        }
    }

    func selectedTrackID(for assignmentID: String) -> Int? {
        assignments.first(where: { $0.id == assignmentID })?.selectedTrackID
    }

    func updateSelectedTrack(_ trackID: Int?, for assignmentID: String) {
        guard let index = assignments.firstIndex(where: { $0.id == assignmentID }) else { return }
        guard let trackID else {
            assignments[index].selectedTrackID = nil
            return
        }

        assignments[index].selectedTrackID = availableTracks.contains { $0.trackID == trackID } ? trackID : nil
    }

    func track(for assignment: AssignmentDraft) -> ITunesTrackResult? {
        guard let id = assignment.selectedTrackID else { return nil }
        return availableTracks.first(where: { $0.trackID == id })
    }

    func isDuplicateAssignment(_ assignment: AssignmentDraft) -> Bool {
        guard let id = assignment.selectedTrackID else { return false }
        return duplicateTrackIDs.contains(id)
    }

    private func buildPlanRow(for assignment: AssignmentDraft) -> ITunesTaggingPlanRow {
        let file = loadedFilesByInputID[assignment.fileInput.id]
        let selectedTrack = track(for: assignment)

        let issueMessage: String?
        if file == nil {
            issueMessage = "The file is no longer loaded in AudioMator."
        } else if selectedTrack == nil {
            issueMessage = "No iTunes track is assigned."
        } else {
            issueMessage = nil
        }

        let changes: [ITunesTaggingFieldChange] = selectedAvailableFields.compactMap { field in
            guard let file else { return nil }
            let localValue = field.localValue(from: file)
            let remoteValue = remoteValue(for: field, selectedTrack: selectedTrack)
            let status = Self.changeStatus(localValue: localValue, remoteValue: remoteValue)
            let willWrite = !remoteValue.isEmpty && status != .same && selectedTrack != nil
            return ITunesTaggingFieldChange(
                field: field,
                localValue: localValue,
                remoteValue: remoteValue,
                status: status,
                willWrite: willWrite
            )
        }
        .sorted { $0.field.writeOrderIndex < $1.field.writeOrderIndex }

        return ITunesTaggingPlanRow(
            fileInput: assignment.fileInput,
            file: file,
            track: selectedTrack,
            changes: changes,
            issueMessage: issueMessage
        )
    }

    private func isFieldAvailable(_ field: ITunesTagWriteField) -> Bool {
        assignments.compactMap(track).contains {
            !remoteValue(for: field, selectedTrack: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func remoteValue(for field: ITunesTagWriteField, selectedTrack: ITunesTrackResult?) -> String {
        guard let selectedTrack else { return "" }
        switch field {
        case .title: return selectedTrack.trackName
        case .artist: return selectedTrack.artistName
        case .albumArtist: return selectedTrack.collectionArtistName.isEmpty ? detail.album.artistName : selectedTrack.collectionArtistName
        case .album: return detail.album.collectionName
        case .genre: return selectedTrack.primaryGenreName.isEmpty ? detail.album.primaryGenreName : selectedTrack.primaryGenreName
        case .trackNumber: return selectedTrack.trackNumber > 0 ? String(selectedTrack.trackNumber) : ""
        case .trackTotal: return selectedTrack.trackCount > 0 ? String(selectedTrack.trackCount) : ""
        case .discNumber: return selectedTrack.discNumber > 0 ? String(selectedTrack.discNumber) : ""
        case .discTotal: return selectedTrack.discCount > 1 ? String(selectedTrack.discCount) : ""
        case .releaseDate: return selectedTrack.releaseDate.isEmpty ? detail.album.releaseDate : selectedTrack.releaseDate
        case .copyright: return selectedTrack.copyright.isEmpty ? detail.album.copyright : selectedTrack.copyright
        case .barcode: return barcodeValue
        case .itunesAlbumID: return String(detail.album.collectionID)
        case .itunesArtistID: return selectedTrack.artistID.map(String.init) ?? detail.album.artistID.map(String.init) ?? ""
        case .itunesCatalogID: return String(selectedTrack.trackID)
        case .isExplicit: return selectedTrack.isExplicit || detail.album.isExplicit ? "Yes" : "No"
        }
    }

    private static func changeStatus(localValue: String, remoteValue: String) -> ITunesTaggingFieldChange.Status {
        let local = localValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = remoteValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if local.isEmpty && remote.isEmpty { return .same }
        if local.isEmpty { return .missingLocal }
        if remote.isEmpty { return .missingRemote }
        if normalized(local) == normalized(remote) { return .same }
        return .different
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
