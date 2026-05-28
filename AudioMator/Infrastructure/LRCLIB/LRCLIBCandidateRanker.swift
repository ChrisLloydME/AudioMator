import Foundation

struct LRCLIBRankedCandidate: Identifiable, Equatable, Sendable {
    let candidate: LRCLIBLyricsCandidate
    let score: Int

    var id: Int { candidate.id }
}

enum LRCLIBCandidateRanker {
    static func rankedCandidates(
        _ candidates: [LRCLIBLyricsCandidate],
        for query: LRCLIBSearchQuery
    ) -> [LRCLIBRankedCandidate] {
        candidates
            .map { candidate in
                LRCLIBRankedCandidate(
                    candidate: candidate,
                    score: score(candidate: candidate, query: query)
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.candidate.hasSyncedLyrics != rhs.candidate.hasSyncedLyrics {
                    return lhs.candidate.hasSyncedLyrics
                }
                return lhs.candidate.trackName.localizedCaseInsensitiveCompare(rhs.candidate.trackName) == .orderedAscending
            }
    }

    static func score(candidate: LRCLIBLyricsCandidate, query: LRCLIBSearchQuery) -> Int {
        var score = 0
        score += textScore(candidate.trackName, query.trackName, exact: 45, partial: 20)
        score += textScore(candidate.artistName, query.artistName, exact: 35, partial: 16)
        score += textScore(candidate.albumName, query.albumName, exact: 20, partial: 8)

        if let queryDuration = query.durationSeconds,
           let candidateDuration = candidate.durationSeconds {
            let delta = abs(candidateDuration - queryDuration)
            switch delta {
            case 0...1:
                score += 20
            case 2...4:
                score += 12
            case 5...8:
                score += 6
            default:
                score -= min(delta, 20)
            }
        }

        if candidate.hasSyncedLyrics {
            score += 10
        } else if candidate.hasPlainLyrics {
            score -= 6
        } else if candidate.instrumental {
            score -= 10
        }

        return score
    }

    private static func textScore(
        _ candidateValue: String,
        _ queryValue: String,
        exact: Int,
        partial: Int
    ) -> Int {
        let candidate = normalized(candidateValue)
        let query = normalized(queryValue)
        guard !candidate.isEmpty, !query.isEmpty else { return 0 }
        if candidate == query { return exact }
        if candidate.contains(query) || query.contains(candidate) { return partial }
        return 0
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
