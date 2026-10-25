import XCTest
@testable import AudioMator

final class LicenseDisclosureTests: XCTestCase {
    func testEveryLicenseEntryIsCompleteAndUnique() {
        let entries = LicenseDisclosure.allEntries

        XCTAssertEqual(Set(entries.map(\.id)), Set(LicenseDisclosure.Entry.ID.allCases))
        XCTAssertEqual(entries.count, LicenseDisclosure.Entry.ID.allCases.count)
        XCTAssertEqual(Set(entries.map(\.title)).count, entries.count)

        for entry in entries {
            XCTAssertFalse(entry.title.isEmpty, entry.id.rawValue)
            XCTAssertFalse(entry.copyright.isEmpty, entry.id.rawValue)
            XCTAssertFalse(entry.summary.isEmpty, entry.id.rawValue)
            XCTAssertFalse(entry.documents.isEmpty, entry.id.rawValue)
            XCTAssertEqual(Set(entry.documents.map(\.id)).count, entry.documents.count, entry.id.rawValue)

            for document in entry.documents {
                XCTAssertFalse(document.title.isEmpty, entry.id.rawValue)
                XCTAssertFalse(document.resourceName.isEmpty, entry.id.rawValue)
            }
        }
    }

    func testEveryBundledLicenseTextIsAvailableAndNonEmpty() {
        for entry in LicenseDisclosure.allEntries {
            for document in entry.documents {
                let text = LicenseDisclosure.loadText(for: document)

                XCTAssertNotNil(text, "\(entry.id.rawValue): \(document.resourceName)")
                XCTAssertFalse(
                    text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
                    "\(entry.id.rawValue): \(document.resourceName)"
                )
            }
        }
    }

    func testBundledAGPLTextMatchesRepositoryLicense() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repositoryLicense = try String(
            contentsOf: repositoryURL.appendingPathComponent("LICENSE"),
            encoding: .utf8
        )

        guard let entry = LicenseDisclosure.entry(for: .audioMator),
              let document = entry.documents.first else {
            return XCTFail("AudioMator license entry is missing")
        }

        XCTAssertEqual(LicenseDisclosure.loadText(for: document), repositoryLicense)
    }

    func testTagLibKeepsBothDualLicenseDocuments() {
        guard let tagLib = LicenseDisclosure.entry(for: .tagLib) else {
            return XCTFail("TagLib entry is missing")
        }

        XCTAssertEqual(tagLib.version, "2.3.1")
        XCTAssertEqual(tagLib.sourceURL?.absoluteString, "https://github.com/taglib/taglib/tree/v2.3.1")
        XCTAssertEqual(tagLib.documents.map(\.resourceName), ["TagLib-LGPL-2.1", "TagLib-MPL-1.1"])
    }

    func testBundledTextsContainTheExpectedLicenseAndCopyrightMarkers() {
        let expectedMarkers: [LicenseDisclosure.Entry.ID: [String]] = [
            .audioMator: ["GNU AFFERO GENERAL PUBLIC LICENSE", "Version 3"],
            .tagLib: ["GNU LESSER GENERAL PUBLIC LICENSE", "Version 2.1"],
            .tagLibAudioMetadata: ["MIT License", "Copyright (c) 2026 Christopher Lloyd"],
            .utfcpp: ["Copyright 2006 Nemanja Trifunovic", "Boost Software License"]
        ]

        for (id, markers) in expectedMarkers {
            guard let entry = LicenseDisclosure.entry(for: id) else {
                return XCTFail("Missing entry: \(id.rawValue)")
            }

            let combinedText = entry.documents
                .compactMap { LicenseDisclosure.loadText(for: $0) }
                .joined(separator: "\n")

            for marker in markers {
                XCTAssertTrue(combinedText.contains(marker), "\(id.rawValue) is missing \(marker)")
            }
        }
    }
}
