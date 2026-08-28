import Foundation

private extension MusicBrainzClientError {
    nonisolated var isRecoverableServerFailure: Bool {
        guard case .requestFailed(let statusCode) = self else { return false }
        return (500...599).contains(statusCode)
    }
}

actor MusicBrainzRateLimiter {
    private let minimumIntervalNanoseconds: UInt64
    private var lastRequestUptimeNanoseconds: UInt64?

    init(minimumIntervalNanoseconds: UInt64 = 1_100_000_000) {
        self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
    }

    func waitIfNeeded() async throws {
        let now = DispatchTime.now().uptimeNanoseconds

        if let lastRequestUptimeNanoseconds {
            let elapsed = now &- lastRequestUptimeNanoseconds
            if elapsed < minimumIntervalNanoseconds {
                try await Task.sleep(nanoseconds: minimumIntervalNanoseconds - elapsed)
            }
        }

        lastRequestUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
    }
}

nonisolated protocol MusicBrainzBrowserClient: Sendable {
    func search(matching query: MusicBrainzSearchQuery, limit: Int) async throws -> MusicBrainzSearchResults
    func recordingDetail(
        id: String,
        fallbackReleases: [MusicBrainzRecordingResult.Release]
    ) async throws -> MusicBrainzRecordingDetail
    func releaseDetail(id: String) async throws -> MusicBrainzReleaseDetail
}

