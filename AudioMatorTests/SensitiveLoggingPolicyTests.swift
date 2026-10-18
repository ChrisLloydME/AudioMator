import Foundation
import XCTest

final class SensitiveLoggingPolicyTests: XCTestCase {
    func testMetadataPipelineContainsNoUnconditionalMetadataValueLogger() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryURL
            .appendingPathComponent("AudioMator/Infrastructure/TagLib/TagLibAudioMetadataPipeline.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("logMetadataWrite("))
        XCTAssertFalse(source.contains("[AudioMator] Will write metadata"))
    }

    func testMetadataWriteViewModelDoesNotPrintWarningPayloads() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryURL
            .appendingPathComponent("AudioMator/Features/Main/ViewModels/AudioViewModel+MetadataWrite.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("Metadata write completed with warning"))
        XCTAssertFalse(source.contains("NSLog("))
    }

    func testAppSourceDoesNotUseDiagnosticConsoleLogging() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = repositoryURL.appendingPathComponent("AudioMator")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: appSourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))

        var offenders: [String] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if Self.containsDiagnosticConsoleLogging(in: source) {
                offenders.append(fileURL.path.replacingOccurrences(of: repositoryURL.path + "/", with: ""))
            }
        }

        XCTAssertTrue(offenders.isEmpty, "Diagnostic console logging found in app source: \(offenders.sorted())")
    }

    func testDiagnosticLoggerDetectorFailsClosedAndCoversLoggerAPIs() {
        XCTAssertTrue(Self.containsDiagnosticConsoleLogging(in: "print(\"value\")"))
        XCTAssertTrue(Self.containsDiagnosticConsoleLogging(in: "Logger(subsystem: \"x\", category: \"y\")"))
        XCTAssertTrue(Self.containsDiagnosticConsoleLogging(in: "os_log(\"value\")"))
        XCTAssertFalse(Self.containsDiagnosticConsoleLogging(in: "let sprint = 1"))
    }

    private static func containsDiagnosticConsoleLogging(in source: String) -> Bool {
        let pattern = #"(?<![A-Za-z0-9_])(print|debugPrint|NSLog|os_log|Logger)\s*\("#
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            // A broken detector must not silently report that the source is clean.
            return true
        }
        return expression.firstMatch(in: source, range: range) != nil
    }
}
