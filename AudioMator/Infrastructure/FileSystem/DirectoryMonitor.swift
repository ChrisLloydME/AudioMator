import Foundation
import Darwin

struct DirectoryMonitoringPlan: Equatable, Sendable {
    let monitoredURLs: [URL]
    let totalDirectoryCount: Int
    let omittedByLimitCount: Int

    nonisolated static func make(
        directories: [URL],
        rootURL: URL,
        limit: Int
    ) -> DirectoryMonitoringPlan {
        let boundedLimit = max(1, limit)
        var urlsByPath: [String: URL] = [:]

        for url in directories + [rootURL] {
            let normalizedURL = url.standardizedFileURL
            let path = FileSystemPathSemantics.key(for: normalizedURL)
            urlsByPath[path] = normalizedURL
        }

        let normalizedRootURL = rootURL.standardizedFileURL
        let normalizedRootPath = FileSystemPathSemantics.key(for: normalizedRootURL)
        let nestedURLs = urlsByPath
            .filter { $0.key != normalizedRootPath }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.value)
        let orderedURLs = [urlsByPath[normalizedRootPath] ?? normalizedRootURL] + nestedURLs
        let monitoredURLs = Array(orderedURLs.prefix(boundedLimit))

        return DirectoryMonitoringPlan(
            monitoredURLs: monitoredURLs,
            totalDirectoryCount: orderedURLs.count,
            omittedByLimitCount: max(0, orderedURLs.count - monitoredURLs.count)
        )
    }
}

struct DirectoryMonitoringStatus: Equatable, Sendable {
    let totalDirectoryCount: Int
    let monitoredDirectoryCount: Int
    let omittedByLimitCount: Int
    let failedToOpenCount: Int
    let scanFailureCount: Int
    let metadataReadFailureCount: Int

    var isDegraded: Bool {
        omittedByLimitCount > 0 || failedToOpenCount > 0 || scanFailureCount > 0 || metadataReadFailureCount > 0
    }

    var message: String {
        guard isDegraded else {
            return "Automatic refresh is monitoring all \(monitoredDirectoryCount) folders."
        }

        var reasons: [String] = []
        if omittedByLimitCount > 0 {
            reasons.append(omittedByLimitCount == 1 ? String(localized: "1 folder exceeds the monitoring limit") : String(localized: "\(omittedByLimitCount) folders exceed the monitoring limit"))
        }
        if failedToOpenCount > 0 {
            reasons.append(failedToOpenCount == 1 ? String(localized: "1 folder couldn’t be opened") : String(localized: "\(failedToOpenCount) folders couldn't be opened"))
        }
        if scanFailureCount > 0 {
            reasons.append(scanFailureCount == 1
                ? String(localized: "1 folder scan couldn’t be completed")
                : String(localized: "\(scanFailureCount) folder scans couldn't be completed"))
        }
        if metadataReadFailureCount > 0 {
            reasons.append(metadataReadFailureCount == 1
                ? String(localized: "1 audio file couldn’t be read")
                : String(localized: "\(metadataReadFailureCount) audio files couldn't be read"))
        }

        var message = String(localized: "Automatic refresh is active for \(monitoredDirectoryCount) of \(totalDirectoryCount) folders. \(reasons.joined(separator: ", ")).")
        if omittedByLimitCount > 0 || failedToOpenCount > 0 {
            message += " " + String(localized: "Changes in unmonitored subfolders may not appear until a scan succeeds.")
        }
        if metadataReadFailureCount > 0 {
            message += " " + String(localized: "Previously loaded metadata is still shown where available.")
        }
        if scanFailureCount > 0 {
            message += " " + String(localized: "The previous file list will stay visible until a scan completes successfully.")
        }
        return message
    }
}

final class DirectoryMonitor {
    private let queue: DispatchQueue
    private let eventHandler: @Sendable () -> Void

    private var fileDescriptor: CInt
    private var source: DispatchSourceFileSystemObject?

    init?(
        url: URL,
        queue: DispatchQueue = DispatchQueue(label: "AudioMator.DirectoryMonitor", qos: .utility),
        eventHandler: @escaping @Sendable () -> Void
    ) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        self.queue = queue
        self.eventHandler = eventHandler
        self.fileDescriptor = descriptor
    }

    // Keep the non-isolated fallback for toolchains that predate stable
    // isolated deinitializers.
    #if compiler(>=6.2)
    isolated deinit {
        stop()
    }
    #else
    deinit {
        stop()
    }
    #endif

    func start() {
        guard source == nil, fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: queue
        )

        source.setEventHandler(handler: eventHandler)
        source.setCancelHandler { [descriptor = fileDescriptor] in
            guard descriptor >= 0 else { return }
            close(descriptor)
        }

        self.source = source
        source.resume()
    }

    func stop() {
        if let source {
            self.source = nil
            source.cancel()
            fileDescriptor = -1
            return
        }

        guard fileDescriptor >= 0 else { return }
        close(fileDescriptor)
        fileDescriptor = -1
    }
}