nonisolated struct MusicBrainzClient: MusicBrainzBrowserClient, Sendable {
    private static let baseURL = URL(string: "https://\(NetworkServiceDisclosure.MusicBrainz.host)/ws/2")!
    private static let multiFileFallbackQueryLimit = 3
    private static let maximumReleaseDetailCandidates = 3

    private let session: URLSession
    private let decoder: JSONDecoder
    private let rateLimiter: MusicBrainzRateLimiter
    private let userAgent: String

    init(
        session: URLSession = .shared,
        rateLimiter: MusicBrainzRateLimiter = MusicBrainzRateLimiter()
    ) {
        self.session = session
        self.rateLimiter = rateLimiter

        let decoder = JSONDecoder()
        self.decoder = decoder

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.chrislloydme.AudioMator"
        let contactURL = "https://github.com/ChrisLloydME/AudioMator"
        // MusicBrainz asks clients to identify themselves clearly in the User-Agent.
        self.userAgent = "AudioMator/\(version) (\(contactURL); \(bundleIdentifier))"
    }

    func search(matching query: MusicBrainzSearchQuery, limit: Int = 25) async throws -> MusicBrainzSearchResults {
        switch query.mode {
        case .track:
            return .recordings(try await searchRecordings(matching: query, limit: limit))
        case .album:
            return .releases(try await searchReleases(matching: query, limit: limit))
        case .file:
            if query.isMultiFileSelection {
                return .releases(try await searchFileSelections(matching: query, limit: max(limit, 8)))
            }
            return .recordings(try await searchFiles(matching: query, limit: max(limit, 50)))
        case .link:
            return try await searchByLink(matching: query)
        }
    }

    func searchByLink(matching query: MusicBrainzSearchQuery) async throws -> MusicBrainzSearchResults {
        guard !query.link.isEmpty else {
            throw MusicBrainzClientError.emptyQuery
        }

        let parsedLink = try MusicBrainzLinkParser.parse(query.link)

        switch parsedLink {
        case .recording(let id):
            return .recordings([try await recordingSummary(id: id)])
        case .release(let id):
            return .releases([try await releaseSummary(id: id)])
        }
    }

    func searchRecordings(matching query: MusicBrainzSearchQuery, limit: Int = 25) async throws -> [MusicBrainzRecordingResult] {
        guard !query.isEmpty else {
            throw MusicBrainzClientError.emptyQuery
        }

        let luceneQueries = MusicBrainzLuceneQueryBuilder.recordingSearchQueries(from: query)
        let results = try await searchRecordings(luceneQueries: luceneQueries, limit: limit)
        return MusicBrainzResultRanker.rerankRecordings(results, query: query)
    }

    func searchReleases(matching query: MusicBrainzSearchQuery, limit: Int = 25) async throws -> [MusicBrainzReleaseSearchResult] {
        guard !query.isEmpty else {
            throw MusicBrainzClientError.emptyQuery
        }

        let luceneQueries = MusicBrainzLuceneQueryBuilder.releaseSearchQueries(from: query)
        let releases = try await searchReleases(luceneQueries: luceneQueries, limit: limit)
        return MusicBrainzResultRanker.rerankReleases(releases, query: query)
    }

    func searchFileSelections(
        matching query: MusicBrainzSearchQuery,
        limit: Int = 8
    ) async throws -> [MusicBrainzReleaseSearchResult] {
        guard let selectionSummary = query.fileSelectionSummary, selectionSummary.isMultiFile else {
            throw MusicBrainzClientError.emptyQuery
        }

        var candidates: [MusicBrainzReleaseSearchResult] = []
        var filenameEvidenceByReleaseID: [String: Double] = [:]
        let selectionQuery = query.selectionReleaseQuery

        if let releaseID = selectionSummary.musicBrainzAlbumIDCandidate.validMBID {
            let release = try await releaseSummary(id: releaseID)
            if query.releaseFilters.isEmpty || query.releaseFilters.matches(
                date: release.date,
                country: release.country,
                status: release.status,
                candidateMediaFormats: release.mediaFormats
            ) {
                candidates.append(release)
            }
            filenameEvidenceByReleaseID[releaseID, default: 0] += 1.0
        }

        let strongQueries = MusicBrainzLuceneQueryBuilder.fileClusterStrongReleaseSearchQueries(from: query)
        if let strongQuery = MusicBrainzLuceneQueryBuilder.combinedSearchQuery(
            from: strongQueries,
            maximumClauseCount: Self.multiFileFallbackQueryLimit
        ) {
            candidates.append(contentsOf: try await searchReleases(
                luceneQueries: [strongQuery],
                limit: 12
            ))
        }

        if candidates.isEmpty {
            let broadQueries = MusicBrainzLuceneQueryBuilder.fileClusterBroadReleaseSearchQueries(from: query)
            if let broadQuery = MusicBrainzLuceneQueryBuilder.combinedSearchQuery(
                from: broadQueries,
                maximumClauseCount: Self.multiFileFallbackQueryLimit
            ) {
                candidates.append(contentsOf: try await searchReleases(
                    luceneQueries: [broadQuery],
                    limit: 20
                ))
            }
        }

        if candidates.isEmpty {
            for candidate in try await releaseCandidatesFromRepresentativeFiles(
                selectionSummary,
                filters: query.releaseFilters
            ) {
                candidates.append(candidate.release)
                filenameEvidenceByReleaseID[candidate.release.id, default: 0] += candidate.evidence
            }
        }

        let deduplicatedCandidates = Self.deduplicatedReleases(candidates)
        let rerankedCandidates = MusicBrainzResultRanker.rerankReleases(
            deduplicatedCandidates,
            query: selectionQuery
        )
        let rerankedPositions = Dictionary(
            uniqueKeysWithValues: rerankedCandidates.enumerated().map { ($1.id, $0) }
        )
        let orderedCandidates = deduplicatedCandidates.sorted { lhs, rhs in
            let lhsEvidence = filenameEvidenceByReleaseID[lhs.id] ?? 0
            let rhsEvidence = filenameEvidenceByReleaseID[rhs.id] ?? 0

            if lhsEvidence != rhsEvidence {
                return lhsEvidence > rhsEvidence
            }

            let lhsPosition = rerankedPositions[lhs.id] ?? Int.max
            let rhsPosition = rerankedPositions[rhs.id] ?? Int.max
            if lhsPosition != rhsPosition {
                return lhsPosition < rhsPosition
            }

            return lhs.score > rhs.score
        }

        var matchedResults: [MusicBrainzReleaseSearchResult] = []
        for (candidateIndex, candidate) in orderedCandidates
            .prefix(Self.maximumReleaseDetailCandidates)
            .enumerated() {
            try Task.checkCancellation()
            do {
                let detail = try await releaseDetail(id: candidate.id)
                let preview = MusicBrainzFileSelectionMatcher.match(
                    selection: selectionSummary,
                    release: detail
                )
                matchedResults.append(
                    candidate.withSelectionMatchPreview(
                        preview,
                        selectionMatchScore: preview.overallScore
                    )
                )
                let nextCandidate = orderedCandidates.dropFirst(candidateIndex + 1).first
                if Self.shouldStopReleaseDetailVerification(
                    candidate: candidate,
                    nextCandidate: nextCandidate,
                    preview: preview,
                    evidence: filenameEvidenceByReleaseID[candidate.id] ?? 0
                ) {
                    break
                }
            } catch {
                try Task.checkCancellation()
                matchedResults.append(candidate)
            }
        }

        return matchedResults
            .sorted { lhs, rhs in
                let lhsScore = lhs.selectionMatchScore ?? Double(lhs.score)
                let rhsScore = rhs.selectionMatchScore ?? Double(rhs.score)

                if lhsScore == rhsScore {
                    let lhsEvidence = filenameEvidenceByReleaseID[lhs.id] ?? 0
                    let rhsEvidence = filenameEvidenceByReleaseID[rhs.id] ?? 0

                    if lhsEvidence == rhsEvidence {
                        return lhs.score > rhs.score
                    }

                    return lhsEvidence > rhsEvidence
                }

                return lhsScore > rhsScore
            }
            .prefix(limit)
            .map { $0 }
    }

    private func releaseCandidatesFromRepresentativeFiles(
        _ summary: MusicBrainzFileSelectionSummary,
        filters: MusicBrainzReleaseFilters
    ) async throws -> [(release: MusicBrainzReleaseSearchResult, evidence: Double)] {
        let representativeFiles = Self.representativeFilesForReleaseLookup(from: summary.files)
        guard !representativeFiles.isEmpty else { return [] }

        var evidenceByReleaseID: [String: Double] = [:]

        // One representative recording is enough to discover release IDs. The
        // full selection is compared against release details later in the flow.
        for (fileIndex, file) in representativeFiles.prefix(1).enumerated() {
            try Task.checkCancellation()
            let title = file.title.isEmpty ? file.preferredDisplayTitle : file.title
            guard !title.isEmpty else { continue }

            let query = MusicBrainzSearchQuery(
                mode: .file,
                title: title,
                artist: file.artist,
                albumArtist: file.albumArtist,
                album: file.album,
                trackNumber: file.trackNumber,
                trackTotal: file.trackTotal,
                durationMilliseconds: file.durationMilliseconds,
                releaseDate: file.releaseDate,
                isrc: file.isrc,
                barcode: file.barcode,
                musicBrainzAlbumID: file.musicBrainzAlbumID,
                musicBrainzTrackID: file.musicBrainzTrackID,
                fileInputs: [file],
                link: "",
                releaseFilters: filters
            )

            let recordings = try await searchFiles(
                matching: query,
                limit: 6,
                fallbackQueryLimit: Self.multiFileFallbackQueryLimit
            )
            let fileWeight = max(0.45, 1.0 - (Double(fileIndex) * 0.2))

            for (recordingIndex, recording) in recordings.prefix(4).enumerated() {
                let recordingWeight = fileWeight * max(0.25, Double(recording.score) / 100.0) * max(0.4, 1.0 - (Double(recordingIndex) * 0.18))

                for release in recording.releases.prefix(3) {
                    evidenceByReleaseID[release.id, default: 0] += recordingWeight
                }
            }
        }

        guard !evidenceByReleaseID.isEmpty else { return [] }

        var candidates: [(release: MusicBrainzReleaseSearchResult, evidence: Double)] = []
        for releaseID in evidenceByReleaseID.keys
            .sorted(by: { (evidenceByReleaseID[$0] ?? 0) > (evidenceByReleaseID[$1] ?? 0) })
            .prefix(6) {
            try Task.checkCancellation()
            let release = try await releaseSummary(id: releaseID)
            guard filters.isEmpty || filters.matches(
                date: release.date,
                country: release.country,
                status: release.status,
                candidateMediaFormats: release.mediaFormats
            ) else {
                continue
            }

            candidates.append(
                (
                    release: release,
                    evidence: evidenceByReleaseID[releaseID] ?? 0
                )
            )
        }

        return candidates
    }

    func searchFiles(
        matching query: MusicBrainzSearchQuery,
        limit: Int = 50,
        fallbackQueryLimit: Int? = nil
    ) async throws -> [MusicBrainzRecordingResult] {
        guard !query.isEmpty else {
            throw MusicBrainzClientError.emptyQuery
        }

        var candidates: [MusicBrainzRecordingResult] = []
        var preferredRecordingIDs: Set<String> = []

        let strongQueries = Self.limitedQueries(
            MusicBrainzLuceneQueryBuilder.fileStrongSearchQueries(from: query),
            maximumCount: fallbackQueryLimit
        )
        let preparedStrongQueries = Self.preparedFallbackQueries(
            strongQueries,
            maximumCount: fallbackQueryLimit
        )
        if !preparedStrongQueries.isEmpty {
            let exactMatches = try await searchRecordings(luceneQueries: preparedStrongQueries, limit: 15)
            candidates.append(contentsOf: exactMatches)
            preferredRecordingIDs.formUnion(exactMatches.map(\.id))
        }

        let broadQueries = Self.limitedQueries(
            MusicBrainzLuceneQueryBuilder.fileSearchQueries(from: query),
            maximumCount: fallbackQueryLimit
        )
        let preparedBroadQueries = Self.preparedFallbackQueries(
            broadQueries,
            maximumCount: fallbackQueryLimit
        )
        if !preparedBroadQueries.isEmpty {
            candidates.append(contentsOf: try await searchRecordings(luceneQueries: preparedBroadQueries, limit: limit))
        }

        let deduplicatedCandidates = Self.deduplicatedRecordings(candidates)
        return MusicBrainzResultRanker.rerankRecordings(
            deduplicatedCandidates,
            query: query,
            preferredRecordingIDs: preferredRecordingIDs
        )
    }

    func recordingDetail(
        id: String,
        fallbackReleases: [MusicBrainzRecordingResult.Release] = []
    ) async throws -> MusicBrainzRecordingDetail {
        let data = try await performRequest(
            resource: "recording",
            id: id,
            queryItems: [
                URLQueryItem(name: "fmt", value: "json"),
                URLQueryItem(
                    name: "inc",
                    value: "artist-credits+isrcs+genres+tags+ratings+annotation+releases+artist-rels+label-rels+place-rels+recording-rels+release-rels+release-group-rels+series-rels+url-rels+work-rels+work-level-rels"
                )
            ]
        )

        let payload: MusicBrainzRecordingLookupDTO
        do {
            payload = try decoder.decode(MusicBrainzRecordingLookupDTO.self, from: data)
        } catch let error as DecodingError {
            throw MusicBrainzClientError.decodingFailed(Self.describeDecodingError(error))
        }

        return MusicBrainzRecordingDetail(dto: payload, releases: fallbackReleases)
    }

    func releaseDetail(id: String) async throws -> MusicBrainzReleaseDetail {
        let data = try await performRequest(
            resource: "release",
            id: id,
            queryItems: [
                URLQueryItem(name: "fmt", value: "json"),
                URLQueryItem(name: "inc", value: "artist-credits+genres+tags+annotation+labels+recordings+release-groups+media+discids+isrcs")
            ]
        )

        let payload: MusicBrainzReleaseLookupDTO
        do {
            payload = try decoder.decode(MusicBrainzReleaseLookupDTO.self, from: data)
        } catch let error as DecodingError {
            throw MusicBrainzClientError.decodingFailed(Self.describeDecodingError(error))
        }

        return MusicBrainzReleaseDetail(dto: payload)
    }

    private func recordingSummary(id: String) async throws -> MusicBrainzRecordingResult {
        let detail = try await recordingDetail(id: id, fallbackReleases: [])
        return MusicBrainzRecordingResult(
            id: detail.id,
            title: detail.title,
            artistCredit: detail.artistCredit,
            score: 100,
            disambiguation: detail.disambiguation,
            firstReleaseDate: detail.firstReleaseDate,
            durationMilliseconds: detail.durationMilliseconds,
            releases: detail.releases
        )
    }

    private func releaseSummary(id: String) async throws -> MusicBrainzReleaseSearchResult {
        let detail = try await releaseDetail(id: id)
        let mediaFormats = Array(NSOrderedSet(array: detail.media.map(\.format).filter { !$0.isEmpty })) as? [String] ?? []

        let releaseGroup: MusicBrainzReleaseSearchResult.ReleaseGroup?
        if !detail.releaseGroupID.isEmpty {
            releaseGroup = .init(
                id: detail.releaseGroupID,
                primaryType: detail.releaseGroupPrimaryType,
                secondaryTypes: detail.releaseGroupSecondaryTypes
            )
        } else {
            releaseGroup = nil
        }

        return MusicBrainzReleaseSearchResult(
            id: detail.id,
            title: detail.title,
            artistCredit: detail.artistCredit,
            score: 100,
            date: detail.date,
            country: detail.country,
            status: detail.status,
            mediaFormats: mediaFormats,
            releaseGroup: releaseGroup,
            selectionMatchPreview: nil,
            selectionMatchScore: nil
        )
    }

    private func searchRecordings(luceneQuery: String, limit: Int) async throws -> [MusicBrainzRecordingResult] {
        guard !luceneQuery.isEmpty else {
            return []
        }

        let data = try await performRequest(
            resource: "recording",
            queryItems: [
                URLQueryItem(name: "query", value: luceneQuery),
                URLQueryItem(name: "fmt", value: "json"),
                URLQueryItem(name: "limit", value: String(max(1, min(limit, 100))))
            ]
        )

        let payload: MusicBrainzRecordingSearchResponse
        do {
            payload = try decoder.decode(MusicBrainzRecordingSearchResponse.self, from: data)
        } catch let error as DecodingError {
            throw MusicBrainzClientError.decodingFailed(Self.describeDecodingError(error))
        }

        return payload.recordings.map(MusicBrainzRecordingResult.init)
    }

    private func searchRecordings(luceneQueries: [String], limit: Int) async throws -> [MusicBrainzRecordingResult] {
        let normalizedQueries = luceneQueries.filter { !$0.isEmpty }
        guard !normalizedQueries.isEmpty else { return [] }

        var mergedResults: [MusicBrainzRecordingResult] = []
        var seenIDs: Set<String> = []
        var lastRecoverableError: MusicBrainzClientError?

        for luceneQuery in normalizedQueries {
            try Task.checkCancellation()
            do {
                let results = try await searchRecordings(
                    luceneQuery: luceneQuery,
                    limit: max(8, min(limit, 25))
                )

                for result in results where seenIDs.insert(result.id).inserted {
                    mergedResults.append(result)
                }

                if mergedResults.count >= limit {
                    break
                }
            } catch let error as MusicBrainzClientError {
                if error.isRecoverableServerFailure {
                    lastRecoverableError = error
                    continue
                }
                throw error
            }
        }

        if !mergedResults.isEmpty {
            return Array(mergedResults.prefix(limit))
        }

        if let lastRecoverableError {
            throw lastRecoverableError
        }

        return []
    }

    private func searchReleases(luceneQuery: String, limit: Int) async throws -> [MusicBrainzReleaseSearchResult] {
        guard !luceneQuery.isEmpty else {
            return []
        }

        let data = try await performRequest(
            resource: "release",
            queryItems: [
                URLQueryItem(name: "query", value: luceneQuery),
                URLQueryItem(name: "fmt", value: "json"),
                URLQueryItem(name: "limit", value: String(max(1, min(limit, 100))))
            ]
        )

        let payload: MusicBrainzReleaseSearchResponse
        do {
            payload = try decoder.decode(MusicBrainzReleaseSearchResponse.self, from: data)
        } catch let error as DecodingError {
            throw MusicBrainzClientError.decodingFailed(Self.describeDecodingError(error))
        }

        return payload.releases.map(MusicBrainzReleaseSearchResult.init)
    }

    private func searchReleases(luceneQueries: [String], limit: Int) async throws -> [MusicBrainzReleaseSearchResult] {
        let normalizedQueries = luceneQueries.filter { !$0.isEmpty }
        guard !normalizedQueries.isEmpty else { return [] }

        var mergedResults: [MusicBrainzReleaseSearchResult] = []
        var seenIDs: Set<String> = []
        var lastRecoverableError: MusicBrainzClientError?

        for luceneQuery in normalizedQueries {
            try Task.checkCancellation()
            do {
                let results = try await searchReleases(
                    luceneQuery: luceneQuery,
                    limit: max(8, min(limit, 25))
                )

                for result in results where seenIDs.insert(result.id).inserted {
                    mergedResults.append(result)
                }

                if mergedResults.count >= limit {
                    break
                }
            } catch let error as MusicBrainzClientError {
                if error.isRecoverableServerFailure {
                    lastRecoverableError = error
                    continue
                }
                throw error
            }
        }

        if !mergedResults.isEmpty {
            return Array(mergedResults.prefix(limit))
        }

        if let lastRecoverableError {
            throw lastRecoverableError
        }

        return []
    }

    private static func deduplicatedRecordings(_ recordings: [MusicBrainzRecordingResult]) -> [MusicBrainzRecordingResult] {
        var seenIDs: Set<String> = []
        var orderedResults: [MusicBrainzRecordingResult] = []

        for recording in recordings where seenIDs.insert(recording.id).inserted {
            orderedResults.append(recording)
        }

        return orderedResults
    }

    private static func limitedQueries(_ queries: [String], maximumCount: Int?) -> [String] {
        guard let maximumCount else { return queries }
        return Array(queries.prefix(max(0, maximumCount)))
    }

    private static func preparedFallbackQueries(
        _ queries: [String],
        maximumCount: Int?
    ) -> [String] {
        guard let maximumCount else { return queries }
        guard let combinedQuery = MusicBrainzLuceneQueryBuilder.combinedSearchQuery(
            from: queries,
            maximumClauseCount: maximumCount
        ) else {
            return []
        }
        return [combinedQuery]
    }

    private static func deduplicatedReleases(_ releases: [MusicBrainzReleaseSearchResult]) -> [MusicBrainzReleaseSearchResult] {
        var seenIDs: Set<String> = []
        var orderedResults: [MusicBrainzReleaseSearchResult] = []

        for release in releases where seenIDs.insert(release.id).inserted {
            orderedResults.append(release)
        }

        return orderedResults
    }

    static func representativeFilesForReleaseLookup(
        from files: [MusicBrainzFileSearchInput]
    ) -> [MusicBrainzFileSearchInput] {
        files
            .filter { !$0.preferredDisplayTitle.isEmpty }
            .sorted {
                let lhsScore = representativeInformationScore($0)
                let rhsScore = representativeInformationScore($1)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return ($0.normalizedDiscNumber ?? 0, $0.normalizedTrackNumber ?? 0, $0.preferredDisplayTitle)
                    < ($1.normalizedDiscNumber ?? 0, $1.normalizedTrackNumber ?? 0, $1.preferredDisplayTitle)
            }
    }

    static func shouldStopReleaseDetailVerification(
        candidate: MusicBrainzReleaseSearchResult,
        nextCandidate: MusicBrainzReleaseSearchResult?,
        preview: MusicBrainzReleaseMatchPreview,
        evidence: Double
    ) -> Bool {
        guard !preview.selectionLooksMixed else { return false }
        guard preview.totalSelectedFiles > 0 else { return false }
        let coverage = Double(preview.matchedFileCount) / Double(preview.totalSelectedFiles)
        guard coverage >= 0.9 else { return false }
        guard preview.averageTrackScore >= 0.88 else { return false }
        guard preview.unmatchedFiles.isEmpty else { return false }

        if evidence >= 1 {
            return true
        }

        guard candidate.score >= 90 else { return false }
        guard let nextCandidate else { return true }
        return candidate.score - nextCandidate.score >= 8
    }

    private static func representativeInformationScore(
        _ file: MusicBrainzFileSearchInput
    ) -> Int {
        var score = 0
        if file.musicBrainzTrackID.validMBID != nil { score += 100 }
        if !file.isrc.isEmpty { score += 80 }
        if !file.title.isEmpty { score += 24 }
        if !file.artist.isEmpty { score += 18 }
        if !file.albumArtist.isEmpty { score += 12 }
        if !file.album.isEmpty { score += 12 }
        if file.normalizedTrackNumber != nil { score += 8 }
        if file.durationMilliseconds != nil { score += 8 }
        if !file.normalizedReleaseYear.isEmpty { score += 4 }
        return score
    }

    private func performRequest(
        resource: String,
        id: String? = nil,
        queryItems: [URLQueryItem]
    ) async throws -> Data {
        let baseURL: URL
        if let id {
            baseURL = Self.baseURL
                .appending(path: resource)
                .appending(path: id)
        } else {
            baseURL = Self.baseURL.appending(path: resource)
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw MusicBrainzClientError.invalidRequest
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        try await rateLimiter.waitIfNeeded()
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MusicBrainzClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MusicBrainzClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return data
    }

    private static func describeDecodingError(_ error: DecodingError) -> String {
        func codingPathDescription(_ path: [CodingKey]) -> String {
            let parts = path.map(\.stringValue).filter { !$0.isEmpty }
            return parts.isEmpty ? "(root)" : parts.joined(separator: ".")
        }

        switch error {
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(codingPathDescription(context.codingPath))."
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(codingPathDescription(context.codingPath))."
        case .valueNotFound(let type, let context):
            return "Missing value for \(type) at \(codingPathDescription(context.codingPath))."
        case .dataCorrupted(let context):
            return "Corrupted data at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error."
        }
    }
}

extension String {
    nonisolated var validMBID: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else { return nil }
        return trimmed
    }
}

