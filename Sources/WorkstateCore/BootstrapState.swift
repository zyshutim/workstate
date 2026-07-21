import Foundation

public enum WorkstateBootstrap {
    public static func makeInitialState(now: Date = Date()) -> WorkspaceSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        func days(_ value: Int) -> Date {
            calendar.date(byAdding: .day, value: value, to: now) ?? now
        }
        func hours(_ value: Int, from date: Date) -> Date {
            calendar.date(byAdding: .hour, value: value, to: date) ?? date
        }

        let multicamSession = SourceReference(
            id: "source-codex-multicam",
            kind: "conversation",
            label: "Codex · Reframe 多机位前端修改",
            locator: "codex://threads/demo-multicam-session",
            threadID: "demo-multicam-session"
        )
        let materialSession = SourceReference(
            id: "source-codex-material",
            kind: "conversation",
            label: "Codex · Reframe 素材图谱/agent 实验",
            locator: "codex://threads/demo-material-session",
            threadID: "demo-material-session"
        )
        let reviewSource = SourceReference(
            id: "source-codex-review-demo",
            kind: "conversation",
            label: "Codex · Storyboard 产品定位讨论",
            locator: "codex://threads/demo-material-session",
            threadID: "demo-material-session",
            turnIDs: ["review-demo"],
            excerpt: [
                ConversationMessage(
                    id: "review-demo-user",
                    role: "user",
                    text: "Storyboard 现在是否还应该继续作为独立工作区？",
                    timestamp: days(-1)
                ),
                ConversationMessage(
                    id: "review-demo-assistant",
                    role: "assistant",
                    text: "当前对话出现了与既有产品模型不同的方向，需要确认后才能覆盖项目理解。",
                    timestamp: days(-1)
                )
            ],
            contentHash: "review-demo"
        )
        let globalSpec = SourceReference(
            id: "source-spec-global",
            kind: "file",
            label: "Reframe 全局规范",
            locator: "/Users/demo/Documents/reframe-docs/00-全局规范.md"
        )
        let moduleASpec = SourceReference(
            id: "source-spec-a",
            kind: "file",
            label: "模块 A · 内容理解",
            locator: "/Users/demo/Documents/reframe-docs/02-模块A-内容理解.md"
        )
        let moduleBSpec = SourceReference(
            id: "source-spec-b",
            kind: "file",
            label: "模块 B · 视频预览",
            locator: "/Users/demo/Documents/reframe-docs/03-模块B-视频预览.md"
        )
        let moduleCSpec = SourceReference(
            id: "source-spec-c",
            kind: "file",
            label: "模块 C · 粗剪",
            locator: "/Users/demo/Documents/reframe-docs/01-模块C-粗剪.md"
        )
        let reframeRepository = SourceReference(
            id: "source-reframe-repo",
            kind: "repository",
            label: "Reframe App",
            locator: "/Users/demo/Documents/reframe-app"
        )

        let multicamStart = days(-36)
        let previewMergedAt = hours(20, from: multicamStart)
        let matrixMergedAt = hours(27, from: multicamStart)
        let sourceMergedAt = hours(33, from: multicamStart)
        let selectionMergedAt = hours(42, from: multicamStart)
        let reportHandoffAt = hours(48, from: multicamStart)

