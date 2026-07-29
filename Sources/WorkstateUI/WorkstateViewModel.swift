import AppKit
import Combine
import Foundation
import WorkstateCore
import WorkstateIngestion

@MainActor
public final class WorkstateViewModel: ObservableObject {
    @Published public private(set) var workspace: WorkspaceSnapshot
    @Published public var selectedProjectID: String?
    @Published public var selectedTaskID: String?
    @Published public var selectedEventID: String?
    @Published public var isContextExpanded = false
    @Published public var isReviewInboxPresented = false
    @Published public var selectedReviewID: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var liveActivities: [LiveProjectActivity] = []
    @Published public private(set) var runtimeStatus = RuntimeSnapshot()
    @Published public private(set) var ownerConversations: [String: ProjectOwnerConversation] = [:]
    @Published public private(set) var ownerChatSendingProjectIDs: Set<String> = []
    @Published public private(set) var globalConversation = GlobalConversation()
    @Published public private(set) var isGlobalChatSending = false
    @Published public private(set) var isGlobalChatPresented = false
    @Published public private(set) var collaborationProfile = CollaborationProfile()
    @Published public private(set) var collaborationConversation = CollaborationConversation()
    @Published public private(set) var isCollaborationPresented = false
    @Published public private(set) var isCollaborationSending = false
    @Published public private(set) var dailyBrief: DailyBrief?
    @Published public private(set) var isDailyBriefPresented = false
    @Published public private(set) var hasUnreadDailyBrief = false
    @Published public private(set) var settings = WorkstateSettings()
    @Published public private(set) var availableModels: [CodexModelRecord] = []
    @Published public private(set) var needsOnboarding = true
    @Published public private(set) var isSettingsPresented = false
    @Published public private(set) var modelCatalogError: String?
    @Published public private(set) var copiedHandoffProjectID: String?
    @Published public private(set) var isManualSyncing = false

    public let repository: WorkstateRepository
    private let service: WorkstateService
    private let runtimeStatusRepository: RuntimeStatusRepository
    private let ownerConversationRepository: ProjectOwnerConversationRepository
    private let ownerTurnRepository: ProjectOwnerTurnRepository
    private let globalConversationRepository: GlobalConversationRepository
    private let collaborationProfileRepository: CollaborationProfileRepository
    private let collaborationConversationRepository: CollaborationConversationRepository
    private let durableMemoryRepository: DurableMemoryRepository
    private let dailyBriefRepository: DailyBriefRepository
    private let agentRuntime: AgentRuntimeClient
    private let settingsRepository: WorkstateSettingsRepository
    private let modelCatalog: CodexModelCatalog
    private var lastModificationDate: Date?
    private var lastSettingsModificationDate: Date?
    private var conversationRuntime: AppHostedConversationRuntime?

    public init(repository: WorkstateRepository = .init()) {
        self.repository = repository
        service = WorkstateService(repository: repository)
        runtimeStatusRepository = RuntimeStatusRepository(root: repository.paths.root)
        ownerConversationRepository = ProjectOwnerConversationRepository(root: repository.paths.root)
        ownerTurnRepository = ProjectOwnerTurnRepository(root: repository.paths.root)
        globalConversationRepository = GlobalConversationRepository(root: repository.paths.root)
        collaborationProfileRepository = CollaborationProfileRepository(root: repository.paths.root)
        collaborationConversationRepository = CollaborationConversationRepository(root: repository.paths.root)
        durableMemoryRepository = DurableMemoryRepository(root: repository.paths.root)
        dailyBriefRepository = DailyBriefRepository(root: repository.paths.root)
        agentRuntime = AgentRuntimeClient(runtimeRoot: repository.paths.root)
        settingsRepository = WorkstateSettingsRepository(root: repository.paths.root)
        modelCatalog = CodexModelCatalog()
        do {
            try repository.ensureInitialized()
            workspace = try repository.load()
            settings = try settingsRepository.load(workspaceHasProjects: !workspace.projects.isEmpty)
            if !FileManager.default.fileExists(atPath: settingsRepository.url.path),
               settings.setupCompleted {
                try settingsRepository.save(settings)
            }
            needsOnboarding = !settings.setupCompleted
            lastModificationDate = repository.modificationDate()
            lastSettingsModificationDate = settingsModificationDate()
            if settings.liveMonitoringEnabled,
               let restored = try? runtimeStatusRepository.load(),
               restored.isFresh() {
                runtimeStatus = restored
                liveActivities = restored.liveActivities
            }
            globalConversation = (try? globalConversationRepository.load()) ?? GlobalConversation()
            collaborationProfile = (try? collaborationProfileRepository.load()) ?? CollaborationProfile()
            collaborationConversation = (try? collaborationConversationRepository.load())
                ?? CollaborationConversation()
        } catch {
            workspace = WorkspaceSnapshot()
            errorMessage = error.localizedDescription
        }
        do {
            availableModels = try modelCatalog.load()
        } catch {
            modelCatalogError = error.localizedDescription
        }
        refreshLatestActivityBrief()
        configureConversationRuntime()
    }

