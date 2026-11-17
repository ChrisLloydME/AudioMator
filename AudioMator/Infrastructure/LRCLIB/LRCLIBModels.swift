import Foundation

enum LRCLIBClientError: LocalizedError, Equatable {
    case emptyQuery
    case invalidRequest
    case invalidResponse
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return String(localized: "Add a title or artist to this file before searching for lyrics.")
        case .invalidRequest:
            return String(localized: "This LRCLIB search couldn’t be started. Check the search details and try again.")
        case .invalidResponse:
            return String(localized: "The response from LRCLIB couldn’t be read. Try again later.")
        case .requestFailed(let statusCode):
            return String(localized: "This LRCLIB search couldn’t be completed. Try again later.\nDetails: HTTP \(statusCode).")
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
