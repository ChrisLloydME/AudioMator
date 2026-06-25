import Foundation
import Combine

enum MusicBrainzTagWriteField: String, CaseIterable, Identifiable, Hashable {
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
    case publisher
    case isrc
    case barcode
    case musicBrainzAlbumID
    case musicBrainzTrackID
    case musicBrainzReleaseGroupID
    case language
    case mediaType
    case releaseType
    case catalogNumber
    case releaseCountry
    case composer
    case lyricist
    case producer
    case engineer
    case remixer
    case copyright

    var id: String { rawValue }

    var writeOrderIndex: Int {
        Self.allCases.firstIndex(of: self) ?? Int.max
    }

    var displayName: String {
        switch self {
        case .title:
            return L10n.string("Title")
        case .artist:
            return L10n.string("Artist")
        case .albumArtist:
            return L10n.string("Album Artist")
        case .album:
            return L10n.string("Album")
        case .genre:
            return L10n.string("Genre")
        case .trackNumber:
            return L10n.string("Track Number")
        case .trackTotal:
            return L10n.string("Total Tracks")
        case .discNumber:
            return L10n.string("Disc Number")
        case .discTotal:
            return L10n.string("Total Discs")
        case .releaseDate:
            return L10n.string("Release Date")
        case .publisher:
            return L10n.string("Publisher")
        case .isrc:
            return L10n.string("ISRC")
        case .barcode:
            return L10n.string("Barcode")
        case .musicBrainzAlbumID:
            return L10n.string("MusicBrainz Release ID")
        case .musicBrainzTrackID:
            return L10n.string("MusicBrainz Track ID")
        case .musicBrainzReleaseGroupID:
            return L10n.string("MusicBrainz Release Group ID")
        case .language:
            return L10n.string("Language")
        case .mediaType:
            return L10n.string("Media Type")
        case .releaseType:
            return L10n.string("Release Type")
        case .catalogNumber:
            return L10n.string("Catalog Number")
        case .releaseCountry:
            return L10n.string("Release Country")
        case .composer:
            return L10n.string("Composer")
        case .lyricist:
            return L10n.string("Lyricist")
        case .producer:
            return L10n.string("Producer")
        case .engineer:
            return L10n.string("Engineer")
        case .remixer:
            return L10n.string("Remixer")
        case .copyright:
            return L10n.string("Copyright")
        }
    }

    var description: String {
        switch self {
        case .title:
            return L10n.string("Track title from the matched release track.")
        case .artist:
            return L10n.string("Track artist credit, or the release artist when the track artist is blank.")
        case .albumArtist:
            return L10n.string("Release artist credit.")
        case .album:
            return L10n.string("Release title.")
        case .genre:
            return L10n.string("Release genres from MusicBrainz.")
        case .trackNumber:
            return L10n.string("Matched track index.")
        case .trackTotal:
            return L10n.string("Total tracks from the matched MusicBrainz medium.")
        case .discNumber:
            return L10n.string("Matched disc index.")
        case .discTotal:
            return L10n.string("Total discs from the matched MusicBrainz release.")
        case .releaseDate:
            return L10n.string("Release date from MusicBrainz.")
        case .publisher:
            return L10n.string("Primary label from the release.")
        case .isrc:
            return L10n.string("ISRC codes from the matched track.")
        case .barcode:
            return L10n.string("Release barcode or UPC/EAN.")
        case .musicBrainzAlbumID:
            return L10n.string("MusicBrainz release MBID.")
        case .musicBrainzTrackID:
            return L10n.string("MusicBrainz track MBID.")
        case .musicBrainzReleaseGroupID:
            return L10n.string("MusicBrainz release group MBID.")
        case .language:
            return L10n.string("Release text language.")
        case .mediaType:
            return L10n.string("Release medium format, such as CD or Digital Media.")
        case .releaseType:
            return L10n.string("Release group type, such as Album or EP.")
        case .catalogNumber:
            return L10n.string("Primary catalog number from the release label.")
        case .releaseCountry:
            return L10n.string("Release country code from MusicBrainz.")
        case .composer:
            return L10n.string("Composer credit from the matched recording's relationship data.")
        case .lyricist:
            return L10n.string("Lyricist or writer credits from the matched recording.")
        case .producer:
            return L10n.string("Producer credits from the matched recording.")
        case .engineer:
            return L10n.string("Engineer credits from the matched recording.")
        case .remixer:
            return L10n.string("Remixer credits from the matched recording.")
        case .copyright:
            return L10n.string("Phonographic copyright credits from the matched recording.")
        }
    }