        let multicamTasks = [
            TaskRecord(
                id: "task-preview-focus",
                title: "蓝框与预览源联动",
                objective: "让蓝框、模块 B 预览源和真实播放状态保持一致",
                status: .completed,
                accent: .blue,
                currentStage: .completed,
                startedAt: hours(1, from: multicamStart),
                updatedAt: previewMergedAt,
                completedAt: previewMergedAt,
                branchedFromEventID: "mc-project-start",
                mergedByEventID: "mc-preview-merged",
                tags: ["全局联动", "模块 A", "模块 B", "模块 C"],
                sourceIDs: [multicamSession.id, globalSpec.id]
            ),
            TaskRecord(
                id: "task-matrix-gap",
                title: "Matrix 空档状态",
                objective: "没有真实 Chunk 的机位不显示陈旧或下一帧画面",
                status: .completed,
                accent: .green,
                currentStage: .completed,
                startedAt: hours(21, from: multicamStart),
                updatedAt: matrixMergedAt,
                completedAt: matrixMergedAt,
                branchedFromEventID: "mc-preview-merged",
                mergedByEventID: "mc-matrix-merged",
                tags: ["模块 B", "多机位 Matrix"],
                sourceIDs: [multicamSession.id, moduleBSpec.id]
            ),
            TaskRecord(
                id: "task-source-coupling",
                title: "播放高亮与音视频源解耦",
                objective: "取消播放时的 Chunk 强制高亮，并让视频源切换不再改动音频源",
                status: .completed,
                accent: .amber,
                currentStage: .completed,
                startedAt: hours(22, from: multicamStart),
                updatedAt: sourceMergedAt,
                completedAt: sourceMergedAt,
                branchedFromEventID: "mc-preview-merged",
                mergedByEventID: "mc-source-merged",
                tags: ["模块 A", "模块 B", "选择状态", "音视频源"],
                sourceIDs: [multicamSession.id, moduleASpec.id, moduleBSpec.id]
            ),
            TaskRecord(
                id: "task-box-selection",
                title: "A/C 框选语义对齐",
                objective: "模块 A 框选只改变 focused Chunk，不移动 playhead",
                status: .completed,
                accent: .violet,
                currentStage: .completed,
                startedAt: hours(34, from: multicamStart),
                updatedAt: selectionMergedAt,
                completedAt: selectionMergedAt,
                branchedFromEventID: "mc-source-merged",
                mergedByEventID: "mc-selection-merged",
                tags: ["模块 A", "模块 C", "框选"],
                sourceIDs: [multicamSession.id, moduleASpec.id, moduleCSpec.id]
            )
        ]

