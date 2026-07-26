import Foundation

nonisolated enum MusicBrainzLinkTarget: Equatable, Sendable {
    case recording(String)
    case release(String)
}

nonisolated enum MusicBrainzLinkParser {
    private static let supportedHosts = Set(NetworkServiceDisclosure.MusicBrainz.acceptedLinkDomains)

    static func parse(_ rawValue: String) throws -> MusicBrainzLinkTarget {
        do {
            switch try MusicBrainzProviderLinkParser.parse(rawValue, supportedHosts: supportedHosts) {
            case .recording(let id):
                return .recording(id)
            case .release(let id):
                return .release(id)
            }
        } catch CoreProviderRequestError.invalidLink {
            throw MusicBrainzClientError.invalidLink
        } catch CoreProviderRequestError.unsupportedLink {
            throw MusicBrainzClientError.unsupportedLink
        } catch {
            throw error
        }
    }
}