private nonisolated struct MusicBrainzRecordingSearchResponse: Decodable {
    let recordings: [MusicBrainzRecordingDTO]
}

private nonisolated struct MusicBrainzReleaseSearchResponse: Decodable {
    let releases: [MusicBrainzReleaseSearchDTO]
}

private nonisolated struct MusicBrainzRecordingDTO: Decodable {
    let id: String
    let title: String
    let score: Int
    let disambiguation: String
    let firstReleaseDate: String
    let length: Int?
    let artistCredit: [MusicBrainzArtistCreditDTO]
    let releases: [MusicBrainzReleaseDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case score
        case disambiguation
        case length
        case releases
        case firstReleaseDate = "first-release-date"
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
        firstReleaseDate = try container.decodeIfPresent(String.self, forKey: .firstReleaseDate) ?? ""
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
        releases = try container.decodeIfPresent([MusicBrainzReleaseDTO].self, forKey: .releases) ?? []

        if let score = try container.decodeIfPresent(Int.self, forKey: .score) {
            self.score = score
        } else if
            let scoreString = try container.decodeIfPresent(String.self, forKey: .score),
            let score = Int(scoreString)
        {
            self.score = score
        } else {
            self.score = 0
        }
    }
}

private nonisolated struct MusicBrainzArtistCreditDTO: Decodable {
    let name: String?
    let joinPhrase: String
    let artist: MusicBrainzArtistDTO?

    enum CodingKeys: String, CodingKey {
        case name
        case artist
        case joinPhrase = "joinphrase"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        joinPhrase = try container.decodeIfPresent(String.self, forKey: .joinPhrase) ?? ""
        artist = try container.decodeIfPresent(MusicBrainzArtistDTO.self, forKey: .artist)
    }
}

