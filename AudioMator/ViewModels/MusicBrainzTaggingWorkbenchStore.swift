import Foundation
import Combine

enum MusicBrainzTagWriteField: String, CaseIterable, Identifiable, Hashable {
    case title
    case artist
    case albumArtist
    case album
    case trackNumber
    case discNumber
    case releaseDate
    case publisher
    case composer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .title:
            return "Title"
        case .artist:
            return "Artist"
        case .albumArtist:
            return "Album Artist"
        case .album:
            return "Album"
        case .trackNumber:
            return "Track Number"
        case .discNumber:
            return "Disc Number"
        case .releaseDate:
            return "Release Date"
        case .publisher:
            return "Publisher"
        case .composer:
            return "Composer"
        }
    }

    var description: String {
        switch self {
        case .title:
            return "Track title from the matched release track."
        case .artist:
            return "Track artist credit, or the release artist when the track artist is blank."
        case .albumArtist:
            return "Release artist credit."
        case .album:
            return "Release title."
        case .trackNumber:
            return "Matched track index, with total when MusicBrainz provides it."
        case .discNumber:
            return "Matched disc index, with total discs when available."
        case .releaseDate:
            return "Release date from MusicBrainz."
        case .publisher:
            return "Primary label from the release."
        case .composer:
            return "Composer credit from the matched recording's relationship data."
        }
    }

    var isDefaultSelected: Bool {
        switch self {
        case .composer:
            return false
        case .title, .artist, .albumArtist, .album, .trackNumber, .discNumber, .releaseDate, .publisher:
            return true
        }
    }

    func localValue(from file: AudioFile) -> String {
        switch self {
        case .title:
            return file.title
        case .artist:
            return file.artist
        case .albumArtist:
            return file.albumArtist
        case .album:
            return file.album
        case .trackNumber:
            return file.trackNumberText
        case .discNumber:
            return file.discNumberText
        case .releaseDate:
            return file.releaseDate.isEmpty ? file.year : file.releaseDate
        case .publisher:
            return file.publisher
        case .composer:
            return file.composer
        }
    }

    func apply(_ value: String, to edit: inout SingleFileEditModel) {
        switch self {
        case .title:
            edit.title = value
        case .artist:
            edit.artist = value
        case .albumArtist:
            edit.albumArtist = value
        case .album:
            edit.album = value
        case .trackNumber:
            edit.trackNumberText = value
        case .discNumber:
            edit.discNumberText = value
        case .releaseDate:
            edit.releaseDate = value
        case .publisher:
            edit.publisher = value
        case .composer:
            edit.composer = value
        }
    }
}

struct MusicBrainzTaggingWriteEntry: Identifiable {
    let fileID: UUID
    let fileName: String
    let values: [MusicBrainzTagWriteField: String]

    var id: UUID { fileID }
}

struct MusicBrainzTaggingFieldChange: Identifiable {
    enum Status: Equatable {
        case same
        case different
        case missingLocal
        case missingRemote
    }

    let field: MusicBrainzTagWriteField
    let localValue: String
    let remoteValue: String
    let status: Status
    let willWrite: Bool

    var id: String { field.rawValue }
}

struct MusicBrainzTaggingPlanRow: Identifiable {
    let fileInput: MusicBrainzFileSearchInput
    let file: AudioFile?
    let track: MusicBrainzReleaseMatchTrack?
    let changes: [MusicBrainzTaggingFieldChange]
    let issueMessage: String?

    var id: String { fileInput.id }

    var writeEntry: MusicBrainzTaggingWriteEntry? {
        guard let file else { return nil }

        let values = Dictionary(
            uniqueKeysWithValues: changes
                .filter(\.willWrite)
                .map { ($0.field, $0.remoteValue) }
        )

        guard !values.isEmpty else { return nil }

        return MusicBrainzTaggingWriteEntry(
            fileID: file.id,
            fileName: file.url.lastPathComponent,
            values: values
        )
    }
}

struct MusicBrainzTaggingPlan {
    let rows: [MusicBrainzTaggingPlanRow]

    var writeEntries: [MusicBrainzTaggingWriteEntry] {
        rows.compactMap(\.writeEntry)
    }

