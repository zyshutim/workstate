import Foundation
import WorkstateCore
import WorkstateIngestion

public enum ProjectOwnerSessionChecks {
    public static func run() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "workstate-owner-session-check-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runtimeScript = root.appendingPathComponent("fake-owner-session-runtime.js")
        let script = #"""
        let input = "";
        process.stdin.setEncoding("utf8");
        process.stdin.on("data", chunk => input += chunk);
        process.stdin.on("end", () => {
          const request = JSON.parse(input);
          if (request.mode !== "reset_owner_session" || request.projectId !== "project-a") {
            process.stderr.write("unexpected reset request");
            process.exit(7);
            return;
          }
          process.stdout.write(JSON.stringify({
            mode: request.mode,
            runtimeThreadId: "11111111-1111-1111-1111-111111111111",
            usage: null,
            telemetry: null,
            result: {
              projectId: request.projectId,
              removedThreadId: "11111111-1111-1111-1111-111111111111"
            }
          }));
        });
        """#
        try Data(script.utf8).write(to: runtimeScript)

        let client = AgentRuntimeClient(
            runtimeScript: runtimeScript,
            nodePath: AgentRuntimeClient.defaultNodePath(),
            runtimeRoot: root
        )
        let removed = try client.resetProjectOwnerSession(projectID: "project-a")
        try require(
            removed == "11111111-1111-1111-1111-111111111111",
            "Swift reset API returns the removed Owner thread"
        )
        try expectFailure {
            _ = try client.resetProjectOwnerSession(projectID: "   ")
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw WorkstateStorageError.invalidState(message)
        }
    }

    private static func expectFailure(_ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch WorkstateStorageError.invalidState {
            return
        }
        throw WorkstateStorageError.invalidState("Expected Owner-session check failure")
    }
}
