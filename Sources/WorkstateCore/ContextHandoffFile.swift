import Foundation

public struct ContextHandoffFile: Equatable, Sendable {
    public var url: URL
    public var prompt: String

    public init(url: URL, prompt: String) {
        self.url = url
        self.prompt = prompt
    }
}

public struct ContextHandoffExporter: Sendable {
    public let root: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        self.root = root
    }

    public func export(_ snapshot: ContextSnapshot) throws -> ContextHandoffFile {
        let projectID = snapshot.project.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectID.isEmpty,
              projectID.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics
                      .union(CharacterSet(charactersIn: "-_"))
                      .contains($0)
              }) else {
            throw WorkstateStorageError.invalidState("Project id cannot be used as a handoff filename")
        }

        let directory = root.appendingPathComponent("handoffs", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("\(projectID).md")
        let markdown = ContextSnapshotMarkdownRenderer().render(snapshot)
        try Data(markdown.utf8).write(to: url, options: .atomic)

        let prompt = """
        请先读取 Workstate 项目交接文件：
        \(url.path)

        把文件中的项目背景、当前工作、待决策与待验证议题、协作方式作为本次任务的起始上下文。先核对当前仓库和运行状态，再继续文件中的当前工作；不要把未确认内容当成已确认事实。
        """
        return ContextHandoffFile(url: url, prompt: prompt)
    }
}
