import Darwin
import Foundation
import WorkstateCore
import WorkstateIngestion
import WorkstateUI

@main
struct WorkstateChecks {
    @MainActor
    static func main() throws {
        try bootstrapGraphIntegrity()
        try newWorkspaceStartsEmpty()
        try settingsRoundTrip()
        try modelCatalogFiltersUnsupportedOptions()
        try legacyStateMigration()
        try schemaV3Migration()
        try projectPositionUpdate()
        try projectModelReplacement()
        try daemonStatusWritesOnlyOnChange()
        try dailyBriefProjectsVerifiedDailyState()
        try topicRequiresExplicitPromotion()
        try taskBranchAndMerge()
        try worklineReconciliationRepairsSemanticOwnership()
        try contextRevisionAuthority()
        try projectTimelineHierarchy()
        try projectTimelineParallelProjection()
        try projectBranchTreeProjection()
        try timelineSelectionHierarchy()
        try reviewResolutionAuthority()
        try projectUpdateReviewWritesEventOnConfirmation()
        try sessionScannerIncremental()
        try sessionScannerReadsOnlyChangedFile()
        try sessionScannerPreservesIncompleteLine()
        try sessionCatalogAndHistoryRangeImport()
        try monitoringCutoffDropsDisabledPeriod()
        try segmentProcessingIsIdempotent()
        try sessionWatcherReceivesFileChanges()
        try scannerMemoryRemainsBounded()
        try liveActivityProjection()
        try projectRebuildAppliesVerifiedEvidence()
        try projectRebuildRejectsUnknownEvidence()
        try projectRebuildRejectsDeltaOutsideWorkline()
        try workspaceReconcileRebindsRelationsAndPrunesSources()
        print("Workstate checks passed")
    }

    private static func newWorkspaceStartsEmpty() throws {
        try withFixture { repository in
            try repository.ensureInitialized()
            let snapshot = try repository.load()
            try require(snapshot.projects.isEmpty, "new workspace does not install demo projects")
        }
    }

    private static func settingsRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-settings-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = WorkstateSettingsRepository(root: root)
        let initial = try repository.load(workspaceHasProjects: true)
        try require(initial.setupCompleted, "existing project workspace skips onboarding")
        try require(initial.profile(for: .route).modelID == "gpt-5.6-luna", "router default model")

