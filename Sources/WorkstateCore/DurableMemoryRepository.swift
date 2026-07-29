import CryptoKit
import Foundation

public struct DurableMemoryRepository: Sendable {
    public let root: URL
    private let engine = DurableMemoryEngine()

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        self.root = root.appendingPathComponent("memory", isDirectory: true)
    }

    public func load() throws -> DurableMemoryLibrary {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return DurableMemoryLibrary()
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return DurableMemoryLibrary()
        }
        let documents = try enumerator.compactMap { item -> DurableMemoryDocument? in
            guard let url = item as? URL,
                  url.pathExtension == "json",
                  url.lastPathComponent != "manifest.json" else { return nil }
            return try WorkstateCoding.makeDecoder().decode(
                DurableMemoryDocument.self,
                from: Data(contentsOf: url)
            )
        }
        let library = DurableMemoryLibrary(documents: documents)
        try engine.validate(library)
        return library
    }

    @discardableResult
    public func apply(
        _ mutation: DurableMemoryMutation
    ) throws -> DurableMemoryMutationReceipt {
        let application = try engine.applying(mutation, to: load())
        guard let document = application.library.documents.first(where: {
            $0.key == application.receipt.document
        }) else {
            throw WorkstateStorageError.invalidState(
                "Durable memory mutation did not produce its target document"
            )
        }
        let url = documentURL(for: document.key)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try WorkstateCoding.makeEncoder().encode(document).write(to: url, options: .atomic)
        try appendReceipt(application.receipt)
        return application.receipt
    }

    public func retrieve(
        _ selection: DurableMemorySelection
    ) throws -> [DurableMemoryDocument] {
        try engine.retrieve(from: load(), matching: selection)
    }

    public func documentURL(for key: DurableMemoryDocumentKey) -> URL {
        root
            .appendingPathComponent(key.namespace.rawValue, isDirectory: true)
            .appendingPathComponent(key.scope.kind.rawValue, isDirectory: true)
            .appendingPathComponent(
                key.scope.identifier.isEmpty ? "global" : safeComponent(key.scope.identifier),
                isDirectory: true
            )
            .appendingPathComponent(
                "\(safeComponent(key.slug))--\(keyDigest(key).prefix(10)).json"
            )
    }

    private func appendReceipt(_ receipt: DurableMemoryMutationReceipt) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("mutations.jsonl")
        try rotateIfNeeded(url)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        var data = try WorkstateCoding.makeEncoder(pretty: false).encode(receipt)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func rotateIfNeeded(_ url: URL, maximumBytes: Int = 2 * 1024 * 1024) throws {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size >= maximumBytes else { return }
        let previous = root.appendingPathComponent("mutations.previous.jsonl")
        if FileManager.default.fileExists(atPath: previous.path) {
            try FileManager.default.removeItem(at: previous)
        }
        try FileManager.default.moveItem(at: url, to: previous)
    }

    private func safeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let output = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return output.isEmpty ? "memory" : output
    }

    private func keyDigest(_ key: DurableMemoryDocumentKey) -> String {
        let text = [
            key.namespace.rawValue,
            key.scope.kind.rawValue,
            key.scope.identifier,
            key.slug
        ].joined(separator: "\u{0}")
        return SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
