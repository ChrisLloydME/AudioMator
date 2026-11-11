import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class InspectorDirtyStateTests: XCTestCase {
    @MainActor
    private func model(_ files: [AudioFile]) -> AudioViewModel {
        let vm = AudioViewModelTestFactory.make(metadataPipeline: TagLibAudioMetadataPipeline())
        vm.mergeQuickImportFiles(files)
        vm.setSelectedAudioIDs(Set(files.map(\.id)))
        return vm
    }

    @MainActor
    func testReenteringEverySharedBatchValueDoesNotBecomeDirty() {
        let files = ["a", "b"].map { name in
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/dirty-\(name).m4a"),
                title: "Shared", album: "Album", track: 7, trackTotal: 12,
                disc: 2, discTotal: 3, trackNumberText: "07 / 12", discNumberText: "02 / 03")
        }
        let vm = model(files)
        for field in MultiFileEditableTextField.allCases {
            vm.cancelEditing()
            let original = vm.multiEdit!.text(for: field)
            vm.multiEdit?.setText(original, for: field)
            XCTAssertFalse(vm.hasUnsavedInspectorChanges, "Same value for \(field)")
        }
    }

    @MainActor
    func testBatchEditThenRevertDoesNotRequestDiscardConfirmation() {
        let vm = model(["a", "b"].map { name in
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/revert-\(name).m4a"), album: "Shared")
        })
        vm.multiEdit?.setText("Changed", for: .album)
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        vm.multiEdit?.setText("Shared", for: .album)
        var confirmations = 0
        var transitions = 0
        ContentView.performSidebarSelectionChange(hasUnsavedInspectorChanges: vm.hasUnsavedInspectorChanges,
            suppressesDiscardWarning: false, requestDiscardConfirmation: { _ in confirmations += 1 },
            discardInspectorEdits: { XCTFail("No draft should be discarded") }, commitSelection: { transitions += 1 })
        XCTAssertEqual(confirmations, 0)
        XCTAssertEqual(transitions, 1)
    }

    @MainActor
    func testBatchChoosingExistingAdvisoryAndRemovingAbsentArtworkAreClean() {
        let vm = model(["a", "b"].map { name in
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/advisory-\(name).m4a"), contentAdvisory: .clean)
        })
        vm.multiEdit?.explicitEditState = .set(.clean)
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        vm.multiEdit?.setArtworkEditAction(.remove)
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        vm.multiEdit?.explicitEditState = .set(.explicit)
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testMixedBlankIsAnExplicitClearAndStillRequiresConfirmation() {
        let vm = model([AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/mixed-a.m4a"), title: "A"),
                        AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/mixed-b.m4a"), title: "B")])
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        vm.multiEdit?.setText("", for: .title)
        XCTAssertTrue(vm.hasUnsavedInspectorChanges, "Mixed placeholder must not hide explicit clears")
        vm.cancelEditing()
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testUnchangedSplitNumberBindingPreservesStoredRepresentation() {
        let file = AudioFileTestFactory.make(track: 7, trackTotal: 12, disc: 2, discTotal: 3,
                                            trackNumberText: "07 / 12", discNumberText: "02 / 03")
        var edit = SingleFileEditModel(from: file)
        edit.setTrackNumberFieldText(edit.trackNumberFieldText)
        edit.setTrackTotalFieldText(edit.trackTotalFieldText)
        edit.setDiscNumberFieldText(edit.discNumberFieldText)
        edit.setDiscTotalFieldText(edit.discTotalFieldText)
        XCTAssertEqual(edit.trackNumberText, file.trackNumberText)
        XCTAssertEqual(edit.discNumberText, file.discNumberText)
        XCTAssertFalse(edit.hasUnsavedChanges(comparedTo: file))
        edit.setTrackNumberFieldText("8")
        XCTAssertTrue(edit.hasUnsavedChanges(comparedTo: file))
        edit.setTrackNumberFieldText("07")
        XCTAssertFalse(edit.hasUnsavedChanges(comparedTo: file), "Undo restores the displayed component intent")
        edit.setDiscTotalFieldText("4")
        XCTAssertTrue(edit.hasUnsavedChanges(comparedTo: file))
        edit.setDiscTotalFieldText("03")
        XCTAssertFalse(edit.hasUnsavedChanges(comparedTo: file))
        edit.setTrackNumberFieldText("7")
        XCTAssertTrue(edit.hasUnsavedChanges(comparedTo: file), "Changed zero-padding remains text intent")
    }

    @MainActor
    func testRemovingAlreadyAbsentContainerValueIsCleanButFalseAndZeroArePresent() {
        let files = ["a", "b"].map { name in
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/container-\(name).m4a"))
        }
        let vm = model(files)
        vm.multiEdit?.setContainerValue(.text(""), for: .tvShow)
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        vm.multiEdit?.setContainerValue(.boolean(false), for: .itunesGapless)
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        vm.cancelEditing()
        vm.multiEdit?.setContainerValue(.integer(0), for: .tvSeason)
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        var edit = SingleFileEditModel(from: files[0])
        edit.containerValues[.tvShow] = .text("")
        XCTAssertFalse(edit.hasUnsavedChanges(comparedTo: files[0]))
    }

    @MainActor
    func testCleanReloadFollowsNewBaselineButDirtyReloadRetainsDraft() {
        let file = AudioFileTestFactory.make(title: "Original")
        let vm = model([file])
        vm.replaceLoadedFile(AudioFileTestFactory.make(id: file.id, url: file.url, title: "External"))
        XCTAssertEqual(vm.edit?.title, "External")
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        vm.edit?.title = "Draft"
        vm.replaceLoadedFile(AudioFileTestFactory.make(id: file.id, url: file.url, title: "External again"))
        XCTAssertEqual(vm.edit?.title, "Draft")
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
    }
}