        let multicamEvents = [
            ProjectEvent(
                id: "mc-project-start",
                timestamp: multicamStart,
                title: "多机位交互修复开始",
                summary: "围绕模块 A/B/C 的播放焦点、预览源和选择状态开始集中走查",
                kind: .projectStarted,
                loopStage: .intake,
                facts: ["问题跨越模块 A、B、C，不能按单文件修复"],
                delivery: .init(stage: .unchanged),
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-preview-start",
                taskID: "task-preview-focus",
                timestamp: hours(1, from: multicamStart),
                title: "恢复 Bug 账本",
                summary: "回退零散补丁，重新整理蓝框与预览源相关问题",
                kind: .taskStarted,
                loopStage: .reconstruction,
                parentEventIDs: ["mc-project-start"],
                facts: ["旧修复来回打补丁仍无法稳定解决问题"],
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-preview-audit",
                taskID: "task-preview-focus",
                timestamp: hours(5, from: multicamStart),
                title: "审计 A/B/C 播放状态",
                summary: "逐条核对点击、双击、播放和跨模块操作的真实响应",
                kind: .investigation,
                loopStage: .audit,
                parentEventIDs: ["mc-preview-start"],
                facts: ["activePlaybackSource 只改变蓝框", "moduleBPreviewMode 决定 B 实际显示内容"],
                operations: .init(
                    cwd: "/Users/demo/Documents/reframe-app",
                    repository: "/Users/demo/Documents/reframe-app",
                    branch: "dev-frontend",
                    files: ["src/views/ProjectMultiCamera.vue"]
                ),
                sourceIDs: [multicamSession.id, reframeRepository.id]
            ),
            ProjectEvent(
                id: "mc-preview-model",
                taskID: "task-preview-focus",
                timestamp: hours(8, from: multicamStart),
                title: "确认蓝框与预览模式脱节",
                summary: "把播放来源、预览模式、播放状态和选中状态重新拆开建模",
                kind: .decision,
                loopStage: .modeling,
                parentEventIDs: ["mc-preview-audit"],
                decisions: [
                    DecisionRecord(
                        text: "蓝框只表示模块 B 当前内容来自 A 还是 C，不表示选择状态",
                        status: .confirmed,
                        sourceIDs: [globalSpec.id, multicamSession.id]
                    )
                ],
                tags: ["activePlaybackSource", "moduleBPreviewMode"],
                sourceIDs: [multicamSession.id, globalSpec.id]
            ),
            ProjectEvent(
                id: "mc-preview-confirmed",
                taskID: "task-preview-focus",
                timestamp: hours(11, from: multicamStart),
                title: "完整路径走查表确认",
                summary: "用户逐条确认 A/B/C 点击与播放焦点联动规则",
                kind: .decision,
                loopStage: .confirmation,
                parentEventIDs: ["mc-preview-model"],
                facts: ["交互路径表全部通过用户确认"],
                delivery: .init(stage: .userAccepted, checks: ["用户逐条确认路径"], verifiedAt: hours(11, from: multicamStart)),
                sourceIDs: [multicamSession.id, globalSpec.id]
            ),
            ProjectEvent(
                id: "mc-preview-implemented",
                taskID: "task-preview-focus",
                timestamp: hours(15, from: multicamStart),
                title: "重写完整来源切换",
                summary: "用明确 handler 同步暂停、预览模式、播放来源和当前时间",
                kind: .implementation,
                loopStage: .implementation,
                parentEventIDs: ["mc-preview-confirmed"],
                operations: .init(
                    cwd: "/Users/demo/Documents/reframe-app",
                    repository: "/Users/demo/Documents/reframe-app",
                    branch: "dev-frontend",
                    files: ["src/views/ProjectMultiCamera.vue"]
                ),
                delivery: .init(stage: .changed),
                sourceIDs: [multicamSession.id, reframeRepository.id]
            ),
            ProjectEvent(
                id: "mc-preview-verified",
                taskID: "task-preview-focus",
                timestamp: hours(18, from: multicamStart),
                title: "多机位路径完整走查",
                summary: "模块 A/C 来源切换、播放和蓝框状态在真实 App 内通过",
                kind: .verification,
                loopStage: .verification,
                parentEventIDs: ["mc-preview-implemented"],
                facts: ["六项蓝框问题在真实 App 内复测通过"],
                delivery: .init(stage: .rendered, checks: ["真实 App 走查"], verifiedAt: hours(18, from: multicamStart)),
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-preview-accepted",
                taskID: "task-preview-focus",
                timestamp: hours(19, from: multicamStart),
                title: "蓝框修复被接受",
                summary: "用户确认状态明显稳定，可以整理进入主分支",
                kind: .accepted,
                loopStage: .acceptance,
                parentEventIDs: ["mc-preview-verified"],
                delivery: .init(stage: .userAccepted, checks: ["用户走查接受"], verifiedAt: hours(19, from: multicamStart)),
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-preview-merged",
                timestamp: previewMergedAt,
                title: "蓝框与预览源修复汇入主线",
                summary: "跨模块播放焦点规则成为当前多机位基线",
                kind: .integrated,
                loopStage: .integration,
                parentEventIDs: ["mc-project-start", "mc-preview-accepted"],
                delivery: .init(stage: .integrated),
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-matrix-start",
                taskID: "task-matrix-gap",
                timestamp: hours(21, from: multicamStart),
                title: "发现 Matrix 空档残帧",
                summary: "当前机位没有 Chunk 时仍显示下一帧或陈旧画面",
                kind: .taskStarted,
                loopStage: .audit,
                parentEventIDs: ["mc-preview-merged"],
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-matrix-implemented",
                taskID: "task-matrix-gap",
                timestamp: hours(24, from: multicamStart),
                title: "空档改为明确空状态",
                summary: "无真实 Chunk 时只显示机位名称和中性背景",
                kind: .implementation,
                loopStage: .implementation,
                parentEventIDs: ["mc-matrix-start"],
                operations: .init(
                    cwd: "/Users/demo/Documents/reframe-app",
                    repository: "/Users/demo/Documents/reframe-app",
                    files: ["src/features/multi-camera-timeline/components/VideoPreviewPanel.vue"]
                ),
                delivery: .init(stage: .changed),
                sourceIDs: [multicamSession.id, moduleBSpec.id]
            ),
            ProjectEvent(
                id: "mc-matrix-accepted",
                taskID: "task-matrix-gap",
                timestamp: hours(26, from: multicamStart),
                title: "Matrix 空状态通过",
                summary: "真实播放中空档不再显示错误画面",
                kind: .accepted,
                loopStage: .acceptance,
                parentEventIDs: ["mc-matrix-implemented"],
                delivery: .init(stage: .userAccepted, checks: ["用户实机确认"], verifiedAt: hours(26, from: multicamStart)),
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-matrix-merged",
                timestamp: matrixMergedAt,
                title: "Matrix 空状态汇入主线",
                summary: "模块 B 空档显示规则成为当前基线",
                kind: .integrated,
                loopStage: .integration,
                parentEventIDs: ["mc-preview-merged", "mc-matrix-accepted"],
                delivery: .init(stage: .integrated),
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-source-start",
                taskID: "task-source-coupling",
                timestamp: hours(22, from: multicamStart),
                title: "高亮跟随与音频耦合复现",
                summary: "播放 Chunk 强制高亮，切换主机位视频源时音频源也被改变",
                kind: .taskStarted,
                loopStage: .reconstruction,
                parentEventIDs: ["mc-preview-merged"],
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-source-audit",
                taskID: "task-source-coupling",
                timestamp: hours(25, from: multicamStart),
                title: "定位两个残留联动",
                summary: "高亮由播放跟随 computed 覆盖，视频源切换仍携带 syncAudio",
                kind: .investigation,
                loopStage: .audit,
                parentEventIDs: ["mc-source-start"],
                facts: ["播放位置和用户选择必须解耦", "视频源和音频源必须解耦"],
                sourceIDs: [multicamSession.id, moduleASpec.id, moduleBSpec.id]
            ),
            ProjectEvent(
                id: "mc-source-implemented",
                taskID: "task-source-coupling",
                timestamp: hours(29, from: multicamStart),
                title: "移除强制跟随并关闭音频同步",
                summary: "播放不再覆盖选中集合，机位切换使用 syncAudio=false",
                kind: .implementation,
                loopStage: .implementation,
                parentEventIDs: ["mc-source-audit"],
                operations: .init(
                    cwd: "/Users/demo/Documents/reframe-app",
                    repository: "/Users/demo/Documents/reframe-app",
                    files: ["src/views/ProjectMultiCamera.vue", "src/features/multi-camera-timeline/components/MultiCameraDetailPanel.vue"]
                ),
                delivery: .init(stage: .changed),
                sourceIDs: [multicamSession.id, reframeRepository.id]
            ),
            ProjectEvent(
                id: "mc-source-accepted",
                taskID: "task-source-coupling",
                timestamp: hours(32, from: multicamStart),
                title: "选择与音视频源解耦通过",
                summary: "用户复测后确认播放与机位切换行为恢复正常",
                kind: .accepted,
                loopStage: .acceptance,
                parentEventIDs: ["mc-source-implemented"],
                delivery: .init(stage: .userAccepted, checks: ["用户复测"], verifiedAt: hours(32, from: multicamStart)),
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-source-merged",
                timestamp: sourceMergedAt,
                title: "选择与来源解耦汇入主线",
                summary: "多机位播放、选择、视频源和音频源成为四个独立状态",
                kind: .integrated,
                loopStage: .integration,
                parentEventIDs: ["mc-matrix-merged", "mc-source-accepted"],
                delivery: .init(stage: .integrated),
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-selection-start",
                taskID: "task-box-selection",
                timestamp: hours(34, from: multicamStart),
                title: "A 框选语义与 C 不一致",
                summary: "A 框选只移动 playhead，没有让框内 Chunk 进入 focused",
                kind: .taskStarted,
                loopStage: .audit,
                parentEventIDs: ["mc-source-merged"],
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-selection-model",
                taskID: "task-box-selection",
                timestamp: hours(36, from: multicamStart),
                title: "以 C 的框选行为为契约",
                summary: "框选只改变 focused 集合，playhead 保持不动，样式同步模块 C",
                kind: .decision,
                loopStage: .confirmation,
                parentEventIDs: ["mc-selection-start"],
                decisions: [
                    DecisionRecord(
                        text: "模块 A 与 C 的框选必须共享选择语义",
                        status: .confirmed,
                        sourceIDs: [multicamSession.id, moduleASpec.id, moduleCSpec.id]
                    )
                ],
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-selection-accepted",
                taskID: "task-box-selection",
                timestamp: hours(40, from: multicamStart),
                title: "框选修复由 Codex 接手完成",
                summary: "实现已作为新 commit 提交，Claude 会话同步最新进展",
                kind: .accepted,
                loopStage: .acceptance,
                parentEventIDs: ["mc-selection-model"],
                delivery: .init(stage: .integrated, checks: ["新 commit 已存在"], verifiedAt: hours(40, from: multicamStart)),
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-selection-merged",
                timestamp: selectionMergedAt,
                title: "A/C 框选语义汇入主线",
                summary: "多机位选择模型完成一次跨模块统一",
                kind: .integrated,
                loopStage: .integration,
                parentEventIDs: ["mc-source-merged", "mc-selection-accepted"],
                delivery: .init(stage: .integrated),
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "mc-report-handoff",
                timestamp: reportHandoffAt,
                title: "工作范围转入报告交互",
                summary: "同一会话开始研究报告正文选择、拖拽和自动分段，后续归入独立项目",
                kind: .handedOff,
                loopStage: .completed,
                parentEventIDs: ["mc-selection-merged"],
                facts: ["会话来源不等于项目边界"],
                sourceIDs: [multicamSession.id]
            )
        ]

