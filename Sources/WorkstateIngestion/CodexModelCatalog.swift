import Foundation
import WorkstateCore

public struct CodexModelRecord: Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var defaultEffort: AgentReasoningEffort
    public var supportedEfforts: [AgentReasoningEffort]

    public init(
        id: String,
        displayName: String,
        defaultEffort: AgentReasoningEffort,
        supportedEfforts: [AgentReasoningEffort]
    ) {
        self.id = id
        self.displayName = displayName
        self.defaultEffort = defaultEffort
        self.supportedEfforts = supportedEfforts
    }
}

public struct CodexModelCatalog: Sendable {
    public let url: URL

    public init(
        url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/models_cache.json")
    ) {
        self.url = url
    }

    public func load() throws -> [CodexModelRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WorkstateStorageError.invalidState(
                "Codex model catalog not found. Open Codex once, then reopen Workstate."
            )
        }
        let cache: ModelCache
        do {
            cache = try JSONDecoder().decode(ModelCache.self, from: Data(contentsOf: url))
        } catch is DecodingError {
            throw WorkstateStorageError.invalidState(
                "Codex 模型列表格式发生变化，当前版本的 Workstate 暂时无法读取。"
            )
        }
        let models = cache.models.compactMap { model -> CodexModelRecord? in
            guard model.visibility == "list", model.supportedInAPI else { return nil }
            let efforts = AgentReasoningEffort.allCases.filter { effort in
                model.supportedReasoningLevels.contains { $0.effort == effort.rawValue }
            }
            guard !efforts.isEmpty else { return nil }
            let defaultEffort = model.defaultReasoningLevel
                .flatMap(AgentReasoningEffort.init(rawValue:))
                .flatMap { efforts.contains($0) ? $0 : nil }
                ?? efforts[0]
            return CodexModelRecord(
                id: model.slug,
                displayName: model.displayName,
                defaultEffort: defaultEffort,
                supportedEfforts: efforts
            )
        }
        guard !models.isEmpty else {
            throw WorkstateStorageError.invalidState("Codex model catalog contains no usable models")
        }
        return models
    }
}

private struct ModelCache: Decodable {
    var models: [CachedModel]
}

private struct CachedModel: Decodable {
    var slug: String
    var displayName: String
    var visibility: String
    var supportedInAPI: Bool
    var defaultReasoningLevel: String?
    var supportedReasoningLevels: [CachedReasoningLevel]

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case visibility
        case supportedInAPI = "supported_in_api"
        case defaultReasoningLevel = "default_reasoning_level"
        case supportedReasoningLevels = "supported_reasoning_levels"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        displayName = try container.decode(String.self, forKey: .displayName)
        visibility = try container.decode(String.self, forKey: .visibility)
        supportedInAPI = try container.decode(Bool.self, forKey: .supportedInAPI)
        defaultReasoningLevel = try container.decodeIfPresent(
            String.self,
            forKey: .defaultReasoningLevel
        )
        supportedReasoningLevels = try container.decodeIfPresent(
            [CachedReasoningLevel].self,
            forKey: .supportedReasoningLevels
        ) ?? []
    }
}

private struct CachedReasoningLevel: Decodable {
    var effort: String
}