    var changeCount: Int {
        rows.reduce(0) { partialResult, row in
            partialResult + row.changes.filter(\.willWrite).count
        }
    }

    var filesWithChangesCount: Int {
        writeEntries.count
    }

    var unresolvedIssueCount: Int {
        rows.filter { $0.issueMessage != nil }.count
    }
}

@MainActor
final class MusicBrainzTaggingWorkbenchStore: ObservableObject, Identifiable {
    struct AssignmentDraft: Identifiable, Hashable {
        let fileInput: MusicBrainzFileSearchInput
        let initialTrackID: String?
        let initialReason: String?
        let initialScore: Double?
        var selectedTrackID: String?

        var id: String { fileInput.id }
    }

    enum ComposerLookupState: Equatable {
        case idle
        case loading
        case loaded(String)
        case failed(String)

        var resolvedValue: String {
            switch self {
            case .loaded(let value):
                return value
            case .idle, .loading, .failed:
                return ""
            }
        }

        var isLoading: Bool {
            if case .loading = self {
                return true
            }
            return false
        }
    }

    let id = UUID()
    let release: MusicBrainzReleaseDetail

    @Published private(set) var assignments: [AssignmentDraft]
    @Published private(set) var availableTracks: [MusicBrainzReleaseMatchTrack]
    @Published private(set) var loadedFilesByInputID: [String: AudioFile]
    @Published var selectedFields: Set<MusicBrainzTagWriteField>
    @Published private(set) var composerStates: [String: ComposerLookupState] = [:]

    private let browserStore: MusicBrainzBrowserStore
    private var composerLoadTasks: [String: Task<Void, Never>] = [:]
    private let releaseArtistCredit: String
    private let publisherName: String
    private let totalMediumCount: Int

    init(
        release: MusicBrainzReleaseDetail,
        preview: MusicBrainzReleaseMatchPreview,
        loadedFiles: [AudioFile],
        browserStore: MusicBrainzBrowserStore
    ) {
        self.release = release
        self.browserStore = browserStore
        self.availableTracks = Self.flattenedTracks(from: release)
        self.loadedFilesByInputID = Dictionary(
            uniqueKeysWithValues: loadedFiles.map { ($0.id.uuidString, $0) }
        )
        self.selectedFields = Set(MusicBrainzTagWriteField.allCases.filter(\.isDefaultSelected))
        self.releaseArtistCredit = release.artistCredit
        self.publisherName = release.labels.first(where: { !$0.labelName.isEmpty })?.labelName ?? ""
        self.totalMediumCount = max(release.media.count, 1)

        let autoAssignments = Dictionary(
            uniqueKeysWithValues: preview.matchedAssignments.map { ($0.file.id, $0) }
        )
        let orderedFiles = preview.matchedAssignments.map(\.file) + preview.unmatchedFiles

        self.assignments = orderedFiles.map { file in
            let autoAssignment = autoAssignments[file.id]
            return AssignmentDraft(
                fileInput: file,
                initialTrackID: autoAssignment?.track.id,
                initialReason: autoAssignment?.reason,
                initialScore: autoAssignment?.score,
                selectedTrackID: autoAssignment?.track.id
            )
        }
    }

    deinit {
        composerLoadTasks.values.forEach { $0.cancel() }
    }

    var plan: MusicBrainzTaggingPlan {
        MusicBrainzTaggingPlan(rows: assignments.map(buildPlanRow))
    }

    var hasDuplicateTrackAssignments: Bool {
        !duplicateTrackIDs.isEmpty
    }

    var duplicateTrackIDs: Set<String> {
        let ids = assignments.compactMap(\.selectedTrackID)
        var seen: Set<String> = []
        var duplicates: Set<String> = []

        for id in ids {
            if !seen.insert(id).inserted {
                duplicates.insert(id)
            }
        }

        return duplicates
    }

    var hasPendingComposerLoads: Bool {
        composerStates.values.contains(where: \.isLoading)
    }

    var composerFailureCount: Int {
        composerStates.values.reduce(into: 0) { count, state in
            if case .failed = state {
                count += 1
            }
        }
    }

