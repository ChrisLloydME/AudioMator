import Foundation

enum MusicBrainzLinkTarget: Equatable {
    case recording(String)
    case release(String)
}

enum MusicBrainzLinkParser {
    private static let supportedHosts = Set(NetworkServiceDisclosure.MusicBrainz.acceptedLinkDomains)

    static func parse(_ rawValue: String) throws -> MusicBrainzLinkTarget {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MusicBrainzClientError.invalidLink
        }

        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: normalized),
              let host = components.host?.lowercased(),
              supportedHosts.contains(host) else {
            throw MusicBrainzClientError.invalidLink
        }

        let pathComponents = components.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard pathComponents.count >= 2 else {
            throw MusicBrainzClientError.invalidLink
        }

        let entity = pathComponents[0].lowercased()
        let id = pathComponents[1]

        guard UUID(uuidString: id) != nil else {
            throw MusicBrainzClientError.invalidLink
        }

        switch entity {
        case "recording":
            return .recording(id)
        case "release":
            return .release(id)
        default:
            throw MusicBrainzClientError.unsupportedLink
        }
    }
}