private nonisolated struct MusicBrainzArtistDTO: Decodable {
    let id: String
    let name: String?
    let disambiguation: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case disambiguation
    }
}

private nonisolated struct MusicBrainzReleaseDTO: Decodable {
    let id: String
    let title: String
    let date: String
    let country: String
    let status: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case country
        case status
    }
}

private nonisolated struct MusicBrainzReleaseSearchDTO: Decodable {
    let id: String
    let title: String
    let score: Int
    let date: String
    let country: String
    let status: String
    let media: [MusicBrainzMediumDTO]
    let artistCredit: [MusicBrainzArtistCreditDTO]
    let releaseGroup: MusicBrainzReleaseGroupDTO?

    enum CodingKeys: String, CodingKey {
        case id, title, score, date, country, status
        case media
        case artistCredit = "artist-credit"
        case releaseGroup = "release-group"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        media = try container.decodeIfPresent([MusicBrainzMediumDTO].self, forKey: .media) ?? []
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
        releaseGroup = try container.decodeIfPresent(MusicBrainzReleaseGroupDTO.self, forKey: .releaseGroup)

        if let score = try container.decodeIfPresent(Int.self, forKey: .score) {
            self.score = score
        } else if
            let scoreString = try container.decodeIfPresent(String.self, forKey: .score),
            let score = Int(scoreString)
        {
            self.score = score
        } else {
            self.score = 0
        }
    }
}

