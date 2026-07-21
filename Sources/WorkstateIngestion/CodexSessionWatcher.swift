import CoreServices
import Foundation

public struct SessionChangeBatch: Sendable {
    public var paths: [String]
    public var requiresFullScan: Bool

    public init(paths: [String], requiresFullScan: Bool = false) {
        self.paths = paths
        self.requiresFullScan = requiresFullScan
    }
}

public enum SessionWatcherError: LocalizedError {
    case couldNotCreateStream
    case couldNotStartStream

    public var errorDescription: String? {
        switch self {
        case .couldNotCreateStream: "Could not create the Codex session FSEvents stream"
        case .couldNotStartStream: "Could not start the Codex session FSEvents stream"
        }
    }
}

public final class CodexSessionWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable (SessionChangeBatch) -> Void

    private let root: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.timshu.workstate.session-watcher")
    private let lock = NSLock()
    private var stream: FSEventStreamRef?

    public init(root: URL, handler: @escaping Handler) {
        self.root = root
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let created = FSEventStreamCreate(
            nil,
            workstateSessionWatcherCallback,
            &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            throw SessionWatcherError.couldNotCreateStream
        }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            throw SessionWatcherError.couldNotStartStream
        }
        stream = created
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func receive(
        count: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        autoreleasepool {
            let values = unsafeBitCast(eventPaths, to: CFArray.self) as NSArray
            var paths = Set<String>()
            var requiresFullScan = false
            for index in 0..<count {
                if let path = values[index] as? String {
                    paths.insert(path)
                }
                let flags = eventFlags[index]
                if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
                    || flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
                    || flags & FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped) != 0 {
                    requiresFullScan = true
                }
            }
            handler(SessionChangeBatch(paths: paths.sorted(), requiresFullScan: requiresFullScan))
        }
    }
}

private func workstateSessionWatcherCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let watcher = Unmanaged<CodexSessionWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
    watcher.receive(count: numEvents, eventPaths: eventPaths, eventFlags: eventFlags)
}
