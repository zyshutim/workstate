import Foundation

public enum AgentRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case route
    case steward
    case distill
    case rebuild
    case ownerChat = "owner_chat"
    case brief

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .route: "总路由"
        case .steward: "项目日常更新"
        case .distill: "历史分段整理"
        case .rebuild: "冷启动重建"
        case .ownerChat: "Project Owner 对话"
        case .brief: "日报总结"
        }
    }

    public var detail: String {
        switch self {
        case .route: "判断一段工作属于哪个项目"
        case .steward: "维护项目理解、工作线和最新进展"
        case .distill: "把较长的历史记录整理成完整证据"
        case .rebuild: "从历史证据建立项目当前状态"
        case .ownerChat: "讨论议题、待办和产品方向"
        case .brief: "整理上一工作日的项目摘要"
        }
    }
}

public enum AgentReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high
    case xhigh

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "X-High"
        }
    }
}

public struct AgentProfile: Codable, Equatable, Sendable {
    public var modelID: String
    public var effort: AgentReasoningEffort

    public init(modelID: String, effort: AgentReasoningEffort) {
        self.modelID = modelID
        self.effort = effort
    }
}

public struct WorkstateSettings: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var setupCompleted: Bool
    public var liveMonitoringEnabled: Bool
    public var liveMonitoringStartedAt: Date?
    public var agentProfiles: [AgentRole: AgentProfile]

    public init(
        schemaVersion: Int = 1,
        setupCompleted: Bool = false,
        liveMonitoringEnabled: Bool = true,
        liveMonitoringStartedAt: Date? = nil,
        agentProfiles: [AgentRole: AgentProfile] = WorkstateSettings.defaultProfiles
    ) {
        self.schemaVersion = schemaVersion
        self.setupCompleted = setupCompleted
        self.liveMonitoringEnabled = liveMonitoringEnabled
        self.liveMonitoringStartedAt = liveMonitoringStartedAt
        self.agentProfiles = agentProfiles
    }

    public static let defaultProfiles: [AgentRole: AgentProfile] = [
        .route: AgentProfile(modelID: "gpt-5.6-luna", effort: .low),
        .steward: AgentProfile(modelID: "gpt-5.6-terra", effort: .medium),
        .distill: AgentProfile(modelID: "gpt-5.6-terra", effort: .medium),
        .rebuild: AgentProfile(modelID: "gpt-5.6-sol", effort: .high),
        .ownerChat: AgentProfile(modelID: "gpt-5.6-sol", effort: .medium),
        .brief: AgentProfile(modelID: "gpt-5.6-sol", effort: .medium)
    ]

    public func profile(for role: AgentRole) -> AgentProfile {
        agentProfiles[role] ?? Self.defaultProfiles[role]!
    }
}

public struct WorkstateSettingsRepository: Sendable {
    public let url: URL

    public init(root: URL = WorkstatePaths.defaultPaths().root) {
        url = root.appendingPathComponent("settings.json")
    }

    public func load(workspaceHasProjects: Bool = false) throws -> WorkstateSettings {
        guard FileManager.default.fileExists(atPath: url.path) else {
            var settings = WorkstateSettings()
            settings.setupCompleted = workspaceHasProjects
            return settings
        }
        let settings = try WorkstateCoding.makeDecoder().decode(
            WorkstateSettings.self,
            from: Data(contentsOf: url)
        )
        guard settings.schemaVersion == 1 else {
            throw WorkstateStorageError.invalidState(
                "Unsupported Workstate settings schema \(settings.schemaVersion)"
            )
        }
        return settings
    }

    public func save(_ settings: WorkstateSettings) throws {
        guard settings.schemaVersion == 1 else {
            throw WorkstateStorageError.invalidState("Expected Workstate settings schema 1")
        }
        let missingRoles = Set(AgentRole.allCases).subtracting(settings.agentProfiles.keys)
        guard missingRoles.isEmpty else {
            throw WorkstateStorageError.invalidState(
                "Missing agent profiles: \(missingRoles.map(\.rawValue).sorted().joined(separator: ", "))"
            )
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try WorkstateCoding.makeEncoder().encode(settings).write(to: url, options: .atomic)
    }
}