private nonisolated struct MusicBrainzReleaseGroupDTO: Decodable {
    let id: String
    let primaryType: String
    let secondaryTypes: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case primaryType = "primary-type"
        case secondaryTypes = "secondary-types"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        primaryType = try container.decodeIfPresent(String.self, forKey: .primaryType) ?? ""
        secondaryTypes = try container.decodeIfPresent([String].self, forKey: .secondaryTypes) ?? []
    }
}

private nonisolated struct MusicBrainzTermDTO: Decodable {
    let name: String
    let count: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            name = value
            count = nil
            return
        }

        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        name = try keyed.decodeIfPresent(String.self, forKey: .name) ?? ""
        if let count = try keyed.decodeIfPresent(Int.self, forKey: .count) {
            self.count = count
        } else if
            let countString = try keyed.decodeIfPresent(String.self, forKey: .count),
            let count = Int(countString)
        {
            self.count = count
        } else {
            self.count = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case count
    }
}

private nonisolated struct MusicBrainzRatingDTO: Decodable {
    let value: Double?
    let voteCount: Int

    enum CodingKeys: String, CodingKey {
        case value
        case voteCount = "votes-count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let value = try container.decodeIfPresent(Double.self, forKey: .value) {
            self.value = value
        } else if
            let valueString = try container.decodeIfPresent(String.self, forKey: .value),
            let value = Double(valueString)
        {
            self.value = value
        } else {
            self.value = nil
        }

        if let voteCount = try container.decodeIfPresent(Int.self, forKey: .voteCount) {
            self.voteCount = voteCount
        } else if
            let voteCountString = try container.decodeIfPresent(String.self, forKey: .voteCount),
            let voteCount = Int(voteCountString)
        {
            self.voteCount = voteCount
        } else {
            self.voteCount = 0
        }
    }
}

private nonisolated struct MusicBrainzTextRepresentationDTO: Decodable {
    let language: String
    let script: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        script = try container.decodeIfPresent(String.self, forKey: .script) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case language
        case script
    }
}

private nonisolated struct MusicBrainzRecordingLookupDTO: Decodable {
    let id: String
    let title: String
    let disambiguation: String
    let firstReleaseDate: String
    let length: Int?
    let annotation: String
    let artistCredit: [MusicBrainzArtistCreditDTO]
    let isrcs: [String]
    let genres: [MusicBrainzTermDTO]
    let tags: [MusicBrainzTermDTO]
    let rating: MusicBrainzRatingDTO?
    let releases: [MusicBrainzReleaseDTO]
    let relations: [MusicBrainzRelationDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case disambiguation
        case length
        case annotation
        case isrcs
        case genres
        case tags
        case rating
        case releases
        case relations
        case firstReleaseDate = "first-release-date"
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
        firstReleaseDate = try container.decodeIfPresent(String.self, forKey: .firstReleaseDate) ?? ""
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        annotation = try container.decodeIfPresent(String.self, forKey: .annotation) ?? ""
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
        isrcs = try container.decodeIfPresent([String].self, forKey: .isrcs) ?? []
        genres = try container.decodeIfPresent([MusicBrainzTermDTO].self, forKey: .genres) ?? []
        tags = try container.decodeIfPresent([MusicBrainzTermDTO].self, forKey: .tags) ?? []
        rating = try container.decodeIfPresent(MusicBrainzRatingDTO.self, forKey: .rating)
        releases = try container.decodeIfPresent([MusicBrainzReleaseDTO].self, forKey: .releases) ?? []
        relations = try container.decodeIfPresent([MusicBrainzRelationDTO].self, forKey: .relations) ?? []
    }
}

private nonisolated struct MusicBrainzReleaseLookupDTO: Decodable {
    let id: String
    let title: String
    let date: String
    let country: String
    let status: String
    let barcode: String
    let packaging: String
    let asin: String
    let quality: String
    let annotation: String
    let artistCredit: [MusicBrainzArtistCreditDTO]
    let genres: [MusicBrainzTermDTO]
    let tags: [MusicBrainzTermDTO]
    let textRepresentation: MusicBrainzTextRepresentationDTO?
    let releaseGroup: MusicBrainzReleaseGroupLookupDTO?
    let labelInfo: [MusicBrainzLabelInfoDTO]
    let media: [MusicBrainzMediumDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case country
        case status
        case barcode
        case packaging
        case asin
        case quality
        case annotation
        case genres
        case tags
        case media
        case textRepresentation = "text-representation"
        case artistCredit = "artist-credit"
        case releaseGroup = "release-group"
        case labelInfo = "label-info"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        barcode = try container.decodeIfPresent(String.self, forKey: .barcode) ?? ""
        packaging = try container.decodeIfPresent(String.self, forKey: .packaging) ?? ""
        asin = try container.decodeIfPresent(String.self, forKey: .asin) ?? ""
        quality = try container.decodeIfPresent(String.self, forKey: .quality) ?? ""
        annotation = try container.decodeIfPresent(String.self, forKey: .annotation) ?? ""
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
        genres = try container.decodeIfPresent([MusicBrainzTermDTO].self, forKey: .genres) ?? []
        tags = try container.decodeIfPresent([MusicBrainzTermDTO].self, forKey: .tags) ?? []
        textRepresentation = try container.decodeIfPresent(MusicBrainzTextRepresentationDTO.self, forKey: .textRepresentation)
        releaseGroup = try container.decodeIfPresent(MusicBrainzReleaseGroupLookupDTO.self, forKey: .releaseGroup)
        labelInfo = try container.decodeIfPresent([MusicBrainzLabelInfoDTO].self, forKey: .labelInfo) ?? []
        media = try container.decodeIfPresent([MusicBrainzMediumDTO].self, forKey: .media) ?? []
    }
}

private nonisolated struct MusicBrainzReleaseGroupLookupDTO: Decodable {
    let id: String
    let title: String
    let primaryType: String
    let secondaryTypes: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case primaryType = "primary-type"
        case secondaryTypes = "secondary-types"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        primaryType = try container.decodeIfPresent(String.self, forKey: .primaryType) ?? ""
        secondaryTypes = try container.decodeIfPresent([String].self, forKey: .secondaryTypes) ?? []
    }
}

private nonisolated struct MusicBrainzLabelInfoDTO: Decodable {
    let catalogNumber: String
    let label: MusicBrainzLabelDTO?

    enum CodingKeys: String, CodingKey {
        case catalogNumber = "catalog-number"
        case label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        catalogNumber = try container.decodeIfPresent(String.self, forKey: .catalogNumber) ?? ""
        label = try container.decodeIfPresent(MusicBrainzLabelDTO.self, forKey: .label)
    }
}

private nonisolated struct MusicBrainzLabelDTO: Decodable {
    let id: String
    let name: String
    let disambiguation: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case disambiguation
    }
}

private nonisolated struct MusicBrainzPlaceDTO: Decodable {
    let id: String
    let name: String
    let disambiguation: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case disambiguation
    }
}

private nonisolated struct MusicBrainzSeriesDTO: Decodable {
    let id: String
    let name: String
    let disambiguation: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case disambiguation
    }
}

private nonisolated struct MusicBrainzURLDTO: Decodable {
    let id: String
    let resource: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        resource = try container.decodeIfPresent(String.self, forKey: .resource) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case resource
    }
}

private nonisolated struct MusicBrainzRelatedRecordingDTO: Decodable {
    let id: String
    let title: String
    let disambiguation: String
    let artistCredit: [MusicBrainzArtistCreditDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case disambiguation
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
    }
}