    public var selectedProject: ProjectRecord? {
        guard let selectedProjectID else { return nil }
        return workspace.project(id: selectedProjectID)
    }

    public var selectedEvent: ProjectEvent? {
        guard let selectedProject, let selectedEventID else { return nil }
        return selectedProject.event(id: selectedEventID)
    }

    public var selectedTask: TaskRecord? {
        guard let selectedProject, let selectedTaskID else { return nil }
        return selectedProject.task(id: selectedTaskID)
    }

    public var pendingReviews: [ReviewItem] {
        workspace.pendingReviews
    }

    public func liveActivity(for projectID: String) -> LiveProjectActivity? {
        liveActivities
            .filter { $0.projectID == projectID }
            .max { $0.updatedAt < $1.updatedAt }
    }

    public var selectedReview: ReviewItem? {
        guard let selectedReviewID else { return pendingReviews.first }
        return workspace.reviewInbox.first { $0.id == selectedReviewID }
    }

    public var preferredWidth: CGFloat {
        needsOnboarding || isSettingsPresented || isDailyBriefPresented || isGlobalChatPresented
            || isCollaborationPresented || selectedProjectID != nil
            ? WorkstateTheme.projectWidth
            : WorkstateTheme.graphWidth
    }

    public var preferredHeight: CGFloat {
        needsOnboarding || isSettingsPresented || isDailyBriefPresented || isGlobalChatPresented
            || isCollaborationPresented || selectedProjectID != nil
            ? WorkstateTheme.projectHeight
            : WorkstateTheme.graphHeight
    }

    public func presentSettings() {
        isSettingsPresented = true
    }

    public func closeSettings() {
        isSettingsPresented = false
    }

