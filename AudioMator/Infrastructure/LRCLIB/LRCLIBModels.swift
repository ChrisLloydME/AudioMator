import Foundation

enum LRCLIBClientError: LocalizedError, Equatable {
    case emptyQuery
    case invalidRequest
    case invalidResponse
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "The selected file does not have enough title or artist metadata to search LRCLIB."
        case .invalidRequest:
            return "AudioMator could not build a valid LRCLIB request."
        case .invalidResponse:
            return "LRCLIB returned an unexpected response."
        case .requestFailed(let statusCode):
            return "LRCLIB request failed with HTTP \(statusCode)."
        }
    }
}

struct LRCLIBSearchQuery: Equatable, Sendable {
    var trackName: String
    var artistName: String
    var albumName: String
    var durationSeconds: Int?

    nonisolated var isEmpty: Bool {
        trackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct LRCLIBLyricsCandidate: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let name: String?
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double?
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?

    var hasSyncedLyrics: Bool {
        !(syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var hasPlainLyrics: Bool {
        !(plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var durationSeconds: Int? {
        duration.flatMap(AudioNumericConversion.positiveDurationSeconds)
    }

    var lyricsAvailabilityLabel: String {
        if hasSyncedLyrics { return "Synced" }
        if hasPlainLyrics { return "Plain only" }
        if instrumental { return "Instrumental" }
        return "No lyrics"
    }
}

protocol LRCLIBLyricsSearching: Sendable {
    nonisolated func search(matching query: LRCLIBSearchQuery, limit: Int) async throws -> [LRCLIBLyricsCandidate]
}