    var isDefaultSelected: Bool {
        switch self {
        case .composer, .lyricist, .producer, .engineer, .remixer, .copyright, .genre,
             .trackTotal, .discTotal:
            return false
        case .title, .artist, .albumArtist, .album, .trackNumber, .discNumber, .releaseDate,
             .publisher, .isrc, .barcode, .musicBrainzAlbumID, .musicBrainzTrackID,
             .musicBrainzReleaseGroupID, .language, .mediaType, .releaseType,
             .catalogNumber, .releaseCountry:
            return true
        }
    }

    var requiresRecordingDetail: Bool {
        switch self {
        case .composer, .lyricist, .producer, .engineer, .remixer, .copyright:
            return true
        case .title, .artist, .albumArtist, .album, .genre, .trackNumber, .trackTotal, .discNumber,
             .discTotal,
             .releaseDate, .publisher, .isrc, .barcode, .musicBrainzAlbumID,
             .musicBrainzTrackID, .musicBrainzReleaseGroupID, .language, .mediaType,
             .releaseType, .catalogNumber, .releaseCountry:
            return false
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
        case .genre:
            return file.genre
        case .trackNumber:
            return AudioTagNumberPair(
                rawText: file.trackNumberText,
                number: file.track,
                total: file.trackTotal
            ).displayedNumberText
        case .trackTotal:
            return AudioTagNumberPair(
                rawText: file.trackNumberText,
                number: file.track,
                total: file.trackTotal
            ).displayedTotalText
        case .discNumber:
            return AudioTagNumberPair(
                rawText: file.discNumberText,
                number: file.disc,
                total: file.discTotal
            ).displayedNumberText
        case .discTotal:
            return AudioTagNumberPair(
                rawText: file.discNumberText,
                number: file.disc,
                total: file.discTotal
            ).displayedTotalText
        case .releaseDate:
            return file.releaseDate.isEmpty ? file.year : file.releaseDate
        case .publisher:
            return file.publisher
        case .isrc:
            return file.isrc
        case .barcode:
            return file.barcode
        case .musicBrainzAlbumID:
            return file.musicBrainzAlbumID
        case .musicBrainzTrackID:
            return file.musicBrainzTrackID
        case .musicBrainzReleaseGroupID:
            return file.musicBrainzReleaseGroupID
        case .language:
            return file.language
        case .mediaType:
            return file.mediaType
        case .releaseType:
            return file.releaseType
        case .catalogNumber:
            return file.catalogNumber
        case .releaseCountry:
            return file.releaseCountry
        case .composer:
            return file.composer
        case .lyricist:
            return file.lyricist
        case .producer:
            return file.producer
        case .engineer:
            return file.engineer
        case .remixer:
            return file.remixer
        case .copyright:
            return file.copyright
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
        case .genre:
            edit.genre = value
        case .trackNumber:
            edit.setTrackNumberFieldText(value)
        case .trackTotal:
            edit.setTrackTotalFieldText(value)
        case .discNumber:
            edit.setDiscNumberFieldText(value)
        case .discTotal:
            edit.setDiscTotalFieldText(value)
        case .releaseDate:
            edit.releaseDate = value
        case .publisher:
            edit.publisher = value
        case .isrc:
            edit.isrc = value
        case .barcode:
            edit.barcode = value
        case .musicBrainzAlbumID:
            edit.musicBrainzAlbumID = value
        case .musicBrainzTrackID:
            edit.musicBrainzTrackID = value
        case .musicBrainzReleaseGroupID:
            edit.musicBrainzReleaseGroupID = value
        case .language:
            edit.language = value
        case .mediaType:
            edit.mediaType = value
        case .releaseType:
            edit.releaseType = value
        case .catalogNumber:
            edit.catalogNumber = value
        case .releaseCountry:
            edit.releaseCountry = value
        case .composer:
            edit.composer = value
        case .lyricist:
            edit.lyricist = value
        case .producer:
            edit.producer = value
        case .engineer:
            edit.engineer = value
        case .remixer:
            edit.remixer = value
        case .copyright:
            edit.copyright = value
        }
    }
}

