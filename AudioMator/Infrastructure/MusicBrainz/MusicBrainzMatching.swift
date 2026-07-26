import Foundation

nonisolated enum MusicBrainzTaggingPreviewBuilder {
    static func makePreview(
        files: [MusicBrainzFileSearchInput],
        release: MusicBrainzReleaseDetail
    ) -> MusicBrainzReleaseMatchPreview? {
        guard !files.isEmpty else { return nil }
        let selection = MusicBrainzFileSelectionSummary(files: files)
        return MusicBrainzFileSelectionMatcher.match(
            selection: selection,
            release: release
        )
    }

    static func makeSingleTrackPreview(
        file: MusicBrainzFileSearchInput,
        release: MusicBrainzReleaseDetail,
        recordingID: String
    ) -> MusicBrainzReleaseMatchPreview? {
        MusicBrainzFileSelectionMatcher.matchSingleTrack(
            file: file,
            release: release,
            recordingID: recordingID
        )
    }
}

nonisolated enum MusicBrainzFileSelectionMatcher {
    static func match(
        selection: MusicBrainzFileSelectionSummary,
        release: MusicBrainzReleaseDetail
    ) -> MusicBrainzReleaseMatchPreview {
        let releaseTracks = flattenedTracks(from: release)
        let exactCandidates = buildCandidates(
            files: selection.files,
            tracks: releaseTracks,
            releaseArtistCredit: release.artistCredit,
            exactOnly: true
        )
        let exactAssignments = greedyAssignments(from: exactCandidates)

        let assignedFileIDs = Set(exactAssignments.map(\.file.id))
        let assignedTrackIDs = Set(exactAssignments.map(\.track.id))

        let remainingFiles = selection.files.filter { !assignedFileIDs.contains($0.id) }
        let remainingTracks = releaseTracks.filter { !assignedTrackIDs.contains($0.id) }

        let similarityCandidates = buildCandidates(
            files: remainingFiles,
            tracks: remainingTracks,
            releaseArtistCredit: release.artistCredit,
            exactOnly: false
        )
        let similarityAssignments = greedyAssignments(from: similarityCandidates)

        let allAssignments = (exactAssignments + similarityAssignments)
            .sorted {
                ($0.file.normalizedDiscNumber ?? 0, $0.file.normalizedTrackNumber ?? 0, $0.file.preferredDisplayTitle)
                    < ($1.file.normalizedDiscNumber ?? 0, $1.file.normalizedTrackNumber ?? 0, $1.file.preferredDisplayTitle)
            }

        let finalAssignedFileIDs = Set(allAssignments.map(\.file.id))
        let finalAssignedTrackIDs = Set(allAssignments.map(\.track.id))
        let unmatchedFiles = selection.files.filter { !finalAssignedFileIDs.contains($0.id) }
        let unassignedTracks = releaseTracks.filter { !finalAssignedTrackIDs.contains($0.id) }

        let averageTrackScore: Double
        if allAssignments.isEmpty {
            averageTrackScore = 0
        } else {
            averageTrackScore = allAssignments.map(\.score).reduce(0, +) / Double(allAssignments.count)
        }

        let releaseMetadataScore = releaseScore(selection: selection, release: release)
        let coverage = selection.files.isEmpty ? 0 : Double(allAssignments.count) / Double(selection.files.count)
        var overallScore = releaseMetadataScore
        overallScore += coverage * 420
        overallScore += averageTrackScore * 340
        overallScore -= Double(unmatchedFiles.count) * 90
        overallScore -= Double(unassignedTracks.count) * 15

        if selection.selectionLooksMixed {
            overallScore -= 60
        }

        return MusicBrainzReleaseMatchPreview(
            totalSelectedFiles: selection.totalSelectedFiles,
            matchedAssignments: allAssignments,
            unmatchedFiles: unmatchedFiles,
            unassignedTracks: unassignedTracks,
            averageTrackScore: averageTrackScore,
            overallScore: max(0, overallScore),
            selectionLooksMixed: selection.selectionLooksMixed
        )
    }

    static func matchSingleTrack(
        file: MusicBrainzFileSearchInput,
        release: MusicBrainzReleaseDetail,
        recordingID: String
    ) -> MusicBrainzReleaseMatchPreview? {
        let normalizedRecordingID = recordingID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRecordingID.isEmpty else { return nil }

        let releaseTracks = flattenedTracks(from: release)
        guard let selectedTrack = releaseTracks.first(where: {
            $0.recordingID == normalizedRecordingID || $0.id == normalizedRecordingID
        }) else {
            return nil
        }

        let selection = MusicBrainzFileSelectionSummary(files: [file])
        let assignment = MusicBrainzReleaseMatchAssignment(
            id: "\(file.id)::\(selectedTrack.id)",
            file: file,
            track: selectedTrack,
            score: 1,
            reason: "selected MusicBrainz track"
        )

        return MusicBrainzReleaseMatchPreview(
            totalSelectedFiles: 1,
            matchedAssignments: [assignment],
            unmatchedFiles: [],
            unassignedTracks: releaseTracks.filter { $0.id != selectedTrack.id },
            averageTrackScore: 1,
            overallScore: releaseScore(selection: selection, release: release) + 760,
            selectionLooksMixed: false
        )
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
                    isrcs: track.isrcs,
                    )
            }
        }
    }

    private static func buildCandidates(
        files: [MusicBrainzFileSearchInput],
        tracks: [MusicBrainzReleaseMatchTrack],
        releaseArtistCredit: String,
        exactOnly: Bool
    ) -> [MusicBrainzReleaseMatchAssignment] {
        var candidates: [MusicBrainzReleaseMatchAssignment] = []

        for file in files {
            for track in tracks {
                let candidate = candidateAssignment(
                    file: file,
                    track: track,
                    releaseArtistCredit: releaseArtistCredit,
                    exactOnly: exactOnly
                )

                if let candidate {
                    candidates.append(candidate)
                }
            }
        }

        return candidates.sorted {
            if $0.score == $1.score {
                return $0.file.preferredDisplayTitle < $1.file.preferredDisplayTitle
            }
            return $0.score > $1.score
        }
    }

    private static func greedyAssignments(
        from candidates: [MusicBrainzReleaseMatchAssignment]
    ) -> [MusicBrainzReleaseMatchAssignment] {
        var assignedFileIDs: Set<String> = []
        var assignedTrackIDs: Set<String> = []
        var assignments: [MusicBrainzReleaseMatchAssignment] = []

        for candidate in candidates {
            guard !assignedFileIDs.contains(candidate.file.id) else { continue }
            guard !assignedTrackIDs.contains(candidate.track.id) else { continue }

            assignedFileIDs.insert(candidate.file.id)
            assignedTrackIDs.insert(candidate.track.id)
            assignments.append(candidate)
        }

        return assignments
    }

    private static func candidateAssignment(
        file: MusicBrainzFileSearchInput,
        track: MusicBrainzReleaseMatchTrack,
        releaseArtistCredit: String,
        exactOnly: Bool
    ) -> MusicBrainzReleaseMatchAssignment? {
        if let exactReason = exactMatchReason(file: file, track: track) {
            return MusicBrainzReleaseMatchAssignment(
                id: "\(file.id)::\(track.id)",
                file: file,
                track: track,
                score: exactReason.score,
                reason: exactReason.reason
            )
        }

        guard !exactOnly else { return nil }

        let titleScore = weightedSimilarity(file.title, track.title)
        let artistTargets = [track.artistCredit, releaseArtistCredit].filter { !$0.isEmpty }
        let artistScore = bestSimilarity(file.artistCandidates, candidates: artistTargets)
        let durationScore = durationSimilarity(file.durationMilliseconds, track.durationMilliseconds)
        let trackNumberScore = trackIndexSimilarity(file.normalizedTrackNumber, candidateValue: track.number)
        let discNumberScore = discIndexSimilarity(file.normalizedDiscNumber, candidateValue: track.mediumPosition)
        let albumScore = weightedSimilarity(file.album, track.mediumTitle.isEmpty ? "" : track.mediumTitle)

        let similarity =
            (titleScore * 0.42) +
            (artistScore * 0.18) +
            (durationScore * 0.16) +
            (trackNumberScore * 0.14) +
            (discNumberScore * 0.05) +
            (albumScore * 0.05)

        guard similarity >= 0.48 else { return nil }

        return MusicBrainzReleaseMatchAssignment(
            id: "\(file.id)::\(track.id)",
            file: file,
            track: track,
            score: similarity,
            reason: trackNumberScore >= 1 ? "Track number + metadata" : "Metadata similarity"
        )
    }

    private static func exactMatchReason(
        file: MusicBrainzFileSearchInput,
        track: MusicBrainzReleaseMatchTrack
    ) -> (score: Double, reason: String)? {
        if let trackID = file.musicBrainzTrackID.validMBID,
           trackID == track.id || trackID == track.recordingID {
            return (1.0, "MusicBrainz ID")
        }

        if !file.isrc.isEmpty, track.isrcs.contains(file.isrc) {
            return (0.99, "ISRC")
        }

        let sameTrackNumber = trackIndexSimilarity(file.normalizedTrackNumber, candidateValue: track.number) >= 1
        let sameDiscNumber = file.normalizedDiscNumber == nil || discIndexSimilarity(file.normalizedDiscNumber, candidateValue: track.mediumPosition) >= 1
        let titleSimilarity = weightedSimilarity(file.title, track.title)

        if sameTrackNumber, sameDiscNumber, titleSimilarity >= 0.88 {
            return (0.94, "Track number + title")
        }

        return nil
    }

    private static func releaseScore(
        selection: MusicBrainzFileSelectionSummary,
        release: MusicBrainzReleaseDetail
    ) -> Double {
        let albumScore = weightedSimilarity(selection.albumCandidate, release.title) * 260
        let artistScore = bestSimilarity(
            [selection.albumArtistCandidate, selection.primaryArtistCandidate].filter { !$0.isEmpty },
            candidates: [release.artistCredit]
        ) * 170
        let yearScore = yearSimilarity(selection.releaseYearCandidate, candidateDate: release.date) * 70
        let trackCountScore = releaseTrackCountSimilarity(
            selectedCount: selection.totalSelectedFiles,
            releaseTrackCount: totalTrackCount(in: release)
        ) * 110

        var total = albumScore + artistScore + yearScore + trackCountScore

        if !selection.barcodeCandidate.isEmpty, selection.barcodeCandidate == release.barcode {
            total += 260
        }

        if let releaseID = selection.musicBrainzAlbumIDCandidate.validMBID, releaseID == release.id {
            total += 420
        }

        return total
    }

    private static func totalTrackCount(in release: MusicBrainzReleaseDetail) -> Int {
        let summed = release.media.reduce(0) { partialResult, medium in
            AudioNumericConversion.saturatingNonnegativeSum(
                partialResult,
                max(medium.trackCount, medium.tracks.count)
            )
        }
        return max(summed, release.media.flatMap(\.tracks).count)
    }

    private static func releaseTrackCountSimilarity(selectedCount: Int, releaseTrackCount: Int) -> Double {
        guard selectedCount > 0, releaseTrackCount > 0 else { return 0 }
        if selectedCount == releaseTrackCount {
            return 1
        }
        if selectedCount < releaseTrackCount {
            return 0.3
        }
        return 0
    }

    private static func trackIndexSimilarity(_ expected: Int?, candidateValue: String) -> Double {
        guard let expected else { return 0 }
        let candidate = normalizedIndex(candidateValue)
        guard let candidate else { return 0 }
        if expected == candidate {
            return 1
        }
        if AudioNumericConversion.boundedDistance(expected, candidate, maximum: 1) == 1 {
            return 0.35
        }
        return 0
    }

    private static func discIndexSimilarity(_ expected: Int?, candidateValue: Int) -> Double {
        guard let expected else { return 0 }
        return expected == candidateValue ? 1 : 0
    }

    private static func durationSimilarity(_ lhs: Int?, _ rhs: Int?) -> Double {
        guard let lhs, let rhs else { return 0 }
        guard let difference = AudioNumericConversion.boundedDistance(lhs, rhs, maximum: 29_999) else {
            return 0
        }
        return 1 - (Double(difference) / 30_000)
    }

    private static func yearSimilarity(_ queryYear: String, candidateDate: String) -> Double {
        let digits = candidateDate.filter(\.isNumber)
        guard digits.count >= 4, !queryYear.isEmpty else { return 0 }
        let candidateYear = String(digits.prefix(4))
        guard let queryValue = Int(queryYear), let candidateValue = Int(candidateYear) else { return 0 }
        guard let difference = AudioNumericConversion.boundedDistance(queryValue, candidateValue, maximum: 2) else {
            return 0
        }
        switch difference {
        case 0:
            return 1
        case 1:
            return 0.65
        case 2:
            return 0.3
        default:
            return 0
        }
    }

    private static func bestSimilarity(_ queries: [String], candidates: [String]) -> Double {
        var best = 0.0
        for query in queries {
            for candidate in candidates {
                best = max(best, weightedSimilarity(query, candidate))
            }
        }
        return best
    }

    private static func weightedSimilarity(_ lhs: String, _ rhs: String) -> Double {
        FuzzyStringSimilarity.score(lhs, rhs)
    }

    private static func normalizedIndex(_ rawValue: String) -> Int? {
        AudioTagNumberText.positiveIndex(from: rawValue)
    }
}

