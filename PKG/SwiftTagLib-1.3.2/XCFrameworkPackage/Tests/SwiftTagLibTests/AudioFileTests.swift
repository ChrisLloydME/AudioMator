
import Foundation
import Testing
@testable import SwiftTagLib

@Suite("Audio File Tests", .serialized)
struct AudioFileTests {
    @Test("Reading from same file twice should produce exactly same metadata.", arguments: AudioSample.supported)
    func readingMetadata(sample: AudioSample) {
        do {
            let metadata = try AudioFile(url: sample.url).metadata
            let secondReadMetadata = try AudioFile(url: sample.url).metadata
            #expect(metadata.hashValue == secondReadMetadata.hashValue, "reading metadata from same file gives exactly same metadata; \(metadata.tagSource)")
            guard metadata.hashValue != secondReadMetadata.hashValue else { return }
            func compare<T: Equatable & Hashable>(_ keyPaths: [KeyPath<AudioFile.Metadata, T>]) {
                for keyPath in keyPaths {
                    let first = metadata[keyPath: keyPath]
                    let second = secondReadMetadata[keyPath: keyPath]
                    #expect(first == second, "should be same: \(keyPath)")
                }
            }
            compare(AudioFile.Metadata.stringProperties)
            compare(AudioFile.Metadata.intProperties)
            compare(AudioFile.Metadata.dateProperties)
            compare(AudioFile.Metadata.boolProperties)
            #expect(metadata.additional == secondReadMetadata.additional, "same additional metadata")
        } catch {
            Issue.record(error, "file: \(sample.filename)")
        }
    }

    @Test("Overwriting metadata with metadata read from file, no metadata should change.", arguments: AudioSample.supported)
    func sameSelfOverwrite(source: AudioSample) throws {
        let directory = Constants.Directory.test()
        let destination = directory.appending(path: source.filename)
        setup: do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source.url, to: destination)
        }
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            let original = try AudioFile(url: source.url)
            var copy = try AudioFile(url: destination)
            #expect(original.metadata.hashValue == copy.metadata.hashValue, "copy of file has exactly same metadata; \(copy.metadata.tagSource)")
            try copy.write()
            copy = try AudioFile(url: destination)
            #expect(original.metadata.hashValue == copy.metadata.hashValue, "metadata should be same; \(copy.metadata.tagSource)")
            guard original.metadata.hashValue != copy.metadata.hashValue else { return }
            func compare<T: Equatable & Hashable>(_ keyPaths: [KeyPath<AudioFile.Metadata, T>]) {
                for keyPath in keyPaths {
                    let old = original.metadata[keyPath: keyPath]
                    let new = copy.metadata[keyPath: keyPath]
                    #expect(old == new, "should be same: \(keyPath)")
                }
            }
            compare(AudioFile.Metadata.stringProperties)
            compare(AudioFile.Metadata.intProperties)
            compare(AudioFile.Metadata.dateProperties)
            compare(AudioFile.Metadata.boolProperties)
            #expect(original.metadata.attachedPictures.count == copy.metadata.attachedPictures.count, "same amount of attached pictures")
            #expect(original.metadata.attachedPictures.sorted() == copy.metadata.attachedPictures.sorted(), "same attached pictures")
            #expect(original.metadata.additional == copy.metadata.additional, "same additional metadata")
        } catch {
            Issue.record(error, "file: \(source.filename)")
        }
    }

    @Test("Writing metadata, all fields read should match what was written.", arguments: AudioSample.supported)
    func writingMetadata(source: AudioSample) throws {
        let directory = Constants.Directory.test()
        let destination = directory.appending(path: source.filename)
        setup: do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source.url, to: destination)
        }
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            let original = try AudioFile(url: source.url)
            var copy = try AudioFile(url: destination)
            #expect(original.metadata.hashValue == copy.metadata.hashValue, "copy of file has exactly same metadata;  \(original.metadata.tagSource)")
            let metadata: AudioFile.Metadata = .mocked
            copy.metadata = metadata
            try copy.write()
            copy = try AudioFile(url: destination)
            #expect(metadata.hashValue == copy.metadata.hashValue, "metadata written and read should be same; \(copy.metadata.tagSource)")
            guard metadata.hashValue != copy.metadata.hashValue else { return }
            func compare<T: Equatable & Hashable>(_ keyPaths: [KeyPath<AudioFile.Metadata, T>]) {
                for keyPath in keyPaths {
                    let set = metadata[keyPath: keyPath]
                    let read = copy.metadata[keyPath: keyPath]
                    #expect(set == read, "should be same: \(keyPath)")
                }
            }
            compare(AudioFile.Metadata.stringProperties)
            compare(AudioFile.Metadata.intProperties)
            compare(AudioFile.Metadata.dateProperties)
            compare(AudioFile.Metadata.boolProperties)
            #expect(metadata.attachedPictures.count == copy.metadata.attachedPictures.count, "same amount of attached pictures")
            #expect(metadata.attachedPictures.sorted() == copy.metadata.attachedPictures.sorted(), "same attached pictures")
            #expect(metadata.additional == copy.metadata.additional, "same additional metadata")
        } catch {
            Issue.record(error, "file: \(source.filename)")
        }
    }

    @Test("Erasing metadata, all fields should be empty.", arguments: AudioSample.supported)
    func erasingMetadata(source: AudioSample) throws {
        let directory = Constants.Directory.test()
        let destination = directory.appending(path: source.filename)
        setup: do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source.url, to: destination)
        }
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            let original = try AudioFile(url: source.url)
            var copy = try AudioFile(url: destination)
            #expect(original.metadata.hashValue == copy.metadata.hashValue, "copy of file has exactly same metadata; \(copy.metadata.tagSource)")
            let metadata: AudioFile.Metadata = .init()
            copy.metadata = metadata
            try copy.write()
            copy = try AudioFile(url: destination)
            #expect(metadata.hashValue == copy.metadata.hashValue, "metadata written and read should be same; \(copy.metadata.tagSource)")
            guard metadata.hashValue != copy.metadata.hashValue else { return }
            func compare<T: Equatable & Hashable>(_ keyPaths: [KeyPath<AudioFile.Metadata, T>]) {
                for keyPath in keyPaths {
                    let none = metadata[keyPath: keyPath]
                    let read = copy.metadata[keyPath: keyPath]
                    #expect(none == read, "should be same: \(keyPath)")
                }
            }
            compare(AudioFile.Metadata.stringProperties)
            compare(AudioFile.Metadata.intProperties)
            compare(AudioFile.Metadata.dateProperties)
            compare(AudioFile.Metadata.boolProperties)
            #expect(copy.metadata.attachedPictures.isEmpty, "no attached pictures")
            #expect(copy.metadata.additional.isEmpty, "no additional metadata")
        } catch {
            Issue.record(error, "file: \(source.filename)")
        }
    }

