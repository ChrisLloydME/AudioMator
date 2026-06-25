import Foundation
import XCTest

final class SensitiveLoggingPolicyTests: XCTestCase {
    func testMetadataPipelineContainsNoUnconditionalMetadataValueLogger() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryURL
            .appendingPathComponent("AudioMator/Domain/MetadataEditing/AudioMetadataPipeline.swift")
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
        XCTAssertFalse(source.contains("warnings.map"))
    }
}
