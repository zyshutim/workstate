import Foundation

public struct DaemonStatusRepository: Sendable {
    public let url: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        url = root.appendingPathComponent("daemon-status.json")
    }

    public func load() throws -> DaemonSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DaemonSnapshot()
        }
        return try WorkstateCoding.makeDecoder().decode(
            DaemonSnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    @discardableResult
    public func saveIfChanged(_ snapshot: DaemonSnapshot) throws -> Bool {
        if FileManager.default.fileExists(atPath: url.path),
           try load() == snapshot {
            return false
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try WorkstateCoding.makeEncoder()
            .encode(snapshot)
            .write(to: url, options: .atomic)
        return true
    }
}