//    @Test(arguments: [Sample.supported])
//    func metadataTransplant(urls: [URL]) throws {
//        var urls = Set(urls)
//        guard let donorURL = urls.randomElement() else { return }
//        urls.remove(donorURL)
//
//        let directory = Constants.rootDirectory().appending(path: UUID().uuidString)
//        setup: do {
//            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
//        }
//        var recipients: [URL] = []
//
//        for url in urls {
//            let recipient = directory.appending(path: url.lastPathComponent)
//            try FileManager.default.copyItem(at: url, to: recipient)
//            recipients.append(recipient)
//        }
//        do {
//            let donor = try #require(AudioFile(url: donorURL).metadata)
//            for recipient in recipients {
//                do {
//                    var audio = try AudioFile(url: recipient)
//                    audio.metadata = donor
//                    try audio.write()
//                    let metadata = try #require(AudioFile(url: recipient).metadata)
//                    let difference = metadata.propertiesDiff(from: donor)
//                    if !difference.isEmpty {
//                        Issue.record("donor: \(donorURL.lastPathComponent); recipient: \(recipient.lastPathComponent)")
//                    }
//                    for change in difference {
//                        switch change {
//                            case .insert(_, let element, _):
//                                Issue.record("removed value persisted for key: \(element.key), value: \(element.value); in file: \(recipient.lastPathComponent)")
//                            case .remove(_, let element, _):
//                                Issue.record("missing/wrong value key: \(element.key), value: \(element.value); in file: \(recipient.lastPathComponent)")
//                        }
//                    }
////                    #expect(difference.isEmpty)
//                } catch {
//                    Issue.record(error, "file: \(recipient.lastPathComponent)")
//                }
//            }
//        } catch {
//            Issue.record(error, "donor file: \(donorURL.lastPathComponent)")
//        }
//        cleanup: do {
//            try FileManager.default.removeItem(at: directory)
//        }
//    }
}
