import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

/// Contract coverage for numbering components, advisory values, MP4-exclusive
/// container fields and semantic preservation.
nonisolated final class TagLibMappingContractIntegrationTests: XCTestCase {
    private static let audioFixtureNames = [
        "testAudioFile.mp3",
        "testAudioFile.m4a",
        "testAudioFile.flac",
        "testAudioFile.ogg",
        "testAudioFile.aac",
        "testAudioFile.wav",
    ]

    // MARK: - A07 number components

    @MainActor
    func testNumberComponentEditsPreserveUntouchedComponents() async throws {
        for fixtureName in Self.audioFixtureNames {
            let url = try writableFixture(named: fixtureName)
            defer { removeTemporaryFixtureDirectory(containing: url) }

            _ = try TagLibMetadataManager.applyMetadataPatch(
                MetadataPatch(fields: [
                    .track: .integer(3), .trackTotal: .integer(12),
                    .disc: .integer(2), .discTotal: .integer(3),
                ]),
                to: url
            )
            let pipeline = TagLibAudioMetadataPipeline()

            // Number-only edit preserves the total.
            var file = try await pipeline.loadAudioFile(at: url, id: UUID())
            var edit = SingleFileEditModel(from: file)
            edit.setTrackNumberFieldText("5")
            _ = try pipeline.writeMetadata(
                MetadataEditPayload(edit, comparedTo: file),
                to: url,
                expectedVersion: file.metadataFileVersion
            )
            file = try await pipeline.loadAudioFile(at: url, id: UUID())
            let trackObserved1 = file.track
            XCTAssertEqual(trackObserved1, 5, fixtureName)
            let trackTotalObserved2 = file.trackTotal
            XCTAssertEqual(trackTotalObserved2, 12, fixtureName)
            let discObserved3 = file.disc
            XCTAssertEqual(discObserved3, 2, fixtureName)
            let discTotalObserved4 = file.discTotal
            XCTAssertEqual(discTotalObserved4, 3, fixtureName)

            // Total-only edit preserves the number.
            edit = SingleFileEditModel(from: file)
            edit.setTrackTotalFieldText("15")
            _ = try pipeline.writeMetadata(
                MetadataEditPayload(edit, comparedTo: file),
                to: url,
                expectedVersion: file.metadataFileVersion
            )
            file = try await pipeline.loadAudioFile(at: url, id: UUID())
            let trackObserved5 = file.track
            XCTAssertEqual(trackObserved5, 5, fixtureName)
            let trackTotalObserved6 = file.trackTotal
            XCTAssertEqual(trackTotalObserved6, 15, fixtureName)

            // Removing the number keeps the total-only representation.
            edit = SingleFileEditModel(from: file)
            edit.setTrackNumberFieldText("")
            _ = try pipeline.writeMetadata(
                MetadataEditPayload(edit, comparedTo: file),
                to: url,
                expectedVersion: file.metadataFileVersion
            )
            file = try await pipeline.loadAudioFile(at: url, id: UUID())
            let trackObserved7 = file.track
            XCTAssertEqual(trackObserved7, 0, fixtureName)
            let trackTotalObserved8 = file.trackTotal
            XCTAssertEqual(trackTotalObserved8, 15, fixtureName)

            // Disc-only edit preserves the entire track group.
            edit = SingleFileEditModel(from: file)
            edit.setDiscNumberFieldText("4")
            _ = try pipeline.writeMetadata(
                MetadataEditPayload(edit, comparedTo: file),
                to: url,
                expectedVersion: file.metadataFileVersion
            )
            file = try await pipeline.loadAudioFile(at: url, id: UUID())
            let trackObserved9 = file.track
            XCTAssertEqual(trackObserved9, 0, fixtureName)
            let trackTotalObserved10 = file.trackTotal
            XCTAssertEqual(trackTotalObserved10, 15, fixtureName)
            let discObserved11 = file.disc
            XCTAssertEqual(discObserved11, 4, fixtureName)
            let discTotalObserved12 = file.discTotal
            XCTAssertEqual(discTotalObserved12, 3, fixtureName)
        }
    }

    // MARK: - A08/A09 inventory and captured cleanup plan

    @MainActor
    func testLegacyTrackTotalRecoveryAndCapturedPlanCleanup() async throws {
        let url = try writableFixture(named: "testAudioFile.mp3")
        defer { removeTemporaryFixtureDirectory(containing: url) }

        // TRCK=3 plus a legacy TXXX TRACKTOTAL=12 alias.
        _ = try TagLibMetadataManager.applyRawMetadataPatch(
            RawMetadataPatch(valuesToSet: [
                "TRACKNUMBER": ["3"],
                "TRACKTOTAL": ["12"],
            ]),
            to: url
        )

        let pipeline = TagLibAudioMetadataPipeline()
        let inventory = try TagLibMetadataManager.numberingInventory(at: url)
        XCTAssertEqual(inventory.track.number.state, .native)
        XCTAssertEqual(inventory.track.number.nativeValue, 3)
        XCTAssertEqual(inventory.track.total.state, .recoveredLegacy)
        XCTAssertEqual(inventory.track.total.recoveredValue, 12)
        XCTAssertTrue(
            inventory.track.total.identities.contains { $0.uppercased().contains("TRACKTOTAL") },
            "\(inventory.track.total.identities)"
        )

        // A title-only save preserves the alias.
        var file = try await pipeline.loadAudioFile(at: url, id: UUID())
        var edit = SingleFileEditModel(from: file)
        edit.title = "Inventory Preservation"
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(edit, comparedTo: file),
            to: url,
            expectedVersion: file.metadataFileVersion
        )
        var valueMap = try pipeline.rawMetadataValueMap(for: url)
        XCTAssertEqual(valueMap["TRACKTOTAL"], ["12"])

        // Preview the explicit normalization.
        file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let preview = try TagLibMetadataManager.planNumberNormalization(
            at: url,
            policy: .useLegacy,
            groups: [.track]
        )
        XCTAssertEqual(preview.trackNumber, 3)
        XCTAssertEqual(preview.trackTotal, 12)
        XCTAssertFalse((preview.removals + preview.privateRemovals).isEmpty)

        // Stale plan: another edit changes the file version.
        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [.title: .text("External Revision")]),
            to: url
        )
        let staleBytes = try Data(contentsOf: url)
        XCTAssertThrowsError(
            try TagLibMetadataManager.applyNumberNormalization(preview, to: url, expectedVersion: preview.fileVersion)
        )
        XCTAssertEqual(try Data(contentsOf: url), staleBytes)

        // Fresh preview applies the exact captured plan.
        let fresh = try TagLibMetadataManager.planNumberNormalization(at: url, policy: .useLegacy, groups: [.track])
        _ = try TagLibMetadataManager.applyNumberNormalization(fresh, to: url, expectedVersion: nil)
        file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let trackObserved13 = file.track
        XCTAssertEqual(trackObserved13, 3)
        let trackTotalObserved14 = file.trackTotal
        XCTAssertEqual(trackTotalObserved14, 12)
        valueMap = try pipeline.rawMetadataValueMap(for: url)
        XCTAssertFalse(valueMap.keys.contains { $0.uppercased() == "TRACKTOTAL" })
    }

    @MainActor
    func testTrackCleanupPreservesDiscGroupAndPrivateLookalikes() async throws {
        let url = try writableFixture(named: "testAudioFile.mp3")
        defer { removeTemporaryFixtureDirectory(containing: url) }

        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [
                .track: .integer(3), .disc: .integer(2), .discTotal: .integer(3),
            ]),
            to: url
        )
        _ = try TagLibMetadataManager.applyRawMetadataPatch(
            RawMetadataPatch(valuesToSet: [
                "TRACKTOTAL": ["12"],
                "DISC-TOTAL-LOOKALIKE": ["keep"],
            ]),
            to: url
        )

        let pipeline = TagLibAudioMetadataPipeline()
        let preview = try TagLibMetadataManager.planNumberNormalization(
            at: url,
            policy: .useLegacy,
            groups: [.track]
        )
        _ = try TagLibMetadataManager.applyNumberNormalization(preview, to: url, expectedVersion: nil)

        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let trackObserved15 = file.track
        XCTAssertEqual(trackObserved15, 3)
        let trackTotalObserved16 = file.trackTotal
        XCTAssertEqual(trackTotalObserved16, 12)
        let discObserved17 = file.disc
        XCTAssertEqual(discObserved17, 2)
        let discTotalObserved18 = file.discTotal
        XCTAssertEqual(discTotalObserved18, 3)
        let valueMap = try pipeline.rawMetadataValueMap(for: url)
        XCTAssertEqual(valueMap["DISC-TOTAL-LOOKALIKE"], ["keep"])
        XCTAssertEqual(valueMap["DISCNUMBER"], ["2/3"])
    }

    @MainActor
    func testAmbiguousLegacyTotalsAreSurfacedAndBlockNumberEdits() async throws {
        let url = try writableFixture(named: "testAudioFile.mp3")
        defer { removeTemporaryFixtureDirectory(containing: url) }

        _ = try TagLibMetadataManager.applyRawMetadataPatch(
            RawMetadataPatch(valuesToSet: [
                "TRACKNUMBER": ["3"],
                "TRACKTOTAL": ["12"],
                "TOTALTRACKS": ["14"],
            ]),
            to: url
        )
        let pipeline = TagLibAudioMetadataPipeline()
        let inventory = try TagLibMetadataManager.numberingInventory(at: url)
        // If the package coalesces these aliases, the ambiguity assertion is
        // reported as a coverage gap rather than silently accepted.
        guard inventory.track.total.state == .ambiguous else {
            XCTFail("Expected ambiguous legacy totals, got \(inventory.track.total.state): \(inventory.track.total.identities)")
            return
        }
        XCTAssertGreaterThanOrEqual(inventory.track.total.candidates.count, 2)

        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        var edit = SingleFileEditModel(from: file)
        edit.setTrackNumberFieldText("5")
        let payload = MetadataEditPayload(edit, comparedTo: file)
        let before = try Data(contentsOf: url)
        XCTAssertThrowsError(
            try pipeline.writeMetadata(payload, to: url, expectedVersion: file.metadataFileVersion),
            "An ambiguous recovered total must block a component edit"
        ) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "AudioMator.Numbering")
            XCTAssertEqual(nsError.code, 1)
            XCTAssertTrue(
                nsError.localizedDescription.contains("Total Tracks"),
                "The ambiguous total must be named for the user: \(nsError.localizedDescription)"
            )
        }
        XCTAssertEqual(try Data(contentsOf: url), before)

        // An unrelated edit preserves both candidates.
        var titleEdit = SingleFileEditModel(from: file)
        titleEdit.title = "Preserve Ambiguous Totals"
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(titleEdit, comparedTo: file),
            to: url,
            expectedVersion: file.metadataFileVersion
        )
        let valueMap = try pipeline.rawMetadataValueMap(for: url)
        XCTAssertEqual(valueMap["TRACKTOTAL"], ["12"])
        XCTAssertEqual(valueMap["TOTALTRACKS"], ["14"])
    }

    // MARK: - A10 advisory

    @MainActor
    func testAdvisoryStatesRoundTripAndUnknownCodeIsPreserved() async throws {
        let url = try writableFixture(named: "testAudioFile.m4a")
        defer { removeTemporaryFixtureDirectory(containing: url) }
        let pipeline = TagLibAudioMetadataPipeline()

        let states: [(ExplicitAdvisory, Int?)] = [
            (.unspecified, nil),
            (.notExplicit, 0),
            (.explicit, 1),
            (.clean, 2),
        ]
        for (value, expectedCode) in states {
            _ = try TagLibMetadataManager.applyMetadataPatch(
                MetadataPatch(explicitAdvisory: value),
                to: url
            )
            let snapshot = try TagLibMetadataManager.readSnapshot(from: url)
            let atom = snapshot.structured.mp4Atoms.first { $0.key == "rtng" }
            XCTAssertEqual(atom?.first ?? atom.flatMap { Int($0.value) }, expectedCode)
            let file = try await pipeline.loadAudioFile(at: url, id: UUID())
            let contentAdvisoryObserved19 = file.contentAdvisory
            switch expectedCode {
            case nil: XCTAssertNil(contentAdvisoryObserved19)
            case 0: XCTAssertEqual(contentAdvisoryObserved19, .notExplicit)
            case 1: XCTAssertEqual(contentAdvisoryObserved19, .explicit)
            case 2: XCTAssertEqual(contentAdvisoryObserved19, .clean)
            default: XCTFail("unexpected")
            }
        }

        // Present zero must survive a title-only save.
        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(explicitAdvisory: .notExplicit),
            to: url
        )
        var file = try await pipeline.loadAudioFile(at: url, id: UUID())
        var edit = SingleFileEditModel(from: file)
        edit.title = "Advisory Zero Preservation"
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(edit, comparedTo: file),
            to: url,
            expectedVersion: file.metadataFileVersion
        )
        file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let contentAdvisoryObserved23 = file.contentAdvisory
        XCTAssertEqual(contentAdvisoryObserved23, .notExplicit)
        XCTAssertEqual(
            try TagLibMetadataManager.readSnapshot(from: url).structured.mp4Atoms.first { $0.key == "rtng" }.flatMap { $0.first ?? Int($0.value) },
            0
        )

        // Unknown native code 4 is readable/preserved, not coerced to Clean.
        _ = try TagLibMetadataManager.applyRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["ITUNESADVISORY": ["4"]]),
            to: url
        )
        file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let contentAdvisoryObserved24 = file.contentAdvisory
        XCTAssertNil(contentAdvisoryObserved24)
        let advisoryRawValueObserved25 = file.advisoryRawValue
        XCTAssertEqual(advisoryRawValueObserved25, "4")
        edit = SingleFileEditModel(from: file)
        edit.title = "Unknown Advisory Preservation"
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(edit, comparedTo: file),
            to: url,
            expectedVersion: file.metadataFileVersion
        )
        file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let advisoryRawValueObserved26 = file.advisoryRawValue
        XCTAssertEqual(advisoryRawValueObserved26, "4")
        XCTAssertEqual(MetadataExchangeField.contentAdvisory.value(from: file, index: 0, relativeBasePath: nil), "4")

        // Explicit removal of the unknown code is a distinct user intent.
        edit = SingleFileEditModel(from: file)
        edit.clearsUnknownAdvisory = true
        let clearPayload = MetadataEditPayload(edit, comparedTo: file)
        let contentAdvisoryChangedObserved27 = clearPayload.contentAdvisoryChanged
        XCTAssertTrue(contentAdvisoryChangedObserved27)
        _ = try pipeline.writeMetadata(clearPayload, to: url, expectedVersion: file.metadataFileVersion)
        file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let advisoryRawValueObserved28 = file.advisoryRawValue
        XCTAssertNil(advisoryRawValueObserved28)
        let contentAdvisoryObserved29 = file.contentAdvisory
        XCTAssertNil(contentAdvisoryObserved29)
        XCTAssertNil(
            try TagLibMetadataManager.readSnapshot(from: url).structured.mp4Atoms.first { $0.key == "rtng" }
        )
    }

    // MARK: - A11 MP4 exclusive typed fields

    @MainActor
    func testMP4ExclusiveTypedShapesAndReadOnlyRate() async throws {
        let url = try writableFixture(named: "testAudioFile.m4a")
        defer { removeTemporaryFixtureDirectory(containing: url) }
        let pipeline = TagLibAudioMetadataPipeline()
        var file = try await pipeline.loadAudioFile(at: url, id: UUID())

        var edit = SingleFileEditModel(from: file)
        edit.containerValues[.tvSeason] = .integer(0)
        edit.containerValues[.tvEpisode] = .integer(7)
        edit.containerValues[.itunesGapless] = .boolean(false)
        edit.containerValues[.itunesMediaType] = .integer(4) // unknown media-kind code
        edit.containerValues[.director] = .text("Director One")
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(edit, comparedTo: file),
            to: url,
            expectedVersion: file.metadataFileVersion
        )

        file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let debugSnapshot = try TagLibMetadataManager.readSnapshot(from: url)
        let debugValues = AudioFile.containerValues(
            from: debugSnapshot.basic,
            atoms: debugSnapshot.structured.mp4Atoms
        )
        XCTAssertEqual(debugValues[.tvSeason], .integer(0))
        XCTAssertTrue(ContainerMetadataFieldCatalog.readKeys.contains(.tvSeason))
        XCTAssertEqual(ContainerMetadataFieldCatalog.acceptedKinds(for: .tvSeason), [.integer])
        let containerValuesObserved30 = file.containerValues
        XCTAssertEqual(containerValuesObserved30[.tvSeason], .integer(0))
        let containerValuesObserved31 = file.containerValues
        XCTAssertEqual(containerValuesObserved31[.tvEpisode], .integer(7))
        let itunesGaplessObserved = file.containerValues[.itunesGapless]
        XCTAssertEqual(itunesGaplessObserved, .boolean(false))
        let itunesMediaTypeObserved = file.containerValues[.itunesMediaType]
        XCTAssertEqual(itunesMediaTypeObserved, .integer(4))
        let directorObserved = file.containerValues[.director]
        XCTAssertEqual(directorObserved, .text("Director One"))

        let atoms = try TagLibMetadataManager.readSnapshot(from: url).structured.mp4Atoms
        func atomInteger(_ key: String) -> Int? {
            atoms.first { $0.key == key }.flatMap { $0.first ?? Int($0.value) }
        }
        XCTAssertEqual(atomInteger("tvsn"), 0)
        XCTAssertEqual(atomInteger("tves"), 7)
        XCTAssertEqual(atomInteger("pgap"), 0)
        XCTAssertEqual(atomInteger("stik"), 4)

        // RATE is readable but never writable through the semantic profile.
        XCTAssertTrue(ContainerMetadataFieldCatalog.isReadOnly(.rate))
        XCTAssertNil(
            MetadataFieldRegistry.schema(for: .rate)?.writeTarget(for: MetadataNativeFamily.mp4),
            "RATE must not advertise a typed MP4 write target"
        )
        XCTAssertEqual(
            MetadataFieldRegistry.schema(for: .rate)?.capability(for: MetadataNativeFamily.mp4),
            .readOnly
        )

        // Every registered exclusive field has an explicit classification.
        for descriptor in ContainerMetadataFieldCatalog.fields {
            XCTAssertNotNil(
                ContainerMetadataFieldCatalog.presentation(for: descriptor.key),
                descriptor.key.rawValue
            )
        }
        XCTAssertEqual(ContainerMetadataFieldCatalog.fields.filter(\.isMP4Exclusive).count, 26)

        // MKV must not be advertised as writable and the two TV registrations
        // remain gated/unsupported for Matroska.
        XCTAssertFalse(TagLibMetadataManager.isWritableExtension("mkv"))
        XCTAssertEqual(
            MetadataFieldRegistry.schema(for: .tvEpisode)?.capability(for: MetadataNativeFamily.matroska),
            .unsupported
        )
    }

    // MARK: - A12 independent grouping fields and raw DATE

    @MainActor
    func testContentGroupGroupingWorkAreIndependent() async throws {
        let url = try writableFixture(named: "testAudioFile.m4a")
        defer { removeTemporaryFixtureDirectory(containing: url) }
        let pipeline = TagLibAudioMetadataPipeline()
        var file = try await pipeline.loadAudioFile(at: url, id: UUID())

        var edit = SingleFileEditModel(from: file)
        edit.contentGroup = "Content Group"
        edit.grouping = "Grouping"
        edit.work = "Work"
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(edit, comparedTo: file),
            to: url,
            expectedVersion: file.metadataFileVersion
        )
        file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let groupAtoms = try TagLibMetadataManager.readSnapshot(from: url).structured.mp4Atoms
        let contentGroupObserved32 = file.contentGroup
        XCTAssertEqual(
            contentGroupObserved32,
            "Content Group",
            "atoms: " + groupAtoms.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        )
        let groupingObserved33 = file.grouping
        XCTAssertEqual(groupingObserved33, "Grouping")
        let workObserved34 = file.work
        XCTAssertEqual(workObserved34, "Work")

        let properties = try TagLibMetadataManager.readSnapshot(from: url).structured.properties
        func nativeValue(_ key: String) -> String? {
            properties.first { $0.key == key }?.values.first
        }
        XCTAssertEqual(groupAtoms.first { $0.key == "©grp" }?.value, "Content Group")
        XCTAssertEqual(groupAtoms.first { $0.freeformDescription == "GROUPING" }?.value, "Grouping")
        XCTAssertEqual(groupAtoms.first { $0.key == "©wrk" }?.value, "Work")

        // Changing one does not disturb the others.
        edit = SingleFileEditModel(from: file)
        edit.grouping = "New Grouping"
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(edit, comparedTo: file),
            to: url,
            expectedVersion: file.metadataFileVersion
        )
        file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let contentGroupObserved35 = file.contentGroup
        XCTAssertEqual(contentGroupObserved35, "Content Group")
        let groupingObserved36 = file.grouping
        XCTAssertEqual(groupingObserved36, "New Grouping")
        let workObserved37 = file.work
        XCTAssertEqual(workObserved37, "Work")
    }

    @MainActor
    func testRawDateKeepsPropertyMapMeaningAndDoesNotBecomeStandaloneDate() async throws {
        // On MP4 the PropertyMap DATE key is the YEAR projection.
        let mp4 = try writableFixture(named: "testAudioFile.m4a")
        defer { removeTemporaryFixtureDirectory(containing: mp4) }
        _ = try TagLibMetadataManager.applyRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["DATE": ["2004-07-15"]]),
            to: mp4
        )
        let mp4File = try await TagLibAudioMetadataPipeline().loadAudioFile(at: mp4, id: UUID())
        let yearObserved38 = mp4File.year
        XCTAssertEqual(yearObserved38, "2004-07-15")
        let dateObserved39 = mp4File.date
        XCTAssertEqual(dateObserved39, "")

        // On Xiph DATE is the independent native DATE key, not YEAR.
        let flac = try writableFixture(named: "testAudioFile.flac")
        defer { removeTemporaryFixtureDirectory(containing: flac) }
        _ = try TagLibMetadataManager.applyRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["DATE": ["2008-03-04"]]),
            to: flac
        )
        let flacFile = try await TagLibAudioMetadataPipeline().loadAudioFile(at: flac, id: UUID())
        let flacDateObserved = flacFile.date
        XCTAssertEqual(flacDateObserved, "2008-03-04")
        let yearObserved40 = flacFile.year
        XCTAssertEqual(yearObserved40, "")
    }

    @MainActor
    func testDateEditPreservesCustomArraysAndArtwork() async throws {
        let url = try writableFixture(named: "testAudioFile.flac")
        defer { removeTemporaryFixtureDirectory(containing: url) }

        let customValues = ["A; B", "duplicate", "duplicate", "  padded  "]
        _ = try TagLibMetadataManager.applyRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["X-AUDIOMATOR-DATE-PRESERVE": customValues]),
            to: url
        )
        let artwork = try Data(contentsOf: try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "testCover.jpg", withExtension: nil, subdirectory: "Fixtures/Artwork")
                ?? Bundle(for: Self.self).url(forResource: "testCover.jpg", withExtension: nil)
        ))
        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(
                fields: [.year: .text("2004"), .standaloneDate: .text("2008-03-04")],
                artwork: .replace([StructuredArtwork(mimeType: "image/jpeg", data: artwork)])
            ),
            to: url
        )

        let pipeline = TagLibAudioMetadataPipeline()
        let baseline = try await pipeline.loadAudioFile(at: url, id: UUID())
        let artworkDataObserved41 = baseline.artworkData
        XCTAssertEqual(artworkDataObserved41, artwork)
        var edit = SingleFileEditModel(from: baseline)
        edit.year = "2005"
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(edit, comparedTo: baseline),
            to: url,
            expectedVersion: baseline.metadataFileVersion
        )

        let readBack = try await pipeline.loadAudioFile(at: url, id: UUID())
        let readBackYearObserved = readBack.year
        XCTAssertEqual(readBackYearObserved, "2005")
        let dateObserved43 = readBack.date
        XCTAssertEqual(dateObserved43, "2008-03-04")
        let artworkDataObserved44 = readBack.artworkData
        XCTAssertEqual(artworkDataObserved44, artwork)
        let valueMap = try pipeline.rawMetadataValueMap(for: url)
        XCTAssertEqual(valueMap["X-AUDIOMATOR-DATE-PRESERVE"], customValues)
    }

    // MARK: - Provider and exchange execution

    @MainActor
    func testProviderReleaseDateExecutionLeavesOtherDatesAndReloads() async throws {
        let url = try writableFixture(named: "testAudioFile.m4a")
        defer { removeTemporaryFixtureDirectory(containing: url) }
        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [
                .year: .text("2004"),
                .standaloneDate: .text("2008-03-04"),
                .releaseDate: .text("2017-06-09"),
                .originalReleaseDate: .text("1999-11-12"),
            ]),
            to: url
        )
        let pipeline = TagLibAudioMetadataPipeline()
        let baseline = try await pipeline.loadAudioFile(at: url, id: UUID())
        var edit = SingleFileEditModel(from: baseline)
        iTunesTagWriteField.releaseDate.apply("2020-02-03", to: &edit)
        let payload = MetadataEditPayload(edit, comparedTo: baseline)
        XCTAssertEqual(payload.requestedFields, [.releaseDate])
        _ = try pipeline.writeMetadata(payload, to: url, expectedVersion: baseline.metadataFileVersion)

        let reloaded = try await pipeline.loadAudioFile(at: url, id: UUID())
        XCTAssertEqual(reloaded.releaseDate, "2020-02-03")
        XCTAssertEqual(reloaded.year, "2004")
        XCTAssertEqual(reloaded.date, "2008-03-04")
        XCTAssertEqual(reloaded.originalReleaseDate, "1999-11-12")
    }

    @MainActor
    func testExchangeDateEntryAppliesAndWritesOnlyThatDate() async throws {
        let url = try writableFixture(named: "testAudioFile.flac")
        defer { removeTemporaryFixtureDirectory(containing: url) }
        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [
                .year: .text("2004"),
                .standaloneDate: .text("2008-03-04"),
                .releaseDate: .text("2017-06-09"),
                .originalReleaseDate: .text("1999-11-12"),
            ]),
            to: url
        )
        let pipeline = TagLibAudioMetadataPipeline()
        let baseline = try await pipeline.loadAudioFile(at: url, id: UUID())
        var edit = SingleFileEditModel(from: baseline)
        MetadataExchangeField.date.applyImportedValue("2009-01-02", to: &edit)
        let payload = MetadataEditPayload(edit, comparedTo: baseline)
        XCTAssertEqual(payload.requestedFields, [.standaloneDate])
        _ = try pipeline.writeMetadata(payload, to: url, expectedVersion: baseline.metadataFileVersion)

        let reloaded = try await pipeline.loadAudioFile(at: url, id: UUID())
        let dateObserved45 = reloaded.date
        XCTAssertEqual(dateObserved45, "2009-01-02")
        let yearObserved46 = reloaded.year
        XCTAssertEqual(yearObserved46, "2004")
        let releaseDateObserved47 = reloaded.releaseDate
        XCTAssertEqual(releaseDateObserved47, "2017-06-09")
        let originalReleaseDateObserved48 = reloaded.originalReleaseDate
        XCTAssertEqual(originalReleaseDateObserved48, "1999-11-12")
    }

    // MARK: - Conflict groups

    @MainActor
    func testIndependentDateConflictDoesNotBlockYearEdit() async throws {
        let url = try writableFixture(named: "testAudioFile.flac")
        defer { removeTemporaryFixtureDirectory(containing: url) }
        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [
                .year: .text("2004"),
                .standaloneDate: .text("2008-03-04"),
                .releaseDate: .text("2017-06-09"),
            ]),
            to: url
        )
        let pipeline = TagLibAudioMetadataPipeline()
        let baselineFile = try await pipeline.loadAudioFile(at: url, id: UUID())
        let original = try XCTUnwrap(baselineFile.metadataConflictBaseline)

        // External change to DATE only (with the YEAR companion needed by
        // 0.7.0), written in place so the same entry identity is retained.
        try externalChange(
            MetadataPatch(fields: [
                .year: .text("2004"),
                .standaloneDate: .text("2008-03-05"),
            ]),
            at: url
        )

        var draft = SingleFileEditModel(from: baselineFile)
        draft.year = "2005"
        let payload = MetadataEditPayload(draft, comparedTo: baselineFile)
        _ = try MetadataConflictResolver.writeMetadata(
            payload,
            original: original,
            originalFingerprint: try XCTUnwrap(baselineFile.fileFingerprint),
            originalVersion: try XCTUnwrap(baselineFile.metadataFileVersion),
            policy: .mergeNonConflicting,
            pipeline: pipeline,
            url: url
        )

        let reloaded = try await pipeline.loadAudioFile(at: url, id: UUID())
        let yearObserved49 = reloaded.year
        XCTAssertEqual(yearObserved49, "2005")
        let dateObserved50 = reloaded.date
        XCTAssertEqual(dateObserved50, "2008-03-05", "A DATE-only disk edit must not block a YEAR draft")
        let releaseDateObserved51 = reloaded.releaseDate
        XCTAssertEqual(releaseDateObserved51, "2017-06-09")
    }

    @MainActor
    func testSharedNumberPairConflictStillBlocksAComponentDraft() async throws {
        let url = try writableFixture(named: "testAudioFile.flac")
        defer { removeTemporaryFixtureDirectory(containing: url) }
        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [.track: .integer(3), .trackTotal: .integer(12)]),
            to: url
        )
        let pipeline = TagLibAudioMetadataPipeline()
        let baselineFile = try await pipeline.loadAudioFile(at: url, id: UUID())
        let original = try XCTUnwrap(baselineFile.metadataConflictBaseline)

        // External change to the other component of the shared native pair.
        try externalChange(
            MetadataPatch(fields: [.trackTotal: .integer(15)]),
            at: url
        )

        var draft = SingleFileEditModel(from: baselineFile)
        draft.setTrackNumberFieldText("5")
        let payload = MetadataEditPayload(draft, comparedTo: baselineFile)
        XCTAssertThrowsError(
            try MetadataConflictResolver.writeMetadata(
                payload,
                original: original,
                originalFingerprint: try XCTUnwrap(baselineFile.fileFingerprint),
                originalVersion: try XCTUnwrap(baselineFile.metadataFileVersion),
                policy: .mergeNonConflicting,
                pipeline: pipeline,
                url: url
            )
        )
    }

    // MARK: - Helpers

    /// Simulates an external editor writing in place, without replacing the
    /// file entry identity.
    private func externalChange(_ patch: MetadataPatch, at url: URL) throws {
        let copy = url.deletingLastPathComponent()
            .appendingPathComponent("external-\(UUID().uuidString).\(url.pathExtension)")
        try FileManager.default.copyItem(at: url, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        _ = try TagLibMetadataManager.applyMetadataPatch(patch, to: copy)
        let bytes = try Data(contentsOf: copy)
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: bytes)
        try handle.synchronize()
    }

    private func writableFixture(named fixtureName: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(
            bundle.url(forResource: fixtureName, withExtension: nil, subdirectory: "Fixtures/Audio")
                ?? bundle.url(forResource: fixtureName, withExtension: nil)
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(fixtureName)
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    private func removeTemporaryFixtureDirectory(containing url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