    public func presentGlobalChat() {
        do {
            globalConversation = try globalConversationRepository.load()
            isGlobalChatPresented = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func closeGlobalChat() {
        isGlobalChatPresented = false
    }

    public func presentCollaborationProfile() {
        do {
            collaborationProfile = try collaborationProfileRepository.load()
            collaborationConversation = try collaborationConversationRepository.load()
            isCollaborationPresented = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func closeCollaborationProfile() {
        isCollaborationPresented = false
    }

    public func saveSettings(_ value: WorkstateSettings) {
        do {
            var updated = normalizedSettings(value)
            updated.setupCompleted = settings.setupCompleted
            if updated.liveMonitoringEnabled != settings.liveMonitoringEnabled {
                updated.liveMonitoringStartedAt = updated.liveMonitoringEnabled ? Date() : nil
            }
            try settingsRepository.save(updated)
            settings = updated
            lastSettingsModificationDate = settingsModificationDate()
            configureConversationRuntime()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func completeOnboarding() {
        do {
            workspace = try repository.load()
            settings = try settingsRepository.load(workspaceHasProjects: !workspace.projects.isEmpty)
            needsOnboarding = !settings.setupCompleted
            lastModificationDate = repository.modificationDate()
            lastSettingsModificationDate = settingsModificationDate()
            configureConversationRuntime()
            errorMessage = nil
            refreshLatestActivityBrief()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public var canShowPreviousDailyBrief: Bool {
        adjacentDailyBriefDateKey(direction: .previous) != nil
    }

    public var canShowNextDailyBrief: Bool {
        adjacentDailyBriefDateKey(direction: .next) != nil
    }

    public func presentDailyBrief() {
        do {
            let briefs = try availableNarrativeBriefs()
            dailyBrief = briefs.last
            isDailyBriefPresented = true
            if let brief = dailyBrief {
                try dailyBriefRepository.markViewed(brief)
            }
            refreshUnreadDailyBrief()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func closeDailyBrief() {
        isDailyBriefPresented = false
    }

    public func showPreviousDailyBrief() {
        showAdjacentDailyBrief(direction: .previous)
    }

    public func showNextDailyBrief() {
        showAdjacentDailyBrief(direction: .next)
    }

    public func openDailyBriefItem(_ item: DailyBriefItem) {
        guard workspace.project(id: item.projectID) != nil else { return }
        isDailyBriefPresented = false
        selectProject(item.projectID)
        if let eventID = item.eventID {
            selectEvent(eventID)
        } else if let taskID = item.taskID {
            selectTask(taskID)
        }
    }

    public func openDailyBriefProject(_ projectID: String) {
        guard workspace.project(id: projectID) != nil else { return }
        isDailyBriefPresented = false
        selectProject(projectID)
    }

    public func selectProject(_ id: String) {
        selectedProjectID = id
        selectedTaskID = nil
        selectedEventID = nil
        isContextExpanded = false
        loadOwnerConversation(projectID: id)
    }

    public func leaveProject() {
        selectedProjectID = nil
        selectedTaskID = nil
        selectedEventID = nil
        isContextExpanded = false
    }

    public func selectTask(_ id: String) {
        guard let selectedProject, selectedProject.task(id: id) != nil else { return }
        selectedTaskID = id
        selectedEventID = selectedProject.events(for: id).first?.id
    }

    public func selectProjectEvent(_ id: String) {
        guard let event = selectedProject?.event(id: id), event.taskID == nil else { return }
        selectedTaskID = nil
        selectedEventID = id
    }

    public func selectEvent(_ id: String) {
        guard let event = selectedProject?.event(id: id) else { return }
        selectedTaskID = event.taskID
        selectedEventID = id
    }

    public func selectTaskEvent(_ id: String) {
        guard let selectedTaskID,
              let event = selectedProject?.event(id: id),
              event.taskID == selectedTaskID else { return }
        selectedEventID = id
    }

    public func closeEvent() {
        selectedTaskID = nil
        selectedEventID = nil
    }

    public func toggleContext() {
        isContextExpanded.toggle()
    }

    public func toggleReviewInbox() {
        isReviewInboxPresented.toggle()
        if isReviewInboxPresented, selectedReviewID == nil {
            selectedReviewID = pendingReviews.first?.id
        }
    }

    public func closeReviewInbox() {
        isReviewInboxPresented = false
        selectedReviewID = nil
    }

    public func selectReview(_ id: String) {
        guard workspace.reviewInbox.contains(where: { $0.id == id }) else { return }
        selectedReviewID = id
    }

    public func resolveSelectedReview(as status: ReviewStatus) {
        guard let review = selectedReview else { return }
        do {
            workspace = try service.resolveReview(id: review.id, status: status)
            lastModificationDate = repository.modificationDate()
            errorMessage = nil
            selectedReviewID = pendingReviews.first?.id
            if pendingReviews.isEmpty {
                closeReviewInbox()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func moveProject(_ id: String, to position: GraphPosition) {
        do {
            workspace = try service.updateProject(
                id: id,
                update: ProjectUpdate(position: position)
            )
            lastModificationDate = repository.modificationDate()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func ownerConversation(for projectID: String) -> ProjectOwnerConversation {
        ownerConversations[projectID] ?? ProjectOwnerConversation(projectID: projectID)
    }

    public func sendOwnerMessage(_ rawMessage: String, projectID: String, topicID: String? = nil) {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
              !ownerChatSendingProjectIDs.contains(projectID),
              workspace.project(id: projectID) != nil else {
            return
        }

        let priorConversation = ownerConversation(for: projectID)
        var pendingConversation = priorConversation
        let turnID = UUID().uuidString.lowercased()
        let userMessage = ProjectOwnerMessage(role: .user, text: message, topicID: topicID)
        pendingConversation.messages.append(userMessage)
        pendingConversation.updatedAt = Date()

        do {
            try ownerConversationRepository.save(pendingConversation)
            try ownerTurnRepository.append(
                ProjectOwnerTurnRecord(
                    id: turnID,
                    projectID: projectID,
                    topicID: topicID,
                    userMessageID: userMessage.id,
                    status: .pending
                )
            )
            ownerConversations[projectID] = pendingConversation
            ownerChatSendingProjectIDs.insert(projectID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let runtime = agentRuntime
        let contextRuntime = conversationRuntime ?? AppHostedConversationRuntime(
            runtimeRoot: repository.paths.root
        )
        conversationRuntime = contextRuntime
        Task { [weak self] in
            do {
                _ = try await contextRuntime.flush(
                    trigger: .ownerContext,
                    projectID: projectID
                )
                guard let self else { return }
                self.reload(force: true)
                guard let project = self.workspace.project(id: projectID) else {
                    throw WorkstateStorageError.missingProject(projectID)
                }
                let openBundles = try CodexSessionScanner(
                    runtimeRoot: self.repository.paths.root
                ).openSemanticBundles()
                let response = try await Task.detached(priority: .userInitiated) {
                    try runtime.ownerChat(
                        project: project,
                        history: Array(priorConversation.messages.suffix(16)),
                        message: message,
                        activeTopicID: topicID,
                        openBundles: openBundles
                    )
                }.value
                let ownerMessage = ProjectOwnerMessage(role: .owner, text: response.reply, topicID: topicID)
                try self.applyOwnerTopicUpdates(
                    response.topicUpdates,
                    projectID: projectID,
                    activeTopicID: topicID,
                    userMessageID: userMessage.id,
                    ownerMessageID: ownerMessage.id
                )
                var completedConversation = self.ownerConversation(for: projectID)
                completedConversation.messages.append(ownerMessage)
                completedConversation.updatedAt = Date()
                try self.ownerConversationRepository.save(completedConversation)
                try self.ownerTurnRepository.append(
                    ProjectOwnerTurnRecord(
                        id: turnID,
                        projectID: projectID,
                        topicID: topicID,
                        userMessageID: userMessage.id,
                        ownerMessageID: ownerMessage.id,
                        status: .applied,
                        runtimeThreadID: response.runtimeThreadID
                    )
                )
                self.ownerConversations[projectID] = completedConversation
                self.ownerChatSendingProjectIDs.remove(projectID)
                self.errorMessage = nil
            } catch {
                guard let self else { return }
                try? self.ownerTurnRepository.append(
                    ProjectOwnerTurnRecord(
                        id: turnID,
                        projectID: projectID,
                        topicID: topicID,
                        userMessageID: userMessage.id,
                        status: .failed,
                        error: error.localizedDescription
                    )
                )
                self.ownerChatSendingProjectIDs.remove(projectID)
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func sendGlobalMessage(_ rawMessage: String) {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isGlobalChatSending, !workspace.projects.isEmpty else { return }

        let priorConversation = globalConversation
        let userMessage = GlobalChatMessage(role: .user, text: message)
        var pendingConversation = priorConversation
        pendingConversation.messages.append(userMessage)
        pendingConversation.updatedAt = Date()
        do {
            try globalConversationRepository.save(pendingConversation)
            globalConversation = pendingConversation
            isGlobalChatSending = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let runtime = agentRuntime
        let currentWorkspace = workspace
        Task { [weak self] in
            do {
                let route = try await Task.detached(priority: .userInitiated) {
                    try runtime.routeGlobalChat(
                        message: message,
                        recentMessages: Array(priorConversation.messages.suffix(12)),
                        workspace: currentWorkspace
                    )
                }.value
                guard let project = currentWorkspace.project(id: route.projectID) else {
                    throw WorkstateStorageError.missingProject(route.projectID)
                }
                guard let self else { return }
                var routedConversation = self.globalConversation
                guard let userIndex = routedConversation.messages.firstIndex(where: {
                    $0.id == userMessage.id
                }) else {
                    throw WorkstateStorageError.invalidState("Global chat lost the pending user message")
                }
                routedConversation.messages[userIndex].projectID = project.id
                routedConversation.messages[userIndex].projectName = project.name
                let previousProjectID = routedConversation.messages[..<userIndex]
                    .last(where: { $0.role == .owner })?
                    .projectID
                if previousProjectID != nil, previousProjectID != project.id {
                    routedConversation.messages.append(
                        GlobalChatMessage(
                            role: .system,
                            text: "转给 \(project.name) Project Owner",
                            projectID: project.id,
                            projectName: project.name
                        )
                    )
                }
                routedConversation.updatedAt = Date()
                try self.globalConversationRepository.save(routedConversation)
                self.globalConversation = routedConversation

                let projectHistory = priorConversation.messages
                    .filter { $0.projectID == project.id && $0.role != .system }
                    .suffix(16)
                    .map {
                        ProjectOwnerMessage(
                            id: $0.id,
                            role: $0.role == .user ? .user : .owner,
                            text: $0.text,
                            timestamp: $0.timestamp,
                            topicID: $0.topicID
                        )
                    }
                let openBundles = try CodexSessionScanner(
                    runtimeRoot: self.repository.paths.root
                ).openSemanticBundles()
                let response = try await Task.detached(priority: .userInitiated) {
                    try runtime.ownerChat(
                        project: project,
                        history: Array(projectHistory),
                        message: message,
                        openBundles: openBundles
                    )
                }.value

                let ownerMessage = GlobalChatMessage(
                    role: .owner,
                    text: response.reply,
                    projectID: project.id,
                    projectName: project.name
                )
                try self.applyOwnerTopicUpdates(
                    response.topicUpdates,
                    projectID: project.id,
                    activeTopicID: nil,
                    userMessageID: userMessage.id,
                    ownerMessageID: ownerMessage.id
                )

                var completed = self.globalConversation
                completed.messages.append(ownerMessage)
                completed.updatedAt = Date()
                try self.globalConversationRepository.save(completed)

                var projectConversation = self.ownerConversation(for: project.id)
                projectConversation.messages.append(
                    ProjectOwnerMessage(
                        id: userMessage.id,
                        role: .user,
                        text: message,
                        timestamp: userMessage.timestamp
                    )
                )
                projectConversation.messages.append(
                    ProjectOwnerMessage(
                        id: ownerMessage.id,
                        role: .owner,
                        text: ownerMessage.text,
                        timestamp: ownerMessage.timestamp
                    )
                )
                projectConversation.updatedAt = Date()
                try self.ownerConversationRepository.save(projectConversation)
                self.ownerConversations[project.id] = projectConversation
                self.globalConversation = completed
                self.isGlobalChatSending = false
                self.errorMessage = nil
            } catch {
                guard let self else { return }
                self.isGlobalChatSending = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func sendCollaborationMessage(_ rawMessage: String) {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isCollaborationSending else { return }
        let priorConversation = collaborationConversation
        let userMessage = CollaborationMessage(role: .user, text: message)
        var pending = priorConversation
        pending.messages.append(userMessage)
        pending.updatedAt = Date()
        do {
            try collaborationConversationRepository.save(pending)
            collaborationConversation = pending
            isCollaborationSending = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let runtime = agentRuntime
        let currentProfile = collaborationProfile
        Task { [weak self] in
            do {
                let response = try await Task.detached(priority: .userInitiated) {
                    try runtime.collaborationSteward(
                        profile: currentProfile,
                        history: Array(priorConversation.messages.suffix(16)),
                        message: message
                    )
                }.value
                guard let self else { return }
                let updatedProfile = try self.applyingCollaborationMutations(
                    response.mutations,
                    to: self.collaborationProfile
                )
                var completed = self.collaborationConversation
                completed.messages.append(
                    CollaborationMessage(role: .owner, text: response.reply)
                )
                completed.updatedAt = Date()
                try self.collaborationProfileRepository.save(updatedProfile)
                try self.collaborationConversationRepository.save(completed)
                self.collaborationProfile = updatedProfile
                self.collaborationConversation = completed
                self.isCollaborationSending = false
                self.errorMessage = nil
            } catch {
                guard let self else { return }
                self.isCollaborationSending = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func applyingCollaborationMutations(
        _ mutations: [CollaborationProfileMutation],
        to profile: CollaborationProfile
    ) throws -> CollaborationProfile {
        try CollaborationProfileApplier().apply(mutations, to: profile)
    }

    public func saveTopic(_ topic: ProjectTopic, projectID: String) {
        do {
            workspace = try service.upsertTopic(
                projectID: projectID,
                input: ProjectTopicUpdateInput(
                    id: topic.id,
                    title: topic.title,
                    summary: topic.summary,
                    status: topic.status,
                    kind: topic.kind,
                    disposition: topic.disposition ?? .futureDecision,
                    currentUnderstanding: topic.currentUnderstanding,
                    proposedDirection: topic.proposedDirection,
                    deferredReason: topic.deferredReason,
                    revisitTrigger: topic.revisitTrigger,
                    openQuestions: topic.openQuestions,
                    note: topic.notes.first,
                    sourceIDs: topic.sourceIDs
                )
            )
            lastModificationDate = repository.modificationDate()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func promoteTopic(
        projectID: String,
        topicID: String,
        kind: ProjectTopicPromotionKind,
        title: String,
        detail: String
    ) {
        do {
            workspace = try service.promoteTopic(
                ProjectTopicPromotionInput(
                    projectID: projectID,
                    topicID: topicID,
                    kind: kind,
                    title: title,
                    detail: detail
                )
            )
            lastModificationDate = repository.modificationDate()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func resolveTopic(
        projectID: String,
        topicID: String,
        resolution: ProjectTopicResolution
    ) {
        do {
            workspace = try service.resolveTopic(
                ProjectTopicResolutionInput(
                    projectID: projectID,
                    topicID: topicID,
                    resolution: resolution
                )
            )
            lastModificationDate = repository.modificationDate()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func copyHandoffPrompt(projectID: String) {
        let runtime = conversationRuntime ?? AppHostedConversationRuntime(
            runtimeRoot: repository.paths.root
        )
        conversationRuntime = runtime
        runtime.flush(trigger: .handoff, projectID: projectID) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.reload(force: true)
                    self.writeHandoffPrompt(projectID: projectID)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func writeHandoffPrompt(projectID: String) {
        do {
            let durableGuidance = try durableMemoryRepository.retrieve(
                DurableMemorySelection(
                    scopes: [DurableMemoryScope(kind: .project, identifier: projectID)]
                )
            )
            .flatMap(\.entries)
            .filter { $0.lifecycle == .active || $0.lifecycle == .prohibited }
            .map(\.text)
            var snapshot = try service.contextSnapshot(
                projectID: projectID,
                collaborationGuidance: Array(
                    Set(collaborationProfile.activeGuidance + durableGuidance)
                )
                .sorted()
            )
            snapshot.openSemanticBundles = try CodexSessionScanner(
                runtimeRoot: repository.paths.root
            ).openSemanticBundles()
                .filter { $0.projectID == projectID }
                .map {
                    ContextSnapshotSemanticBundle(
                        id: $0.id,
                        title: $0.title,
                        summary: $0.summary,
                        threadID: $0.threadID,
                        turnIDs: $0.evidenceIDs.compactMap { id in
                            id.split(separator: ":", maxSplits: 1).last.map(String.init)
                        },
                        updatedAt: $0.updatedAt
                    )
                }
            let handoff = try ContextHandoffExporter(root: repository.paths.root).export(snapshot)
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(handoff.prompt, forType: .string) else {
                throw WorkstateStorageError.invalidState("Cannot write handoff prompt to clipboard")
            }
            copiedHandoffProjectID = projectID
            errorMessage = nil
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if self?.copiedHandoffProjectID == projectID {
                    self?.copiedHandoffProjectID = nil
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func syncNow() {
        guard !isManualSyncing else { return }
        isManualSyncing = true
        let runtime = conversationRuntime ?? AppHostedConversationRuntime(
            runtimeRoot: repository.paths.root
        )
        conversationRuntime = runtime
        runtime.syncNow { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isManualSyncing = false
                switch result {
                case .success:
                    self.reload(force: true)
                    self.errorMessage = nil
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyOwnerTopicUpdates(
        _ updates: [ProjectOwnerTopicUpdate],
        projectID: String,
        activeTopicID: String?,
        userMessageID: String,
        ownerMessageID: String
    ) throws {
        for update in updates {
            guard update.action == "create" || update.action == "update",
                  let status = ProjectTopicStatus(rawValue: update.status),
                  let kind = ProjectTopicKind(rawValue: update.kind),
                  let disposition = ProjectTopicDisposition(rawValue: update.disposition),
                  let noteKind = ProjectTopicNoteKind(rawValue: update.noteKind) else {
                throw WorkstateStorageError.invalidState("Owner returned an unsupported topic update")
            }
            if let activeTopicID, update.topicId != activeTopicID {
                throw WorkstateStorageError.invalidState("Owner tried to update a topic outside the active discussion")
            }
            let existing = workspace.project(id: projectID)?.topic(id: update.topicId)
            guard (update.action == "create" && existing == nil)
                    || (update.action == "update" && existing != nil) else {
                throw WorkstateStorageError.invalidState("Owner topic action does not match current project state")
            }
            workspace = try service.upsertTopic(
                projectID: projectID,
                input: ProjectTopicUpdateInput(
                    id: update.topicId,
                    title: update.title,
                    summary: update.summary,
                    status: status,
                    kind: kind,
                    disposition: disposition,
                    currentUnderstanding: update.currentUnderstanding,
                    proposedDirection: update.proposedDirection,
                    deferredReason: update.deferredReason,
                    revisitTrigger: update.revisitTrigger,
                    openQuestions: update.openQuestions,
                    note: ProjectTopicNote(
                        kind: noteKind,
                        title: update.noteTitle,
                        detail: update.noteDetail,
                        ownerMessageIDs: [userMessageID, ownerMessageID]
                    )
                )
            )
            lastModificationDate = repository.modificationDate()
        }
    }

    public func reload(force: Bool = false) {
        reloadRuntimeStatus()
        reloadSettings()
        let modificationDate = repository.modificationDate()
        guard force || modificationDate != lastModificationDate else { return }
        do {
            workspace = try repository.load()
            lastModificationDate = modificationDate
            errorMessage = nil
            repairSelection()
            refreshLatestActivityBrief()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadSettings() {
        let modificationDate = settingsModificationDate()
        guard modificationDate != lastSettingsModificationDate else { return }
        do {
            settings = try settingsRepository.load(workspaceHasProjects: !workspace.projects.isEmpty)
            needsOnboarding = !settings.setupCompleted
            lastSettingsModificationDate = modificationDate
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func settingsModificationDate() -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: settingsRepository.url.path)
        return attributes?[.modificationDate] as? Date
    }

    private func normalizedSettings(_ value: WorkstateSettings) -> WorkstateSettings {
        guard !availableModels.isEmpty else { return value }
        var output = value
        for role in AgentRole.allCases {
            var profile = output.profile(for: role)
            let model = availableModels.first(where: { $0.id == profile.modelID })
                ?? availableModels[0]
            profile.modelID = model.id
            if !model.supportedEfforts.contains(profile.effort) {
                profile.effort = model.defaultEffort
            }
            output.agentProfiles[role] = profile
        }
        return output
    }

    private func configureConversationRuntime() {
        guard settings.setupCompleted, settings.liveMonitoringEnabled else {
            conversationRuntime?.stop()
            conversationRuntime = nil
            runtimeStatus = RuntimeSnapshot(activity: .stopped, detail: "同步未运行")
            liveActivities = []
            return
        }
        if conversationRuntime == nil {
            conversationRuntime = AppHostedConversationRuntime(
                runtimeRoot: repository.paths.root,
                minimumTimestamp: settings.liveMonitoringStartedAt,
                snapshotObserver: { [weak self] snapshot in
                    Task { @MainActor [weak self] in
                        self?.applyRuntimeSnapshot(snapshot)
                    }
                }
            )
        }
        do {
            try conversationRuntime?.start()
        } catch {
            conversationRuntime?.stop()
            conversationRuntime = nil
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLatestActivityBrief() {
        do {
            let briefs = try availableNarrativeBriefs()
            let latest = briefs.last
            if isDailyBriefPresented, let selectedDateKey = dailyBrief?.dateKey {
                dailyBrief = briefs.first(where: { $0.dateKey == selectedDateKey }) ?? latest
            } else {
                dailyBrief = latest
            }
            if let latest {
                hasUnreadDailyBrief = try dailyBriefRepository.isUnread(latest)
            } else {
                hasUnreadDailyBrief = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshUnreadDailyBrief() {
        do {
            guard let latest = try latestStoredDailyBrief() else {
                hasUnreadDailyBrief = false
                return
            }
            hasUnreadDailyBrief = try dailyBriefRepository.isUnread(latest)
        } catch {
            hasUnreadDailyBrief = false
            errorMessage = error.localizedDescription
        }
    }

    private func latestStoredDailyBrief() throws -> DailyBrief? {
        try availableNarrativeBriefs().last
    }

    private func availableNarrativeBriefs() throws -> [DailyBrief] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let latestAllowedDay = calendar.date(byAdding: .day, value: -1, to: today) else {
            return []
        }
        let components = calendar.dateComponents([.year, .month, .day], from: latestAllowedDay)
        let latestAllowedKey = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return try dailyBriefRepository.availableDateKeys()
            .filter { $0 <= latestAllowedKey }
            .compactMap { try dailyBriefRepository.load(dateKey: $0) }
            .filter { $0.currentNarrative != nil }
    }

    private enum DailyBriefDirection {
        case previous
        case next
    }

    private func adjacentDailyBriefDateKey(direction: DailyBriefDirection) -> String? {
        guard let current = dailyBrief?.dateKey,
              let keys = try? availableNarrativeBriefs().map(\.dateKey) else {
            return nil
        }
        switch direction {
        case .previous:
            return keys.last(where: { $0 < current })
        case .next:
            return keys.first(where: { $0 > current })
        }
    }

    private func showAdjacentDailyBrief(direction: DailyBriefDirection) {
        guard let dateKey = adjacentDailyBriefDateKey(direction: direction) else { return }
        do {
            guard let brief = try dailyBriefRepository.load(dateKey: dateKey) else { return }
            dailyBrief = brief
            try dailyBriefRepository.markViewed(brief)
            refreshUnreadDailyBrief()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadRuntimeStatus() {
        guard settings.liveMonitoringEnabled,
              let snapshot = try? runtimeStatusRepository.load(),
              snapshot.isFresh(),
              snapshot != runtimeStatus else {
            return
        }
        applyRuntimeSnapshot(snapshot)
    }

    private func applyRuntimeSnapshot(_ snapshot: RuntimeSnapshot) {
        runtimeStatus = snapshot
        liveActivities = snapshot.liveActivities
    }

    private func loadOwnerConversation(projectID: String) {
        do {
            ownerConversations[projectID] = try ownerConversationRepository.load(projectID: projectID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func repairSelection() {
        if let selectedProjectID, workspace.project(id: selectedProjectID) == nil {
            leaveProject()
            return
        }

        if let selectedTaskID {
            guard let selectedProject, selectedProject.task(id: selectedTaskID) != nil else {
                self.selectedTaskID = nil
                selectedEventID = nil
                return
            }
            if let selectedEventID,
               selectedProject.event(id: selectedEventID)?.taskID == selectedTaskID {
                return
            }
            selectedEventID = selectedProject.events(for: selectedTaskID).first?.id
            return
        }

        if let selectedEventID,
           let event = selectedProject?.event(id: selectedEventID),
           event.taskID == nil {
            return
        }
        selectedEventID = nil
    }
}
