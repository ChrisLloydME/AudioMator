
import XCTest
import Foundation
@testable import SwiftTagLib

/// While rudimentary it's still should be sensitive to changes
final class PerformanceTests: XCTestCase {
    func testMetadataReading() throws {
        let fileURLs = AudioSample.supported.map(\.url)
        try XCTSkipIf(fileURLs.isEmpty, "no file URLs for test")

        measure(metrics: [
            XCTClockMetric(),
            XCTMemoryMetric(),
            XCTCPUMetric(),
        ]) {
            for url in fileURLs {
                guard let _ = try? AudioFile(url: url) else {
                    XCTFail("failed to read file at: \(url.path)")
                    return
                }
            }
        }
    }

    func testMetadataReadingSkippingPictures() throws {
        let fileURLs = AudioSample.supported.map(\.url)
        try XCTSkipIf(fileURLs.isEmpty, "no file URLs for test")

        measure(metrics: [
            XCTClockMetric(),
            XCTMemoryMetric(),
            XCTCPUMetric(),
        ]) {
            for url in fileURLs {
                guard let _ = try? AudioFile(url: url, options: [.skipPictures]) else {
                    XCTFail("failed to read file at: \(url.path)")
                    return
                }
            }
        }
    }

    func testMetadataWriting() throws {
        let fileURLs = AudioSample.supported.map(\.url)
        try XCTSkipIf(fileURLs.isEmpty, "no file URLs for test")

        typealias TestPair = (source: AudioFile, copy: AudioFile)
        let testPairs: [TestPair] = try fileURLs.compactMap { url in
            let directory = Constants.Directory.test()
            let destination = directory.appending(path: url.lastPathComponent)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            guard let source = try? AudioFile(url: url) else {
                XCTFail("failed to read file at: \(url.path)")
                return .none
            }
            guard let copy = try? AudioFile(url: destination) else {
                XCTFail("failed to read file at: \(destination.path)")
                return .none
            }
            return (source, copy)
        }
        defer {
            for url in testPairs.map(\.copy.url) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        measure(metrics: [
            XCTClockMetric(),
            XCTMemoryMetric(),
            XCTCPUMetric(),
        ]) {
            for (source, copy) in testPairs {
                var copy = copy
                copy.metadata = source.metadata
                try? copy.write()
            }
        }
    }

    func testMetadataCxxRepresentationTransform() throws {
        let fileURLs = AudioSample.supported.map(\.url)
        try XCTSkipIf(fileURLs.isEmpty, "no file URLs for test")

        let files: [AudioFile] = fileURLs.compactMap { url in
            guard let file = try? AudioFile(url: url) else {
                XCTFail("failed to read file at: \(url.path)")
                return .none
            }
            return file
        }

        measure(metrics: [
            XCTClockMetric(),
            XCTMemoryMetric(),
            XCTCPUMetric(),
        ]) {
            for file in files {
                let _ = file.metadata.cxxRepresentation
            }
        }
    }

    func testFormatDetection() throws {
        let fileURLs = AudioSample.supported.map(\.url)
        try XCTSkipIf(fileURLs.isEmpty, "no file URLs for test")

        measure(metrics: [
            XCTClockMetric(),
            XCTMemoryMetric(),
            XCTCPUMetric(),
        ]) {
            for url in fileURLs {
                guard let _ = try? AudioFile.Format.Detector.format(at: url) else {
                    XCTFail("failed to detect format at: \(url.path)")
                    return
                }
            }
        }
    }
}

// MARK: - Convenience
fileprivate extension PerformanceTests {
    func urls(
        in directoryPath: String,
        ignoredFileNames: Set<String> = [
            ".DS_Store",
            ".localized",
        ]
    ) throws -> [URL] {
        let fileManager: FileManager = .default
        var isDirectory: ObjCBool = false
        let directoryExists = fileManager.fileExists(atPath: directoryPath, isDirectory: &isDirectory)
        guard directoryExists, isDirectory.boolValue else {
            return []
        }
        let directoryURL = URL(fileURLWithPath: directoryPath)
        return try fileManager.contentsOfDirectory(atPath: directoryPath).map {
            directoryURL.appending(component: $0)
        }
    }
}
