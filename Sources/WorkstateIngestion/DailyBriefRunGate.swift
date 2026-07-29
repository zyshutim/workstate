import Darwin
import Foundation
import WorkstateCore

public struct DailyBriefRunGate: Sendable {
    public let stateURL: URL
    public let lockURL: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        stateURL = root.appendingPathComponent("daily-brief-run-state.json")
        lockURL = root.appendingPathComponent("daily-brief-run-state.lock")
    }

    public func beginIfNeeded(
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Bool {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw WorkstateStorageError.cannotCreateLock(lockURL.path)
        }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw WorkstateStorageError.cannotLock(lockURL.path)
        }
        defer { flock(descriptor, LOCK_UN) }

        let dateKey = Self.dateKey(now, calendar: calendar)
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let size = try stateURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 4 * 1024 else {
                throw WorkstateStorageError.invalidState(
                    "Daily brief run state exceeded 4 KiB"
                )
            }
            let state = try WorkstateCoding.makeDecoder().decode(
                DailyBriefRunState.self,
                from: Data(contentsOf: stateURL)
            )
            if state.dateKey == dateKey { return false }
        }

        let state = DailyBriefRunState(dateKey: dateKey, startedAt: now)
        try WorkstateCoding.makeEncoder().encode(state).write(to: stateURL, options: .atomic)
        return true
    }

    private static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private struct DailyBriefRunState: Codable {
    var dateKey: String
    var startedAt: Date
}
