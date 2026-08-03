import SwiftUI
import WorkstateCore
import WorkstateIngestion

struct SettingsView: View {
    @ObservedObject var model: WorkstateViewModel
    @State private var draft: WorkstateSettings

    init(model: WorkstateViewModel) {
        self.model = model
        _draft = State(initialValue: model.settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: model.closeSettings) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回项目图谱")

                Text("设置")
                    .font(WorkstateTheme.windowTitleFont)
                Spacer()
                Button("恢复推荐配置") {
                    draft.agentProfiles = WorkstateSettings.defaultProfiles
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .frame(height: WorkstateTheme.headerHeight)

            Divider()

            Form {
                Section("实时更新") {
                    Toggle("监听新的 Codex 对话", isOn: $draft.liveMonitoringEnabled)
                    Text(draft.liveMonitoringEnabled
                        ? "新完成的工作会自动进入对应项目。"
                        : "关闭期间的新内容不会进入 Workstate。")
                        .font(WorkstateTheme.captionFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)

                    Picker("整理间隔", selection: $draft.quietIntervalMinutes) {
                        ForEach(WorkstateSettings.quietIntervalOptionsMinutes, id: \.self) { minutes in
                            Text(intervalLabel(minutes)).tag(minutes)
                        }
                    }
                }

                Section("Agent") {
                    if let error = model.modelCatalogError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(WorkstateTheme.danger)
                    } else {
                        AgentSettingsEditor(
                            settings: $draft,
                            models: model.availableModels
                        )
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("停止服务并退出", role: .destructive) {
                    model.stopServiceAndExit()
                }
                Spacer()
                Button("取消", action: model.closeSettings)
                Button("保存") {
                    model.saveSettings(draft)
                    model.closeSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.availableModels.isEmpty)
            }
            .padding(14)
        }
        .background(WorkstateTheme.windowBackground)
    }

    private func intervalLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "每 \(minutes) 分钟" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0
            ? "每 \(hours) 小时"
            : "每 \(hours) 小时 \(remainingMinutes) 分钟"
    }
}

struct AgentSettingsEditor: View {
    @Binding var settings: WorkstateSettings
    let models: [CodexModelRecord]

    var body: some View {
        ForEach(AgentRole.allCases) { role in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(role.displayName)
                            .font(WorkstateTheme.headlineFont)
                        Text(role.detail)
                            .font(WorkstateTheme.captionFont)
                            .foregroundStyle(WorkstateTheme.secondaryLabel)
                    }
                    Spacer(minLength: 10)
                    Picker("模型", selection: modelBinding(for: role)) {
                        ForEach(models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 154)
                }

                HStack {
                    Text("推理强度")
                        .font(WorkstateTheme.captionFont)
                        .foregroundStyle(WorkstateTheme.secondaryLabel)
                    Spacer()
                    Picker("推理强度", selection: effortBinding(for: role)) {
                        ForEach(supportedEfforts(for: role)) { effort in
                            Text(effort.displayName).tag(effort)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }
            }
            .padding(.vertical, 5)
        }
    }

    private func modelBinding(for role: AgentRole) -> Binding<String> {
        Binding(
            get: { settings.profile(for: role).modelID },
            set: { modelID in
                var profile = settings.profile(for: role)
                guard let model = models.first(where: { $0.id == modelID }) else { return }
                profile.modelID = modelID
                if !model.supportedEfforts.contains(profile.effort) {
                    profile.effort = model.defaultEffort
                }
                settings.agentProfiles[role] = profile
            }
        )
    }

    private func effortBinding(for role: AgentRole) -> Binding<AgentReasoningEffort> {
        Binding(
            get: { settings.profile(for: role).effort },
            set: { effort in
                var profile = settings.profile(for: role)
                guard supportedEfforts(for: role).contains(effort) else { return }
                profile.effort = effort
                settings.agentProfiles[role] = profile
            }
        )
    }

    private func supportedEfforts(for role: AgentRole) -> [AgentReasoningEffort] {
        let profile = settings.profile(for: role)
        return models.first(where: { $0.id == profile.modelID })?.supportedEfforts
            ?? AgentReasoningEffort.allCases
    }
}