private nonisolated struct MusicBrainzWorkDTO: Decodable {
    let id: String
    let title: String
    let disambiguation: String
    let relations: [MusicBrainzNestedRelationDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
        relations = try container.decodeIfPresent([MusicBrainzNestedRelationDTO].self, forKey: .relations) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case disambiguation
        case relations
    }
}

private nonisolated struct MusicBrainzRelationDTO: Decodable {
    let type: String
    let direction: String
    let targetType: String
    let begin: String
    let end: String
    let ended: Bool
    let attributes: [String]
    let attributeValues: [String: String]
    let artist: MusicBrainzArtistDTO?
    let label: MusicBrainzLabelDTO?
    let place: MusicBrainzPlaceDTO?
    let recording: MusicBrainzRelatedRecordingDTO?
    let release: MusicBrainzReleaseDTO?
    let releaseGroup: MusicBrainzReleaseGroupLookupDTO?
    let series: MusicBrainzSeriesDTO?
    let work: MusicBrainzWorkDTO?
    let url: MusicBrainzURLDTO?
    let targetCredit: String
    let sourceCredit: String

    enum CodingKeys: String, CodingKey {
        case type
        case direction
        case targetType = "target-type"
        case begin
        case end
        case ended
        case attributes
        case attributeValues = "attribute-values"
        case artist
        case label
        case place
        case recording
        case release
        case releaseGroup = "release-group"
        case series
        case work
        case url
        case targetCredit = "target-credit"
        case sourceCredit = "source-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        direction = try container.decodeIfPresent(String.self, forKey: .direction) ?? ""
        targetType = try container.decodeIfPresent(String.self, forKey: .targetType) ?? ""
        begin = try container.decodeIfPresent(String.self, forKey: .begin) ?? ""
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        ended = try container.decodeIfPresent(Bool.self, forKey: .ended) ?? false
        attributes = try container.decodeIfPresent([String].self, forKey: .attributes) ?? []
        attributeValues = try container.decodeIfPresent([String: String].self, forKey: .attributeValues) ?? [:]
        artist = try container.decodeIfPresent(MusicBrainzArtistDTO.self, forKey: .artist)
        label = try container.decodeIfPresent(MusicBrainzLabelDTO.self, forKey: .label)
        place = try container.decodeIfPresent(MusicBrainzPlaceDTO.self, forKey: .place)
        recording = try container.decodeIfPresent(MusicBrainzRelatedRecordingDTO.self, forKey: .recording)
        release = try container.decodeIfPresent(MusicBrainzReleaseDTO.self, forKey: .release)
        releaseGroup = try container.decodeIfPresent(MusicBrainzReleaseGroupLookupDTO.self, forKey: .releaseGroup)
        series = try container.decodeIfPresent(MusicBrainzSeriesDTO.self, forKey: .series)
        work = try container.decodeIfPresent(MusicBrainzWorkDTO.self, forKey: .work)
        url = try container.decodeIfPresent(MusicBrainzURLDTO.self, forKey: .url)
        targetCredit = try container.decodeIfPresent(String.self, forKey: .targetCredit) ?? ""
        sourceCredit = try container.decodeIfPresent(String.self, forKey: .sourceCredit) ?? ""
    }
}

private nonisolated struct MusicBrainzNestedRelationDTO: Decodable {
    let type: String
    let direction: String
    let targetType: String
    let begin: String
    let end: String
    let ended: Bool
    let attributes: [String]
    let attributeValues: [String: String]
    let artist: MusicBrainzArtistDTO?
    let label: MusicBrainzLabelDTO?
    let place: MusicBrainzPlaceDTO?
    let recording: MusicBrainzRelatedRecordingDTO?
    let release: MusicBrainzReleaseDTO?
    let releaseGroup: MusicBrainzReleaseGroupLookupDTO?
    let series: MusicBrainzSeriesDTO?
    let url: MusicBrainzURLDTO?
    let targetCredit: String
    let sourceCredit: String

    enum CodingKeys: String, CodingKey {
        case type
        case direction
        case targetType = "target-type"
        case begin
        case end
        case ended
        case attributes
        case attributeValues = "attribute-values"
        case artist
        case label
        case place
        case recording
        case release
        case releaseGroup = "release-group"
        case series
        case url
        case targetCredit = "target-credit"
        case sourceCredit = "source-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        direction = try container.decodeIfPresent(String.self, forKey: .direction) ?? ""
        targetType = try container.decodeIfPresent(String.self, forKey: .targetType) ?? ""
        begin = try container.decodeIfPresent(String.self, forKey: .begin) ?? ""
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        ended = try container.decodeIfPresent(Bool.self, forKey: .ended) ?? false
        attributes = try container.decodeIfPresent([String].self, forKey: .attributes) ?? []
        attributeValues = try container.decodeIfPresent([String: String].self, forKey: .attributeValues) ?? [:]
        artist = try container.decodeIfPresent(MusicBrainzArtistDTO.self, forKey: .artist)
        label = try container.decodeIfPresent(MusicBrainzLabelDTO.self, forKey: .label)
        place = try container.decodeIfPresent(MusicBrainzPlaceDTO.self, forKey: .place)
        recording = try container.decodeIfPresent(MusicBrainzRelatedRecordingDTO.self, forKey: .recording)
        release = try container.decodeIfPresent(MusicBrainzReleaseDTO.self, forKey: .release)
        releaseGroup = try container.decodeIfPresent(MusicBrainzReleaseGroupLookupDTO.self, forKey: .releaseGroup)
        series = try container.decodeIfPresent(MusicBrainzSeriesDTO.self, forKey: .series)
        url = try container.decodeIfPresent(MusicBrainzURLDTO.self, forKey: .url)
        targetCredit = try container.decodeIfPresent(String.self, forKey: .targetCredit) ?? ""
        sourceCredit = try container.decodeIfPresent(String.self, forKey: .sourceCredit) ?? ""
    }
}

private nonisolated struct MusicBrainzMediumDTO: Decodable {
    let id: String
    let title: String
    let format: String
    let trackCount: Int
    let discs: [MusicBrainzDiscDTO]
    let tracks: [MusicBrainzTrackDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case format
        case discs
        case tracks
        case trackCount = "track-count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? ""
        trackCount = try container.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
        discs = try container.decodeIfPresent([MusicBrainzDiscDTO].self, forKey: .discs) ?? []
        tracks = try container.decodeIfPresent([MusicBrainzTrackDTO].self, forKey: .tracks) ?? []
    }
}

private nonisolated struct MusicBrainzDiscDTO: Decodable {
    let id: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
    }
}

private nonisolated struct MusicBrainzTrackDTO: Decodable {
    let id: String
    let number: String
    let title: String
    let length: Int?
    let artistCredit: [MusicBrainzArtistCreditDTO]
    let recording: MusicBrainzTrackRecordingDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case length
        case recording
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        number = try container.decodeIfPresent(String.self, forKey: .number) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
        recording = try container.decodeIfPresent(MusicBrainzTrackRecordingDTO.self, forKey: .recording)
    }
}

private nonisolated struct MusicBrainzTrackRecordingDTO: Decodable {
    let id: String
    let title: String
    let length: Int?
    let isrcs: [String]
    let artistCredit: [MusicBrainzArtistCreditDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case length
        case isrcs
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        isrcs = try container.decodeIfPresent([String].self, forKey: .isrcs) ?? []
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
    }
}