struct MusicBrainzTaggingWriteEntry: Identifiable {
    let fileID: UUID
    let fileName: String
    let values: [MusicBrainzTagWriteField: String]
    let expectedFileFingerprint: AudioFileFingerprint?

    init(
        fileID: UUID,
        fileName: String,
        values: [MusicBrainzTagWriteField: String],
        expectedFileFingerprint: AudioFileFingerprint? = nil
    ) {
        self.fileID = fileID
        self.fileName = fileName
        self.values = values
        self.expectedFileFingerprint = expectedFileFingerprint
    }

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
        guard let file, let fileFingerprint = file.fileFingerprint else { return nil }

        let values = Dictionary(
            uniqueKeysWithValues: changes
                .filter(\.willWrite)
                .map { ($0.field, $0.remoteValue) }
        )

        guard !values.isEmpty else { return nil }

        return MusicBrainzTaggingWriteEntry(
            fileID: file.id,
            fileName: file.url.lastPathComponent,
            values: values,
            expectedFileFingerprint: fileFingerprint
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

    enum RecordingLookupState: Equatable {
        case idle
        case loading
        case loaded(MusicBrainzRecordingDetail)
        case failed(String)

        var recordingDetail: MusicBrainzRecordingDetail? {
            switch self {
            case .loaded(let detail):
                return detail
            case .idle, .loading, .failed:
                return nil
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
    @Published private(set) var recordingStates: [String: RecordingLookupState] = [:]
    @Published private(set) var fieldAvailabilityRecordingIDs: Set<String> = []
    @Published private(set) var recordingPreloadTargetIDs: Set<String> = []

    private let browserStore: MusicBrainzBrowserStore
    private var recordingLoadTasks: [String: Task<Void, Never>] = [:]
    private let releaseArtistCredit: String
    private let publisherName: String
    private let primaryCatalogNumber: String
    private let totalMediumCount: Int
    private let shouldPreloadAllReleaseRecordings: Bool

    init(
        release: MusicBrainzReleaseDetail,
        preview: MusicBrainzReleaseMatchPreview,
        loadedFiles: [AudioFile],
        browserStore: MusicBrainzBrowserStore
    ) {
        self.release = release
        self.browserStore = browserStore
        let flattenedTracks = Self.flattenedTracks(from: release)
        self.availableTracks = flattenedTracks
        self.loadedFilesByInputID = Dictionary(
            uniqueKeysWithValues: loadedFiles.map { ($0.id.uuidString, $0) }
        )
        self.selectedFields = Set(MusicBrainzTagWriteField.allCases.filter(\.isDefaultSelected))
        self.releaseArtistCredit = release.artistCredit
        self.publisherName = release.labels.first(where: { !$0.labelName.isEmpty })?.labelName ?? ""
        self.primaryCatalogNumber = release.labels.first(where: { !$0.catalogNumber.isEmpty })?.catalogNumber ?? ""
        self.totalMediumCount = max(release.media.count, 1)
        self.shouldPreloadAllReleaseRecordings = flattenedTracks.count <= MusicBrainzBrowserStore.fullReleaseRecordingPreloadLimit

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

        refreshRecordingPreloadTargets()
    }

    deinit {
        recordingLoadTasks.values.forEach { $0.cancel() }
    }

    var plan: MusicBrainzTaggingPlan {
        let selectedFields = selectedAvailableFields
        let tracksByID = Dictionary(uniqueKeysWithValues: availableTracks.map { ($0.id, $0) })
        return MusicBrainzTaggingPlan(
            rows: assignments.map { assignment in
                buildPlanRow(
                    for: assignment,
                    selectedFields: selectedFields,
                    selectedTrack: assignment.selectedTrackID.flatMap { tracksByID[$0] }
                )
            }
        )
    }

    var availableFields: [MusicBrainzTagWriteField] {
        guard !isLoadingFieldAvailability else { return [] }

        let tracksByID = Dictionary(uniqueKeysWithValues: availableTracks.map { ($0.id, $0) })
        let selectedTracks = assignments.compactMap { assignment in
            assignment.selectedTrackID.flatMap { tracksByID[$0] }
        }
        return MusicBrainzTagWriteField.allCases.filter { field in
            selectedTracks.contains { track in
                hasRemoteValue(for: field, selectedTrack: track)
            }
        }
    }

    var selectedAvailableFields: Set<MusicBrainzTagWriteField> {
        selectedFields.intersection(availableFields)
    }

    var isLoadingFieldAvailability: Bool {
        fieldAvailabilityRecordingIDs.contains { recordingID in
            switch recordingState(for: recordingID) {
            case .idle, .loading:
                return true
            case .loaded, .failed:
                return false
            }
        }
    }

    var recordingPreloadCompletedCount: Int {
        recordingPreloadTargetIDs.reduce(into: 0) { count, recordingID in
            switch recordingState(for: recordingID) {
            case .loaded, .failed:
                count += 1
            case .idle, .loading:
                break
            }
        }
    }

    var recordingPreloadTotalCount: Int {
        recordingPreloadTargetIDs.count
    }

    var recordingPreloadProgress: Double {
        guard recordingPreloadTotalCount > 0 else { return 1 }
        return Double(recordingPreloadCompletedCount) / Double(recordingPreloadTotalCount)
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

    var hasPendingRecordingLoads: Bool {
        guard selectedFields.contains(where: \.requiresRecordingDetail) else { return false }

        return recordingIDsForAssignedTracks.contains { recordingID in
            recordingState(for: recordingID).isLoading
        }
    }

    var recordingFailureCount: Int {
        guard selectedFields.contains(where: \.requiresRecordingDetail) else { return 0 }

        return recordingIDsForAssignedTracks.reduce(into: 0) { count, recordingID in
            if case .failed = recordingState(for: recordingID) {
                count += 1
            }
        }
    }

    var canApply: Bool {
        canApply(using: plan)
    }

    func canApply(using plan: MusicBrainzTaggingPlan) -> Bool {
        !selectedAvailableFields.isEmpty &&
        !hasDuplicateTrackAssignments &&
        !hasPendingRecordingLoads &&
        !plan.writeEntries.isEmpty
    }

    var applyDisabledReason: String? {
        applyDisabledReason(using: plan)
    }

    func applyDisabledReason(using plan: MusicBrainzTaggingPlan) -> String? {
        if selectedAvailableFields.isEmpty {
            return L10n.string("Choose at least one field to write.")
        }

        if hasDuplicateTrackAssignments {
            return L10n.string("Each MusicBrainz track can only be assigned once before writing.")
        }

        if hasPendingRecordingLoads {
            return L10n.string("MusicBrainz recording details are still loading.")
        }

        if plan.writeEntries.isEmpty {
            return L10n.string("No selected fields would change any loaded files.")
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
            if field.requiresRecordingDetail {
                ensureRecordingDataIfNeeded()
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

        refreshRecordingPreloadTargets()

        if selectedAvailableFields.contains(where: \.requiresRecordingDetail) {
            ensureRecordingDataIfNeeded()
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

    func recordingState(for recordingID: String) -> RecordingLookupState {
        recordingStates[recordingID] ?? .idle
    }

    func ensureRecordingDataIfNeeded() {
        guard selectedFields.contains(where: \.requiresRecordingDetail) else { return }
        refreshRecordingPreloadTargets()
    }

    private var recordingIDsForAssignedTracks: Set<String> {
        Set(
            assignments.compactMap { assignment in
                track(for: assignment)?.recordingID
            }
            .filter { !$0.isEmpty }
        )
    }

    private var recordingIDsForReleaseTracks: Set<String> {
        Set(availableTracks.map(\.recordingID).filter { !$0.isEmpty })
    }

    private func refreshRecordingPreloadTargets() {
        fieldAvailabilityRecordingIDs = recordingIDsForAssignedTracks

        if shouldPreloadAllReleaseRecordings {
            recordingPreloadTargetIDs = recordingIDsForReleaseTracks
        } else {
            recordingPreloadTargetIDs.formUnion(recordingIDsForAssignedTracks)
        }

        ensureRecordingDataIfNeeded(for: recordingPreloadTargetIDs)
    }

    private func ensureRecordingDataIfNeeded(for recordingIDs: Set<String>) {
        for recordingID in recordingIDs {
            let currentState = recordingStates[recordingID] ?? .idle
            guard case .idle = currentState else { continue }

            if let cachedDetail = browserStore.cachedRecordingDetail(id: recordingID) {
                recordingStates[recordingID] = .loaded(cachedDetail)
                continue
            }

            recordingStates[recordingID] = .loading

            recordingLoadTasks[recordingID] = Task { [weak self] in
                guard let self else { return }

                do {
                    let detail = try await self.browserStore.recordingDetail(id: recordingID)

                    await MainActor.run {
                        self.recordingStates[recordingID] = .loaded(detail)
                        self.recordingLoadTasks[recordingID] = nil
                    }
                } catch {
                    await MainActor.run {
                        self.recordingStates[recordingID] = .failed(
                            (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        )
                        self.recordingLoadTasks[recordingID] = nil
                    }
                }
            }
        }
    }

    private func buildPlanRow(
        for assignment: AssignmentDraft,
        selectedFields: Set<MusicBrainzTagWriteField>,
        selectedTrack: MusicBrainzReleaseMatchTrack?
    ) -> MusicBrainzTaggingPlanRow {
        let file = loadedFilesByInputID[assignment.fileInput.id]

        let issueMessage: String?
        if file == nil {
            issueMessage = "The file is no longer loaded in AudioMator."
        } else if file?.fileFingerprint == nil {
            issueMessage = "The file version could not be captured. Reload the file before applying tags."
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
        .sorted { Self.fieldIndex(for: $0.field) < Self.fieldIndex(for: $1.field) }

        return MusicBrainzTaggingPlanRow(
            fileInput: assignment.fileInput,
            file: file,
            track: selectedTrack,
            changes: changes,
            issueMessage: issueMessage
        )
    }

    private func hasRemoteValue(
        for field: MusicBrainzTagWriteField,
        selectedTrack: MusicBrainzReleaseMatchTrack?
    ) -> Bool {
        !remoteValue(
            for: field,
            selectedTrack: selectedTrack
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
    }

    private func remoteValue(
        for field: MusicBrainzTagWriteField,
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
        case .genre:
            return Self.genreValue(from: release)
        case .trackNumber:
            return Self.trackNumberText(for: selectedTrack)
        case .trackTotal:
            return Self.trackTotalText(for: selectedTrack)
        case .discNumber:
            return Self.discNumberText(for: selectedTrack)
        case .discTotal:
            return Self.discTotalText(totalMediumCount: totalMediumCount)
        case .releaseDate:
            return release.date
        case .publisher:
            return publisherName
        case .isrc:
            return Self.joinedList(selectedTrack.isrcs)
        case .barcode:
            return release.barcode
        case .musicBrainzAlbumID:
            return release.id
        case .musicBrainzTrackID:
            return selectedTrack.id
        case .musicBrainzReleaseGroupID:
            return release.releaseGroupID
        case .language:
            return release.language
        case .mediaType:
            return selectedTrack.mediumFormat.isEmpty ? Self.releaseMediaType(from: release) : selectedTrack.mediumFormat
        case .releaseType:
            return Self.releaseTypeValue(from: release)
        case .catalogNumber:
            return primaryCatalogNumber
        case .releaseCountry:
            return release.country
        case .composer:
            return recordingRemoteValue(for: .composer, recordingID: selectedTrack.recordingID)
        case .lyricist:
            return recordingRemoteValue(for: .lyricist, recordingID: selectedTrack.recordingID)
        case .producer:
            return recordingRemoteValue(for: .producer, recordingID: selectedTrack.recordingID)
        case .engineer:
            return recordingRemoteValue(for: .engineer, recordingID: selectedTrack.recordingID)
        case .remixer:
            return recordingRemoteValue(for: .remixer, recordingID: selectedTrack.recordingID)
        case .copyright:
            return recordingRemoteValue(for: .copyright, recordingID: selectedTrack.recordingID)
        }
    }

    private func recordingRemoteValue(
        for field: MusicBrainzTagWriteField,
        recordingID: String
    ) -> String {
        guard
            !recordingID.isEmpty,
            let detail = recordingState(for: recordingID).recordingDetail
        else {
            return ""
        }

        return Self.recordingValue(for: field, from: detail)
    }

    private static func recordingValue(
        for field: MusicBrainzTagWriteField,
        from detail: MusicBrainzRecordingDetail
    ) -> String {
        switch field {
        case .composer:
            return relationshipValue(in: detail, matchingAnyOf: ["composer"])
        case .lyricist:
            return relationshipValue(in: detail, matchingAnyOf: ["lyricist", "writer", "text writer"])
        case .producer:
            return relationshipValue(in: detail, containing: "producer")
        case .engineer:
            return relationshipValue(in: detail, containing: "engineer")
        case .remixer:
            return relationshipValue(in: detail, matchingAnyOf: ["remixer", "remix"])
        case .copyright:
            return relationshipValue(in: detail, matchingAnyOf: ["phonographic copyright (℗) by"])
        case .title, .artist, .albumArtist, .album, .genre, .trackNumber, .trackTotal,
             .discNumber, .discTotal,
             .releaseDate, .publisher, .isrc, .barcode, .musicBrainzAlbumID,
             .musicBrainzTrackID, .musicBrainzReleaseGroupID, .language, .mediaType,
             .releaseType, .catalogNumber, .releaseCountry:
            return ""
        }
    }

    private static func relationshipValue(
        in detail: MusicBrainzRecordingDetail,
        matchingAnyOf exactTitles: [String]
    ) -> String {
        let normalizedTitles = Set(exactTitles.map { $0.lowercased() })
        let matches = detail.relationshipGroups
            .filter { normalizedTitles.contains($0.title.lowercased()) }
            .flatMap(\.values)
        return joinedList(matches)
    }

    private static func relationshipValue(
        in detail: MusicBrainzRecordingDetail,
        containing needle: String
    ) -> String {
        let loweredNeedle = needle.lowercased()
        let matches = detail.relationshipGroups
            .filter { $0.title.lowercased().contains(loweredNeedle) }
            .flatMap(\.values)
        return joinedList(matches)
    }

    private static func genreValue(from release: MusicBrainzReleaseDetail) -> String {
        let preferredTerms = release.genres.isEmpty ? release.tags : release.genres
        return joinedList(preferredTerms.map(\.name))
    }

    private static func releaseTypeValue(from release: MusicBrainzReleaseDetail) -> String {
        joinedList([release.releaseGroupPrimaryType] + release.releaseGroupSecondaryTypes)
    }

    private static func releaseMediaType(from release: MusicBrainzReleaseDetail) -> String {
        joinedList(release.media.map(\.format))
    }

    private static func joinedList(_ values: [String]) -> String {
        let normalizedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedValues.isEmpty else { return "" }

        let uniqueValues = (Array(NSOrderedSet(array: normalizedValues)) as? [String]) ?? normalizedValues
        return uniqueValues.joined(separator: ", ")
    }

    private static func fieldIndex(for field: MusicBrainzTagWriteField) -> Int {
        MusicBrainzTagWriteField.allCases.firstIndex(of: field) ?? Int.max
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
                    mediumTrackCount: medium.trackCount,
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
        return numberComponents(track.number).number
    }

    private static func trackTotalText(for track: MusicBrainzReleaseMatchTrack) -> String {
        let explicitTotal = numberComponents(track.number).total
        if !explicitTotal.isEmpty {
            return explicitTotal
        }

        return track.mediumTrackCount > 0 ? String(track.mediumTrackCount) : ""
    }

    private static func discNumberText(for track: MusicBrainzReleaseMatchTrack) -> String {
        guard track.mediumPosition > 0 else { return "" }
        return String(track.mediumPosition)
    }

    private static func discTotalText(totalMediumCount: Int) -> String {
        totalMediumCount > 1 ? String(totalMediumCount) : ""
    }

    private static func numberComponents(_ value: String) -> (number: String, total: String) {
        let parts = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let number = parts.first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let total = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return (number, total)
    }
}
