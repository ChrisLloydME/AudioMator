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
/// clears it. A stale-selection / superseded fault belongs to the destination
/// draft instead: it is terminal for the sheet's apply path (only closing and
/// starting a new command can recover), never retryable against the network.
enum ArtworkLookupDownloadFault: Equatable {
    case failed(candidateID: iTunesArtworkSearchResult.ID, message: String)
    case cancelled(candidateID: iTunesArtworkSearchResult.ID, message: String)
    case staleSelection(message: String)
    case superseded(message: String)

    var candidateID: iTunesArtworkSearchResult.ID? {
        switch self {
        case .failed(let candidateID, _), .cancelled(let candidateID, _):
            return candidateID
        case .staleSelection, .superseded:
            return nil
        }
    }

    var message: String {
        switch self {
        case .failed(_, let message),
             .cancelled(_, let message),
             .staleSelection(let message),
             .superseded(let message):
            return message
        }
    }

    var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }

    /// Candidate-scoped faults can be retried against the same candidate; a
    /// destination fault cannot.
    var isRetryable: Bool {
        switch self {
        case .failed, .cancelled:
            return true
        case .staleSelection, .superseded:
            return false
        }
    }

    var isTransferFault: Bool {
        switch self {
        case .staleSelection, .superseded:
            return true
        case .failed, .cancelled:
            return false
        }
    }

    var inlineTitle: String {
        switch self {
        case .failed:
            return String(localized: "Artwork Download Failed")
        case .cancelled:
            return String(localized: "Artwork Download Cancelled")
        case .staleSelection:
            return String(localized: "Selection Changed")
        case .superseded:
            return String(localized: "Artwork Wasn’t Applied")
        }
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
    var storefront: iTunesStorefront = .us

    var searchAttemptID: UUID?
    var searchState: ArtworkLookupSearchState = .searching
    var results: [iTunesArtworkSearchResult] = []
    var selectedResultID: iTunesArtworkSearchResult.ID?
    var download: ArtworkLookupDownloadAttempt?
    var downloadFault: ArtworkLookupDownloadFault?
    var emptyMessage: String?
    /// Destination-draft authority captured before the search started. nil means
    /// the lookup is preview-only: results can be inspected but never applied.
    var transfer: ArtworkTransferIntent?

    var isMultiSelection: Bool {
        fileIDs.count > 1
    }

    var isLoading: Bool {
        searchState.isLoading
    }

    var isApplying: Bool {
        download != nil
    }

    /// Storefront changes are allowed whenever no candidate download is in flight.
    /// Switching storefronts cancels any active search and queries the chosen region
    /// while preserving the captured Inspector draft transfer.
    var canChangeStorefront: Bool {
        download == nil
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

    /// A preview-only lookup has no captured Inspector draft to stage into.
    var isPreviewOnly: Bool {
        transfer == nil
    }

    /// The Apply affordance is enabled for a settled grid with a selection, a
    /// captured destination draft, and no in-flight attempt. Candidate-scoped
    /// faults are retryable; destination faults are terminal for this sheet.
    var canApplySelectedResult: Bool {
        guard searchState == .results, download == nil, selectedResult != nil else { return false }
        guard !isPreviewOnly else { return false }
        guard let downloadFault else { return true }
        return downloadFault.isRetryable
    }

    var isRetryingSelectedCandidate: Bool {
        guard let downloadFault, downloadFault.isRetryable, let selectedResultID else { return false }
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
        guard let fault = downloadFault, let candidateID = fault.candidateID else { return nil }
        return results.first { $0.id == candidateID }?.title
    }
}
