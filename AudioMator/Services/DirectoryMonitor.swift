import Foundation
import Darwin

#if os(macOS)
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
#else
final class DirectoryMonitor {
    init?(
        url: URL,
        queue: DispatchQueue = DispatchQueue(label: "AudioMator.DirectoryMonitor", qos: .utility),
        eventHandler: @escaping @Sendable () -> Void
    ) {
        _ = url
        _ = queue
        _ = eventHandler
        return nil
    }

    func start() {}
    func stop() {}
}
#endif
