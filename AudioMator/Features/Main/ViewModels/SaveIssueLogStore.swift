import Foundation
import Combine

struct SaveIssueLogEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let summary: String
    let operation: BatchMetadataOperationKind
    let severity: Severity
    let issues: [Issue]

    enum Severity: String, Codable, Equatable {
        case warning
        case failure
    }

    struct Issue: Codable, Equatable, Identifiable {
        let id: UUID
        let fileName: String
        let messages: [String]

        init(id: UUID = UUID(), fileName: String, messages: [String]) {
            self.id = id
            self.fileName = fileName
            self.messages = messages
        }
    }

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String,
        summary: String,
        operation: BatchMetadataOperationKind,
        severity: Severity,
        issues: [Issue]
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.summary = summary
        self.operation = operation
        self.severity = severity
        self.issues = issues
    }
}

@MainActor
final class SaveIssueLogStore: ObservableObject {
    static let defaultLimit = 200

    @Published private(set) var entries: [SaveIssueLogEntry] = []

    private let fileURL: URL
    private let limit: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    convenience init(limit: Int = 200) {
        self.init(fileURL: Self.defaultFileURL(), limit: limit)
    }

    init(fileURL: URL, limit: Int = 200) {
        self.fileURL = fileURL
        self.limit = limit

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()
    }

    func record(summary: BatchMetadataOperationSummary, date: Date = Date()) {
        guard summary.hudStyle != .success else { return }

        let sourceIssues = summary.failureIssues.isEmpty ? summary.warningIssues : summary.failureIssues
        guard !sourceIssues.isEmpty else { return }

        let entry = SaveIssueLogEntry(
            date: date,
            title: summary.hudTitle,
            summary: summary.hudSubtitle,
            operation: summary.operation,
            severity: summary.failureIssues.isEmpty ? .warning : .failure,
            issues: sourceIssues.map { issue in
                SaveIssueLogEntry.Issue(fileName: issue.fileName, messages: issue.messages)
            }
        )

        append(entry)
    }

    func recordSingleIssue(
        title: String,
        subtitle: String,
        fileName: String,
        messages: [String],
        severity: SaveIssueLogEntry.Severity,
        date: Date = Date()
    ) {
        let trimmedMessages = messages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmedMessages.isEmpty else { return }

        let entry = SaveIssueLogEntry(
            date: date,
            title: title,
            summary: subtitle,
            operation: .write,
            severity: severity,
            issues: [
                SaveIssueLogEntry.Issue(fileName: fileName, messages: trimmedMessages)
            ]
        )

        append(entry)
    }

    func clear() {
        entries = []
        persist()
    }

    private func append(_ entry: SaveIssueLogEntry) {
        entries.insert(entry, at: 0)

        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }

        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            entries = try decoder.decode([SaveIssueLogEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to persist save issue log: \(error)")
        }
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("AudioMator", isDirectory: true)
            .appendingPathComponent("SaveIssueLog.json")
    }
}
