import Foundation

public struct ContextHandoffFile: Equatable, Sendable {
    public var url: URL
    public var sourceIndexURL: URL
    public var prompt: String

    public init(url: URL, sourceIndexURL: URL, prompt: String) {
        self.url = url
        self.sourceIndexURL = sourceIndexURL
        self.prompt = prompt
    }
}

public struct ContextHandoffSourceIndex: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var scope: ContextSnapshotScope
    public var sources: [ContextSourcePointer]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date,
        scope: ContextSnapshotScope,
        sources: [ContextSourcePointer]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.scope = scope
        self.sources = sources
    }
}

public struct ContextHandoffExporter: Sendable {
    public let root: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        self.root = root
    }

    public func export(_ snapshot: ContextSnapshot) throws -> ContextHandoffFile {
        let projectID = snapshot.project.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeFilenameComponent(projectID) else {
            throw WorkstateStorageError.invalidState("Project id cannot be used as a handoff filename")
        }
        let scopeID = snapshot.scope.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeFilenameComponent(scopeID) else {
            throw WorkstateStorageError.invalidState("Handoff scope id cannot be used as a filename")
        }

        let directory = root.appendingPathComponent("handoffs", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let stem = switch snapshot.scope.kind {
        case .project: projectID
        case .task: "\(projectID)--task--\(scopeID)"
        case .thread: "\(projectID)--thread--\(scopeID)"
        }
        let url = directory.appendingPathComponent("\(stem).md")
        let sourceIndexURL = directory.appendingPathComponent("\(stem).sources.json")
        let sourceIndex = ContextHandoffSourceIndex(
            generatedAt: snapshot.generatedAt,
            scope: snapshot.scope,
            sources: snapshot.sources
        )
        try WorkstateCoding.makeEncoder().encode(sourceIndex)
            .write(to: sourceIndexURL, options: .atomic)
        let markdown = ContextSnapshotMarkdownRenderer().render(
            snapshot,
            sourceIndexPath: sourceIndexURL.path
        )
        try Data(markdown.utf8).write(to: url, options: .atomic)

        let prompt = """
        请先读取 Workstate 项目交接文件：
        \(url.path)

        这是交接时生成的 Workstate Context Contract，不会随之后的会话自动刷新。按“正式项目认知 → 当前工作 → 关键转折 → 未确认内容 → 证据索引”的顺序读取。先核对当前仓库和运行状态，再继续当前工作；不要把待确认的认知修改、议题或尚未定性的对话当成已确认事实。只有需要核实时，才读取文件中指向的 sources.json，并按其中的精确指针回读原始会话。
        """
        return ContextHandoffFile(url: url, sourceIndexURL: sourceIndexURL, prompt: prompt)
    }

    private func isSafeFilenameComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics
                    .union(CharacterSet(charactersIn: "-_"))
                    .contains($0)
            }
    }
}