nonisolated enum MusicBrainzResultRanker {
    static func rerankRecordings(
        _ results: [MusicBrainzRecordingResult],
        query: MusicBrainzSearchQuery,
        preferredRecordingIDs: Set<String> = []
    ) -> [MusicBrainzRecordingResult] {
        results.sorted { lhs, rhs in
            let lhsScore = recordingScore(lhs, query: query, preferredRecordingIDs: preferredRecordingIDs)
            let rhsScore = recordingScore(rhs, query: query, preferredRecordingIDs: preferredRecordingIDs)
            if lhsScore == rhsScore {
                return lhs.score > rhs.score
            }
            return lhsScore > rhsScore
        }
    }

    static func rerankReleases(_ results: [MusicBrainzReleaseSearchResult], query: MusicBrainzSearchQuery) -> [MusicBrainzReleaseSearchResult] {
        results.sorted { lhs, rhs in
            let lhsScore = releaseScore(lhs, query: query)
            let rhsScore = releaseScore(rhs, query: query)
            if lhsScore == rhsScore {
                return lhs.score > rhs.score
            }
            return lhsScore > rhsScore
        }
    }

    private static func recordingScore(
        _ result: MusicBrainzRecordingResult,
        query: MusicBrainzSearchQuery,
        preferredRecordingIDs: Set<String>
    ) -> Double {
        var score = Double(result.score) * 1.8

        if preferredRecordingIDs.contains(result.id) {
            score += 700
        }

        if !query.musicBrainzAlbumID.isEmpty,
           result.releases.contains(where: { $0.id == query.musicBrainzAlbumID }) {
            score += 280
        }

        score += weightedSimilarityScore(
            query: query.title,
            candidates: [result.title],
            weight: 360
        )
        score += weightedSimilarityScore(
            queries: query.artistCandidates,
            candidates: [result.artistCredit],
            weight: 230
        )
        score += weightedSimilarityScore(
            queries: query.album.isEmpty ? [] : [query.album],
            candidates: result.releases.map(\.title),
            weight: 180
        )

        if let queryDuration = query.durationMilliseconds,
           let candidateDuration = result.durationMilliseconds {
            score += durationScore(queryDuration, candidateDuration) * 150
        }

        if !query.normalizedReleaseYear.isEmpty {
            score += yearScore(query.normalizedReleaseYear, candidateDate: result.firstReleaseDate) * 70
        }

        return score
    }

    private static func releaseScore(_ result: MusicBrainzReleaseSearchResult, query: MusicBrainzSearchQuery) -> Double {
        var score = Double(result.score) * 1.8

        score += weightedSimilarityScore(
            query: query.album.isEmpty ? query.title : query.album,
            candidates: [result.title],
            weight: 360
        )
        score += weightedSimilarityScore(
            queries: query.artistCandidates,
            candidates: [result.artistCredit],
            weight: 230
        )

        if !query.normalizedReleaseYear.isEmpty {
            score += yearScore(query.normalizedReleaseYear, candidateDate: result.date) * 90
        }

        return score
    }

    private static func weightedSimilarityScore(
        query: String,
        candidates: [String],
        weight: Double
    ) -> Double {
        weightedSimilarityScore(queries: query.isEmpty ? [] : [query], candidates: candidates, weight: weight)
    }

    private static func weightedSimilarityScore(
        queries: [String],
        candidates: [String],
        weight: Double
    ) -> Double {
        guard weight > 0 else { return 0 }

        var bestSimilarity = 0.0

        for query in queries {
            for candidate in candidates {
                bestSimilarity = max(bestSimilarity, FuzzyStringSimilarity.score(query, candidate))
            }
        }

        return bestSimilarity * weight
    }

    private static func durationScore(_ lhs: Int, _ rhs: Int) -> Double {
        guard let difference = AudioNumericConversion.boundedDistance(lhs, rhs, maximum: 29_999) else {
            return 0
        }
        return 1 - (Double(difference) / 30_000)
    }

    private static func yearScore(_ queryYear: String, candidateDate: String) -> Double {
        let candidateYearDigits = candidateDate.filter(\.isNumber)
        guard candidateYearDigits.count >= 4 else { return 0 }
        let candidateYear = String(candidateYearDigits.prefix(4))
        guard let queryValue = Int(queryYear), let candidateValue = Int(candidateYear) else { return 0 }

        guard let difference = AudioNumericConversion.boundedDistance(queryValue, candidateValue, maximum: 2) else {
            return 0
        }
        switch difference {
        case 0:
            return 1
        case 1:
            return 0.65
        case 2:
            return 0.3
        default:
            return 0
        }
    }
}