        var updated = initial
        updated.liveMonitoringEnabled = false
        updated.agentProfiles[.brief] = AgentProfile(modelID: "gpt-5.5", effort: .high)
        try repository.save(updated)
        let loaded = try repository.load()
        try require(!loaded.liveMonitoringEnabled, "monitoring setting persists")
        try require(loaded.profile(for: .brief).effort == .high, "agent effort persists")
    }

    private static func modelCatalogFiltersUnsupportedOptions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-model-catalog-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("models.json")
        let data = """
        {
          "models": [
            {
              "slug": "usable",
              "display_name": "Usable",
              "visibility": "list",
              "supported_in_api": true,
              "default_reasoning_level": "medium",
              "supported_reasoning_levels": [
                {"effort": "low"},
                {"effort": "medium"},
                {"effort": "max"},
                {"effort": "ultra"}
              ]
            },
            {
              "slug": "hidden",
              "display_name": "Hidden",
              "visibility": "hide",
              "supported_in_api": true,
              "default_reasoning_level": "medium",
              "supported_reasoning_levels": [{"effort": "medium"}]
            },
            {
              "slug": "unsupported",
              "display_name": "Unsupported",
              "visibility": "list",
              "supported_in_api": false,
              "default_reasoning_level": "medium",
              "supported_reasoning_levels": [{"effort": "medium"}]
            }
          ]
        }
        """
        try Data(data.utf8).write(to: url)
        let models = try CodexModelCatalog(url: url).load()
        try require(models.map(\.id) == ["usable"], "catalog only exposes listed API models")
        try require(
            models[0].supportedEfforts == [.low, .medium],
            "catalog excludes max, ultra, and unsupported effort options"
        )
    }

    private static func bootstrapGraphIntegrity() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let snapshot = try repository.load()
            try require(snapshot.schemaVersion == 4, "schema version")
            try require(snapshot.projects.count == 3, "bootstrap project count")
            try require(snapshot.relations.count == 2, "bootstrap relation count")

            guard let multicam = snapshot.project(id: "reframe-multicam") else {
                throw CheckFailure.failed("multicam project")
            }
            try require(multicam.tasks.count == 4, "multicam tasks")
            try require(multicam.context.revisions.count == 4, "context revision history")
            try require(multicam.event(id: "mc-report-handoff") != nil, "handoff event")
            try require(
                multicam.event(id: "mc-source-merged")?.parentEventIDs.contains("mc-source-accepted") == true,
                "task merge parent"
            )
            try require(
                snapshot.relations.contains(where: {
                    $0.fromProjectID == "reframe-multicam" && $0.toProjectID == "reframe-report"
                }),
                "cross-project handoff"
            )
        }
    }

    private static func projectPositionUpdate() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let service = WorkstateService(repository: repository)
            let position = GraphPosition(x: 418, y: 276)
            _ = try service.updateProject(
                id: "reframe-multicam",
                update: ProjectUpdate(position: position)
            )
            let updated = try service.snapshot().project(id: "reframe-multicam")
            try require(updated?.graphPosition == position, "project graph position update")
        }
    }

    private static func projectModelReplacement() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let service = WorkstateService(repository: repository)
            _ = try service.updateProjectModel(
                id: "reframe-multicam",
                update: ProjectModelUpdate(
                    currentSummary: "Canonical HEAD",
                    objectModel: ["Project", "Workline", "Delta"],
                    acceptedDecisions: [DecisionRecord(text: "Confirmed decision", status: .confirmed)],
                    forbiddenDirections: ["Do not infer acceptance"],
                    openIssues: ["Verify runtime"]
                )
            )
            let project = try service.snapshot().project(id: "reframe-multicam")
            try require(project?.summary == "Canonical HEAD", "project model updates graph summary")
            try require(project?.context.objectModel == ["Project", "Workline", "Delta"], "project object model replacement")
            try require(project?.context.acceptedDecisions.first?.text == "Confirmed decision", "project accepted decisions replacement")
            try require(project?.context.forbiddenDirections == ["Do not infer acceptance"], "project forbidden directions replacement")
            try require(project?.context.openIssues == ["Verify runtime"], "project open issues replacement")
        }
    }

    private static func legacyStateMigration() throws {
        try withFixture { repository in
            try FileManager.default.createDirectory(at: repository.paths.root, withIntermediateDirectories: true)
            try Data("{\"schemaVersion\":1}".utf8).write(to: repository.paths.state)
            try Data("legacy event\n".utf8).write(to: repository.paths.events)

            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let snapshot = try repository.load()
            let files = try FileManager.default.contentsOfDirectory(atPath: repository.paths.root.path)
            try require(snapshot.schemaVersion == 4, "migrated schema")
            try require(files.contains(where: { $0.hasPrefix("state-v1-backup-") }), "state backup")
            try require(files.contains(where: { $0.hasPrefix("events-v1-backup-") }), "events backup")
        }
    }

    private static func schemaV3Migration() throws {
        try withFixture { repository in
            var object = try JSONSerialization.jsonObject(
                with: WorkstateCoding.makeEncoder().encode(WorkstateBootstrap.makeInitialState())
            ) as! [String: Any]
            object["schemaVersion"] = 3
            object["daemon"] = ["activity": "idle", "pendingEvidenceCount": 0, "detail": "legacy"]
            var projects = object["projects"] as! [[String: Any]]
            for index in projects.indices {
                projects[index].removeValue(forKey: "topics")
            }
            object["projects"] = projects
            let data = try JSONSerialization.data(withJSONObject: object)
            try data.write(to: repository.paths.state)

            try repository.ensureInitialized()
            let snapshot = try repository.load()
            try require(snapshot.schemaVersion == 4, "v3 migrates to v4")
            try require(snapshot.projects.allSatisfy { $0.topics.isEmpty }, "v3 migration initializes topics")
            let migratedText = String(data: try Data(contentsOf: repository.paths.state), encoding: .utf8)!
            try require(!migratedText.contains("\"daemon\""), "daemon leaves canonical state")
        }
    }

    private static func daemonStatusWritesOnlyOnChange() throws {
        try withFixture { repository in
            let statusRepository = DaemonStatusRepository(root: repository.paths.root)
            let status = DaemonSnapshot(activity: .idle, detail: "正在监听 Codex 会话")
            let firstWrite = try statusRepository.saveIfChanged(status)
            try require(firstWrite, "first daemon status write")
            let firstData = try Data(contentsOf: statusRepository.url)
            let secondWrite = try statusRepository.saveIfChanged(status)
            try require(!secondWrite, "identical daemon status is not written")
            let secondData = try Data(contentsOf: statusRepository.url)
            try require(secondData == firstData, "daemon status remains byte-identical")
        }
    }

    private static func dailyBriefProjectsVerifiedDailyState() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 12))!
        let progressTime = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 10))!
        let decisionTime = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 11))!
        let oldTime = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 10))!
        let task = TaskRecord(
            id: "active-task",
            title: "Complete verification",
            objective: "Verify the stable runtime behavior",
            status: .active,
            currentStage: .verification,
            startedAt: oldTime,
            updatedAt: progressTime,
            branchedFromEventID: "start"
        )
        let project = ProjectRecord(
            id: "project",
            name: "Project",
            summary: "Current project state",
            accent: .green,
            context: ProjectContext(
                revisions: [
                    ContextRevision(
                        id: "revision",
                        timestamp: decisionTime,
                        title: "Interaction confirmed",
                        summary: "The final interaction is now authoritative",
                        status: .confirmed
                    )
                ],
                openIssues: ["Observe the foreground canary"]
            ),
            tasks: [task],
            events: [
                ProjectEvent(
                    id: "start",
                    timestamp: oldTime,
                    title: "Project started",
                    summary: "Start",
                    kind: .projectStarted,
                    loopStage: .intake
                ),
                ProjectEvent(
                    id: "progress",
                    taskID: task.id,
                    timestamp: progressTime,
                    title: "Runtime repaired",
                    summary: "Incremental scanning passed",
                    kind: .verification,
                    loopStage: .verification,
                    delivery: DeliverySnapshot(stage: .checked)
                ),
                ProjectEvent(
                    id: "decision",
                    timestamp: decisionTime,
                    title: "Use event-driven ingestion",
                    summary: "Polling is removed",
                    kind: .decision,
                    loopStage: .confirmation
                )
            ]
        )
        let untouched = ProjectRecord(
            id: "untouched",
            name: "Untouched",
            summary: "No changes",
            createdAt: oldTime,
            updatedAt: oldTime,
            lastActivityAt: oldTime
        )
        let workspace = WorkspaceSnapshot(
            updatedAt: decisionTime,
            projects: [project, untouched]
        )
        let brief = try DailyBriefBuilder(calendar: calendar).build(
            workspace: workspace,
            for: day,
            generatedAt: decisionTime
        )
        try require(brief.dateKey == "2026-07-19", "daily brief uses the local calendar day")
        try require(brief.projects.map(\.projectID) == [project.id], "daily brief excludes untouched projects")
        try require(brief.projects.first?.progress.first?.eventID == "progress", "daily progress links to its event")
        try require(brief.confirmedCount == 2, "daily brief collects decisions and confirmed revisions")
        try require(brief.unresolvedCount == 1, "daily brief keeps current unresolved work")
        try require(brief.projects.first?.resumePoints.first?.taskID == task.id, "daily resume links to its task")

        try withFixture { repository in
            let briefs = DailyBriefRepository(root: repository.paths.root)
            let monday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 12))!
            let tuesday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 12))!
            let synchronized = try briefs.synchronize(
                workspace: workspace,
                through: tuesday,
                calendar: calendar
            )
            try require(
                synchronized.map(\.dateKey) == ["2026-07-18", "2026-07-19"],
                "activity history skips calendar days without project changes"
            )
            guard let stored = synchronized.last else {
                throw CheckFailure.failed("latest activity brief exists")
            }
            let initiallyUnread = try briefs.isUnread(stored)
            try require(initiallyUnread, "new daily brief is unread")
            try briefs.markViewed(stored)
            let afterViewing = try briefs.isUnread(stored)
            try require(!afterViewing, "viewed daily brief clears unread state")
            let restored = try briefs.load(dateKey: stored.dateKey)
            try require(restored == stored, "daily brief cache round trip")

            let empty = try briefs.brief(for: monday, workspace: workspace, calendar: calendar)
            try require(empty.isEmpty, "calendar day without activity has no summary")
            let availableAfterEmptyDay = try briefs.availableDateKeys()
            try require(
                availableAfterEmptyDay == ["2026-07-18", "2026-07-19"],
                "empty calendar day is not persisted in history"
            )

            var revisedWorkspace = workspace
            revisedWorkspace.projects[0].events.append(
                ProjectEvent(
                    id: "late-progress",
                    taskID: task.id,
                    timestamp: decisionTime.addingTimeInterval(60),
                    title: "Verification extended",
                    summary: "The same activity day received another meaningful update",
                    kind: .verification,
                    loopStage: .verification
                )
            )
            let revised = try briefs.synchronize(
                workspace: revisedWorkspace,
                through: tuesday,
                calendar: calendar
            ).last!
            try require(
                revised.sourceRevision != stored.sourceRevision,
                "same-day activity changes the summary revision"
            )
            let revisedIsUnread = try briefs.isUnread(revised)
            try require(revisedIsUnread, "same-day new activity restores the unread indicator")

            let tuesdayProgress = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 9))!
            revisedWorkspace.projects[0].events.append(
                ProjectEvent(
                    id: "next-activity-day",
                    taskID: task.id,
                    timestamp: tuesdayProgress,
                    title: "Foreground canary started",
                    summary: "A later activity day now becomes the latest summary",
                    kind: .verification,
                    loopStage: .verification
                )
            )
            let withNextActivityDay = try briefs.synchronize(
                workspace: revisedWorkspace,
                through: tuesday,
                calendar: calendar
            )
            try require(
                withNextActivityDay.map(\.dateKey) == ["2026-07-18", "2026-07-19", "2026-07-21"],
                "the next activity day replaces the latest summary without creating a gap day"
            )
            try require(
                withNextActivityDay[1].projects.allSatisfy {
                    $0.unresolved.isEmpty && $0.resumePoints.isEmpty
                },
                "current unresolved work is not projected backward into historical summaries"
            )

            guard let latestActivityBrief = withNextActivityDay.last else {
                throw CheckFailure.failed("latest narrative activity brief exists")
            }
            let narrative = DailyBriefNarrative(
                sourceRevision: latestActivityBrief.sourceRevision,
                generatedAt: tuesdayProgress,
                overview: "The latest activity is summarized as a narrative.",
                projectSummaries: latestActivityBrief.projects.map {
                    DailyProjectNarrative(projectID: $0.projectID, summary: "Project movement is summarized.")
                },
                nextStep: "Continue the foreground canary."
            )
            let narrated = try briefs.applyNarrative(narrative, to: latestActivityBrief.dateKey)
            try require(narrated.currentNarrative == narrative, "current narrative is persisted with its source revision")

            var changedAgain = revisedWorkspace
            changedAgain.projects[0].events.append(
                ProjectEvent(
                    id: "later-tuesday-progress",
                    taskID: task.id,
                    timestamp: tuesdayProgress.addingTimeInterval(60),
                    title: "Foreground canary advanced",
                    summary: "A later update must not rewrite the scheduled narrative",
                    kind: .verification,
                    loopStage: .verification
                )
            )
            let changedLatest = try briefs.synchronize(
                workspace: changedAgain,
                through: tuesday,
                calendar: calendar
            ).last!
            try require(
                changedLatest == narrated,
                "a scheduled narrative remains immutable when later records arrive"
            )
        }
    }

    private static func topicRequiresExplicitPromotion() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let service = WorkstateService(repository: repository)
            let projectID = "reframe-multicam"
            let topicID = "topic-multitrack"
            _ = try service.upsertTopic(
                projectID: projectID,
                input: ProjectTopicUpdateInput(
                    id: topicID,
                    title: "粗剪多轨讨论",
                    summary: "讨论多轨是否进入产品范围",
                    status: .discussing,
                    kind: .product,
                    currentUnderstanding: "仍是待讨论方向",
                    note: ProjectTopicNote(
                        kind: .origin,
                        title: "议题起源",
                        detail: "用户提出可能需要多轨"
                    )
                )
            )
            let beforePromotion = try service.snapshot().project(id: projectID)
            try require(beforePromotion?.topic(id: topicID)?.status == .discussing, "owner keeps proposal as topic")
            try require(beforePromotion?.context.acceptedDecisions.isEmpty == true, "topic does not alter accepted decisions")

            _ = try service.promoteTopic(
                ProjectTopicPromotionInput(
                    projectID: projectID,
                    topicID: topicID,
                    kind: .decision,
                    title: "粗剪支持多轨",
                    detail: "粗剪时间线进入多轨方向"
                )
            )
            let promoted = try service.snapshot().project(id: projectID)
            try require(promoted?.topic(id: topicID)?.status == .converted, "confirmed topic enters formal flow")
            try require(promoted?.context.acceptedDecisions.last?.text == "粗剪时间线进入多轨方向", "promotion creates decision")
            try require(promoted?.events.contains(where: { $0.title == "粗剪支持多轨" && $0.kind == .decision }) == true, "promotion creates timeline event")
        }
    }

    private static func reviewResolutionAuthority() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let service = WorkstateService(repository: repository)
            let source = SourceReference(
                id: "review-source",
                kind: "conversation",
                label: "Review source",
                locator: "/tmp/source.jsonl",
                threadID: "thread",
                turnIDs: ["turn"],
                excerpt: [ConversationMessage(role: "user", text: "确认修改")]
            )
            _ = try service.addSource(source)
            _ = try service.upsertReview(
                ReviewItem(
                    id: "review",
                    kind: .understandingConflict,
                    projectID: "reframe-multicam",
                    title: "Understanding change",
                    summary: "Confirmed through review",
                    reason: "Conflicts with current HEAD",
                    previousValue: "Old",
                    proposedValue: "New",
                    sourceIDs: [source.id]
                )
            )
            _ = try service.resolveReview(id: "review", status: .confirmed)
            let snapshot = try service.snapshot()
            try require(
                snapshot.reviewInbox.first(where: { $0.id == "review" })?.status == .confirmed,
                "review confirmation state"
            )
            try require(
                snapshot.project(id: "reframe-multicam")?.context.currentSummary == "New",
                "review applies confirmed understanding"
            )
        }
    }

    private static func projectUpdateReviewWritesEventOnConfirmation() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let service = WorkstateService(repository: repository)
            let source = SourceReference(
                id: "update-source",
                kind: "conversation",
                label: "Update source",
                locator: "/tmp/update.jsonl",
                threadID: "thread",
                turnIDs: ["turn"]
            )
            _ = try service.addSource(source)
            let eventDate = timelineDate(42)
            _ = try service.upsertReview(
                ReviewItem(
                    id: "project-update-review",
                    kind: .projectUpdate,
                    projectID: "reframe-multicam",
                    taskID: "task-preview-focus",
                    title: "Verified progress",
                    summary: "A durable project change",
                    reason: "Steward proposal",
                    proposedChanges: ["Check passed"],
                    proposedEvent: ReviewEventProposal(
                        eventID: "approved-delta",
                        timestamp: eventDate,
                        taskID: "task-preview-focus",
                        kind: .verification,
                        stage: .verification,
                        delivery: .checked,
                        facts: ["Check passed"],
                        openIssues: ["Inspect runtime"]
                    ),
                    sourceIDs: [source.id]
                )
            )
            let before = try service.snapshot().project(id: "reframe-multicam")
            try require(before?.event(id: "approved-delta") == nil, "pending update does not mutate project")

            _ = try service.resolveReview(id: "project-update-review", status: .confirmed)
            let project = try service.snapshot().project(id: "reframe-multicam")
            try require(project?.event(id: "approved-delta")?.timestamp == eventDate, "confirmed update preserves event time")
            try require(project?.event(id: "approved-delta")?.delivery.stage == .checked, "confirmed update preserves delivery")
            try require(project?.context.openIssues.contains("Inspect runtime") == true, "confirmed update appends open issue")
        }
    }

    private static func sessionScannerIncremental() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-ingestion-check-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("rollout.jsonl")
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let now = Date()
        let metadataTimestamp = now.addingTimeInterval(-2).formatted(iso)
        let metadata = """
        {"type":"session_meta","timestamp":"\(metadataTimestamp)","payload":{"id":"thread","cwd":"/tmp/project"}}

        """
        try Data(metadata.utf8).write(to: session)

        let scanner = CodexSessionScanner(sessionsRoot: sessions, runtimeRoot: runtime)
        let baseline = try scanner.scan()
        try require(baseline.isEmpty, "first scan establishes baseline")

        let turn = """
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"turn"}}
        {"type":"event_msg","timestamp":"\(now.addingTimeInterval(1).formatted(iso))","payload":{"type":"user_message","message":"Update the project"}}
        {"type":"event_msg","timestamp":"\(now.addingTimeInterval(1).formatted(iso))","payload":{"type":"user_message","message":"Keep the full instruction"}}
        {"type":"event_msg","timestamp":"\(now.addingTimeInterval(2).formatted(iso))","payload":{"type":"task_complete","turn_id":"turn","last_agent_message":"Project updated"}}

        """
        let handle = try FileHandle(forWritingTo: session)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(turn.utf8))
        try handle.close()

        let segments = try scanner.scan()
        try require(segments.count == 1, "one completed turn becomes one segment")
        try require(segments.first?.threadID == "thread", "segment thread id")
        try require(
            segments.first?.userText == "Update the project\n\nKeep the full instruction",
            "segment keeps every user message in the turn"
        )
        try require(segments.first?.assistantText == "Project updated", "segment assistant text")
        let repeated = try scanner.scan()
        try require(repeated.map(\.id) == segments.map(\.id), "pending segment remains available before processing")
        try scanner.markProcessed(segmentIDs: segments.map(\.id))
        let processed = try scanner.scan()
        try require(processed.isEmpty, "processed segment is not returned again")

        let replayTimestamp = now.addingTimeInterval(3).formatted(iso)
        let replay = """
        {"type":"event_msg","timestamp":"\(replayTimestamp)","payload":{"type":"task_started","turn_id":"019e484c-f581-7b63-ac8f-60d1c3c07a7e"}}
        {"type":"event_msg","timestamp":"\(replayTimestamp)","payload":{"type":"user_message","message":"Old replay"}}
        {"type":"event_msg","timestamp":"\(replayTimestamp)","payload":{"type":"task_complete","turn_id":"019e484c-f581-7b63-ac8f-60d1c3c07a7e","last_agent_message":"Old result"}}

        """
        let replayHandle = try FileHandle(forWritingTo: session)
        try replayHandle.seekToEnd()
        try replayHandle.write(contentsOf: Data(replay.utf8))
        try replayHandle.close()
        let replayed = try scanner.scan()
        try require(replayed.count == 1, "a long-running turn is not rejected by turn creation time")
        try require(replayed.first?.userText == "Old replay", "long-running turn content")
        try scanner.markProcessed(segmentIDs: replayed.map(\.id))

        try Data(metadata.utf8).write(to: session, options: .atomic)
        let replaced = try scanner.scan()
        try require(replaced.isEmpty, "a replaced session file establishes a fresh cursor")

        let internalSession = sessions.appendingPathComponent("agent-runtime.jsonl")
        let internalContent = """
        {"type":"session_meta","timestamp":"\(metadataTimestamp)","payload":{"id":"agent-thread","cwd":"/Users/demo/Documents/Workstate/AgentRuntime","originator":"codex_sdk_ts"}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"agent-turn"}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"Router prompt"}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_complete","turn_id":"agent-turn","last_agent_message":"Router result"}}

        """
        try Data(internalContent.utf8).write(to: internalSession)
        let internalResult = try scanner.scan()
        try require(internalResult.isEmpty, "Workstate AgentRuntime sessions never enter project evidence")
        let scannerState = try scanner.loadState()
        try require(
            scannerState.excludedThreadIDs.contains("agent-thread"),
            "Workstate AgentRuntime thread is excluded"
        )

        let guardianSession = sessions.appendingPathComponent("guardian.jsonl")
        let guardian = """
        {"type":"session_meta","timestamp":"\(metadataTimestamp)","payload":{"id":"guardian-thread","cwd":"/tmp/project","originator":"Codex Desktop","source":{"subagent":{"other":"guardian"}}}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"guardian-turn"}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"Approval assessment"}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_complete","turn_id":"guardian-turn","last_agent_message":"Approved"}}

        """
        try Data(guardian.utf8).write(to: guardianSession)
        let guardianResult = try scanner.scan()
        try require(guardianResult.isEmpty, "Codex subagent sessions never enter project evidence")
    }

    private static func sessionScannerReadsOnlyChangedFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-many-sessions-check-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let now = Date()
        var files: [URL] = []
        for index in 0..<400 {
            let file = sessions.appendingPathComponent("rollout-\(index).jsonl")
            let metadata = """
            {"type":"session_meta","timestamp":"\(now.formatted(iso))","payload":{"id":"thread-\(index)","cwd":"/tmp/project-\(index)"}}

            """
            try Data(metadata.utf8).write(to: file)
            files.append(file)
        }

        let scanner = CodexSessionScanner(sessionsRoot: sessions, runtimeRoot: runtime)
        _ = try scanner.scan()
        let baseline = scanner.diagnostics()
        try require(baseline.fullScans == 1, "many-session baseline uses one full scan")
        try require(baseline.metadataReads == 400, "many-session baseline reads each metadata line once")

        let changed = files[237]
        let scannerState = try scanner.loadState()
        let changedPath = scanner.sessionsRoot.appendingPathComponent(changed.lastPathComponent).path
        let changedCursor = scannerState.cursors[changedPath]
        try require(
            changedCursor?.threadID == "thread-237" && changedCursor?.isInternalAgentSession == false,
            "changed-file cursor retains metadata (root \(scanner.sessionsRoot.path), wanted \(changedPath), sample \(scannerState.cursors.keys.sorted().first ?? "nil"), thread \(changedCursor?.threadID ?? "nil"))"
        )
        let turn = """
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"turn"}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"Changed file only"}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_complete","turn_id":"turn","last_agent_message":"Done"}}

        """
        let handle = try FileHandle(forWritingTo: changed)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(turn.utf8))
        try handle.close()

        let segments = try scanner.scanChangedFiles([changed.path])
        let afterChange = scanner.diagnostics()
        try require(segments.count == 1, "changed-file scan captures the completed turn")
        try require(afterChange.changedFileScans == 1, "changed-file scan is recorded")
        try require(afterChange.fullScans == 1, "changed-file event does not enumerate the corpus")
        try require(
            afterChange.metadataReads == baseline.metadataReads,
            "known changed file does not reread corpus metadata (before \(baseline.metadataReads), after \(afterChange.metadataReads))"
        )
        try require(afterChange.evidenceIndexLoads == 1, "evidence index is loaded once")
    }

    private static func sessionScannerPreservesIncompleteLine() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-partial-line-check-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("rollout.jsonl")
        let emptySession = sessions.appendingPathComponent("new-rollout.jsonl")
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let now = Date()
        let metadata = """
        {"type":"session_meta","timestamp":"\(now.formatted(iso))","payload":{"id":"thread","cwd":"/tmp/project"}}

        """
        try Data(metadata.utf8).write(to: session)

        let scanner = CodexSessionScanner(sessionsRoot: sessions, runtimeRoot: runtime)
        _ = try scanner.scan()
        try Data().write(to: emptySession)
        let emptyResult = try scanner.scanChangedFiles([emptySession.path])
        try require(emptyResult.isEmpty, "empty newly-created session waits for metadata")
        try Data("{\"type\":\"session_meta\"".utf8).write(to: emptySession)
        let incompleteMetadataResult = try scanner.scanChangedFiles([emptySession.path])
        try require(incompleteMetadataResult.isEmpty, "incomplete metadata waits for the next file event")

        let prefix = """
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"turn"}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"Keep the partial line"}}

        """
        let completion = """
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_complete","turn_id":"turn","last_agent_message":"Completed after append"}}

        """
        let splitIndex = completion.index(completion.startIndex, offsetBy: completion.count / 2)
        let firstHalf = String(completion[..<splitIndex])
        let secondHalf = String(completion[splitIndex...])
        let firstWrite = try FileHandle(forWritingTo: session)
        try firstWrite.seekToEnd()
        try firstWrite.write(contentsOf: Data((prefix + firstHalf).utf8))
        try firstWrite.close()

        let beforeCompletion = try scanner.scanChangedFiles([session.path])
        try require(beforeCompletion.isEmpty, "incomplete task completion is not consumed")

        let secondWrite = try FileHandle(forWritingTo: session)
        try secondWrite.seekToEnd()
        try secondWrite.write(contentsOf: Data(secondHalf.utf8))
        try secondWrite.close()
        let completed = try scanner.scanChangedFiles([session.path])
        try require(completed.count == 1, "completed partial line becomes evidence on the next event")
        try require(completed.first?.userText == "Keep the partial line", "partial line keeps prior turn state")
    }

    private static func sessionCatalogAndHistoryRangeImport() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-history-import-check-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        let indexURL = root.appendingPathComponent("session_index.jsonl")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let now = Date()
        let old = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let recent = now.addingTimeInterval(-2 * 24 * 60 * 60)
        let selected = sessions.appendingPathComponent("selected.jsonl")
        let irrelevantToolOutput = String(repeating: "x", count: 2 * 1024 * 1024)
        let selectedContent = """
        {"type":"session_meta","timestamp":"\(old.formatted(iso))","payload":{"id":"selected-thread","cwd":"/tmp/SelectedProject"}}
        {"type":"event_msg","timestamp":"\(old.formatted(iso))","payload":{"type":"task_started","turn_id":"old-turn"}}
        {"type":"event_msg","timestamp":"\(old.formatted(iso))","payload":{"type":"user_message","message":"Old history"}}
        {"type":"event_msg","timestamp":"\(old.formatted(iso))","payload":{"type":"task_complete","turn_id":"old-turn","last_agent_message":"Old result"}}
        {"type":"event_msg","timestamp":"\(recent.formatted(iso))","payload":{"type":"task_started","turn_id":"recent-turn"}}
        {"type":"event_msg","timestamp":"\(recent.formatted(iso))","payload":{"type":"user_message","message":"Recent history"}}
        {"type":"response_item","payload":{"type":"tool_output","output":"\(irrelevantToolOutput)"}}
        {"type":"event_msg","timestamp":"\(recent.formatted(iso))","payload":{"type":"task_complete","turn_id":"recent-turn","last_agent_message":"Recent result"}}

        """
        try Data(selectedContent.utf8).write(to: selected)

        let unselected = sessions.appendingPathComponent("unselected.jsonl")
        let unselectedContent = """
        {"type":"session_meta","timestamp":"\(recent.formatted(iso))","payload":{"id":"unselected-thread","cwd":"/tmp/OtherProject"}}

        """
        try Data(unselectedContent.utf8).write(to: unselected)
        let index = """
        {"id":"selected-thread","thread_name":"Older title","updated_at":"\(old.formatted(iso))"}
        {"id":"selected-thread","thread_name":"Selected task title","updated_at":"\(recent.formatted(iso))"}
        {"id":"unselected-thread","thread_name":"Other task","updated_at":"\(recent.formatted(iso))"}

        """
        try Data(index.utf8).write(to: indexURL)

        let scanner = CodexSessionScanner(sessionsRoot: sessions, runtimeRoot: runtime)
        let catalog = try scanner.sessionCatalog(indexURL: indexURL)
        try require(catalog.count == 2, "session catalog lists non-internal Codex tasks")
        try require(
            catalog.first(where: { $0.id == "selected-thread" })?.title == "Selected task title",
            "session catalog keeps the latest Codex title"
        )
        let interval = DateInterval(
            start: now.addingTimeInterval(-3 * 24 * 60 * 60),
            end: now.addingTimeInterval(24 * 60 * 60)
        )
        let preview = try scanner.previewHistory(
            threadIDs: ["selected-thread"],
            interval: interval
        )
        try require(preview.completedTurnCount == 1, "history preview counts completed turns")
        try require(
            preview.evidenceBytes < 32 * 1024,
            "history preview excludes irrelevant tool payloads from model input size"
        )
        let imported = try scanner.importHistory(
            threadIDs: ["selected-thread"],
            interval: interval
        )
        try require(imported.count == 1, "history import applies the selected date range")
        try require(imported[0].turnID == "recent-turn", "history import excludes older turns")
        let recentSegments = try scanner.recentSegments(
            threadID: "selected-thread",
            before: now.addingTimeInterval(2 * 24 * 60 * 60)
        )
        try require(recentSegments.map(\.turnID) == ["recent-turn"], "evidence index reloads text by file location")
        let state = try scanner.loadState()
        try require(state.initialized, "history import establishes the live baseline")
        try require(state.cursors.count == 2, "history import primes selected and unselected tasks")
    }

    private static func monitoringCutoffDropsDisabledPeriod() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-monitoring-cutoff-check-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let now = Date()
        let session = sessions.appendingPathComponent("rollout.jsonl")
        let metadata = """
        {"type":"session_meta","timestamp":"\(now.formatted(iso))","payload":{"id":"thread","cwd":"/tmp/project"}}

        """
        try Data(metadata.utf8).write(to: session)
        let scanner = CodexSessionScanner(sessionsRoot: sessions, runtimeRoot: runtime)
        _ = try scanner.scan()

        let beforeCutoff = now.addingTimeInterval(-60)
        let afterCutoff = now.addingTimeInterval(60)
        let turns = """
        {"type":"event_msg","timestamp":"\(beforeCutoff.formatted(iso))","payload":{"type":"task_started","turn_id":"disabled-turn"}}
        {"type":"event_msg","timestamp":"\(beforeCutoff.formatted(iso))","payload":{"type":"user_message","message":"Disabled period"}}
        {"type":"event_msg","timestamp":"\(beforeCutoff.formatted(iso))","payload":{"type":"task_complete","turn_id":"disabled-turn","last_agent_message":"Ignored"}}
        {"type":"event_msg","timestamp":"\(afterCutoff.formatted(iso))","payload":{"type":"task_started","turn_id":"enabled-turn"}}
        {"type":"event_msg","timestamp":"\(afterCutoff.formatted(iso))","payload":{"type":"user_message","message":"Enabled period"}}
        {"type":"event_msg","timestamp":"\(afterCutoff.formatted(iso))","payload":{"type":"task_complete","turn_id":"enabled-turn","last_agent_message":"Recorded"}}

        """
        let handle = try FileHandle(forWritingTo: session)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(turns.utf8))
        try handle.close()

        let result = try scanner.scanChangedFiles([session.path], minimumTimestamp: now)
        try require(result.map(\.turnID) == ["enabled-turn"], "monitoring cutoff drops disabled-period turns")
        let evidence = try Data(contentsOf: scanner.evidenceURL)
        let evidenceText = String(data: evidence, encoding: .utf8) ?? ""
        try require(!evidenceText.contains("Disabled period"), "disabled-period content never enters evidence")
    }

    private static func segmentProcessingIsIdempotent() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let sessions = repository.paths.root.appendingPathComponent("sessions", isDirectory: true)
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            let session = sessions.appendingPathComponent("rollout.jsonl")
            let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            let now = Date()
            let metadata = """
            {"type":"session_meta","timestamp":"\(now.formatted(iso))","payload":{"id":"thread","cwd":"/tmp/project"}}

            """
            try Data(metadata.utf8).write(to: session)
            let scanner = CodexSessionScanner(sessionsRoot: sessions, runtimeRoot: repository.paths.root)
            _ = try scanner.scan()

            let turn = """
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"turn"}}
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"Persist this segment"}}
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_complete","turn_id":"turn","last_agent_message":"Persisted"}}

            """
            let handle = try FileHandle(forWritingTo: session)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(turn.utf8))
            try handle.close()
            let segments = try scanner.scanChangedFiles([session.path])
            guard let segment = segments.first else {
                throw CheckFailure.failed("processing segment fixture")
            }

            try scanner.beginProcessing(segmentID: segment.id, stage: .routing)
            let runtime = AgentRuntimeClient(
                runtimeScript: repository.paths.root.appendingPathComponent("missing-runtime.js"),
                nodePath: "/missing/node",
                runtimeRoot: repository.paths.root
            )
            let orchestrator = WorkstateOrchestrator(
                service: WorkstateService(repository: repository),
                scanner: scanner,
                runtime: runtime
            )
            let interrupted = try orchestrator.process([segment])
            try require(interrupted.failed == 1, "interrupted segment is marked failed")
            try require(interrupted.agentRuns == 0, "interrupted segment does not call the model")

            let repeated = try orchestrator.process([segment])
            try require(repeated.failed == 1, "failed segment remains pending for diagnosis")
            try require(repeated.agentRuns == 0, "failed segment is not automatically retried")
            let failedRecord = try scanner.processingRecord(segmentID: segment.id)
            try require(failedRecord.stage == .failed, "failed stage persists")

            try scanner.requeue(segmentIDs: [segment.id])
            let requeuedRecord = try scanner.processingRecord(segmentID: segment.id)
            try require(requeuedRecord.stage == .queued, "explicit requeue resets failed stage")
            try scanner.recordRouteResult(
                segmentID: segment.id,
                route: RouteResult(
                    action: "ignore",
                    projectId: "",
                    projectName: "",
                    projectSummary: "",
                    confidence: 1,
                    reason: "No durable project change"
                )
            )
            let resumed = try orchestrator.process([segment])
            try require(resumed.processed == 1, "persisted route result resumes deterministically")
            try require(resumed.agentRuns == 0, "persisted route result does not repeat the model call")
            let completedRecord = try scanner.processingRecord(segmentID: segment.id)
            try require(completedRecord.stage == .completed, "completed stage persists")
        }
    }

    private static func sessionWatcherReceivesFileChanges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-watcher-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let capture = WatcherCapture()
        let watcher = CodexSessionWatcher(root: root) { batch in
            capture.receive(batch)
        }
        try watcher.start()
        defer { watcher.stop() }

        let session = root.appendingPathComponent("rollout.jsonl")
        let content = """
        {"type":"session_meta","timestamp":"2026-07-17T00:00:00.000Z","payload":{"id":"thread","cwd":"/tmp/project"}}

        """
        try Data(content.utf8).write(to: session)
        let result = capture.wait(timeout: 5)
        try require(result != nil, "FSEvents watcher receives a session file change")
        try require(
            result?.requiresFullScan == true || result?.paths.contains(where: { $0.hasSuffix("rollout.jsonl") }) == true,
            "FSEvents watcher identifies the changed session file"
        )
    }

    private static func scannerMemoryRemainsBounded() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-memory-check-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let metadata = """
        {"type":"session_meta","timestamp":"2026-07-17T00:00:00.000Z","payload":{"id":"thread","cwd":"/tmp/project"}}

        """
        let session = sessions.appendingPathComponent("rollout.jsonl")
        try Data(metadata.utf8).write(to: session)
        for index in 1..<400 {
            let file = sessions.appendingPathComponent("rollout-\(index).jsonl")
            let content = metadata.replacingOccurrences(of: "\"thread\"", with: "\"thread-\(index)\"")
            try Data(content.utf8).write(to: file)
        }

        let scanner = CodexSessionScanner(sessionsRoot: sessions, runtimeRoot: runtime)
        _ = try scanner.scan()
        for _ in 0..<200 {
            autoreleasepool {
                _ = try? scanner.scanChangedFiles([session.path])
            }
        }
        let before = try residentMemoryBytes()
        for _ in 0..<5_000 {
            try autoreleasepool {
                _ = try scanner.scanChangedFiles([session.path])
            }
        }
        let after = try residentMemoryBytes()
        let growth = after > before ? after - before : 0
        try require(growth < 32 * 1024 * 1024, "incremental scanner memory remains bounded (grew \(growth) bytes)")
        let diagnostics = scanner.diagnostics()
        try require(diagnostics.fullScans == 1, "memory soak performs only one full scan")
        try require(diagnostics.metadataReads == 400, "memory soak never rereads known metadata")
    }

    private static func residentMemoryBytes() throws -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            throw CheckFailure.failed("could not read scanner resident memory")
        }
        return UInt64(info.resident_size)
    }

    private static func liveActivityProjection() throws {
        let source = SourceReference(
            id: "source",
            kind: "conversation",
            label: "Thread",
            locator: "codex://thread",
            threadID: "thread"
        )
        let project = ProjectRecord(
            id: "project",
            name: "Project",
            summary: "Summary",
            graphPosition: .init(x: 0, y: 0),
            sourceIDs: [source.id]
        )
        let session = ActiveSession(
            threadID: "thread",
            turnID: "turn",
            cwd: "/tmp/project",
            userText: "正在完成实时状态节点",
            updatedAt: timelineDate(10)
        )
        let activities = LiveActivityProjector().project(
            sessions: [session],
            workspace: WorkspaceSnapshot(projects: [project], sources: [source])
        )

        try require(activities.count == 1, "known project thread creates live activity")
        try require(activities.first?.projectID == project.id, "live activity uses source-owned project")
        try require(activities.first?.title == session.userText, "live activity keeps current objective")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-live-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LiveActivityRepository(root: root)
        let snapshot = LiveActivitySnapshot(updatedAt: timelineDate(11), activities: activities)
        try repository.save(snapshot)
        let restored = try repository.load()
        try require(restored == snapshot, "live activity snapshot round trip")
    }

    private static func projectRebuildAppliesVerifiedEvidence() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkspaceSnapshot())
            let service = WorkstateService(repository: repository)
            _ = try service.createProject(
                ProjectCreateInput(
                    id: "project",
                    name: "Project",
                    summary: "Old state",
                    purpose: "Old purpose",
                    position: GraphPosition(x: 80, y: 120)
                )
            )
            let evidence = rebuildEvidence()
            _ = try ProjectRebuildApplier(repository: repository).apply(
                rebuildProposal(evidenceID: evidence.id),
                evidence: [evidence]
            )

            guard let project = try repository.load().project(id: "project") else {
                throw CheckFailure.failed("rebuilt project exists")
            }
            try require(project.summary == "Verified project HEAD", "rebuild replaces project HEAD")
            try require(project.context.objectModel == ["Project", "Workline", "Delta"], "rebuild replaces object model")
            try require(project.tasks.map(\.id) == ["project-core-workline"], "rebuild creates semantic workline")
            try require(project.events.contains(where: { $0.id == "project-core-delta" }), "rebuild creates delta")
            try require(project.events.contains(where: { $0.id == "rebuild-merge-project-core-workline" }), "completed workline merges")
            guard let source = try repository.load().sources.first(where: { $0.threadID == evidence.threadID }) else {
                throw CheckFailure.failed("rebuild source")
            }
            try require(source.turnIDs == [evidence.turnID], "rebuild source keeps exact turn")
            try require(source.excerpt.first?.text == evidence.userText, "rebuild source keeps conversation excerpt")
        }
    }

    private static func projectRebuildRejectsUnknownEvidence() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkspaceSnapshot())
            let service = WorkstateService(repository: repository)
            _ = try service.createProject(
                ProjectCreateInput(
                    id: "project",
                    name: "Project",
                    summary: "Old state",
                    purpose: "Old purpose",
                    position: GraphPosition(x: 80, y: 120)
                )
            )
            let evidence = rebuildEvidence()
            do {
                _ = try ProjectRebuildApplier(repository: repository).apply(
                    rebuildProposal(evidenceID: "unknown-turn"),
                    evidence: [evidence]
                )
                throw CheckFailure.failed("unknown rebuild evidence must fail")
            } catch let error as WorkstateStorageError {
                guard case .invalidState(let message) = error else { throw error }
                try require(message.contains("unknown evidence"), "unknown evidence diagnostic")
            }
            let unchanged = try repository.load().project(id: "project")
            try require(unchanged?.summary == "Old state", "failed rebuild is atomic")
        }
    }

    private static func projectRebuildRejectsDeltaOutsideWorkline() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkspaceSnapshot())
            let service = WorkstateService(repository: repository)
            _ = try service.createProject(
                ProjectCreateInput(
                    id: "project",
                    name: "Project",
                    summary: "Old state",
                    purpose: "Old purpose",
                    position: GraphPosition(x: 80, y: 120)
                )
            )
            let evidence = rebuildEvidence()
            var proposal = rebuildProposal(evidenceID: evidence.id)
            proposal.worklines[0].startedAt = "1970-01-01T00:04:00Z"
            proposal.worklines[0].updatedAt = "1970-01-01T00:05:00Z"
            proposal.worklines[0].completedAt = "1970-01-01T00:05:00Z"
            do {
                _ = try ProjectRebuildApplier(repository: repository).apply(proposal, evidence: [evidence])
                throw CheckFailure.failed("delta outside workline must fail")
            } catch let error as WorkstateStorageError {
                guard case .invalidState(let message) = error else { throw error }
                try require(message.contains("predates workline"), "workline boundary diagnostic")
            }
        }
    }

    private static func workspaceReconcileRebindsRelationsAndPrunesSources() throws {
        try withFixture { repository in
            let retained = SourceReference(id: "retained", kind: "conversation", label: "Retained", locator: "codex://thread")
            let obsolete = SourceReference(id: "obsolete", kind: "conversation", label: "Obsolete", locator: "claude://thread")
            let first = ProjectRecord(
                id: "first",
                name: "First",
                summary: "First",
                graphPosition: GraphPosition(x: 0, y: 0),
                sourceIDs: [retained.id]
            )
            let second = ProjectRecord(
                id: "second",
                name: "Second",
                summary: "Second",
                graphPosition: GraphPosition(x: 100, y: 0)
            )
            let relation = ProjectRelation(
                id: "relation",
                fromProjectID: first.id,
                toProjectID: second.id,
                kind: .sharesContext,
                label: "Relation",
                sourceIDs: [obsolete.id]
            )
            try repository.ensureInitialized(
                initial: WorkspaceSnapshot(
                    projects: [first, second],
                    relations: [relation],
                    sources: [retained, obsolete]
                )
            )
            let result = try WorkspaceReconciler(repository: repository).reconcile(
                relationSources: [
                    RelationSourceReplacement(relationID: relation.id, sourceIDs: [retained.id])
                ]
            )
            try require(result.snapshot.relations.first?.sourceIDs == [retained.id], "relation source replacement")
            try require(result.snapshot.sources.map(\.id) == [retained.id], "unused source pruning")
            try require(result.removedSourceCount == 1, "removed source count")
        }
    }

    private static func rebuildEvidence() -> SessionSegment {
        SessionSegment(
            threadID: "thread",
            turnID: "turn",
            sourcePath: "/tmp/thread.jsonl",
            startOffset: 10,
            endOffset: 20,
            cwd: "/tmp/project",
            userText: "确认最终结构",
            assistantText: "已经完成并验证",
            timestamp: Date(timeIntervalSince1970: 200)
        )
    }

    private static func rebuildProposal(evidenceID: String) -> ProjectRebuildProposal {
        ProjectRebuildProposal(
            projectId: "project",
            status: "completed",
            currentSummary: "Verified project HEAD",
            purpose: "Preserve durable project context",
            inScope: ["Project context"],
            outOfScope: ["Operational housekeeping"],
            objectModel: [
                RebuildStatement(text: "Project", evidenceIds: [evidenceID]),
                RebuildStatement(text: "Workline", evidenceIds: [evidenceID]),
                RebuildStatement(text: "Delta", evidenceIds: [evidenceID])
            ],
            understanding: [
                RebuildUnderstanding(text: "The project is complete", status: "confirmed", evidenceIds: [evidenceID])
            ],
            acceptedDecisions: [
                RebuildDecision(text: "Use verified evidence", rationale: "Confirmed by the user", evidenceIds: [evidenceID])
            ],
            forbiddenDirections: [
                RebuildStatement(text: "Do not infer acceptance", evidenceIds: [evidenceID])
            ],
            openIssues: [],
            worklines: [
                RebuildWorkline(
                    id: "project-core-workline",
                    title: "Core workline",
                    objective: "Reach the verified result",
                    status: "completed",
                    stage: "completed",
                    startedAt: "1970-01-01T00:02:00Z",
                    updatedAt: "1970-01-01T00:03:20Z",
                    completedAt: "1970-01-01T00:03:20Z",
                    tags: ["core"],
                    evidenceIds: [evidenceID]
                )
            ],
            deltas: [
                RebuildDelta(
                    id: "project-core-delta",
                    worklineId: "project-core-workline",
                    timestamp: "1970-01-01T00:03:20Z",
                    title: "Result verified",
                    summary: "The user confirmed the final result.",
                    kind: "accepted",
                    stage: "acceptance",
                    delivery: "userAccepted",
                    facts: ["The result was rendered"],
                    decisions: ["The result is accepted"],
                    evidenceIds: [evidenceID]
                )
            ]
        )
    }

    private static func taskBranchAndMerge() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkspaceSnapshot())
            let service = WorkstateService(repository: repository)
            _ = try service.createProject(
                ProjectCreateInput(
                    id: "project",
                    name: "Project",
                    summary: "Graph test",
                    purpose: "Verify branching",
                    position: GraphPosition(x: 100, y: 100)
                )
            )
            guard let start = try service.snapshot().project(id: "project")?.latestEvent else {
                throw CheckFailure.failed("project start event")
            }
            _ = try service.startTask(
                TaskStartInput(
                    projectID: "project",
                    id: "task",
                    title: "Task",
                    objective: "Branch and merge",
                    branchedFromEventID: start.id
                )
            )
            _ = try service.appendEvent(
                EventInput(
                    id: "implementation",
                    projectID: "project",
                    taskID: "task",
                    title: "Implemented",
                    summary: "Changed state",
                    kind: .implementation,
                    stage: .implementation,
                    delivery: DeliverySnapshot(stage: .changed)
                )
            )
            _ = try service.appendEvent(
                EventInput(
                    id: "merge",
                    projectID: "project",
                    mergeTaskID: "task",
                    title: "Merged",
                    summary: "Task returned to mainline",
                    kind: .integrated,
                    stage: .integration,
                    delivery: DeliverySnapshot(stage: .integrated)
                )
            )

            guard let project = try service.snapshot().project(id: "project"),
                  let task = project.task(id: "task"),
                  let taskStart = project.events.first(where: { $0.taskID == "task" && $0.kind == .taskStarted }),
                  let implementation = project.event(id: "implementation"),
                  let merge = project.event(id: "merge") else {
                throw CheckFailure.failed("stored branch graph")
            }
            try require(task.status == .completed, "merged task status")
            try require(task.mergedByEventID == "merge", "task merge event")
            try require(implementation.parentEventIDs == [taskStart.id], "inferred task parent")
            try require(merge.parentEventIDs.contains(start.id), "mainline merge parent")
            try require(merge.parentEventIDs.contains("implementation"), "branch merge parent")
        }
    }

    private static func contextRevisionAuthority() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let service = WorkstateService(repository: repository)
            let projectID = "reframe-multicam"
            let original = try service.snapshot().project(id: projectID)?.context.currentSummary

            _ = try service.reviseContext(
                ContextRevisionInput(
                    id: "inferred",
                    projectID: projectID,
                    title: "Inference",
                    summary: "Not authoritative",
                    status: .inferred,
                    currentSummary: "Must not become current",
                    statementID: "candidate",
                    statement: "Candidate understanding"
                )
            )
            let afterInference = try service.snapshot().project(id: projectID)
            try require(afterInference?.context.currentSummary == original, "inference does not replace current summary")
            try require(
                afterInference?.context.understanding.first(where: { $0.id == "candidate" })?.status == .inferred,
                "inference remains labeled"
            )

            _ = try service.reviseContext(
                ContextRevisionInput(
                    id: "confirmed",
                    projectID: projectID,
                    title: "Confirmed",
                    summary: "Authoritative update",
                    status: .confirmed,
                    currentSummary: "New current understanding",
                    statementID: "candidate",
                    statement: "Confirmed understanding"
                )
            )
            let confirmed = try service.snapshot().project(id: projectID)
            try require(confirmed?.context.currentSummary == "New current understanding", "confirmed summary update")
            try require(
                confirmed?.context.understanding.first(where: { $0.id == "candidate" })?.status == .confirmed,
                "statement authority update"
            )
        }
    }

    private static func projectTimelineHierarchy() throws {
        let start = ProjectEvent(
            id: "project-start",
            timestamp: timelineDate(0),
            title: "Project started",
            summary: "Start",
            kind: .projectStarted,
            loopStage: .intake
        )
        let task = timelineTask(id: "task", start: 1, update: 3, completion: 4)
        let taskStart = ProjectEvent(
            id: "task-start",
            taskID: task.id,
            timestamp: timelineDate(1),
            title: "Task started",
            summary: "Synthetic wrapper",
            kind: .taskStarted,
            loopStage: .intake
        )
        let internalEvent = ProjectEvent(
            id: "task-progress",
            taskID: task.id,
            timestamp: timelineDate(3),
            title: "Implemented",
            summary: "Internal progress",
            kind: .implementation,
            loopStage: .implementation
        )
        let merge = ProjectEvent(
            id: "merge",
            timestamp: timelineDate(4),
            title: "Merged",
            summary: "Returned to mainline",
            kind: .integrated,
            loopStage: .integration
        )
        let project = ProjectRecord(
            id: "project",
            name: "Project",
            summary: "Summary",
            graphPosition: .init(x: 0, y: 0),
            tasks: [task],
            events: [start, taskStart, internalEvent, merge]
        )
        let layout = ProjectTimelineLayout(project: project)

        try require(layout.nodes.map(\.id) == [internalEvent.id, start.id], "timeline shows durable events newest first")
        try require(layout.nodes.allSatisfy { $0.point.x == ProjectTimelineLayout.mainlineX }, "ordinary events stay on mainline")
        try require(!layout.nodes.contains(where: { $0.id == taskStart.id }), "synthetic task start stays hidden")
        try require(!layout.nodes.contains(where: { $0.id == merge.id }), "synthetic merge stays hidden")
        try require(Set(layout.nodes.map { $0.point.y }).count == layout.nodes.count, "every visible event gets its own row")
    }

    private static func projectBranchTreeProjection() throws {
        let projectStart = ProjectEvent(
            id: "project-start",
            timestamp: timelineDate(0),
            title: "Project started",
            summary: "Start",
            kind: .projectStarted,
            loopStage: .intake
        )
        let parent = TaskRecord(
            id: "base-method",
            title: "Base method",
            objective: "Establish the base method",
            status: .active,
            startedAt: timelineDate(1),
            updatedAt: timelineDate(3),
            branchedFromEventID: projectStart.id
        )
        let baseEvent = ProjectEvent(
            id: "base-result",
            taskID: parent.id,
            timestamp: timelineDate(2),
            title: "Base result",
            summary: "Established the base",
            kind: .implementation,
            loopStage: .implementation
        )
        let child = TaskRecord(
            id: "variant-method",
            title: "Variant method",
            objective: "Test one modification",
            status: .abandoned,
            startedAt: timelineDate(3),
            updatedAt: timelineDate(5),
            branchedFromEventID: baseEvent.id
        )
        let childEvent = ProjectEvent(
            id: "variant-result",
            taskID: child.id,
            timestamp: timelineDate(4),
            title: "Variant failed",
            summary: "Recorded why the branch did not work",
            kind: .verification,
            loopStage: .verification
        )
        let project = ProjectRecord(
            id: "project",
            name: "Project",
            summary: "Summary",
            graphPosition: .init(x: 0, y: 0),
            tasks: [parent, child],
            events: [projectStart, baseEvent, childEvent]
        )

        let currentLayout = ProjectBranchTreeLayout(project: project)
        try require(currentLayout.rows.map(\.id) == [parent.id], "current branch tree hides abandoned tasks")
        try require(!currentLayout.nodes.contains(where: { $0.id == childEvent.id }), "current branch tree hides abandoned task logs")

        let layout = ProjectBranchTreeLayout(project: project, includesHistory: true)
        try require(layout.rows.map(\.id) == [parent.id, child.id], "branch tree keeps parent before child")
        try require(layout.rows.last?.depth == 1, "branch tree records child depth")
        guard let parentPoint = layout.nodes.first(where: { $0.id == baseEvent.id })?.point,
              let childPath = layout.paths.first(where: { $0.task.id == child.id }) else {
            throw CheckFailure.failed("branch tree geometry")
        }
        try require(childPath.points.first == parentPoint, "branch starts from its exact parent event")
        try require(layout.nodes.contains(where: { $0.id == childEvent.id }), "failed branch log remains visible")

        let completedParent = TaskRecord(
            id: parent.id,
            title: parent.title,
            objective: parent.objective,
            status: .completed,
            startedAt: parent.startedAt,
            updatedAt: parent.updatedAt,
            completedAt: parent.updatedAt,
            branchedFromEventID: parent.branchedFromEventID
        )
        let activeChild = TaskRecord(
            id: child.id,
            title: child.title,
            objective: child.objective,
            status: .active,
            startedAt: child.startedAt,
            updatedAt: child.updatedAt,
            branchedFromEventID: child.branchedFromEventID
        )
        let currentProject = ProjectRecord(
            id: project.id,
            name: project.name,
            summary: project.summary,
            graphPosition: project.graphPosition,
            tasks: [completedParent, activeChild],
            events: project.events
        )
        let promotedLayout = ProjectBranchTreeLayout(project: currentProject)
        try require(promotedLayout.rows.map(\.id) == [activeChild.id], "active child remains visible when completed parent is hidden")
        try require(promotedLayout.rows.first?.parentTaskID == nil, "active child becomes a current-view root")
        try require(promotedLayout.rows.first?.depth == 0, "promoted active child has root depth")
    }

    private static func worklineReconciliationRepairsSemanticOwnership() throws {
        try withFixture { repository in
            let start = ProjectEvent(
                id: "project-start",
                timestamp: timelineDate(0),
                title: "Project started",
                summary: "Start",
                kind: .projectStarted,
                loopStage: .intake
            )
            let parent = TaskRecord(
                id: "parent",
                title: "Parent",
                objective: "Parent objective",
                status: .active,
                currentStage: .implementation,
                startedAt: timelineDate(1),
                updatedAt: timelineDate(5),
                branchedFromEventID: start.id
            )
            let base = ProjectEvent(
                id: "base",
                taskID: parent.id,
                timestamp: timelineDate(1),
                title: "Base",
                summary: "Parent base",
                kind: .implementation,
                loopStage: .implementation
            )
            let interaction = ProjectEvent(
                id: "interaction",
                taskID: parent.id,
                timestamp: timelineDate(2),
                title: "Interaction",
                summary: "Interaction scope",
                kind: .decision,
                loopStage: .confirmation
            )
            let interactionDone = ProjectEvent(
                id: "interaction-done",
                taskID: parent.id,
                timestamp: timelineDate(3),
                title: "Interaction done",
                summary: "Completed scope",
                kind: .implementation,
                loopStage: .implementation
            )
            let repair = ProjectEvent(
                id: "repair",
                taskID: parent.id,
                timestamp: timelineDate(4),
                title: "Repair",
                summary: "Independent repair",
                kind: .investigation,
                loopStage: .audit
            )
            let project = ProjectRecord(
                id: "project",
                name: "Project",
                summary: "Summary",
                graphPosition: .init(x: 0, y: 0),
                tasks: [parent],
                events: [start, base, interaction, interactionDone, repair]
            )
            try repository.ensureInitialized(initial: WorkspaceSnapshot(projects: [project]))
            let service = WorkstateService(repository: repository)
            _ = try service.reconcileWorklines(
                WorklineReconciliationInput(
                    projectID: project.id,
                    worklines: [
                        WorklineReconciliation(
                            id: "interaction-workline",
                            title: "Interaction workline",
                            objective: "Settle interaction rules",
                            status: .completed,
                            accent: .amber,
                            branchedFromEventID: base.id,
                            mergedByEventID: interactionDone.id,
                            eventIDs: [interaction.id, interactionDone.id]
                        ),
                        WorklineReconciliation(
                            id: "repair-workline",
                            title: "Repair workline",
                            objective: "Repair display data",
                            status: .active,
                            accent: .cyan,
                            branchedFromEventID: base.id,
                            eventIDs: [repair.id]
                        )
                    ]
                )
            )

            let repaired = try service.snapshot().project(id: project.id)!
            try require(repaired.event(id: interaction.id)?.taskID == "interaction-workline", "interaction event ownership")
            try require(repaired.event(id: repair.id)?.taskID == "repair-workline", "repair event ownership")
            try require(repaired.task(id: "interaction-workline")?.status == .completed, "completed workline status")
            try require(repaired.task(id: "repair-workline")?.status == .active, "active workline status")
            try require(repaired.task(id: parent.id)?.updatedAt == base.timestamp, "parent workline timestamp is recalculated")
            try require(ProjectTimelineLayout(project: repaired).branches.count == 2, "semantic worklines create independent branches")
        }
    }

    private static func projectTimelineParallelProjection() throws {
        let firstTask = timelineTask(id: "first", start: 1, update: 3, completion: nil)
        let secondTask = TaskRecord(
            id: "second",
            title: "second",
            objective: "second",
            status: .active,
            accent: .violet,
            currentStage: .implementation,
            startedAt: timelineDate(2),
            updatedAt: timelineDate(2),
            branchedFromEventID: "before"
        )
        let start = ProjectEvent(
            id: "start",
            timestamp: timelineDate(0),
            title: "Start",
            summary: "Start",
            kind: .projectStarted,
            loopStage: .intake
        )
        let before = ProjectEvent(
            id: "before",
            taskID: firstTask.id,
            timestamp: timelineDate(1),
            title: "Before",
            summary: "Before parallel work",
            kind: .implementation,
            loopStage: .implementation
        )
        let main = ProjectEvent(
            id: "main",
            taskID: firstTask.id,
            timestamp: timelineDate(2),
            title: "Main",
            summary: "Main batch event",
            kind: .implementation,
            loopStage: .implementation
        )
        let parallel = ProjectEvent(
            id: "parallel",
            taskID: secondTask.id,
            timestamp: timelineDate(2).addingTimeInterval(1),
            title: "Parallel",
            summary: "Parallel batch event",
            kind: .implementation,
            loopStage: .implementation
        )
        let after = ProjectEvent(
            id: "after",
            taskID: firstTask.id,
            timestamp: timelineDate(3),
            title: "After",
            summary: "After parallel work",
            kind: .verification,
            loopStage: .verification
        )
        let project = ProjectRecord(
            id: "project",
            name: "Project",
            summary: "Summary",
            graphPosition: .init(x: 0, y: 0),
            tasks: [firstTask, secondTask],
            events: [start, before, main, parallel, after]
        )

        let layout = ProjectTimelineLayout(project: project)
        try require(layout.branches.count == 1, "independent workline creates one semantic branch")
        try require(layout.branches.first?.eventID == parallel.id, "branch is independent of timestamp equality")
        try require(layout.nodes.first(where: { $0.id == main.id })?.isOnMainline == true, "continued workline uses mainline")
        try require(layout.nodes.first(where: { $0.id == parallel.id })?.isOnMainline == false, "parallel event uses branch lane")
        guard let branch = layout.branches.first else {
            throw CheckFailure.failed("parallel branch geometry")
        }
        try require(branch.points.count >= 2, "branch contains its lifecycle path")
        try require(branch.points.first!.y > branch.points.last!.y, "branch starts at the parent and advances independently")
    }

    @MainActor
    private static func timelineSelectionHierarchy() throws {
        try withFixture { repository in
            let start = ProjectEvent(
                id: "project-start",
                timestamp: timelineDate(0),
                title: "Project started",
                summary: "Start",
                kind: .projectStarted,
                loopStage: .intake
            )
            let task = timelineTask(id: "task", start: 1, update: 3, completion: nil)
            let first = ProjectEvent(
                id: "first",
                taskID: task.id,
                timestamp: timelineDate(2),
                title: "First",
                summary: "First progress",
                kind: .investigation,
                loopStage: .audit
            )
            let latest = ProjectEvent(
                id: "latest",
                taskID: task.id,
                timestamp: timelineDate(3),
                title: "Latest",
                summary: "Latest progress",
                kind: .implementation,
                loopStage: .implementation
            )
            let project = ProjectRecord(
                id: "project",
                name: "Project",
                summary: "Summary",
                graphPosition: .init(x: 0, y: 0),
                tasks: [task],
                events: [start, first, latest]
            )
            try repository.ensureInitialized(initial: WorkspaceSnapshot(projects: [project]))
            let model = WorkstateViewModel(repository: repository)

            model.selectProject(project.id)
            model.selectTask(task.id)
            try require(model.selectedTaskID == task.id, "task node selects the task")
            try require(model.selectedEventID == latest.id, "task node opens latest internal progress")

            model.selectTaskEvent(first.id)
            try require(model.selectedTaskID == task.id, "internal progress keeps task selected")
            try require(model.selectedEventID == first.id, "internal progress changes reference detail")

            model.selectProjectEvent(start.id)
            try require(model.selectedTaskID == nil, "project checkpoint clears task selection")
            try require(model.selectedEventID == start.id, "project checkpoint opens its own detail")
        }
    }

    private static func timelineTask(
        id: String,
        start: TimeInterval,
        update: TimeInterval,
        completion: TimeInterval?
    ) -> TaskRecord {
        TaskRecord(
            id: id,
            title: id,
            objective: id,
            status: completion == nil ? .active : .completed,
            accent: .blue,
            currentStage: completion == nil ? .implementation : .completed,
            startedAt: timelineDate(start),
            updatedAt: timelineDate(update),
            completedAt: completion.map { timelineDate($0) },
            branchedFromEventID: "project-start",
            mergedByEventID: completion == nil ? nil : "merge"
        )
    }

    private static func timelineDate(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private static func withFixture(_ body: (WorkstateRepository) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-checks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try body(WorkstateRepository(paths: WorkstatePaths(root: root)))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        guard condition() else { throw CheckFailure.failed(label) }
    }
}

private final class WatcherCapture: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var batches: [SessionChangeBatch] = []

    func receive(_ batch: SessionChangeBatch) {
        lock.lock()
        batches.append(batch)
        lock.unlock()
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) -> SessionChangeBatch? {
        let deadline = DispatchTime.now() + timeout
        while semaphore.wait(timeout: deadline) == .success {
            lock.lock()
            let combined = SessionChangeBatch(
                paths: Array(Set(batches.flatMap(\.paths))).sorted(),
                requiresFullScan: batches.contains(where: \.requiresFullScan)
            )
            lock.unlock()
            if combined.requiresFullScan || !combined.paths.isEmpty {
                return combined
            }
        }
        return nil
    }
}

private enum CheckFailure: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let label): "Check failed: \(label)"
        }
    }
}
