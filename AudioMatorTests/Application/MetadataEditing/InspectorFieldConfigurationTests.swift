import XCTest
@testable import AudioMator

@MainActor
final class InspectorFieldConfigurationTests: XCTestCase {
    private func withPreferences(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "InspectorFieldConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    func testFreshInspectorUsesCuratedDefaultsAndOptionalDatesStayIndependent() {
        withPreferences { defaults in
            let state = SharedState(userDefaults: defaults)
            let expected: Set<InspectorMetadataField> = [.title, .artist, .album, .composer,
                .genre, .year, .trackNumber, .totalTracks, .discNumber, .totalDiscs,
                .comment, .albumArtist, .releaseDate, .publisher, .copyright, .explicit, .credits]
            XCTAssertEqual(state.visibleInspectorMetadataFields, expected)
            XCTAssertEqual(Set(InspectorMetadataField.configurableFields), Set(InspectorMetadataField.allCases))
            XCTAssertEqual(InspectorMetadataField.configurableFields.count, Set(InspectorMetadataField.configurableFields).count)
            XCTAssertFalse(state.visibleInspectorMetadataFields.contains(.date))
            XCTAssertFalse(state.visibleInspectorMetadataFields.contains(.originalReleaseDate))
            state.visibleInspectorMetadataFields = [.year, .date, .releaseDate, .originalReleaseDate]
            XCTAssertEqual(state.orderedVisibleInspectorMetadataFields, [.year, .date, .releaseDate, .originalReleaseDate])
        }
    }

    func testSettingsPersistExactChoicesWithoutReenablingHiddenFields() {
        withPreferences { defaults in
            defaults.set(["title", "date", "unknownFutureField"], forKey: "inspector.metadata.visibleFields")
            let state = SharedState(userDefaults: defaults)
            XCTAssertEqual(state.orderedVisibleInspectorMetadataFields, [.title, .date])
            state.visibleInspectorMetadataFields = [.album, .originalReleaseDate]
            XCTAssertEqual(SharedState(userDefaults: defaults).orderedVisibleInspectorMetadataFields, [.album, .originalReleaseDate])
            XCTAssertEqual(Set(defaults.stringArray(forKey: "inspector.metadata.visibleFields")!), ["album", "originalReleaseDate"])
        }
    }

    func testExistingExpandedPreferencesArePreservedAndEmptyPreferencesRecover() {
        withPreferences { defaults in
            defaults.set(InspectorMetadataField.allCases.map(\.rawValue), forKey: "inspector.metadata.visibleFields")
            XCTAssertEqual(SharedState(userDefaults: defaults).visibleInspectorMetadataFields, Set(InspectorMetadataField.allCases))
            defaults.set([], forKey: "inspector.metadata.visibleFields")
            XCTAssertEqual(SharedState(userDefaults: defaults).visibleInspectorMetadataFields, Set(InspectorMetadataField.defaultVisibleFields))
        }
    }

    func testVisibilityChangesPreserveSingleAndMultiSelectionDrafts() {
        withPreferences { defaults in
            let state = SharedState(userDefaults: defaults)
            let files = ["first", "second"].map {
                AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/\($0).m4a"), title: "Original", album: "Original album")
            }
            let vm = AudioViewModelTestFactory.make(metadataPipeline: TagLibAudioMetadataPipeline())
            vm.mergeQuickImportFiles(files)
            vm.setSelectedAudioIDs([files[0].id])
            vm.edit?.album = "Single draft"
            state.visibleInspectorMetadataFields = [.title]
            XCTAssertEqual(vm.edit?.album, "Single draft")
            XCTAssertTrue(vm.hasUnsavedInspectorChanges)
            vm.cancelEditing()
            vm.setSelectedAudioIDs(Set(files.map(\.id)))
            vm.multiEdit?.setText("Batch draft", for: .album)
            state.visibleInspectorMetadataFields = [.artist]
            XCTAssertEqual(vm.multiEdit?.text(for: .album), "Batch draft")
            XCTAssertTrue(vm.hasUnsavedInspectorChanges)
            state.visibleInspectorMetadataFields = [.album]
            XCTAssertEqual(vm.multiEdit?.text(for: .album), "Batch draft")
        }
    }

    func testInspectorAndSettingsHaveOneControlledFieldRoute() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let pane = try String(contentsOf: root.appendingPathComponent("AudioMator/Features/Main/Views/InspectorPane.swift"), encoding: .utf8)
        let settings = try String(contentsOf: root.appendingPathComponent("AudioMator/Features/Settings/Views/SettingsView.swift"), encoding: .utf8)
        XCTAssertTrue(pane.contains("state.orderedVisibleInspectorMetadataFields"))
        XCTAssertEqual(pane.components(separatedBy: "let fields = visibleInspectorMetadataFields").count - 1, 2,
                       "Single and multi selection must both use the preference-controlled projection")
        XCTAssertFalse(pane.contains("ContainerMetadataFieldCatalog"), "Container fields belong in Metadata Editor")
        XCTAssertFalse(pane.contains("containerFieldsSection"))
        XCTAssertTrue(settings.contains("ForEach(InspectorMetadataField.configurableFields)"))
    }
}