    var canApply: Bool {
        !selectedFields.isEmpty &&
        !hasDuplicateTrackAssignments &&
        !hasPendingComposerLoads &&
        !plan.writeEntries.isEmpty
    }

    var applyDisabledReason: String? {
        if selectedFields.isEmpty {
            return "Choose at least one field to write."
        }

        if hasDuplicateTrackAssignments {
            return "Each MusicBrainz track can only be assigned once before writing."
        }

        if hasPendingComposerLoads {
            return "Composer credits are still loading from MusicBrainz."
        }

        if plan.writeEntries.isEmpty {
            return "No selected fields would change any loaded files."
        }

        return nil
    }

    func refreshLoadedFiles(_ files: [AudioFile]) {
        loadedFilesByInputID = Dictionary(
            uniqueKeysWithValues: files.map { ($0.id.uuidString, $0) }
        )
    }

    func isFieldSelected(_ field: MusicBrainzTagWriteField) -> Bool {
        selectedFields.contains(field)
    }

    func setFieldSelected(_ isSelected: Bool, for field: MusicBrainzTagWriteField) {
        if isSelected {
            selectedFields.insert(field)
            if field == .composer {
                ensureComposerDataIfNeeded()
            }
        } else {
            selectedFields.remove(field)
        }
    }

    func selectedTrackID(for assignmentID: String) -> String? {
        assignments.first(where: { $0.id == assignmentID })?.selectedTrackID
    }

    func updateSelectedTrack(_ trackID: String?, for assignmentID: String) {
        guard let index = assignments.firstIndex(where: { $0.id == assignmentID }) else { return }
        assignments[index].selectedTrackID = trackID

        if selectedFields.contains(.composer) {
            ensureComposerDataIfNeeded()
        }
    }

    func track(for assignment: AssignmentDraft) -> MusicBrainzReleaseMatchTrack? {
        guard let selectedTrackID = assignment.selectedTrackID else { return nil }
        return availableTracks.first(where: { $0.id == selectedTrackID })
    }

    func isDuplicateAssignment(_ assignment: AssignmentDraft) -> Bool {
        guard let selectedTrackID = assignment.selectedTrackID else { return false }
        return duplicateTrackIDs.contains(selectedTrackID)
    }

    func composerState(for recordingID: String) -> ComposerLookupState {
        composerStates[recordingID] ?? .idle
    }

    func composerRemoteValue(for recordingID: String) -> String {
        composerState(for: recordingID).resolvedValue
    }