        let multicamContext = ProjectContext(
            currentSummary: "多机位版本已完成播放焦点、预览源、选择状态和音视频来源的解耦；后续工作转入报告交互实验。",
            purpose: "让模块 A、B、C 在多机位场景下共享一致、可预测的播放与选择语义。",
            inScope: ["模块 A 多机位轨道", "模块 B 视频预览与 Matrix", "模块 C 粗剪", "跨模块播放焦点"],
            outOfScope: ["报告正文分段", "素材图谱视觉实验", "Agent 模块"],
            understanding: [
                ContextStatement(
                    id: "mc-understanding-focus",
                    text: "蓝框表示模块 B 当前预览来源，只能属于模块 A 或 C，不表示选择。",
                    status: .confirmed,
                    updatedAt: previewMergedAt,
                    sourceIDs: [globalSpec.id, multicamSession.id]
                ),
                ContextStatement(
                    id: "mc-understanding-selection",
                    text: "播放位置、focused Chunk、视频源与音频源是四类独立状态。",
                    status: .confirmed,
                    updatedAt: sourceMergedAt,
                    sourceIDs: [multicamSession.id]
                ),
                ContextStatement(
                    id: "mc-understanding-box",
                    text: "框选只改变选择集合，不应隐式移动 playhead。",
                    status: .confirmed,
                    updatedAt: selectionMergedAt,
                    sourceIDs: [moduleASpec.id, moduleCSpec.id, multicamSession.id]
                )
            ],
            revisions: [
                ContextRevision(
                    id: "mc-revision-start",
                    timestamp: multicamStart,
                    title: "从零散 Bug 转为统一状态审计",
                    summary: "确认问题跨模块，停止继续在局部路径打补丁。",
                    status: .confirmed,
                    changes: ["建立统一 Bug 账本", "把 A/B/C 联动作为一个状态系统"],
                    sourceIDs: [multicamSession.id]
                ),
                ContextRevision(
                    id: "mc-revision-focus",
                    timestamp: previewMergedAt,
                    title: "播放焦点模型确认",
                    summary: "蓝框、预览模式和播放状态由明确动作共同更新。",
                    status: .confirmed,
                    changes: ["蓝框不再等同于选择", "单击与双击拥有不同来源切换语义"],
                    sourceIDs: [multicamSession.id, globalSpec.id]
                ),
                ContextRevision(
                    id: "mc-revision-decoupling",
                    timestamp: sourceMergedAt,
                    title: "选择与来源彻底解耦",
                    summary: "播放不再强制改变选中集合，视频源也不再隐式同步音频源。",
                    status: .confirmed,
                    changes: ["取消播放 Chunk 高亮跟随", "视频源切换使用 syncAudio=false"],
                    sourceIDs: [multicamSession.id]
                ),
                ContextRevision(
                    id: "mc-revision-handoff",
                    timestamp: reportHandoffAt,
                    title: "会话范围发生转移",
                    summary: "报告正文交互不再继续记入多机位项目。",
                    status: .confirmed,
                    changes: ["创建 Reframe · 报告交互关系", "保留原会话作为共同来源"],
                    sourceIDs: [multicamSession.id]
                )
            ]
        )

