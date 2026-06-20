import Foundation

struct MusicBrainzReleaseSearchResult: Identifiable, Equatable, Hashable {
    struct ReleaseGroup: Equatable, Hashable {
        let id: String
        let primaryType: String
        let secondaryTypes: [String]
    }

    let id: String
    let title: String
    let artistCredit: String
    let score: Int
    let date: String
    let country: String
    let status: String
    let mediaFormats: [String]
    let releaseGroup: ReleaseGroup?
    let selectionMatchPreview: MusicBrainzReleaseMatchPreview?
    let selectionMatchScore: Double?

    var mediaFormatSummary: String {
        mediaFormats.joined(separator: " • ")
    }

    var musicBrainzURL: URL? {
        NetworkServiceDisclosure.MusicBrainz.webURL(path: "/release/\(id)")
    }
}

extension MusicBrainzReleaseSearchResult {
    init(recordingRelease release: MusicBrainzRecordingResult.Release) {
        self.init(
            id: release.id,
            title: release.title,
            artistCredit: "",
            score: 0,
            date: release.date,
            country: release.country,
            status: release.status,
            mediaFormats: [],
            releaseGroup: nil,
            selectionMatchPreview: nil,
            selectionMatchScore: nil
        )
    }
}

enum MusicBrainzSearchResults: Equatable {
    case recordings([MusicBrainzRecordingResult])
    case releases([MusicBrainzReleaseSearchResult])

    var count: Int {
        switch self {
        case .recordings(let items): return items.count
        case .releases(let items): return items.count
        }
    }

    var isEmpty: Bool { count == 0 }
}

struct MusicBrainzRecordingResult: Identifiable, Equatable, Hashable {
    struct Release: Identifiable, Equatable, Hashable {
        let id: String
        let title: String
        let date: String
        let country: String
        let status: String

        var musicBrainzURL: URL? {
            NetworkServiceDisclosure.MusicBrainz.webURL(path: "/release/\(id)")
        }
    }

    let id: String
    let title: String
    let artistCredit: String
    let score: Int
    let disambiguation: String
    let firstReleaseDate: String
    let durationMilliseconds: Int?
    let releases: [Release]

    var musicBrainzURL: URL? {
        NetworkServiceDisclosure.MusicBrainz.webURL(path: "/recording/\(id)")
    }

    var primaryRelease: Release? {
        releases.first
    }
}

struct MusicBrainzRecordingDetail: Equatable {
    let id: String
    let title: String
    let artistCredit: String
    let disambiguation: String
    let firstReleaseDate: String
    let durationMilliseconds: Int?
    let annotation: String
    let isrcs: [String]
    let genres: [MusicBrainzTerm]
    let tags: [MusicBrainzTerm]
    let rating: MusicBrainzRating?
    let releases: [MusicBrainzRecordingResult.Release]
    let relationshipGroups: [MusicBrainzRelationshipGroup]

    var musicBrainzURL: URL? {
        NetworkServiceDisclosure.MusicBrainz.webURL(path: "/recording/\(id)")
    }
}

struct MusicBrainzRelationshipGroup: Equatable, Identifiable {
    let title: String
    var values: [String]

    var id: String { title }
}

struct MusicBrainzTerm: Equatable {
    let name: String
    let count: Int?

    nonisolated init(name: String, count: Int?) {
        self.name = name
        self.count = count
    }
}

struct MusicBrainzRating: Equatable {
    let value: Double?
    let voteCount: Int

    nonisolated init(value: Double?, voteCount: Int) {
        self.value = value
        self.voteCount = voteCount
    }
}

struct MusicBrainzReleaseDetail: Equatable {
    struct LabelInfo: Identifiable, Equatable, Hashable {
        let id: String
        let labelName: String
        let catalogNumber: String
    }

    struct Medium: Identifiable, Equatable, Hashable {
        struct Track: Identifiable, Equatable, Hashable {
            let id: String
            let number: String
            let title: String
            let artistCredit: String
            let durationMilliseconds: Int?
            let recordingID: String
            let isrcs: [String]
        }

        let id: String
        let title: String
        let format: String
        let trackCount: Int
        let discIDs: [String]
        let tracks: [Track]
    }

    let id: String
    let title: String
    let artistCredit: String
    let date: String
    let country: String
    let status: String
    let barcode: String
    let packaging: String
    let asin: String
    let quality: String
    let language: String
    let script: String
    let annotation: String
    let genres: [MusicBrainzTerm]
    let tags: [MusicBrainzTerm]
    let releaseGroupTitle: String
    let releaseGroupID: String
    let releaseGroupPrimaryType: String
    let releaseGroupSecondaryTypes: [String]
    let labels: [LabelInfo]
    let media: [Medium]
    var selectionMatchPreview: MusicBrainzReleaseMatchPreview?

    var musicBrainzURL: URL? {
        NetworkServiceDisclosure.MusicBrainz.webURL(path: "/release/\(id)")
    }
}

struct MusicBrainzTrackDetail: Equatable {
    let track: MusicBrainzReleaseDetail.Medium.Track
    let recordingDetail: MusicBrainzRecordingDetail?
}

enum MusicBrainzMetadataDetail: Equatable {
    case recording(MusicBrainzRecordingDetail)
    case release(MusicBrainzReleaseDetail)
    case track(MusicBrainzTrackDetail)
}

enum MusicBrainzClientError: LocalizedError {
    case emptyQuery
    case invalidLink
    case unsupportedLink
    case invalidRequest
    case requestFailed(statusCode: Int)
    case invalidResponse
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Enter at least one search field."
        case .invalidLink:
            return "Paste a valid MusicBrainz link."
        case .unsupportedLink:
            return "Only MusicBrainz release and recording links are supported."
        case .invalidRequest:
            return "Couldn't create the MusicBrainz request."
        case .requestFailed(let statusCode):
            return "MusicBrainz returned HTTP \(statusCode)."
        case .invalidResponse:
            return "MusicBrainz returned an unexpected response."
        case .decodingFailed(let detail):
            return "MusicBrainz returned data AudioMator couldn't read. \(detail)"
        }
    }
}