private extension MusicBrainzRecordingResult {
    nonisolated init(dto: MusicBrainzRecordingDTO) {
        id = dto.id
        title = dto.title
        score = dto.score
        disambiguation = dto.disambiguation
        firstReleaseDate = dto.firstReleaseDate
        durationMilliseconds = dto.length
        artistCredit = dto.artistCredit
            .map { credit in
                let baseName = credit.name ?? credit.artist?.name ?? ""
                return baseName + credit.joinPhrase
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        releases = dto.releases.compactMap {
            guard !$0.id.isEmpty, !$0.title.isEmpty else { return nil }
            return Release(
                id: $0.id,
                title: $0.title,
                date: $0.date,
                country: $0.country,
                status: $0.status
            )
        }
    }
}

private extension MusicBrainzReleaseSearchResult {
    nonisolated init(dto: MusicBrainzReleaseSearchDTO) {
        id = dto.id
        title = dto.title
        score = dto.score
        date = dto.date
        country = dto.country
        status = dto.status
        mediaFormats = Array(
            NSOrderedSet(
                array: dto.media
                    .map(\.format)
                    .filter { !$0.isEmpty }
            )
        ) as? [String] ?? []
        artistCredit = dto.artistCredit
            .map { credit in
                let baseName = credit.name ?? credit.artist?.name ?? ""
                return baseName + credit.joinPhrase
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let group = dto.releaseGroup, !group.id.isEmpty {
            releaseGroup = ReleaseGroup(
                id: group.id,
                primaryType: group.primaryType,
                secondaryTypes: group.secondaryTypes
            )
        } else {
            releaseGroup = nil
        }

        selectionMatchPreview = nil
        selectionMatchScore = nil
    }
}

private extension MusicBrainzRecordingDetail {
    nonisolated init(dto: MusicBrainzRecordingLookupDTO, releases: [MusicBrainzRecordingResult.Release]) {
        id = dto.id
        title = dto.title
        disambiguation = dto.disambiguation
        firstReleaseDate = dto.firstReleaseDate
        durationMilliseconds = dto.length
        annotation = dto.annotation
        isrcs = dto.isrcs.filter { !$0.isEmpty }
        genres = dto.genres.compactMap { MusicBrainzTerm($0) }
        tags = dto.tags.compactMap { MusicBrainzTerm($0) }
        rating = dto.rating.map { MusicBrainzRating(value: $0.value, voteCount: $0.voteCount) }
        relationshipGroups = MusicBrainzRelationshipBuilder.makeGroups(from: dto.relations)
        let lookupReleases = dto.releases.compactMap { dtoRelease -> MusicBrainzRecordingResult.Release? in
            guard !dtoRelease.id.isEmpty, !dtoRelease.title.isEmpty else { return nil }
            return MusicBrainzRecordingResult.Release(
                id: dtoRelease.id,
                title: dtoRelease.title,
                date: dtoRelease.date,
                country: dtoRelease.country,
                status: dtoRelease.status
            )
        }
        self.releases = lookupReleases.isEmpty ? releases : lookupReleases
        artistCredit = dto.artistCredit
            .map { credit in
                let baseName = credit.name ?? credit.artist?.name ?? ""
                return baseName + credit.joinPhrase
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension MusicBrainzReleaseDetail {
    nonisolated init(dto: MusicBrainzReleaseLookupDTO) {
        id = dto.id
        title = dto.title
        date = dto.date
        country = dto.country
        status = dto.status
        barcode = dto.barcode
        packaging = dto.packaging
        asin = dto.asin
        quality = dto.quality
        language = dto.textRepresentation?.language ?? ""
        script = dto.textRepresentation?.script ?? ""
        annotation = dto.annotation
        genres = dto.genres.compactMap { MusicBrainzTerm($0) }
        tags = dto.tags.compactMap { MusicBrainzTerm($0) }
        releaseGroupTitle = dto.releaseGroup?.title ?? ""
        releaseGroupID = dto.releaseGroup?.id ?? ""
        releaseGroupPrimaryType = dto.releaseGroup?.primaryType ?? ""
        releaseGroupSecondaryTypes = dto.releaseGroup?.secondaryTypes ?? []
        labels = dto.labelInfo.compactMap { info in
            let labelName = info.label?.name ?? ""
            guard !labelName.isEmpty || !info.catalogNumber.isEmpty else { return nil }
            let id = info.label?.id ?? "\(labelName)-\(info.catalogNumber)"
            return LabelInfo(
                id: id,
                labelName: labelName,
                catalogNumber: info.catalogNumber
            )
        }
        media = dto.media.map { medium in
            Medium(
                id: medium.id,
                title: medium.title,
                format: medium.format,
                trackCount: medium.trackCount,
                discIDs: medium.discs.map(\.id).filter { !$0.isEmpty },
                tracks: medium.tracks.map { track in
                    Medium.Track(
                        id: track.id,
                        number: track.number,
                        title: track.title.isEmpty ? (track.recording?.title ?? "") : track.title,
                        artistCredit: musicBrainzJoinedArtistCredit(
                            track.artistCredit.isEmpty ? (track.recording?.artistCredit ?? []) : track.artistCredit
                        ),
                        durationMilliseconds: track.length ?? track.recording?.length,
                        recordingID: track.recording?.id ?? "",
                        isrcs: track.recording?.isrcs.filter { !$0.isEmpty } ?? []
                    )
                }
            )
        }
        selectionMatchPreview = nil
        artistCredit = dto.artistCredit
            .map { credit in
                let baseName = credit.name ?? credit.artist?.name ?? ""
                return baseName + credit.joinPhrase
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension MusicBrainzReleaseSearchResult {
    nonisolated func withSelectionMatchPreview(
        _ preview: MusicBrainzReleaseMatchPreview,
        selectionMatchScore: Double
    ) -> MusicBrainzReleaseSearchResult {
        MusicBrainzReleaseSearchResult(
            id: id,
            title: title,
            artistCredit: artistCredit,
            score: score,
            date: date,
            country: country,
            status: status,
            mediaFormats: mediaFormats,
            releaseGroup: releaseGroup,
            selectionMatchPreview: preview,
            selectionMatchScore: selectionMatchScore
        )
    }
}

private extension MusicBrainzTerm {
    nonisolated init?(_ dto: MusicBrainzTermDTO) {
        guard !dto.name.isEmpty else { return nil }
        self.init(name: dto.name, count: dto.count)
    }
}

nonisolated private func musicBrainzJoinedArtistCredit(_ credits: [MusicBrainzArtistCreditDTO]) -> String {
    credits
        .map { credit in
            let baseName = credit.name ?? credit.artist?.name ?? ""
            return baseName + credit.joinPhrase
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private nonisolated enum MusicBrainzRelationshipBuilder {
    static func makeGroups(from relations: [MusicBrainzRelationDTO]) -> [MusicBrainzRelationshipGroup] {
        var groups: [MusicBrainzRelationshipGroup] = []

        for relation in relations {
            append(relation: relation, to: &groups)

            if let work = relation.work {
                for nestedRelation in work.relations {
                    append(nestedRelation: nestedRelation, to: &groups)
                }
            }
        }

        return groups
    }

    private static func append(relation: MusicBrainzRelationDTO, to groups: inout [MusicBrainzRelationshipGroup]) {
        let title = relationTitle(
            type: relation.type,
            attributes: relation.attributes,
            attributeValues: relation.attributeValues,
            targetType: relation.targetType
        )
        let value = relationValue(from: relation)
        appendGroup(title: title, value: value, to: &groups)
    }

    private static func append(nestedRelation: MusicBrainzNestedRelationDTO, to groups: inout [MusicBrainzRelationshipGroup]) {
        let title = relationTitle(
            type: nestedRelation.type,
            attributes: nestedRelation.attributes,
            attributeValues: nestedRelation.attributeValues,
            targetType: nestedRelation.targetType
        )
        let value = relationValue(from: nestedRelation)
        appendGroup(title: title, value: value, to: &groups)
    }

    private static func appendGroup(title: String, value: String, to groups: inout [MusicBrainzRelationshipGroup]) {
        guard !title.isEmpty, !value.isEmpty else { return }

        if let index = groups.firstIndex(where: { $0.title == title }) {
            if !groups[index].values.contains(value) {
                groups[index].values.append(value)
            }
        } else {
            groups.append(MusicBrainzRelationshipGroup(title: title, values: [value]))
        }
    }

    private static func relationTitle(
        type: String,
        attributes: [String],
        attributeValues: [String: String],
        targetType: String
    ) -> String {
        if type == "performance", targetType == "work" {
            return "recording of"
        }

        if type == "phonographic copyright" {
            return "phonographic copyright (℗) by"
        }

        let loweredType = type.lowercased()
        if loweredType == "instrument" || loweredType == "vocal" || loweredType == "performer" {
            let attributeTitle = instrumentTitle(attributes: attributes, attributeValues: attributeValues)
            return attributeTitle.isEmpty ? loweredType : attributeTitle
        }

        if !attributes.isEmpty, shouldPrefixAttributes(to: loweredType) {
            return (attributes + [loweredType]).joined(separator: " ").lowercased()
        }

        return loweredType
    }

    private static func shouldPrefixAttributes(to relationType: String) -> Bool {
        switch relationType {
        case "engineer", "mix", "producer", "miscellaneous support":
            return true
        default:
            return false
        }
    }

    private static func instrumentTitle(attributes: [String], attributeValues: [String: String]) -> String {
        guard !attributes.isEmpty else { return "" }

        var title = joinList(attributes)
        if let creditedAs = attributeValues["credited-as"], !creditedAs.isEmpty, !title.contains("[\(creditedAs)]") {
            title += " [\(creditedAs)]"
        }
        return title
    }

    private static func relationValue(from relation: MusicBrainzRelationDTO) -> String {
        relationValue(
            artist: relation.artist,
            label: relation.label,
            place: relation.place,
            recording: relation.recording,
            release: relation.release,
            releaseGroup: relation.releaseGroup,
            series: relation.series,
            work: relation.work,
            url: relation.url,
            targetCredit: relation.targetCredit,
            sourceCredit: relation.sourceCredit,
            attributeValues: relation.attributeValues,
            begin: relation.begin,
            end: relation.end
        )
    }

    private static func relationValue(from relation: MusicBrainzNestedRelationDTO) -> String {
        relationValue(
            artist: relation.artist,
            label: relation.label,
            place: relation.place,
            recording: relation.recording,
            release: relation.release,
            releaseGroup: relation.releaseGroup,
            series: relation.series,
            work: nil,
            url: relation.url,
            targetCredit: relation.targetCredit,
            sourceCredit: relation.sourceCredit,
            attributeValues: relation.attributeValues,
            begin: relation.begin,
            end: relation.end
        )
    }

    private static func relationValue(
        artist: MusicBrainzArtistDTO?,
        label: MusicBrainzLabelDTO?,
        place: MusicBrainzPlaceDTO?,
        recording: MusicBrainzRelatedRecordingDTO?,
        release: MusicBrainzReleaseDTO?,
        releaseGroup: MusicBrainzReleaseGroupLookupDTO?,
        series: MusicBrainzSeriesDTO?,
        work: MusicBrainzWorkDTO?,
        url: MusicBrainzURLDTO?,
        targetCredit: String,
        sourceCredit: String,
        attributeValues: [String: String],
        begin: String,
        end: String
    ) -> String {
        var base = ""

        if let artist {
            base = creditedName(
                credit: targetCredit.isEmpty ? sourceCredit : targetCredit,
                fallback: artist.name ?? "",
                disambiguation: artist.disambiguation
            )
        } else if let label {
            base = appendDisambiguation(to: label.name, disambiguation: label.disambiguation)
        } else if let place {
            base = appendDisambiguation(to: place.name, disambiguation: place.disambiguation)
        } else if let recording {
            var recordingTitle = recording.title
            let artistCredit = joinedArtistCredit(recording.artistCredit)
            if !artistCredit.isEmpty {
                recordingTitle += " by \(artistCredit)"
            }
            base = appendDisambiguation(to: recordingTitle, disambiguation: recording.disambiguation)
        } else if let release, !release.title.isEmpty {
            base = release.title
        } else if let releaseGroup, !releaseGroup.title.isEmpty {
            base = releaseGroup.title
        } else if let series {
            base = appendDisambiguation(to: series.name, disambiguation: series.disambiguation)
        } else if let work {
            base = appendDisambiguation(to: work.title, disambiguation: work.disambiguation)
        } else if let url, !url.resource.isEmpty {
            base = url.resource
        }

        guard !base.isEmpty else { return "" }

        var extras: [String] = []
        for key in attributeValues.keys.sorted() {
            let value = attributeValues[key] ?? ""
            guard !value.isEmpty, key != "credited-as" else { continue }
            extras.append("\(key): \(value)")
        }

        if let dateText = relationDateText(begin: begin, end: end) {
            extras.append(dateText)
        }

        if !extras.isEmpty {
            base += " (" + extras.joined(separator: "; ") + ")"
        }

        return base
    }

    private static func relationDateText(begin: String, end: String) -> String? {
        if !begin.isEmpty && begin == end {
            return "in \(begin)"
        }

        if !begin.isEmpty && end.isEmpty {
            return "from \(begin)"
        }

        if begin.isEmpty && !end.isEmpty {
            return "until \(end)"
        }

        if !begin.isEmpty && !end.isEmpty {
            return "\(begin) to \(end)"
        }

        return nil
    }

    private static func creditedName(credit: String, fallback: String, disambiguation: String) -> String {
        let name = credit.isEmpty ? fallback : credit
        return appendDisambiguation(to: name, disambiguation: disambiguation)
    }

    private static func appendDisambiguation(to value: String, disambiguation: String) -> String {
        guard !value.isEmpty else { return "" }
        guard !disambiguation.isEmpty else { return value }
        return "\(value) (\(disambiguation))"
    }

    private static func joinedArtistCredit(_ credits: [MusicBrainzArtistCreditDTO]) -> String {
        credits
            .map { credit in
                let baseName = credit.name ?? credit.artist?.name ?? ""
                return baseName + credit.joinPhrase
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func joinList(_ values: [String]) -> String {
        switch values.count {
        case 0:
            return ""
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) and \(values[1])"
        default:
            let prefix = values.dropLast().joined(separator: ", ")
            return "\(prefix) and \(values.last ?? "")"
        }
    }
}
