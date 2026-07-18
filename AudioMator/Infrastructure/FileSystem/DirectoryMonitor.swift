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
            let path = normalizedURL.resolvingSymlinksInPath().path
            urlsByPath[path] = normalizedURL
        }

        let normalizedRootURL = rootURL.standardizedFileURL
        let normalizedRootPath = normalizedRootURL.resolvingSymlinksInPath().path
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
            return "Automatic refresh is monitoring all \(monitoredDirectoryCount) directories."
        }

        var reasons: [String] = []
        if omittedByLimitCount > 0 {
            reasons.append("\(omittedByLimitCount) omitted by the safety limit")
        }
        if failedToOpenCount > 0 {
            reasons.append("\(failedToOpenCount) could not be opened")
        }
        if scanFailureCount > 0 {
            let scanLabel = scanFailureCount == 1 ? "scan error" : "scan errors"
            reasons.append("\(scanFailureCount) \(scanLabel)")
        }
        if metadataReadFailureCount > 0 {
            let fileLabel = metadataReadFailureCount == 1 ? "audio file" : "audio files"
            reasons.append("\(metadataReadFailureCount) \(fileLabel) could not be read")
        }

        var message = "Automatic refresh is monitoring \(monitoredDirectoryCount) of \(totalDirectoryCount) directories (\(reasons.joined(separator: ", ")))."
        if omittedByLimitCount > 0 || failedToOpenCount > 0 {
            message += " Some nested changes may not refresh immediately."
        }
        if metadataReadFailureCount > 0 {
            message += " Last known metadata is retained where available."
        }
        if scanFailureCount > 0 {
            message += " The last known file list is retained until scanning succeeds."
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

    deinit {
        stop()
    }

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
