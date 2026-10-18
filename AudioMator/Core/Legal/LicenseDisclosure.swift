import Foundation

/// User-facing inventory of the licenses and copyright notices that apply to
/// AudioMator and the third-party code shipped in its app bundle.
enum LicenseDisclosure {
    struct Document: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let resourceName: String
    }

    struct Entry: Identifiable, Equatable, Sendable {
        enum ID: String, CaseIterable, Hashable, Sendable {
            case audioMator
            case tagLib
            case tagLibAudioMetadata
            case utfcpp
        }

        let id: ID
        let title: String
        let version: String?
        let copyright: String
        let summary: String
        let projectURL: URL?
        let sourceURL: URL?
        let documents: [Document]
    }

    nonisolated static let allEntries: [Entry] = [
        Entry(
            id: .audioMator,
            title: "AudioMator",
            version: nil,
            copyright: "Copyright © 2025–2026 Christopher Lloyd.",
            summary: "AudioMator is licensed under the GNU Affero General Public License v3.0. The complete corresponding source code is available from the project repository.",
            projectURL: URL(string: "https://github.com/ChrisLloydME/AudioMator"),
            sourceURL: URL(string: "https://github.com/ChrisLloydME/AudioMator"),
            documents: [
                Document(
                    id: "audiomator-agpl",
                    title: "GNU Affero General Public License v3.0",
                    resourceName: "AudioMator-AGPL-3.0"
                )
            ]
        ),
        Entry(
            id: .tagLib,
            title: "TagLib",
            version: "2.3.1",
            copyright: "Copyright (C) 2002–2008 Scott Wheeler and TagLib contributors.",
            summary: "Low-level audio metadata parsing and writing. AudioMator uses TagLib through the TagLibAudioMetadata package; the TagLib library is bundled as a dynamic framework. TagLib is dual-licensed under the GNU Lesser General Public License v2.1 and the Mozilla Public License 1.1.",
            projectURL: URL(string: "https://taglib.org/"),
            sourceURL: URL(string: "https://github.com/taglib/taglib/tree/v2.3.1"),
            documents: [
                Document(
                    id: "taglib-lgpl",
                    title: "GNU Lesser General Public License v2.1",
                    resourceName: "TagLib-LGPL-2.1"
                ),
                Document(
                    id: "taglib-mpl",
                    title: "Mozilla Public License 1.1",
                    resourceName: "TagLib-MPL-1.1"
                )
            ]
        ),
        Entry(
            id: .tagLibAudioMetadata,
            title: "TagLibAudioMetadata",
            version: "0.5.3",
            copyright: "Copyright (c) 2026 Christopher Lloyd.",
            summary: "Swift Package Manager dependency that exposes the TagLib-backed metadata manager used by AudioMator. Licensed under the MIT License.",
            projectURL: URL(string: "https://github.com/ChrisLloydME/TagLibAudioMetadata"),
            sourceURL: URL(string: "https://github.com/ChrisLloydME/TagLibAudioMetadata"),
            documents: [
                Document(
                    id: "taglibaudiometadata-mit",
                    title: "MIT License",
                    resourceName: "TagLibAudioMetadata-MIT"
                )
            ]
        ),
        Entry(
            id: .utfcpp,
            title: "utf8-cpp (utfcpp)",
            version: nil,
            copyright: "Copyright 2006 Nemanja Trifunovic.",
            summary: "UTF-8 conversion library bundled with the TagLib framework. Licensed under the Boost Software License 1.0.",
            projectURL: URL(string: "https://github.com/nemtrif/utfcpp"),
            sourceURL: URL(string: "https://github.com/nemtrif/utfcpp"),
            documents: [
                Document(
                    id: "utfcpp-boost",
                    title: "Boost Software License 1.0",
                    resourceName: "utfcpp-Boost-1.0"
                )
            ]
        )
    ]

    nonisolated static func entry(for id: Entry.ID) -> Entry? {
        allEntries.first { $0.id == id }
    }

    /// Loads a bundled license text. The app copies synchronized resources to
    /// the bundle root today, but the `Licenses` subdirectory is checked first
    /// so the resources keep working if the project later preserves folders.
    nonisolated static func loadText(for document: Document, in bundle: Bundle = .main) -> String? {
        let urls = [
            bundle.url(forResource: document.resourceName, withExtension: "txt", subdirectory: "Licenses"),
            bundle.url(forResource: document.resourceName, withExtension: "txt")
        ]

        for url in urls.compactMap({ $0 }) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            return text
        }

        return nil
    }
}