        let multicamProject = ProjectRecord(
            id: "reframe-multicam",
            name: "Reframe · 多机位",
            summary: "跨模块播放、预览、选择和来源状态的统一",
            status: .waiting,
            accent: .blue,
            createdAt: multicamStart,
            updatedAt: reportHandoffAt,
            lastActivityAt: reportHandoffAt,
            graphPosition: .init(x: 250, y: 245),
            context: multicamContext,
            tasks: multicamTasks,
            events: multicamEvents,
            sourceIDs: [multicamSession.id, globalSpec.id, moduleASpec.id, moduleBSpec.id, moduleCSpec.id, reframeRepository.id]
        )

        let reportStart = reportHandoffAt
        let reportTask = TaskRecord(
            id: "task-report-paragraphs",
            title: "报告正文自动分段",
            objective: "用 Chunk 序号、来源文件和标点恢复可读段落",
            status: .parked,
            accent: .amber,
            currentStage: .verification,
            startedAt: reportStart,
            updatedAt: hours(8, from: reportStart),
            branchedFromEventID: "report-project-start",
            tags: ["模块 A", "报告视图", "数据规律"],
            sourceIDs: [multicamSession.id]
        )
        let reportEvents = [
            ProjectEvent(
                id: "report-project-start",
                timestamp: reportStart,
                title: "报告交互从多机位会话分出",
                summary: "报告正文选择、拖拽与分段获得独立项目边界",
                kind: .projectStarted,
                loopStage: .intake,
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "report-paragraph-start",
                taskID: reportTask.id,
                timestamp: hours(1, from: reportStart),
                title: "分析超大项目正文数据",
                summary: "寻找无需后端计算、可直接用于前端渲染的段落信号",
                kind: .taskStarted,
                loopStage: .audit,
                parentEventIDs: ["report-project-start"],
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "report-paragraph-model",
                taskID: reportTask.id,
                timestamp: hours(5, from: reportStart),
                title: "确认组合分段规则",
                summary: "后一句以句号开头，且 Chunk gap>1 或来源文件变化时分段",
                kind: .decision,
                loopStage: .modeling,
                parentEventIDs: ["report-paragraph-start"],
                decisions: [
                    DecisionRecord(
                        text: "标点归属上一段结尾，不成为新段段首",
                        status: .confirmed,
                        sourceIDs: [multicamSession.id]
                    )
                ],
                sourceIDs: [multicamSession.id]
            ),
            ProjectEvent(
                id: "report-paragraph-preview",
                taskID: reportTask.id,
                timestamp: hours(8, from: reportStart),
                title: "前端分段规则待视觉确认",
                summary: "组合规则与两字符缩进已实现，等待真实报告视图检查",
                kind: .verification,
                loopStage: .verification,
                parentEventIDs: ["report-paragraph-model"],
                delivery: .init(stage: .changed),
                sourceIDs: [multicamSession.id]
            )
        ]
        let reportProject = ProjectRecord(
            id: "reframe-report",
            name: "Reframe · 报告交互",
            summary: "报告正文选择、拖拽和长文本结构实验",
            status: .parked,
            accent: .amber,
            createdAt: reportStart,
            updatedAt: hours(8, from: reportStart),
            lastActivityAt: hours(8, from: reportStart),
            graphPosition: .init(x: 655, y: 155),
            context: ProjectContext(
                currentSummary: "正文分段规则已实现到前端，尚未完成最终视觉确认和集成。",
                purpose: "提高超大项目报告正文的可读性，同时保持 Chunk 级交互。",
                inScope: ["报告正文", "Chunk 选择", "自动分段"],
                outOfScope: ["多机位播放焦点"],
                understanding: [
                    ContextStatement(
                        text: "句号常位于下一 Chunk 开头，渲染时应移动到上一段结尾。",
                        status: .observed,
                        updatedAt: hours(5, from: reportStart),
                        sourceIDs: [multicamSession.id]
                    )
                ],
                revisions: [
                    ContextRevision(
                        timestamp: reportStart,
                        title: "从多机位项目分出",
                        summary: "报告正文工作获得独立目标与完成条件。",
                        status: .confirmed,
                        changes: ["建立独立项目边界"],
                        sourceIDs: [multicamSession.id]
                    )
                ]
            ),
            tasks: [reportTask],
            events: reportEvents,
            sourceIDs: [multicamSession.id, moduleASpec.id]
        )