    func ensureComposerDataIfNeeded() {
        guard selectedFields.contains(.composer) else { return }

        let recordingIDs = Set(
            assignments.compactMap { assignment in
                track(for: assignment)?.recordingID
            }
            .filter { !$0.isEmpty }
        )

        for recordingID in recordingIDs {
            let currentState = composerStates[recordingID] ?? .idle
            guard case .idle = currentState else { continue }

            composerStates[recordingID] = .loading

            composerLoadTasks[recordingID] = Task { [weak self] in
                guard let self else { return }

                do {
                    let detail = try await self.browserStore.recordingDetail(id: recordingID)
                    let composer = Self.composerValue(from: detail)

                    await MainActor.run {
                        self.composerStates[recordingID] = .loaded(composer)
                        self.composerLoadTasks[recordingID] = nil
                    }
                } catch {
                    await MainActor.run {
                        self.composerStates[recordingID] = .failed(
                            (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        )
                        self.composerLoadTasks[recordingID] = nil
                    }
                }
            }
        }
    }

    private func buildPlanRow(for assignment: AssignmentDraft) -> MusicBrainzTaggingPlanRow {
        let file = loadedFilesByInputID[assignment.fileInput.id]
        let selectedTrack = track(for: assignment)

        let issueMessage: String?
        if file == nil {
            issueMessage = "The file is no longer loaded in AudioMator."
        } else if selectedTrack == nil {
            issueMessage = "No MusicBrainz track is assigned."
        } else {
            issueMessage = nil
        }

        let changes: [MusicBrainzTaggingFieldChange] = selectedFields.compactMap { field in
            guard let file else { return nil }
            let localValue = field.localValue(from: file)
            let remoteValue = remoteValue(
                for: field,
                assignment: assignment,
                selectedTrack: selectedTrack
            )
            let status = Self.changeStatus(localValue: localValue, remoteValue: remoteValue)
            let willWrite = !remoteValue.isEmpty && status != .same && selectedTrack != nil

            return MusicBrainzTaggingFieldChange(
                field: field,
                localValue: localValue,
                remoteValue: remoteValue,
                status: status,
                willWrite: willWrite
            )
        }
        .sorted { $0.field.rawValue < $1.field.rawValue }

        return MusicBrainzTaggingPlanRow(
            fileInput: assignment.fileInput,
            file: file,
            track: selectedTrack,
            changes: changes,
            issueMessage: issueMessage
        )
    }

    private func remoteValue(
        for field: MusicBrainzTagWriteField,
        assignment: AssignmentDraft,
        selectedTrack: MusicBrainzReleaseMatchTrack?
    ) -> String {
        guard let selectedTrack else { return "" }

        switch field {
        case .title:
            return selectedTrack.title
        case .artist:
            return selectedTrack.artistCredit.isEmpty ? releaseArtistCredit : selectedTrack.artistCredit
        case .albumArtist:
            return releaseArtistCredit
        case .album:
            return release.title
        case .trackNumber:
            return Self.trackNumberText(for: selectedTrack)
        case .discNumber:
            return Self.discNumberText(for: selectedTrack, totalMediumCount: totalMediumCount)
        case .releaseDate:
            return release.date
        case .publisher:
            return publisherName
        case .composer:
            if selectedTrack.recordingID.isEmpty {
                return ""
            }
            return composerRemoteValue(for: selectedTrack.recordingID)
        }
    }

    private static func composerValue(from detail: MusicBrainzRecordingDetail) -> String {
        detail.relationshipGroups
            .first(where: { $0.title.caseInsensitiveCompare("composer") == .orderedSame })?
            .values
            .joined(separator: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func changeStatus(localValue: String, remoteValue: String) -> MusicBrainzTaggingFieldChange.Status {
        let normalizedLocal = localValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRemote = remoteValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedLocal.isEmpty && normalizedRemote.isEmpty {
            return .same
        }

        if normalizedLocal.isEmpty {
            return .missingLocal
        }

        if normalizedRemote.isEmpty {
            return .missingRemote
        }

        if normalizedComparisonValue(normalizedLocal) == normalizedComparisonValue(normalizedRemote) {
            return .same
        }

        return .different
    }

    private static func normalizedComparisonValue(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func flattenedTracks(from release: MusicBrainzReleaseDetail) -> [MusicBrainzReleaseMatchTrack] {
        release.media.enumerated().flatMap { mediumIndex, medium in
            medium.tracks.map { track in
                MusicBrainzReleaseMatchTrack(
                    id: track.id,
                    mediumTitle: medium.title,
                    mediumFormat: medium.format,
                    mediumPosition: mediumIndex + 1,
                    mediumTrackCount: max(medium.trackCount, medium.tracks.count),
                    releaseMediumCount: max(release.media.count, 1),
                    number: track.number,
                    title: track.title,
                    artistCredit: track.artistCredit,
                    durationMilliseconds: track.durationMilliseconds,
                    recordingID: track.recordingID,
                    isrcs: track.isrcs
                )
            }
        }
    }

    private static func trackNumberText(for track: MusicBrainzReleaseMatchTrack) -> String {
        guard !track.number.isEmpty else { return "" }

        if track.number.contains("/") || track.mediumTrackCount <= 0 {
            return track.number
        }

        guard track.number.allSatisfy(\.isNumber) else {
            return track.number
        }

        return "\(track.number)/\(track.mediumTrackCount)"
    }

    private static func discNumberText(
        for track: MusicBrainzReleaseMatchTrack,
        totalMediumCount: Int
    ) -> String {
        guard track.mediumPosition > 0 else { return "" }

        if totalMediumCount > 1 {
            return "\(track.mediumPosition)/\(totalMediumCount)"
        }

        return String(track.mediumPosition)
    }
}
