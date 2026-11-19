import Foundation

enum ArtworkLookupSource: String {
    case iTunesAlbumID = "iTunes Album ID"
    case album = "Album"
    case trackTitle = "Track Title"
}

struct ArtworkLookupRequestDescriptor {
    let query: String
    let entity: iTunesArtworkSearchEntity
    let source: ArtworkLookupSource

    var summary: String {
        "\(source.rawValue): \(query)"
    }
}

/// Search lifecycle for one artwork lookup session. Only a failed search exposes
/// a search-level retry; a cancelled search stays terminal for its result set,
/// matching the pre-split behaviour.
enum ArtworkLookupSearchState: Equatable {
    case searching
    case results
    case failed(message: String)
    case cancelled(message: String)

    var isLoading: Bool {
        self == .searching
    }

    var failureMessage: String? {
        guard case .failed(let message) = self else { return nil }
        return message
    }

    var cancellationMessage: String? {
        guard case .cancelled(let message) = self else { return nil }
        return message
    }
}

/// A download fault belongs to exactly one candidate. It never replaces the
/// search state and it is retryable for that candidate; switching candidates
/// clears it.
enum ArtworkLookupDownloadFault: Equatable {
    case failed(candidateID: iTunesArtworkSearchResult.ID, message: String)
    case cancelled(candidateID: iTunesArtworkSearchResult.ID, message: String)

    var candidateID: iTunesArtworkSearchResult.ID {
        switch self {
        case .failed(let candidateID, _), .cancelled(let candidateID, _):
            return candidateID
        }
    }

    var message: String {
        switch self {
        case .failed(_, let message), .cancelled(_, let message):
            return message
        }
    }

    var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

/// Identity of the single in-flight apply/download attempt. Completions publish
/// only while this exact attempt is still installed in the session.
struct ArtworkLookupDownloadAttempt: Equatable {
    let id: UUID
    let candidateID: iTunesArtworkSearchResult.ID
}

struct ArtworkLookupSession: Identifiable {
    let id = UUID()
    let fileIDs: [AudioFile.ID]
    let selectionTitle: String
    let request: ArtworkLookupRequestDescriptor

    var searchAttemptID: UUID?
    var searchState: ArtworkLookupSearchState = .searching
    var results: [iTunesArtworkSearchResult] = []
    var selectedResultID: iTunesArtworkSearchResult.ID?
    var download: ArtworkLookupDownloadAttempt?
    var downloadFault: ArtworkLookupDownloadFault?
    var emptyMessage: String?

    var isMultiSelection: Bool {
        fileIDs.count > 1
    }

    var isLoading: Bool {
        searchState.isLoading
    }

    var isApplying: Bool {
        download != nil
    }

    var selectedResult: iTunesArtworkSearchResult? {
        guard let selectedResultID else { return nil }
        return results.first { $0.id == selectedResultID }
    }

    /// Candidate tiles are only selectable for a settled result grid with no
    /// download in flight. A download fault never blocks this.
    var canSelectCandidate: Bool {
        searchState == .results && download == nil
    }

    /// The Apply affordance is enabled for any settled grid with a selection
    /// while no download is in flight. A previous candidate fault is retryable.
    var canApplySelectedResult: Bool {
        searchState == .results && download == nil && selectedResult != nil
    }

    var isRetryingSelectedCandidate: Bool {
        guard let downloadFault, let selectedResultID else { return false }
        return downloadFault.candidateID == selectedResultID
    }

    var applyActionTitle: String {
        if isRetryingSelectedCandidate {
            return String(localized: "Try Again")
        }
        return isMultiSelection
            ? String(localized: "Apply to Selected Files")
            : String(localized: "Use Selected Artwork")
    }

    var showsSearchRetry: Bool {
        if case .failed = searchState { return true }
        return false
    }

    var searchFailureMessage: String? {
        searchState.failureMessage
    }

    var searchCancellationMessage: String? {
        searchState.cancellationMessage
    }

    var downloadFaultMessage: String? {
        downloadFault?.message
    }

    var downloadFaultCandidateTitle: String? {
        guard let fault = downloadFault else { return nil }
        return results.first { $0.id == fault.candidateID }?.title
    }
}