        let materialStart = days(-9)
        let materialTask = TaskRecord(
            id: "task-material-interaction",
            title: "素材图谱交互语义审计",
            objective: "把 group 滚动、focus、playhead 和蓝框状态拆清",
            status: .active,
            accent: .green,
            currentStage: .modeling,
            startedAt: materialStart,
            updatedAt: days(-1),
            branchedFromEventID: "material-project-start",
            tags: ["模块 A", "素材图谱", "交互模型"],
            sourceIDs: [materialSession.id, moduleASpec.id, globalSpec.id]
        )
        let materialEvents = [
            ProjectEvent(
                id: "material-project-start",
                timestamp: materialStart,
                title: "素材图谱前端实验开始",
                summary: "基于真实数据和模块 A 规范建立可运行交互实验",
                kind: .projectStarted,
                loopStage: .intake,
                sourceIDs: [materialSession.id]
            ),
            ProjectEvent(
                id: "material-audit-start",
                taskID: materialTask.id,
                timestamp: days(-7),
                title: "对照文档与原型",
                summary: "检查 group 滚动、focusedChunkId、playheadAbsoluteTime 和蓝框归属",
                kind: .taskStarted,
                loopStage: .audit,
                parentEventIDs: ["material-project-start"],
                sourceIDs: [materialSession.id, moduleASpec.id, globalSpec.id]
            ),
            ProjectEvent(
                id: "material-model-current",
                taskID: materialTask.id,
                timestamp: days(-1),
                title: "状态解耦模型进行中",
                summary: "正在区分 focus、playhead、播放来源和组滚动四类状态",
                kind: .decision,
                loopStage: .modeling,
                parentEventIDs: ["material-audit-start"],
                delivery: .init(stage: .changed),
                sourceIDs: [materialSession.id, moduleASpec.id]
            )
        ]
        let materialProject = ProjectRecord(
            id: "reframe-material-graph",
            name: "Reframe · 素材图谱",
            summary: "模块 A 素材关系、导航和状态语义实验",
            status: .active,
            accent: .green,
            createdAt: materialStart,
            updatedAt: days(-1),
            lastActivityAt: days(-1),
            graphPosition: .init(x: 560, y: 470),
            context: ProjectContext(
                currentSummary: "真实数据、原型和文档正在对齐；focus、playhead、蓝框和 group 滚动需要保持解耦。",
                purpose: "建立可用于素材探索和 Agent 操作的模块 A 新视图。",
                inScope: ["素材图谱", "group 导航", "Chunk 状态", "真实数据"],
                outOfScope: ["粗剪实现", "完整多机位播放修复"],
                understanding: [
                    ContextStatement(
                        text: "模块 A 的 focus、playhead 和蓝框不能共享同一个状态。",
                        status: .confirmed,
                        updatedAt: days(-1),
                        sourceIDs: [materialSession.id, globalSpec.id]
                    )
                ],
                revisions: [
                    ContextRevision(
                        timestamp: days(-1),
                        title: "借用多机位交互契约",
                        summary: "只复用已经确认的选择与播放语义，不复制旧界面结构。",
                        status: .confirmed,
                        changes: ["复用框选解耦原则", "复用蓝框来源定义"],
                        sourceIDs: [materialSession.id, globalSpec.id]
                    )
                ]
            ),
            tasks: [materialTask],
            events: materialEvents,
            sourceIDs: [materialSession.id, moduleASpec.id, globalSpec.id]
        )

