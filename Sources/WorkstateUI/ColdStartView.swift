import SwiftUI
import WorkstateCore
import WorkstateIngestion

@MainActor
final class ColdStartViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case history
        case projects
        case agents
        case review
        case processing

        var title: String {
            switch self {
            case .history: "历史记录"
            case .projects: "项目边界"
            case .agents: "Agent 设置"
            case .review: "确认"
            case .processing: "建立中"
            }
        }
    }

    @Published var step: Step = .history
    @Published var sessions: [CodexSessionRecord] = []
    @Published var selectedSessionIDs = Set<String>()
    @Published var searchText = ""
    @Published var rangePresetDays = 30
    @Published var startDate: Date
    @Published var endDate = Date()
    @Published var projectSeeds = [ColdStartProjectSeed(name: "", purpose: "")]
    @Published var sessionProjectHints: [String: String] = [:]
    @Published var settings: WorkstateSettings
    @Published var isLoadingSessions = true
    @Published var progress: ColdStartProgress?
    @Published var errorMessage: String?
    @Published var historyPreview: HistoryImportPreview?
    @Published var isPreparingReview = false

    private let scanner: CodexSessionScanner
    private let service: ColdStartService
    private var restoredConfiguration = false

    init(repository: WorkstateRepository, settings: WorkstateSettings) {
        scanner = CodexSessionScanner(runtimeRoot: repository.paths.root)
        service = ColdStartService(repository: repository)
        self.settings = settings
        startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        if let saved = try? ColdStartConfigurationRepository(
            root: repository.paths.root
        ).load() {
            selectedSessionIDs = saved.selectedThreadIDs
            startDate = saved.startDate
            endDate = Calendar.current.date(
                byAdding: .day,
                value: -1,
                to: saved.endDate
            ) ?? saved.endDate
            projectSeeds = saved.projectSeeds
            sessionProjectHints = saved.sessionProjectHints
            self.settings = saved.settings
            rangePresetDays = 0
            restoredConfiguration = true
        }
        loadSessions()
    }

    deinit {
        service.cancel()
    }

    var visibleSessions: [CodexSessionRecord] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let endStart = calendar.startOfDay(for: endDate)
        let end = calendar.date(byAdding: .day, value: 1, to: endStart) ?? endDate
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessions.filter { session in
            guard session.updatedAt >= start && session.createdAt < end else { return false }
            guard !query.isEmpty else { return true }
            return session.title.localizedCaseInsensitiveContains(query)
                || session.workspaceName.localizedCaseInsensitiveContains(query)
                || session.cwd.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedSessions: [CodexSessionRecord] {
        sessions.filter { selectedSessionIDs.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var canAdvance: Bool {
        switch step {
        case .history:
            !selectedSessionIDs.isEmpty && startDate <= endDate
        case .projects:
            !projectSeeds.isEmpty && projectSeeds.allSatisfy {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .agents:
            true
        case .review:
            true
        case .processing:
            false
        }
    }

    func applyRangePreset(_ days: Int) {
        rangePresetDays = days
        guard days > 0 else { return }
        endDate = Date()
        startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        removeHiddenSelections()
    }

    func removeHiddenSelections() {
        let visibleIDs = Set(visibleSessions.map(\.id))
        selectedSessionIDs.formIntersection(visibleIDs)
        sessionProjectHints = sessionProjectHints.filter { selectedSessionIDs.contains($0.key) }
    }

    func toggleVisibleSessions() {
        let visibleIDs = Set(visibleSessions.map(\.id))
        if visibleIDs.isSubset(of: selectedSessionIDs) {
            selectedSessionIDs.subtract(visibleIDs)
        } else {
            selectedSessionIDs.formUnion(visibleIDs)
        }
    }

    func removeProject(at index: Int) {
        guard projectSeeds.indices.contains(index) else { return }
        let id = projectSeeds[index].id
        projectSeeds.remove(at: index)
        sessionProjectHints = sessionProjectHints.filter { $0.value != id }
    }

    func advance() {
        guard canAdvance else { return }
        switch step {
        case .history: step = .projects
        case .projects: step = .agents
        case .agents: prepareReview()
        case .review, .processing: break
        }
    }

    func goBack() {
        switch step {
        case .projects: step = .history
        case .agents: step = .projects
        case .review: step = .agents
        case .history, .processing: break
        }
    }

    func start(completion: @escaping @MainActor () -> Void) {
        guard step == .review else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let endStart = calendar.startOfDay(for: endDate)
        let end = calendar.date(byAdding: .day, value: 1, to: endStart) ?? endDate
        let configuration = ColdStartConfiguration(
            selectedThreadIDs: selectedSessionIDs,
            startDate: start,
            endDate: end,
            projectSeeds: projectSeeds,
            sessionProjectHints: sessionProjectHints.filter {
                selectedSessionIDs.contains($0.key)
            },
            settings: settings
        )
        let service = self.service
        step = .processing
        errorMessage = nil
        progress = .init(phase: .preparing, completed: 0, total: 1, detail: "正在准备")

        Task.detached(priority: .userInitiated) {
            do {
                _ = try service.run(configuration) { update in
                    Task { @MainActor [weak self] in
                        self?.progress = update
                    }
                }
                await MainActor.run {
                    completion()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func stop() {
        progress?.detail = "正在停止…"
        let service = self.service
        Task.detached(priority: .userInitiated) {
            service.cancel()
        }
    }

    private func loadSessions() {
        let scanner = self.scanner
        Task.detached(priority: .userInitiated) {
            do {
                let catalog = try scanner.sessionCatalog()
                await MainActor.run { [weak self] in
                    self?.sessions = catalog
                    self?.isLoadingSessions = false
                    if self?.restoredConfiguration == false {
                        self?.applyRangePreset(30)
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isLoadingSessions = false
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func prepareReview() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let endStart = calendar.startOfDay(for: endDate)
        let end = calendar.date(byAdding: .day, value: 1, to: endStart) ?? endDate
        let selected = selectedSessionIDs
        let scanner = self.scanner
        isPreparingReview = true
        errorMessage = nil
        Task.detached(priority: .userInitiated) {
            do {
                let preview = try scanner.previewHistory(
                    threadIDs: selected,
                    interval: DateInterval(start: start, end: end)
                )
                guard preview.completedTurnCount > 0 else {
                    throw WorkstateStorageError.invalidState(
                        "The selected tasks contain no completed turns in this range"
                    )
                }
                await MainActor.run { [weak self] in
                    self?.historyPreview = preview
                    self?.isPreparingReview = false
                    self?.step = .review
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isPreparingReview = false
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct ColdStartView: View {
    @ObservedObject private var workspaceModel: WorkstateViewModel
    @StateObject private var model: ColdStartViewModel

    init(model workspaceModel: WorkstateViewModel) {
        self.workspaceModel = workspaceModel
        _model = StateObject(wrappedValue: ColdStartViewModel(
            repository: workspaceModel.repository,
            settings: workspaceModel.settings
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if model.step != .processing {
                Divider()
                footer
            }
        }
        .background(WorkstateTheme.windowBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("建立 Workstate", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(WorkstateTheme.windowTitleFont)
                Spacer()
                Text(model.step.title)
                    .font(WorkstateTheme.captionFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
            }
            HStack(spacing: 5) {
                ForEach(Array(ColdStartViewModel.Step.allCases.prefix(4).enumerated()), id: \.offset) {
                    index, step in
                    Capsule()
                        .fill(index <= model.step.rawValue
                            ? WorkstateTheme.activeState
                            : WorkstateTheme.separator)
                        .frame(height: 3)
                        .accessibilityLabel(step.title)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .history:
            historyStep
        case .projects:
            projectsStep
        case .agents:
            agentsStep
        case .review:
            reviewStep
        case .processing:
            processingStep
        }
    }

    private var historyStep: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("时间范围", selection: Binding(
                    get: { model.rangePresetDays },
                    set: { value in model.applyRangePreset(value) }
                )) {
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                    Text("自定义").tag(0)
                }
                .pickerStyle(.segmented)

                if model.rangePresetDays == 0 {
                    HStack {
                        DatePicker("开始", selection: $model.startDate, displayedComponents: .date)
                        DatePicker("结束", selection: $model.endDate, displayedComponents: .date)
                    }
                    .onChange(of: model.startDate) { model.removeHiddenSelections() }
                    .onChange(of: model.endDate) { model.removeHiddenSelections() }
                }

                HStack {
                    TextField("搜索任务或工作目录", text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                    Button(model.visibleSessions.allSatisfy {
                        model.selectedSessionIDs.contains($0.id)
                    } ? "取消全选" : "全选") {
                        model.toggleVisibleSessions()
                    }
                    .disabled(model.visibleSessions.isEmpty)
                }
            }
            .padding(16)

            Divider()

            if model.isLoadingSessions {
                Spacer()
                ProgressView("正在读取 Codex 任务索引")
                Spacer()
            } else {
                List {
                    ForEach(groupedSessions, id: \.name) { group in
                        Section(group.name) {
                            ForEach(group.sessions) { session in
                                SessionSelectionRow(
                                    session: session,
                                    isSelected: model.selectedSessionIDs.contains(session.id)
                                ) {
                                    if model.selectedSessionIDs.contains(session.id) {
                                        model.selectedSessionIDs.remove(session.id)
                                        model.sessionProjectHints.removeValue(forKey: session.id)
                                    } else {
                                        model.selectedSessionIDs.insert(session.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var projectsStep: some View {
        Form {
            Section {
                Text("这些项目会成为 Router 的初始认知；会话仍可在不同项目之间切换。")
                    .font(WorkstateTheme.captionFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
            }

            ForEach(Array(model.projectSeeds.indices), id: \.self) { index in
                Section("项目 \(index + 1)") {
                    TextField("项目名称", text: $model.projectSeeds[index].name)
                    TextField(
                        "这个项目是什么、目前要解决什么",
                        text: $model.projectSeeds[index].purpose,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    if model.projectSeeds.count > 1 {
                        Button("删除项目", role: .destructive) {
                            model.removeProject(at: index)
                        }
                    }
                }
            }

            Section {
                Button {
                    model.projectSeeds.append(
                        ColdStartProjectSeed(name: "", purpose: "")
                    )
                } label: {
                    Label("添加项目", systemImage: "plus")
                }
            }

            Section("会话预分组") {
                ForEach(model.selectedSessions) { session in
                    HStack {
                        Text(session.title)
                            .lineLimit(1)
                        Spacer()
                        Picker("项目", selection: projectHintBinding(session.id)) {
                            Text("自动判断").tag("")
                            ForEach(model.projectSeeds) { seed in
                                Text(seed.name.isEmpty ? "未命名项目" : seed.name).tag(seed.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var agentsStep: some View {
        Form {
            Section("实时更新") {
                Toggle("冷启动后监听新的 Codex 对话", isOn: $model.settings.liveMonitoringEnabled)
                Text("关闭期间的新内容不会进入 Workstate，可在设置中重新开启。")
                    .font(WorkstateTheme.captionFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
            }
            Section("Agent") {
                if let error = workspaceModel.modelCatalogError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(WorkstateTheme.danger)
                } else {
                    AgentSettingsEditor(
                        settings: $model.settings,
                        models: workspaceModel.availableModels
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    private var reviewStep: some View {
        Form {
            Section("历史范围") {
                LabeledContent("开始", value: model.startDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("结束", value: model.endDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("任务", value: "\(model.selectedSessionIDs.count) 个")
                if let preview = model.historyPreview {
                    LabeledContent("完整回合", value: "\(preview.completedTurnCount) 条")
                    LabeledContent(
                        "证据量",
                        value: ByteCountFormatter.string(
                            fromByteCount: Int64(preview.evidenceBytes),
                            countStyle: .file
                        )
                    )
                }
            }
            Section("初始项目") {
                ForEach(model.projectSeeds) { seed in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(seed.name).font(WorkstateTheme.headlineFont)
                        Text(seed.purpose)
                            .font(WorkstateTheme.captionFont)
                            .foregroundStyle(WorkstateTheme.secondaryLabel)
                    }
                }
            }
            Section("实时更新") {
                Text(model.settings.liveMonitoringEnabled ? "建立后自动监听" : "暂不监听")
            }
        }
        .formStyle(.grouped)
    }

    private var processingStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: model.errorMessage == nil
                ? "point.3.connected.trianglepath.dotted"
                : "exclamationmark.triangle")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(model.errorMessage == nil
                    ? WorkstateTheme.activeState
                    : WorkstateTheme.danger)

            if let error = model.errorMessage {
                Text("建立工作区时停止")
                    .font(WorkstateTheme.sectionTitleFont)
                Text(error)
                    .font(WorkstateTheme.captionFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button("返回检查设置") {
                    model.step = .review
                }
            } else if let progress = model.progress {
                Text(progress.detail)
                    .font(WorkstateTheme.sectionTitleFont)
                ProgressView(
                    value: Double(progress.completed),
                    total: Double(max(progress.total, 1))
                )
                .frame(width: 320)
                Text("关闭菜单面板不会中断处理；停止后可从已完成阶段继续。")
                    .font(WorkstateTheme.captionFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
                Button("停止") {
                    model.stop()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if model.step != .history {
                Button("返回") {
                    model.goBack()
                }
            }
            Spacer()
            Text(model.step == .history
                ? "已选 \(model.selectedSessionIDs.count) 个任务"
                : "")
                .font(WorkstateTheme.captionFont)
                .foregroundStyle(WorkstateTheme.secondaryLabel)
            if model.step == .review {
                Button("开始建立") {
                    model.start {
                        workspaceModel.completeOnboarding()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(workspaceModel.availableModels.isEmpty)
            } else {
                Button(model.isPreparingReview ? "正在统计历史…" : "继续") {
                    model.advance()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canAdvance || model.isPreparingReview)
            }
        }
        .padding(14)
        .overlay(alignment: .top) {
            if let error = model.errorMessage, model.step != .processing {
                Text(error)
                    .font(WorkstateTheme.captionFont)
                    .foregroundStyle(WorkstateTheme.danger)
                    .padding(.top, 2)
            }
        }
    }

    private var groupedSessions: [(name: String, sessions: [CodexSessionRecord])] {
        Dictionary(grouping: model.visibleSessions, by: \.workspaceName)
            .map { (name: $0.key, sessions: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func projectHintBinding(_ threadID: String) -> Binding<String> {
        Binding(
            get: { model.sessionProjectHints[threadID] ?? "" },
            set: { projectID in
                if projectID.isEmpty {
                    model.sessionProjectHints.removeValue(forKey: threadID)
                } else {
                    model.sessionProjectHints[threadID] = projectID
                }
            }
        )
    }
}

private struct SessionSelectionRow: View {
    let session: CodexSessionRecord
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected
                        ? WorkstateTheme.activeState
                        : WorkstateTheme.tertiaryLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .foregroundStyle(WorkstateTheme.primaryLabel)
                        .lineLimit(2)
                    Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(WorkstateTheme.captionFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
