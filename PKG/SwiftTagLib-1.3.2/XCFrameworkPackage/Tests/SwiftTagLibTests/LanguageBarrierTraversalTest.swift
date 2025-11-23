
import Foundation
import Testing
@testable import SwiftTagLib

/// Just a sanity check to confirm correct conversion of Metadata aggregate from Swift to C++ and back to Swift.
@Suite("Language Barrier Traversal Test")
struct LanguageBarrierTraversalTest {
    @Test("Empty metadata remains empty")
    func emptyMetadataRemainsEmpty() {
        let metadata = AudioFile.Metadata()
        let converted = AudioFile.Metadata(cxxRepresentation: metadata.cxxRepresentation)
        #expect(metadata == converted)
    }

    @Test("String properties change persits", arguments: AudioFile.Metadata.stringProperties)
    func stringPropertyChangePersists(property: WritableKeyPath<AudioFile.Metadata, String?>) {
        /// some
        var metadata = AudioFile.Metadata()
        metadata[keyPath: property] = UUID().uuidString
        var converted = AudioFile.Metadata(cxxRepresentation: metadata.cxxRepresentation)
        #expect(metadata[keyPath: property] == converted[keyPath: property], "\(property)")
        /// none
        metadata[keyPath: property] = .none
        converted = AudioFile.Metadata(cxxRepresentation: metadata.cxxRepresentation)
        #expect(metadata[keyPath: property] == converted[keyPath: property], "\(property)")
    }

    @Test("Int properties change persits", arguments: AudioFile.Metadata.intProperties)
    func intPropertyChangePersists(property: WritableKeyPath<AudioFile.Metadata, Int32?>) {
        /// some
        var metadata = AudioFile.Metadata()
        metadata[keyPath: property] = Int32.random(in: Int32(UInt16.min) ... Int32(UInt16.max))
        var converted = AudioFile.Metadata(cxxRepresentation: metadata.cxxRepresentation)
        #expect(metadata[keyPath: property] == converted[keyPath: property])
        /// none
        metadata[keyPath: property] = .none
        converted = AudioFile.Metadata(cxxRepresentation: metadata.cxxRepresentation)
        #expect(metadata[keyPath: property] == converted[keyPath: property])
    }

    @Test("Release date change persits")
    func releaseDateChangePersists() {
        /// some
        var metadata = AudioFile.Metadata()
        metadata.releaseDate = "\(Int.random(in: 1960 ... 2024))"
        var converted = AudioFile.Metadata(cxxRepresentation: metadata.cxxRepresentation)
        #expect(metadata.releaseDate == converted.releaseDate)
        /// none
        metadata.releaseDate = .none
        converted = AudioFile.Metadata(cxxRepresentation: metadata.cxxRepresentation)
        #expect(metadata.releaseDate == converted.releaseDate)
    }

    @Test("Compilation change persits")
    func compilationChangePersists() {
        var metadata = AudioFile.Metadata()
        metadata.compilation = true
        var converted = AudioFile.Metadata(cxxRepresentation: metadata.cxxRepresentation)
        #expect(metadata.compilation == converted.compilation)
        metadata.compilation = false
        converted = AudioFile.Metadata(cxxRepresentation: metadata.cxxRepresentation)
        #expect(metadata.compilation == converted.compilation)
    }

    @Test("Attached pictures change persists")
    func attachedPicturesChangePersists() {

    }

    @Test("Additional metadata change persists")
    func additionalMetadataChangePersists() {

    }
}