        let relations = [
            ProjectRelation(
                id: "relation-multicam-report",
                fromProjectID: multicamProject.id,
                toProjectID: reportProject.id,
                kind: .workTransferred,
                label: "工作转移",
                status: .confirmed,
                createdAt: reportHandoffAt,
                sourceIDs: [multicamSession.id]
            ),
            ProjectRelation(
                id: "relation-multicam-material",
                fromProjectID: multicamProject.id,
                toProjectID: materialProject.id,
                kind: .sharesContext,
                label: "共享交互契约",
                status: .confirmed,
                createdAt: days(-1),
                sourceIDs: [materialSession.id, globalSpec.id]
            )
        ]

        return WorkspaceSnapshot(
            updatedAt: now,
            projects: [multicamProject, reportProject, materialProject],
            relations: relations,
            sources: [
                multicamSession,
                materialSession,
                globalSpec,
                moduleASpec,
                moduleBSpec,
                moduleCSpec,
                reframeRepository,
                reviewSource
            ],
            reviewInbox: [
                ReviewItem(
                    id: "review-demo",
                    kind: .understandingConflict,
                    projectID: materialProject.id,
                    title: "确认 Storyboard 的产品定位",
                    summary: "新增对话可能改变 Storyboard 与素材图谱的关系。",
                    reason: "新方向会覆盖当前已经确认的独立工作区模型。",
                    previousValue: "Storyboard 是独立工作区，素材图谱负责内容理解。",
                    proposedValue: "Storyboard 并入素材图谱，作为同一工作区的结构视图。",
                    proposedChanges: ["修改 Storyboard 边界", "更新素材图谱与编排关系"],
                    sourceIDs: [reviewSource.id],
                    createdAt: days(-1),
                    updatedAt: days(-1)
                )
            ]
        )
    }
}
