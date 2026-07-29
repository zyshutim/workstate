import Darwin
import CryptoKit
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
        try collaborationRepositoriesRoundTrip()
        try collaborationInferenceCannotRewriteActiveProfile()
        try modelCatalogFiltersUnsupportedOptions()
        try agentRuntimeStreamsRequestThroughStdin()
        try legacyStateMigration()
        try schemaV3Migration()
        try projectPositionUpdate()
        try projectModelReplacement()
        try contextSnapshotSelectsCurrentWork()
        try daemonStatusWritesOnlyOnChange()
        try eventLogRotatesAtFixedBoundary()
        try dailyBriefProjectsVerifiedDailyState()
        try topicRequiresExplicitPromotion()
        try topicResolutionPreservesDisposition()
        try taskBranchAndMerge()
        try worklineReconciliationRepairsSemanticOwnership()
        try contextRevisionAuthority()
        try ingestionBatchIsAtomicAndUpdatesProjectHead()
        try ingestionBatchBranchesNewProjectFromHistoricalStart()
        try ingestionFocusSwitchDoesNotCompletePreviousWorkline()
        try projectTimelineHierarchy()
        try projectTimelineParallelProjection()
        try projectTimelineSequentialWorkStaysOnMainline()
        try projectBranchTreeProjection()
        try timelineSelectionHierarchy()
        try reviewResolutionAuthority()
        try projectUpdateReviewWritesEventOnConfirmation()
        try sessionScannerIncremental()
        try sessionScannerMigratesLegacyActiveTurn()
        try sessionScannerPreservesAllUserMessagesAcrossRestart()
        try sessionScannerReadsOnlyChangedFile()
        try sessionScannerFastPollIgnoresDeletedFiles()
        try sessionScannerPreservesIncompleteLine()
        try sessionCatalogAndHistoryRangeImport()
        try conversationSourceIndexFreezesBatchHighWaterMark()
        try conversationBatchPolicyRequiresQuietOrExplicitTrigger()
        try batchRouterExpandsSemanticPacketCoverage()
        try conversationBatchesAreIsolatedByThread()
        try conversationBatchCapsRouterTurns()
        try conversationBatchQuarantinesOnlyUnreadablePointers()
        try semanticBundlesWaitForCommitBeforeOwner()
        try stewardReceivesOnlyActiveWorklines()
        try largeConversationResolvesByMessageSpans()
        try durableMemoryPersistsSelectiveDocuments()
        try monitoringCutoffDropsDisabledPeriod()
        try interruptedProcessingRecoversWithoutRepeatingCompletedStages()
        try interruptedBatchFailsWithoutModelRetry()
        try semanticBundlesPersistRoutedEvidence()
        try completedBatchMetadataIsPruned()
        try sessionWatcherReceivesFileChanges()
        try sessionWatcherReceivesNestedFileAppend()
        try scannerMemoryRemainsBounded()
        try previousActivityDaySkipsCalendarGaps()
        try dailyBriefRunGateRunsOncePerDay()
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
        try require(!initial.liveMonitoringEnabled, "existing workspace does not start monitoring implicitly")
        try require(initial.liveMonitoringStartedAt == nil, "disabled monitoring has no start time")
        try require(initial.profile(for: .route).modelID == "gpt-5.6-luna", "router default model")

        var updated = initial
        updated.liveMonitoringEnabled = false
        updated.agentProfiles[.brief] = AgentProfile(modelID: "gpt-5.5", effort: .high)
        try repository.save(updated)
        let loaded = try repository.load()
        try require(!loaded.liveMonitoringEnabled, "monitoring setting persists")
        try require(loaded.profile(for: .brief).effort == .high, "agent effort persists")

        var legacy = initial
        legacy.liveMonitoringEnabled = true
        legacy.liveMonitoringStartedAt = nil
        try repository.save(legacy)
        let fileDate = Date(timeIntervalSince1970: 1_784_619_029)
        try FileManager.default.setAttributes(
            [.modificationDate: fileDate],
            ofItemAtPath: repository.url.path
        )
        let migrated = try repository.load()
        try require(
            migrated.liveMonitoringStartedAt == fileDate,
            "legacy monitoring start migrates from the last explicit settings save"
        )
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

    private static func agentRuntimeStreamsRequestThroughStdin() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-agent-stdin-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = WorkstateRepository(paths: WorkstatePaths(root: root))
        try repository.ensureInitialized(initial: WorkspaceSnapshot())
        _ = try WorkstateService(repository: repository).createProject(
            ProjectCreateInput(
                id: "workstate",
                name: "Workstate",
                summary: "Local project memory",
                purpose: "Verify streamed Agent requests",
                position: GraphPosition(x: 0, y: 0)
            )
        )
        let runtimeScript = root.appendingPathComponent("fake-runtime.js")
        let source = #"""
        let input = "";
        process.stdin.setEncoding("utf8");
        process.stdin.on("data", chunk => { input += chunk; });
        process.stdin.on("end", () => {
          const request = JSON.parse(input);
          if (request.mode !== "route") process.exit(2);
          process.stdout.write(JSON.stringify({
            mode: "route",
            runtimeThreadId: "ephemeral-run-test",
            usage: null,
            result: {
              action: "select_project",
              projectId: "workstate",
              projectName: "Workstate",
              projectSummary: "Local project memory",
              disposition: "commit",
              bundleId: "bundle-test",
              bundleTitle: "Streamed request",
              bundleSummary: "The request arrived through stdin",
              signals: [{ type: "decision", authority: "observed", summary: "stdin works" }],
              confidence: 1,
              reason: "test"
            }
          }));
        });
        """#
        try Data(source.utf8).write(to: runtimeScript, options: .atomic)
        let nodePath = AgentRuntimeClient.defaultNodePath()
        guard FileManager.default.isExecutableFile(atPath: nodePath) else {
            throw CheckFailure.failed("Node executable for Agent stdin check")
        }
        let scanner = CodexSessionScanner(
            sessionsRoot: root.appendingPathComponent("sessions", isDirectory: true),
            runtimeRoot: root
        )
        let runtime = AgentRuntimeClient(
            runtimeScript: runtimeScript,
            nodePath: nodePath,
            runtimeRoot: root
        )
        let result = try runtime.route(
            segment: SessionSegment(
                threadID: "thread",
                turnID: "turn",
                sourcePath: "/tmp/source.jsonl",
                startOffset: 0,
                endOffset: 1,
                cwd: "/tmp",
                userText: "Route this through stdin",
                assistantText: "Done",
                timestamp: Date()
            ),
            workspace: try repository.load(),
            scanner: scanner
        )
        try require(result.projectId == "workstate", "Swift streams Agent request through stdin")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
        try require(
            !leftovers.contains(where: { $0.hasPrefix("agent-request-") }),
            "Agent request is never copied to a temporary JSON file"
        )
    }

    private static func collaborationRepositoriesRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-collaboration-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let profileRepository = CollaborationProfileRepository(root: root)
        let entry = CollaborationProfileEntry(
            id: "direct-language",
            kind: .preference,
            status: .active,
            title: "直接表达",
            detail: "使用简洁、具体的中文"
        )
        let profile = CollaborationProfile(entries: [entry])
        try profileRepository.save(profile)
        let loadedProfile = try profileRepository.load()
        try require(
            loadedProfile.entries.map(\.id) == [entry.id]
                && loadedProfile.entries.first?.detail == entry.detail,
            "collaboration profile round trips"
        )

        let conversationRepository = GlobalConversationRepository(root: root)
        let conversation = GlobalConversation(
            messages: [
                GlobalChatMessage(
                    id: "message",
                    role: .user,
                    text: "记录这个议题",
                    projectID: "project",
                    projectName: "Project"
                )
            ]
        )
        try conversationRepository.save(conversation)
        let loadedConversation = try conversationRepository.load()
        try require(
            loadedConversation.messages.map(\.id) == conversation.messages.map(\.id)
                && loadedConversation.messages.first?.text == conversation.messages.first?.text,
            "global conversation preserves original text and route"
        )
    }

    private static func collaborationInferenceCannotRewriteActiveProfile() throws {
        let applier = CollaborationProfileApplier()
        let invalid = CollaborationProfileMutation(
            action: "create",
            authority: "inference",
            id: "invalid-active-inference",
            kind: "rule",
            status: "active",
            title: "Invalid",
            detail: "An inference cannot become active"
        )
        do {
            _ = try applier.apply([invalid], to: CollaborationProfile())
            throw CheckFailure.failed("inferred active collaboration rule is rejected")
        } catch let error as WorkstateStorageError {
            guard error.localizedDescription.contains("candidate") else { throw error }
        }

        let candidate = CollaborationProfileMutation(
            action: "create",
            authority: "inference",
            id: "candidate",
            kind: "preference",
            status: "candidate",
            title: "Candidate",
            detail: "Needs user confirmation"
        )
        let applied = try applier.apply([candidate], to: CollaborationProfile())
        try require(
            applied.entries.first?.status == .candidate,
            "inferred collaboration pattern remains a candidate"
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
                    forbiddenDirections: ["Do not infer acceptance"]
                )
            )
            let project = try service.snapshot().project(id: "reframe-multicam")
            try require(project?.summary == "Canonical HEAD", "project model updates graph summary")
            try require(project?.context.objectModel == ["Project", "Workline", "Delta"], "project object model replacement")
            try require(project?.context.acceptedDecisions.first?.text == "Confirmed decision", "project accepted decisions replacement")
            try require(project?.context.forbiddenDirections == ["Do not infer acceptance"], "project forbidden directions replacement")
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

    private static func eventLogRotatesAtFixedBoundary() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkspaceSnapshot())
            try Data(repeating: 0x61, count: 4 * 1024 * 1024).write(
                to: repository.paths.events,
                options: .atomic
            )
            _ = try WorkstateService(repository: repository).createProject(
                ProjectCreateInput(
                    id: "rotation-project",
                    name: "Rotation",
                    summary: "Verify bounded event storage",
                    purpose: "Test log rotation",
                    position: GraphPosition(x: 0, y: 0)
                )
            )
            let previous = repository.paths.root.appendingPathComponent("events.previous.jsonl")
            try require(
                FileManager.default.fileExists(atPath: previous.path),
                "event log keeps one rotated generation"
            )
            let currentSize = ((try FileManager.default.attributesOfItem(
                atPath: repository.paths.events.path
            )[.size]) as? NSNumber)?.intValue ?? Int.max
            try require(currentSize < 1024 * 1024, "active event log restarts below its fixed boundary")
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
                ]
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
            ],
            topics: [
                ProjectTopic(
                    id: "foreground-canary",
                    title: "Observe the foreground canary",
                    summary: "Verify the foreground result",
                    disposition: .awaitingVerification,
                    currentUnderstanding: "The foreground result is not verified",
                    updatedAt: decisionTime
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

    private static func topicResolutionPreservesDisposition() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkstateBootstrap.makeInitialState())
            let service = WorkstateService(repository: repository)
            let projectID = "reframe-multicam"

            _ = try service.upsertTopic(
                projectID: projectID,
                input: ProjectTopicUpdateInput(
                    id: "await-result",
                    title: "等待运行结果",
                    summary: "实现已经结束，但结果未知",
                    status: .captured,
                    kind: .backend,
                    disposition: .awaitingVerification,
                    currentUnderstanding: "需要等待真实运行结果"
                )
            )
            let captured = try service.snapshot().project(id: projectID)?.topic(id: "await-result")
            try require(
                captured?.disposition == .awaitingVerification,
                "topic keeps awaiting-verification disposition"
            )

            _ = try service.resolveTopic(
                ProjectTopicResolutionInput(
                    projectID: projectID,
                    topicID: "await-result",
                    resolution: .completed
                )
            )
            let completed = try service.snapshot().project(id: projectID)?.topic(id: "await-result")
            try require(completed?.status == .closed, "verified topic closes")
            try require(completed?.resolution == .completed, "verified topic records completion")

            _ = try service.upsertTopic(
                projectID: projectID,
                input: ProjectTopicUpdateInput(
                    id: "future-choice",
                    title: "未来方向",
                    summary: "尚未决定是否继续",
                    status: .captured,
                    kind: .product,
                    disposition: .futureDecision,
                    currentUnderstanding: "等待产品决策"
                )
            )
            _ = try service.resolveTopic(
                ProjectTopicResolutionInput(
                    projectID: projectID,
                    topicID: "future-choice",
                    resolution: .cancelled
                )
            )
            let cancelled = try service.snapshot().project(id: projectID)?.topic(id: "future-choice")
            try require(cancelled?.status == .closed, "cancelled topic closes")
            try require(cancelled?.resolution == .cancelled, "topic records cancellation")
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
                        facts: ["Check passed"]
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
            !scannerState.excludedThreadIDs.contains("agent-thread")
                && scannerState.cursors[internalSession.path] == nil,
            "Workstate AgentRuntime metadata is not retained"
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

    private static func sessionScannerMigratesLegacyActiveTurn() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-legacy-active-turn-check-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)

        let source = sessions.appendingPathComponent("rollout.jsonl")
        let now = Date()
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let metadata = """
        {"type":"session_meta","timestamp":"\(now.formatted(iso))","payload":{"id":"legacy-thread","cwd":"/tmp/project"}}

        """
        let started = """
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"legacy-turn"}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"Legacy unfinished request"}}

        """
        let initialData = Data((metadata + started).utf8)
        try initialData.write(to: source)

        let scanner = CodexSessionScanner(
            sessionsRoot: sessions,
            runtimeRoot: runtime,
            retainsLegacyPendingState: false
        )
        let state = IngestionSnapshot(
            initialized: true,
            cursors: [
                source.path: SessionCursor(
                    offset: UInt64(initialData.count),
                    threadID: "legacy-thread",
                    cwd: "/tmp/project",
                    activeTurnID: "legacy-turn",
                    activeTurnOffset: UInt64(Data(metadata.utf8).count),
                    userText: "Legacy unfinished request",
                    sourceSpans: nil,
                    lastActivityAt: now,
                    isInternalAgentSession: false
                )
            ],
            lastScanAt: now
        )
        try WorkstateCoding.makeEncoder().encode(state).write(to: scanner.stateURL, options: .atomic)

        let completion = """
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_complete","turn_id":"legacy-turn","last_agent_message":"Legacy request completed"}}

        """
        let handle = try FileHandle(forWritingTo: source)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(completion.utf8))
        try handle.close()

        let captured = try scanner.scanChangedFiles([source.path])
        try require(captured.count == 1, "legacy active turn completes once")
        try require(
            captured[0].sourceSpans?.map(\.kind) == [.userMessage, .assistantCompletion],
            "legacy active turn recovers exact user and completion spans"
        )

        let index = try ConversationSourceIndex(databaseURL: scanner.sourceIndexURL)
        let pointer = try index.pointer(
            id: ConversationSourcePointerID(
                provider: "codex",
                threadID: "legacy-thread",
                turnID: "legacy-turn"
            )
        )
        try require(pointer != nil, "legacy active turn stores one source pointer")
        let resolved = try scanner.segments(pointerRecords: [pointer!])
        try require(
            resolved.first?.userText == "Legacy unfinished request"
                && resolved.first?.assistantText == "Legacy request completed",
            "legacy active turn resolves from original source after migration"
        )
        let stateText = try String(contentsOf: scanner.stateURL, encoding: .utf8)
        try require(
            !stateText.contains("Legacy unfinished request"),
            "legacy active turn raw text is removed after source spans are recovered"
        )
    }

    private static func sessionScannerPreservesAllUserMessagesAcrossRestart() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-restarted-turn-check-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let source = sessions.appendingPathComponent("rollout.jsonl")
        let now = Date()
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let metadata = """
        {"type":"session_meta","timestamp":"\(now.formatted(iso))","payload":{"id":"restart-thread","cwd":"/tmp/project"}}

        """
        try Data(metadata.utf8).write(to: source)

        let firstScanner = CodexSessionScanner(
            sessionsRoot: sessions,
            runtimeRoot: runtime,
            retainsLegacyPendingState: false
        )
        _ = try firstScanner.scan()
        let firstPart = """
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"restart-turn"}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"First request"}}

        """
        let firstHandle = try FileHandle(forWritingTo: source)
        try firstHandle.seekToEnd()
        try firstHandle.write(contentsOf: Data(firstPart.utf8))
        try firstHandle.close()
        _ = try firstScanner.scanChangedFiles([source.path])

        let secondPart = """
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"Correction after restart"}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_complete","turn_id":"restart-turn","last_agent_message":"Final answer"}}

        """
        let secondHandle = try FileHandle(forWritingTo: source)
        try secondHandle.seekToEnd()
        try secondHandle.write(contentsOf: Data(secondPart.utf8))
        try secondHandle.close()

        let restartedScanner = CodexSessionScanner(
            sessionsRoot: sessions,
            runtimeRoot: runtime,
            retainsLegacyPendingState: false
        )
        let captured = try restartedScanner.scanChangedFiles([source.path])
        try require(captured.count == 1, "a restarted scanner completes the active turn once")
        try require(
            captured[0].userText == "First request\n\nCorrection after restart",
            "a restart does not drop user messages captured before it"
        )
        let index = try ConversationSourceIndex(databaseURL: restartedScanner.sourceIndexURL)
        let pointer = try index.pointer(
            id: ConversationSourcePointerID(
                provider: "codex",
                threadID: "restart-thread",
                turnID: "restart-turn"
            )
        )
        let resolved = try restartedScanner.segments(pointerRecords: [pointer!])
        try require(
            resolved.first?.userText == "First request\n\nCorrection after restart",
            "the stored pointer hash covers every user message after a restart"
        )

        var legacyPointer = pointer!.pointer
        let legacyDigest = SHA256.hash(
            data: Data("Correction after restart\u{0}Final answer".utf8)
        )
        legacyPointer.contentHash = legacyDigest
            .map { String(format: "%02x", $0) }
            .joined()
        try index.upsertPointer(legacyPointer)
        let legacyRecord = try index.pointer(id: legacyPointer.id)!
        let repaired = try restartedScanner.segment(pointerRecord: legacyRecord)
        try require(
            repaired.userText == "First request\n\nCorrection after restart",
            "a pending legacy suffix hash repairs to the complete user turn"
        )
        let repairedRecord = try index.pointer(id: legacyPointer.id)!
        try require(
            repairedRecord.pointer.contentHash != legacyPointer.contentHash,
            "legacy pointer repair persists the complete content hash"
        )
        try require(
            restartedScanner.diagnostics().repairedLegacyPointerHashes == 1,
            "legacy pointer hash repair is observable in diagnostics"
        )
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

        let scanner = CodexSessionScanner(
            sessionsRoot: sessions,
            runtimeRoot: runtime,
            retainsLegacyPendingState: false
        )
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
        try require(afterChange.evidenceIndexLoads == 0, "scanner no longer builds a copied evidence index")
        try require(
            FileManager.default.fileExists(atPath: scanner.sourceIndexURL.path),
            "changed-file scan stores source pointers in SQLite"
        )
        try require(
            !FileManager.default.fileExists(atPath: scanner.evidenceURL.path),
            "changed-file scan does not copy conversation text"
        )
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

        let stateBeforeCursorOnlyScan = try Data(contentsOf: scanner.stateURL)
        let beforeCompletion = try scanner.scanChangedFiles([session.path])
        try require(beforeCompletion.isEmpty, "incomplete task completion is not consumed")
        let stateAfterCursorOnlyScan = try Data(contentsOf: scanner.stateURL)
        try require(
            stateAfterCursorOnlyScan == stateBeforeCursorOnlyScan,
            "cursor-only progress does not rewrite ingestion-state.json"
        )

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

    private static func conversationSourceIndexFreezesBatchHighWaterMark() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-pointer-index-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let index = try ConversationSourceIndex(
            databaseURL: root.appendingPathComponent("source-index.sqlite")
        )
        let first = ConversationSourcePointer(
            provider: "codex",
            threadID: "thread",
            turnID: "turn-1",
            sourcePath: "/tmp/source.jsonl",
            startOffset: 10,
            endOffset: 40,
            timestamp: Date(timeIntervalSince1970: 10),
            cwd: "/tmp",
            contentHash: "hash-1",
            messageSpans: [
                ConversationSourceSpan(kind: .userMessage, startOffset: 12, endOffset: 20),
                ConversationSourceSpan(kind: .assistantCompletion, startOffset: 30, endOffset: 40)
            ]
        )
        try index.upsertPointer(first)
        guard let highWaterMark = try index.captureHighWaterMark() else {
            throw CheckFailure.failed("pointer high-water mark")
        }
        let second = ConversationSourcePointer(
            provider: "codex",
            threadID: "thread",
            turnID: "turn-2",
            sourcePath: "/tmp/source.jsonl",
            startOffset: 41,
            endOffset: 80,
            timestamp: Date(timeIntervalSince1970: 20),
            cwd: "/tmp",
            contentHash: "hash-2"
        )
        try index.upsertPointer(second)
        guard let batch = try index.createBatch(through: highWaterMark) else {
            throw CheckFailure.failed("pointer batch")
        }
        try require(batch.pointers.map(\.pointer.turnID) == ["turn-1"], "batch freezes its high-water mark")
        _ = try index.finalizeBatch(
            batch.id,
            completedPointerIDs: [first.id],
            projectAssignments: [
                ConversationPointerProjectAssignment(pointerID: first.id, projectID: "project")
            ]
        )
        let reassigned = try index.reassignCompletedPointers([first.id], to: "research")
        try require(reassigned == 1, "one completed pointer can be reassigned explicitly")
        let reassignedPointer = try index.pointer(id: first.id)
        try require(
            reassignedPointer?.projectID == "research",
            "completed pointer reassignment updates only project ownership"
        )
        let pending = try index.pendingPointers()
        try require(pending.map(\.pointer.turnID) == ["turn-2"], "later pointers remain pending")

        for number in 3...551 {
            try index.upsertPointer(
                ConversationSourcePointer(
                    provider: "codex",
                    threadID: number == 551 ? "target-thread" : "other-thread",
                    turnID: "turn-\(number)",
                    sourcePath: "/tmp/source.jsonl",
                    startOffset: UInt64(number * 100),
                    endOffset: UInt64(number * 100 + 40),
                    timestamp: Date(timeIntervalSince1970: TimeInterval(number)),
                    cwd: "/tmp",
                    contentHash: "hash-\(number)"
                )
            )
        }
        let targeted = try index.pendingPointers(
            provider: "codex",
            threadIDs: ["target-thread"],
            limit: 500
        )
        try require(
            targeted.map(\.pointer.turnID) == ["turn-551"],
            "project lookup does not lose a target behind unrelated backlog"
        )
        guard let backlogHighWater = try index.captureHighWaterMark(),
              let backlogBatch = try index.createBatch(
                through: backlogHighWater,
                limit: 500
              ) else {
            throw CheckFailure.failed("bounded backlog batch")
        }
        try require(backlogBatch.pointers.count == 500, "one batch is capped at 500 pointers")
        _ = try index.finalizeBatch(
            backlogBatch.id,
            completedPointerIDs: backlogBatch.pointers.map(\.id)
        )
        let remainingBacklogCount = try index.pendingStats().count
        try require(
            remainingBacklogCount == 50,
            "backlog after the first 500 remains visible for later scheduling"
        )
    }

    private static func conversationBatchPolicyRequiresQuietOrExplicitTrigger() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let policy = ConversationBatchPolicy(
            quietInterval: 20 * 60,
            maximumEstimatedSourceBytes: 256 * 1024
        )
        let active = PendingConversationActivity(
            pointerCount: 3,
            oldestCompletedAt: now.addingTimeInterval(-30 * 60),
            latestCompletedAt: now.addingTimeInterval(-19 * 60),
            estimatedSourceBytes: 2_000
        )
        try require(policy.automaticTrigger(for: active, now: now) == nil, "active chat does not auto-process")
        var quiet = active
        quiet.latestCompletedAt = now.addingTimeInterval(-20 * 60)
        try require(
            policy.automaticTrigger(for: quiet, now: now) == .quietPeriod,
            "twenty minutes of global quiet creates one automatic batch"
        )
        var oversized = active
        oversized.estimatedSourceBytes = 256 * 1024
        try require(
            policy.automaticTrigger(for: oversized, now: now) == .safetySize,
            "bounded source size can close a batch before quiet"
        )
    }

    private static func conversationBatchesAreIsolatedByThread() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-thread-batch-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let first = sessions.appendingPathComponent("first.jsonl")
        let second = sessions.appendingPathComponent("second.jsonl")
        let now = Date().addingTimeInterval(-60 * 60)
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

        func prime(_ url: URL, threadID: String) throws {
            let metadata = """
            {"type":"session_meta","timestamp":"\(now.formatted(iso))","payload":{"id":"\(threadID)","cwd":"/tmp/project"}}

            """
            try Data(metadata.utf8).write(to: url)
        }
        try prime(first, threadID: "thread-a")
        try prime(second, threadID: "thread-b")

        let scanner = CodexSessionScanner(
            sessionsRoot: sessions,
            runtimeRoot: root,
            retainsLegacyPendingState: false
        )
        _ = try scanner.scan()

        func appendTurn(_ url: URL, id: String) throws {
            let text = """
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"\(id)"}}
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"Instruction only"}}
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_complete","turn_id":"\(id)","last_agent_message":"Done"}}

            """
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        }
        try appendTurn(first, id: "turn-a")
        _ = try scanner.scanChangedFiles([first.path])
        try appendTurn(second, id: "turn-b")
        _ = try scanner.scanChangedFiles([second.path])

        let runtime = try makeIgnoreBatchRuntime(root: root)
        let repository = WorkstateRepository(paths: WorkstatePaths(root: root))
        try repository.ensureInitialized(initial: WorkspaceSnapshot())
        let coordinator = ConversationBatchCoordinator(
            scanner: scanner,
            orchestrator: WorkstateOrchestrator(
                service: WorkstateService(repository: repository),
                scanner: scanner,
                runtime: runtime
            )
        )
        let activities = try coordinator.pendingThreadActivities()
        try require(
            activities.map(\.threadID) == ["thread-a", "thread-b"],
            "pending conversations retain independent queues"
        )
        let schedulingNow = Date()
        let otherThreadDelay = try coordinator.nextAutomaticDelay(
            now: schedulingNow,
            notBeforeByThread: [
                "thread-a": schedulingNow.addingTimeInterval(10 * 60)
            ]
        )
        try require(
            otherThreadDelay == 0,
            "one conversation cooldown does not delay another due conversation"
        )

        let firstRun = try coordinator.process(trigger: .manual)
        try require(firstRun?.pointerCount == 1, "one processing batch contains one conversation")
        let index = try ConversationSourceIndex(databaseURL: scanner.sourceIndexURL)
        let firstState = try index.pointers(provider: "codex", threadID: "thread-a", limit: 10)
        let secondState = try index.pointers(provider: "codex", threadID: "thread-b", limit: 10)
        try require(firstState.first?.processingState == .completed, "first conversation completes independently")
        try require(secondState.first?.processingState == .pending, "second conversation remains pending")
        let sameThreadDelay = try coordinator.nextAutomaticDelay(
            now: schedulingNow,
            notBeforeByThread: [
                "thread-b": schedulingNow.addingTimeInterval(10 * 60)
            ]
        )
        try require(
            sameThreadDelay.map { abs($0 - 10 * 60) < 1 } == true,
            "a remaining batch from the same conversation observes its cooldown"
        )

        let secondRun = try coordinator.process(trigger: .manual)
        try require(secondRun?.pointerCount == 1, "second conversation creates its own batch")
        let finalSecondState = try index.pointers(provider: "codex", threadID: "thread-b", limit: 10)
        try require(finalSecondState.first?.processingState == .completed, "second conversation completes later")
    }

    private static func batchRouterExpandsSemanticPacketCoverage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-route-packet-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let scanner = CodexSessionScanner(
            sessionsRoot: root.appendingPathComponent("sessions", isDirectory: true),
            runtimeRoot: root,
            retainsLegacyPendingState: false
        )
        let runtime = try makeIgnoreBatchRuntime(root: root)
        let timestamp = Date()
        let segments = [
            SessionSegment(
                threadID: "packet-thread",
                turnID: "first",
                sourcePath: "/tmp/first.jsonl",
                startOffset: 0,
                endOffset: 1,
                cwd: "/tmp/project",
                userText: "First",
                assistantText: "Done",
                timestamp: timestamp
            ),
            SessionSegment(
                threadID: "packet-thread",
                turnID: "second",
                sourcePath: "/tmp/second.jsonl",
                startOffset: 0,
                endOffset: 1,
                cwd: "/tmp/project",
                userText: "Second",
                assistantText: "Done",
                timestamp: timestamp.addingTimeInterval(1)
            )
        ]
        let decisions = try runtime.routeBatch(
            segments: segments,
            workspace: WorkspaceSnapshot(),
            routeHints: [:],
            scanner: scanner
        )
        try require(
            Set(decisions.map(\.segmentId)) == Set(segments.map(\.id))
                && decisions.count == 2,
            "one semantic Router packet expands to every covered source pointer"
        )
    }

    private static func conversationBatchCapsRouterTurns() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-router-cap-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let source = sessions.appendingPathComponent("rollout.jsonl")
        let now = Date().addingTimeInterval(-60 * 60)
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let metadata = """
        {"type":"session_meta","timestamp":"\(now.formatted(iso))","payload":{"id":"thread","cwd":"/tmp/project"}}

        """
        try Data(metadata.utf8).write(to: source)
        let scanner = CodexSessionScanner(
            sessionsRoot: sessions,
            runtimeRoot: root,
            retainsLegacyPendingState: false
        )
        _ = try scanner.scan()

        let handle = try FileHandle(forWritingTo: source)
        try handle.seekToEnd()
        for index in 1...21 {
            let turn = """
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"turn-\(index)"}}
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"Instruction \(index)"}}
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_complete","turn_id":"turn-\(index)","last_agent_message":"Done"}}

            """
            try handle.write(contentsOf: Data(turn.utf8))
        }
        try handle.close()
        _ = try scanner.scanChangedFiles([source.path])

        let repository = WorkstateRepository(paths: WorkstatePaths(root: root))
        try repository.ensureInitialized(initial: WorkspaceSnapshot())
        let coordinator = ConversationBatchCoordinator(
            scanner: scanner,
            orchestrator: WorkstateOrchestrator(
                service: WorkstateService(repository: repository),
                scanner: scanner,
                runtime: try makeIgnoreBatchRuntime(root: root)
            )
        )
        let first = try coordinator.process(trigger: .manual)
        try require(first?.pointerCount == 20, "one Router call is capped at twenty turns")
        let remaining = try coordinator.pendingActivity()
        try require(remaining.pointerCount == 1, "later turns remain pending")
        let second = try coordinator.process(trigger: .manual)
        try require(second?.pointerCount == 1, "the remaining turn forms the next batch")
    }

    private static func stewardReceivesOnlyActiveWorklines() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-active-workline-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runtimeScript = root.appendingPathComponent("active-workline-runtime.js")
        let runtimeSource = #"""
        let input = "";
        process.stdin.setEncoding("utf8");
        process.stdin.on("data", chunk => { input += chunk; });
        process.stdin.on("end", () => {
          const request = JSON.parse(input);
          const ids = request.project.activeWorklines.map(workline => workline.id);
          if (request.mode !== "batch_steward" || JSON.stringify(ids) !== JSON.stringify(["active"])) {
            process.exit(9);
          }
          process.stdout.write(JSON.stringify({
            mode: request.mode,
            runtimeThreadId: "ephemeral-active-workline-check",
            usage: null,
            result: { changes: [] }
          }));
        });
        """#
        try Data(runtimeSource.utf8).write(to: runtimeScript, options: .atomic)
        let now = Date()
        let project = ProjectRecord(
            id: "project",
            name: "Project",
            summary: "Workline state boundary",
            tasks: [
                TaskRecord(
                    id: "parked",
                    title: "Parked",
                    objective: "Must stay out of Owner input",
                    status: .parked,
                    startedAt: now,
                    updatedAt: now,
                    branchedFromEventID: "project-start"
                ),
                TaskRecord(
                    id: "active",
                    title: "Active",
                    objective: "May be continued",
                    status: .active,
                    startedAt: now,
                    updatedAt: now,
                    branchedFromEventID: "project-start"
                )
            ]
        )
        let scanner = CodexSessionScanner(
            sessionsRoot: root.appendingPathComponent("sessions", isDirectory: true),
            runtimeRoot: root,
            retainsLegacyPendingState: false
        )
        let runtime = AgentRuntimeClient(
            runtimeScript: runtimeScript,
            nodePath: AgentRuntimeClient.defaultNodePath(),
            runtimeRoot: root
        )
        let result = try runtime.stewardBatch(
            segments: [
                SessionSegment(
                    threadID: "thread",
                    turnID: "turn",
                    sourcePath: "/tmp/source.jsonl",
                    startOffset: 0,
                    endOffset: 1,
                    cwd: "/tmp",
                    userText: "Continue current work",
                    assistantText: "Done",
                    timestamp: now
                )
            ],
            project: project,
            scanner: scanner
        )
        try require(result.changes.isEmpty, "Steward payload excludes every inactive workline")
    }

    private static func sessionScannerFastPollIgnoresDeletedFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-deleted-session-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let source = sessions.appendingPathComponent("deleted.jsonl")
        let metadata = """
        {"type":"session_meta","timestamp":"2026-07-28T00:00:00.000Z","payload":{"id":"deleted-thread","cwd":"/tmp/project"}}

        """
        try Data(metadata.utf8).write(to: source)
        let scanner = CodexSessionScanner(
            sessionsRoot: sessions,
            runtimeRoot: root,
            retainsLegacyPendingState: false
        )
        _ = try scanner.scan()
        try FileManager.default.removeItem(at: source)
        let fastPollChanges = try scanner.knownSessionPathsWithSizeChanges()
        try require(
            fastPollChanges.isEmpty,
            "fast source polling does not report a deleted file forever"
        )
        _ = try scanner.scan()
        let reconciledChanges = try scanner.knownSessionPathsWithSizeChanges()
        try require(
            reconciledChanges.isEmpty,
            "full reconciliation prunes a deleted session cursor"
        )
    }

    private static func dailyBriefRunGateRunsOncePerDay() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-daily-gate-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = DailyBriefRunGate(root: root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = Date(timeIntervalSince1970: 1_753_660_800)
        let firstRun = try gate.beginIfNeeded(now: first, calendar: calendar)
        try require(
            firstRun,
            "the daily brief starts on the first attempt of a day"
        )
        let repeated = try gate.beginIfNeeded(
            now: first.addingTimeInterval(60 * 60),
            calendar: calendar
        )
        try require(!repeated, "reopening the app does not rerun the same daily brief")
        let nextDay = try gate.beginIfNeeded(
            now: first.addingTimeInterval(24 * 60 * 60),
            calendar: calendar
        )
        try require(nextDay, "the daily brief can run again on the next day")
    }

    private static func conversationBatchQuarantinesOnlyUnreadablePointers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-pointer-isolation-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let valid = sessions.appendingPathComponent("valid.jsonl")
        let stale = sessions.appendingPathComponent("stale.jsonl")
        let later = sessions.appendingPathComponent("later.jsonl")
        let now = Date().addingTimeInterval(-60 * 60)
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

        func source(
            threadID: String,
            turnID: String,
            assistant: String,
            timestamp: Date
        ) -> String {
            """
            {"type":"session_meta","timestamp":"\(timestamp.formatted(iso))","payload":{"id":"\(threadID)","cwd":"/tmp/project"}}
            {"type":"event_msg","timestamp":"\(timestamp.formatted(iso))","payload":{"type":"task_started","turn_id":"\(turnID)"}}
            {"type":"event_msg","timestamp":"\(timestamp.formatted(iso))","payload":{"type":"user_message","message":"Instruction only"}}
            {"type":"event_msg","timestamp":"\(timestamp.formatted(iso))","payload":{"type":"task_complete","turn_id":"\(turnID)","last_agent_message":"\(assistant)"}}

            """
        }
        let metadataOnly = """
        {"type":"session_meta","timestamp":"\(now.formatted(iso))","payload":{"id":"thread","cwd":"/tmp/project"}}

        """
        try Data(metadataOnly.utf8).write(to: valid)
        try Data(metadataOnly.utf8).write(to: stale)
        try Data(metadataOnly.utf8).write(to: later)
        let scanner = CodexSessionScanner(
            sessionsRoot: sessions,
            runtimeRoot: root,
            retainsLegacyPendingState: false
        )
        _ = try scanner.scan()
        try Data(source(
            threadID: "thread",
            turnID: "valid-turn",
            assistant: "Good",
            timestamp: now
        ).utf8).write(to: valid)
        try Data(source(
            threadID: "thread",
            turnID: "stale-turn",
            assistant: "Good",
            timestamp: now
        ).utf8).write(to: stale)
        _ = try scanner.scanChangedFiles([valid.path, stale.path])
        try Data(source(
            threadID: "thread",
            turnID: "stale-turn",
            assistant: "Badd",
            timestamp: now
        ).utf8).write(to: stale)

        let runtime = try makeIgnoreBatchRuntime(root: root)
        let repository = WorkstateRepository(paths: WorkstatePaths(root: root))
        try repository.ensureInitialized(initial: WorkspaceSnapshot())
        let coordinator = ConversationBatchCoordinator(
            scanner: scanner,
            orchestrator: WorkstateOrchestrator(
                service: WorkstateService(repository: repository),
                scanner: scanner,
                runtime: runtime
            )
        )
        let result = try coordinator.process(trigger: .manual)
        try require(result?.pointerCount == 2, "one thread batch includes both source pointers")
        try require(result?.failedPointerCount == 1, "only the unreadable source pointer fails")
        try require(result?.summary.agentRuns == 1, "valid evidence still reaches the Router")

        let index = try ConversationSourceIndex(databaseURL: scanner.sourceIndexURL)
        let records = try index.pointers(provider: "codex", threadID: "thread", limit: 10)
        let byTurn = Dictionary(uniqueKeysWithValues: records.map { ($0.pointer.turnID, $0) })
        try require(byTurn["valid-turn"]?.processingState == .completed, "valid pointer completes")
        try require(byTurn["stale-turn"]?.processingState == .failed, "stale pointer is isolated")

        let laterTimestamp = now.addingTimeInterval(60).formatted(iso)
        let laterTurn = """
        {"type":"event_msg","timestamp":"\(laterTimestamp)","payload":{"type":"task_started","turn_id":"later-turn"}}
        {"type":"event_msg","timestamp":"\(laterTimestamp)","payload":{"type":"user_message","message":"Instruction only"}}
        {"type":"event_msg","timestamp":"\(laterTimestamp)","payload":{"type":"task_complete","turn_id":"later-turn","last_agent_message":"Later"}}

        """
        let laterHandle = try FileHandle(forWritingTo: later)
        try laterHandle.seekToEnd()
        try laterHandle.write(contentsOf: Data(laterTurn.utf8))
        try laterHandle.close()
        _ = try scanner.scanChangedFiles([later.path])
        let laterResult = try coordinator.process(trigger: .manual)
        try require(
            laterResult?.summary.agentRuns == 1,
            "an unreadable historical pointer does not block a later Router batch"
        )
        let laterRecords = try index.pointers(provider: "codex", threadID: "thread", limit: 10)
        try require(
            laterRecords.first(where: { $0.pointer.turnID == "later-turn" })?.processingState == .completed,
            "later evidence completes despite stale optional context"
        )
        try require(
            scanner.diagnostics().recentContextFailures == 1,
            "skipped unreadable recent context is observable in diagnostics"
        )
        let requeued = try index.requeueFailedPointers([
            ConversationSourcePointerID(
                provider: "codex",
                threadID: "thread",
                turnID: "stale-turn"
            )
        ])
        try require(requeued == 1, "one selected failed pointer can be requeued")
        let requeuedRecord = try index.pointer(
            id: ConversationSourcePointerID(
                provider: "codex",
                threadID: "thread",
                turnID: "stale-turn"
            )
        )
        try require(
            requeuedRecord?.processingState == .pending
                && requeuedRecord?.batchID == nil
                && requeuedRecord?.failureMessage == nil,
            "requeue clears failed batch ownership without changing other pointers"
        )
    }

    private static func makeIgnoreBatchRuntime(root: URL) throws -> AgentRuntimeClient {
        let script = root.appendingPathComponent("ignore-batch-runtime.js")
        let source = #"""
        let input = "";
        process.stdin.setEncoding("utf8");
        process.stdin.on("data", chunk => { input += chunk; });
        process.stdin.on("end", () => {
          const request = JSON.parse(input);
          if (request.mode !== "batch_route") process.exit(7);
          const result = { routes: [{
            startPosition: 1,
            endPosition: request.segments.length,
            action: "ignore",
            projectId: "",
            projectName: "",
            projectSummary: "",
            disposition: "ignore",
            bundleId: "",
            bundleTitle: "",
            bundleSummary: "",
            signals: [],
            confidence: 1,
            reason: "No durable consequence"
          }] };
          process.stdout.write(JSON.stringify({
            mode: request.mode,
            runtimeThreadId: "ephemeral-ignore-batch",
            usage: null,
            result
          }));
        });
        """#
        try Data(source.utf8).write(to: script, options: .atomic)
        return AgentRuntimeClient(
            runtimeScript: script,
            nodePath: AgentRuntimeClient.defaultNodePath(),
            runtimeRoot: root
        )
    }

    private static func semanticBundlesWaitForCommitBeforeOwner() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-semantic-batch-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let repository = WorkstateRepository(paths: WorkstatePaths(root: root))
        try repository.ensureInitialized(initial: WorkspaceSnapshot())
        _ = try WorkstateService(repository: repository).createProject(
            ProjectCreateInput(
                id: "project",
                name: "Project",
                summary: "Semantic bundle target",
                purpose: "Verify carry and commit routing",
                position: GraphPosition(x: 0, y: 0)
            )
        )
        _ = try WorkstateService(repository: repository).createProject(
            ProjectCreateInput(
                id: "project-b",
                name: "Project B",
                summary: "Project drift target",
                purpose: "Verify Owner escalation to Router",
                position: GraphPosition(x: 200, y: 0)
            )
        )
        let now = Date()
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let session = sessions.appendingPathComponent("rollout.jsonl")
        let metadata = """
        {"type":"session_meta","timestamp":"\(now.formatted(iso))","payload":{"id":"thread","cwd":"/tmp/project"}}

        """
        try Data(metadata.utf8).write(to: session)
        let scanner = CodexSessionScanner(sessionsRoot: sessions, runtimeRoot: root)
        _ = try scanner.scan()

        let runtimeScript = root.appendingPathComponent("semantic-runtime.js")
        let runtimeSource = #"""
        let input = "";
        process.stdin.setEncoding("utf8");
        process.stdin.on("data", chunk => { input += chunk; });
        process.stdin.on("end", () => {
          const request = JSON.parse(input);
          let result;
          if (request.mode === "batch_route") {
            result = { routes: request.segments.map((segment, index) => {
              const drift = segment.turnID === "drift-turn";
              const carry = segment.turnID === "carry-turn";
              return {
                startPosition: index + 1,
                endPosition: index + 1,
                action: drift ? "switch_project" : "continue_previous",
                projectId: drift ? "project-b" : "project",
                projectName: drift ? "Project B" : "Project",
                projectSummary: drift ? "Project drift target" : "Semantic bundle target",
                disposition: carry ? "carry" : "commit",
                bundleId: drift ? "bundle-project-b" : "bundle-project",
                bundleTitle: drift ? "Project drift" : "Project decision",
                bundleSummary: drift ? "Moved to Project B" : "Compared and selected one option",
                signals: carry ? [] : [{
                  type: "decision",
                  authority: "user_confirmed",
                  summary: drift ? "Project changed" : "Selected the first option"
                }],
                confidence: 1,
                reason: drift ? "Conversation moved to Project B" : "Current binding remains valid"
              };
            }) };
          } else if (request.mode === "batch_steward") {
            result = { changes: [] };
          } else {
            process.exit(5);
          }
          process.stdout.write(JSON.stringify({
            mode: request.mode,
            runtimeThreadId: "ephemeral-run-semantic-test",
            usage: null,
            result
          }));
        });
        """#
        try Data(runtimeSource.utf8).write(to: runtimeScript, options: .atomic)
        let runtime = AgentRuntimeClient(
            runtimeScript: runtimeScript,
            nodePath: AgentRuntimeClient.defaultNodePath(),
            runtimeRoot: root
        )
        let orchestrator = WorkstateOrchestrator(
            service: WorkstateService(repository: repository),
            scanner: scanner,
            runtime: runtime
        )
        let coordinator = ConversationBatchCoordinator(
            scanner: scanner,
            orchestrator: orchestrator
        )
        try scanner.recordRoute(
            threadID: "thread",
            turnID: "initial-binding",
            projectID: "project"
        )

        func appendTurn(id: String, user: String, assistant: String) throws {
            let text = """
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"\(id)"}}
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"\(user)"}}
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_complete","turn_id":"\(id)","last_agent_message":"\(assistant)"}}

            """
            let handle = try FileHandle(forWritingTo: session)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        }

        try appendTurn(id: "carry-turn", user: "Let us compare the options", assistant: "Still open")
        _ = try coordinator.scanChanged(paths: [session.path])
        let carryRun = try coordinator.process(trigger: .manual)
        try require(carryRun?.summary.agentRuns == 1, "carry batch calls only the Router")
        let sourceIndex = try ConversationSourceIndex(databaseURL: scanner.sourceIndexURL)
        let openBundles = try sourceIndex.semanticBundles()
        try require(
            openBundles.map(\.id) == ["bundle-project"],
            "carry batch persists one open semantic bundle"
        )
        let carryProject = try repository.load().project(id: "project")
        try require(
            carryProject?.events.count == 1,
            "no-change Owner result does not mutate the project"
        )

        try appendTurn(id: "commit-turn", user: "Use the first option", assistant: "Confirmed")
        _ = try coordinator.scanChanged(paths: [session.path])
        let commitRun = try coordinator.process(trigger: .manual)
        try require(commitRun?.summary.agentRuns == 2, "commit batch calls Router then Project Owner")
        let bundlesAfterCommit = try sourceIndex.semanticBundles()
        try require(
            bundlesAfterCommit.isEmpty,
            "committed semantic bundle closes after Owner receives all evidence"
        )
        let indexedTurns = try sourceIndex.pointers(
            provider: "codex",
            threadID: "thread",
            limit: 10
        )
        try require(
            indexedTurns.count == 2
                && indexedTurns.allSatisfy { $0.processingState == .completed },
            "carry and commit pointers both finish exactly once"
        )

        try appendTurn(id: "drift-turn", user: "Continue in Project B", assistant: "Switched")
        _ = try coordinator.scanChanged(paths: [session.path])
        let driftRun = try coordinator.process(trigger: .manual)
        try require(
            driftRun?.summary.agentRuns == 2,
            "project drift calls Router then target Owner (got \(driftRun?.summary.agentRuns ?? -1))"
        )
        let driftHistory = try scanner.routeBindingHistory(threadID: "thread")
        try require(
            driftHistory.map(\.projectID) == ["project", "project-b"],
            "Router appends a new project binding after detecting drift"
        )
    }

    private static func largeConversationResolvesByMessageSpans() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-large-source-check-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let source = sessions.appendingPathComponent("rollout.jsonl")
        let now = Date()
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let metadata = """
        {"type":"session_meta","timestamp":"\(now.formatted(iso))","payload":{"id":"large-thread","cwd":"/tmp/project"}}

        """
        try Data(metadata.utf8).write(to: source)
        let scanner = CodexSessionScanner(
            sessionsRoot: sessions,
            runtimeRoot: runtime,
            retainsLegacyPendingState: false
        )
        _ = try scanner.scan()

        let handle = try FileHandle(forWritingTo: source)
        try handle.seekToEnd()
        let prefix = """
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"large-turn"}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"Pointer-only secret sentence"}}
        {"type":"response_item","payload":{"type":"tool_output","output":"
        """
        try handle.write(contentsOf: Data(prefix.utf8))
        let sparseGap: UInt64 = 2 * 1024 * 1024 * 1024
        try handle.seek(toOffset: try handle.offset() + sparseGap)
        let suffix = """
        "}}
        {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_complete","turn_id":"large-turn","last_agent_message":"Resolved without copying the sparse payload"}}

        """
        try handle.write(contentsOf: Data(suffix.utf8))
        try handle.close()

        let captured = try scanner.scanChangedFiles([source.path])
        try require(captured.count == 1, "large sparse source yields one completed turn")
        let sourceReference = SourceReference(
            id: "source-large",
            kind: "conversation",
            label: "Large source",
            locator: source.path,
            threadID: "large-thread",
            turnIDs: ["large-turn"],
            contentHash: captured[0].assistantText.isEmpty ? "" : captured[0].id,
            provider: "codex",
            startOffset: captured[0].startOffset,
            endOffset: captured[0].endOffset,
            messageSpans: captured[0].sourceSpans
        )
        let before = scanner.diagnostics().sourceResolutionBytesRead
        let messages = try scanner.resolveMessages(for: sourceReference)
        let after = scanner.diagnostics().sourceResolutionBytesRead
        try require(messages.map(\.text).contains("Pointer-only secret sentence"), "source resolves original user text")
        try require(after - before < 16 * 1024, "L3 reads only indexed message spans")
        try require(!FileManager.default.fileExists(atPath: scanner.evidenceURL.path), "large source is never copied")
        let stateText = try String(contentsOf: scanner.stateURL, encoding: .utf8)
        try require(!stateText.contains("Pointer-only secret sentence"), "ingestion state stores no raw turn text")
        let pointerOnlyState = try scanner.loadState()
        try require(
            pointerOnlyState.pendingSegmentIDs.isEmpty
                && (pointerOnlyState.processingRecords?.isEmpty != false),
            "live pointer backend does not duplicate pending work into state JSON"
        )
        let databaseText = String(decoding: try Data(contentsOf: scanner.sourceIndexURL), as: UTF8.self)
        try require(!databaseText.contains("Pointer-only secret sentence"), "SQLite stores pointers, not conversation text")
    }

    private static func durableMemoryPersistsSelectiveDocuments() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-memory-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = DurableMemoryRepository(root: root)
        let draft = DurableMemoryDocumentDraft(
            namespace: .collaborationRules,
            slug: "working-rules",
            description: "Confirmed collaboration rules",
            scope: .global,
            entries: [
                DurableMemoryEntryDraft(
                    id: "rule-serious-treatment",
                    text: "Do not soothe; take the work seriously.",
                    authority: .userConfirmed,
                    lifecycle: .active,
                    evidencePointerIDs: ["codex:thread:turn"]
                )
            ]
        )
        _ = try repository.apply(
            DurableMemoryMutation(
                id: "create-rules",
                authorizedBy: .userConfirmed,
                timestamp: Date(),
                operation: .createDocument(draft)
            )
        )
        let selected = try repository.retrieve(DurableMemorySelection())
        try require(selected.flatMap(\.entries).map(\.id) == ["rule-serious-treatment"], "global rules load by default")
        let documentURL = repository.documentURL(for: draft.key)
        try require(FileManager.default.fileExists(atPath: documentURL.path), "memory writes one namespaced document")

        do {
            _ = try repository.apply(
                DurableMemoryMutation(
                    id: "invalid-authority",
                    expectedDocumentVersion: 1,
                    authorizedBy: .agentInferred,
                    timestamp: Date(),
                    operation: .createEntry(
                        document: draft.key,
                        entry: DurableMemoryEntryDraft(
                            id: "invalid-confirmation",
                            text: "Agent cannot promote its own inference.",
                            authority: .userConfirmed,
                            lifecycle: .active
                        )
                    )
                )
            )
            throw CheckFailure.failed("agent inference cannot become user-confirmed memory")
        } catch is DurableMemoryError {
            // Expected fail-fast authority rejection.
        }
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
        let sourceIndex = try ConversationSourceIndex(databaseURL: scanner.sourceIndexURL)
        let disabledPointer = try sourceIndex.pointer(
            id: ConversationSourcePointerID(
                provider: "codex",
                threadID: "thread",
                turnID: "disabled-turn"
            )
        )
        try require(
            disabledPointer == nil,
            "disabled-period turn never enters the source index"
        )

        let historicalTurnID = "019eb0cf-abbf-7913-84c5-c88f18d3c83f"
        let replay = """
        {"type":"event_msg","timestamp":"\(afterCutoff.formatted(iso))","payload":{"type":"task_started","turn_id":"\(historicalTurnID)"}}
        {"type":"event_msg","timestamp":"\(afterCutoff.formatted(iso))","payload":{"type":"user_message","message":"Replayed historical turn"}}
        {"type":"event_msg","timestamp":"\(afterCutoff.formatted(iso))","payload":{"type":"task_complete","turn_id":"\(historicalTurnID)","last_agent_message":"Old result"}}

        """
        let replayHandle = try FileHandle(forWritingTo: session)
        try replayHandle.seekToEnd()
        try replayHandle.write(contentsOf: Data(replay.utf8))
        try replayHandle.close()
        let replayResult = try scanner.scanChangedFiles([session.path], minimumTimestamp: now)
        try require(
            !replayResult.contains(where: { $0.turnID == historicalTurnID }),
            "turn id timestamp rejects replayed historical turns"
        )

        let queuedHistoricalTurnID = "019eb0d2-5a75-78d0-bb01-065e91fe9360"
        let queuedReplay = """
        {"type":"event_msg","timestamp":"\(afterCutoff.formatted(iso))","payload":{"type":"task_started","turn_id":"\(queuedHistoricalTurnID)"}}
        {"type":"event_msg","timestamp":"\(afterCutoff.formatted(iso))","payload":{"type":"user_message","message":"Queued historical turn"}}
        {"type":"event_msg","timestamp":"\(afterCutoff.formatted(iso))","payload":{"type":"task_complete","turn_id":"\(queuedHistoricalTurnID)","last_agent_message":"Old queued result"}}

        """
        let queuedHandle = try FileHandle(forWritingTo: session)
        try queuedHandle.seekToEnd()
        try queuedHandle.write(contentsOf: Data(queuedReplay.utf8))
        try queuedHandle.close()
        _ = try scanner.scanChangedFiles([session.path])
        let pendingAfterReplay = try scanner.pendingSegments()
        try require(
            pendingAfterReplay.contains(where: { $0.turnID == queuedHistoricalTurnID }),
            "historical replay is queued without a monitoring cutoff"
        )
        let hostedRuntime = AppHostedConversationRuntime(
            runtimeRoot: runtime,
            sessionsRoot: sessions,
            minimumTimestamp: now
        )
        try hostedRuntime.start()
        defer { hostedRuntime.stop() }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if try sourceIndex.pointer(
                id: ConversationSourcePointerID(
                    provider: "codex",
                    threadID: "thread",
                    turnID: queuedHistoricalTurnID
                )
            ) == nil {
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        let discardedPointer = try sourceIndex.pointer(
            id: ConversationSourcePointerID(
                provider: "codex",
                threadID: "thread",
                turnID: queuedHistoricalTurnID
            )
        )
        try require(
            discardedPointer == nil,
            "app-hosted monitoring removes queued disabled-period pointers before scheduling"
        )
    }

    private static func interruptedBatchFailsWithoutModelRetry() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkspaceSnapshot())
            _ = try WorkstateService(repository: repository).createProject(
                ProjectCreateInput(
                    id: "project",
                    name: "Project",
                    summary: "Recovery target",
                    purpose: "Verify interrupted batch recovery",
                    position: GraphPosition(x: 0, y: 0)
                )
            )
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
            guard !segments.isEmpty else {
                throw CheckFailure.failed("processing segment fixture")
            }
            let index = try ConversationSourceIndex(databaseURL: scanner.sourceIndexURL)
            guard let highWater = try index.captureHighWaterMark(),
                  let batch = try index.createBatch(through: highWater) else {
                throw CheckFailure.failed("interrupted pointer batch fixture")
            }
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
            let coordinator = ConversationBatchCoordinator(
                scanner: scanner,
                orchestrator: orchestrator
            )
            let recovered = try coordinator.recoverInterruptedBatches()
            try require(recovered == 1, "one interrupted batch is recovered")
            let failedBatch = try index.batch(id: batch.id)
            try require(
                failedBatch?.status == .failed
                    && failedBatch?.pointers.first?.processingState == .failed,
                "interrupted batch becomes a terminal failure"
            )
            let repeatedRecoveryCount = try coordinator.recoverInterruptedBatches()
            try require(
                repeatedRecoveryCount == 0,
                "terminal failure is not retried on the next recovery"
            )
            try require(
                !FileManager.default.fileExists(
                    atPath: repository.paths.root.appendingPathComponent("agent-runs.jsonl").path
                ),
                "interrupted recovery never starts the model"
            )

            let committedTurn = """
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_started","turn_id":"committed-turn"}}
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"user_message","message":"Recover the prepared commit"}}
            {"type":"event_msg","timestamp":"\(now.formatted(iso))","payload":{"type":"task_complete","turn_id":"committed-turn","last_agent_message":"Prepared"}}

            """
            let committedHandle = try FileHandle(forWritingTo: session)
            try committedHandle.seekToEnd()
            try committedHandle.write(contentsOf: Data(committedTurn.utf8))
            try committedHandle.close()
            let committedSegments = try scanner.scanChangedFiles([session.path])
            guard let committedSegment = committedSegments.first,
                  let committedHighWater = try index.captureHighWaterMark(),
                  let committedBatch = try index.createBatch(through: committedHighWater) else {
                throw CheckFailure.failed("prepared commit batch fixture")
            }
            let plan = ConversationBatchCommitPlan(
                changes: [],
                successfulRoutes: [
                    ProcessedSegmentRoute(
                        segmentID: committedSegment.id,
                        threadID: committedSegment.threadID,
                        turnID: committedSegment.turnID,
                        projectID: "project"
                    )
                ],
                failedSegmentIDs: [],
                processed: 1,
                changed: 0,
                ignored: 1,
                agentRuns: 1
            )
            let outcomeRoot = repository.paths.root.appendingPathComponent(
                "batch-outcomes",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: outcomeRoot,
                withIntermediateDirectories: true
            )
            try WorkstateCoding.makeEncoder().encode(
                TestBatchOutcomeRecord(
                    batchID: committedBatch.id,
                    createdAt: now,
                    plan: plan
                )
            ).write(
                to: outcomeRoot.appendingPathComponent("\(committedBatch.id).json"),
                options: .atomic
            )
            let preparedRecoveryCount = try coordinator.recoverInterruptedBatches()
            try require(
                preparedRecoveryCount == 1,
                "prepared commit is finalized without repeating the model"
            )
            let completedBatch = try index.batch(id: committedBatch.id)
            try require(
                completedBatch?.status == .completed
                    && completedBatch?.pointers.first?.projectID == "project",
                "prepared commit restores pointer assignment"
            )
            let recoveredBinding = try scanner.routeBinding(threadID: "thread")
            try require(
                recoveredBinding?.projectID == "project",
                "prepared commit restores the thread route"
            )
        }
    }

    private static func semanticBundlesPersistRoutedEvidence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-semantic-bundle-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("rollout.jsonl")
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let firstDate = Date(timeIntervalSince1970: 1_784_800_000)
        let secondDate = firstDate.addingTimeInterval(1)
        let thirdDate = secondDate.addingTimeInterval(1)
        let metadata = """
        {"type":"session_meta","timestamp":"\(firstDate.formatted(iso))","payload":{"id":"thread","cwd":"/tmp/project"}}

        """
        try Data(metadata.utf8).write(to: session)
        let scanner = CodexSessionScanner(sessionsRoot: sessions, runtimeRoot: root)
        _ = try scanner.scan()
        let turns = """
        {"type":"event_msg","timestamp":"\(firstDate.formatted(iso))","payload":{"type":"task_started","turn_id":"turn-a"}}
        {"type":"event_msg","timestamp":"\(firstDate.formatted(iso))","payload":{"type":"user_message","message":"Discuss option A"}}
        {"type":"event_msg","timestamp":"\(firstDate.formatted(iso))","payload":{"type":"task_complete","turn_id":"turn-a","last_agent_message":"Option A is still open"}}
        {"type":"event_msg","timestamp":"\(secondDate.formatted(iso))","payload":{"type":"task_started","turn_id":"turn-b"}}
        {"type":"event_msg","timestamp":"\(secondDate.formatted(iso))","payload":{"type":"user_message","message":"Legacy routed turn"}}
        {"type":"event_msg","timestamp":"\(secondDate.formatted(iso))","payload":{"type":"task_complete","turn_id":"turn-b","last_agent_message":"Legacy result"}}
        {"type":"event_msg","timestamp":"\(thirdDate.formatted(iso))","payload":{"type":"task_started","turn_id":"turn-c"}}
        {"type":"event_msg","timestamp":"\(thirdDate.formatted(iso))","payload":{"type":"user_message","message":"Legacy routed turn"}}
        {"type":"event_msg","timestamp":"\(thirdDate.formatted(iso))","payload":{"type":"task_complete","turn_id":"turn-c","last_agent_message":"Legacy result"}}

        """
        let handle = try FileHandle(forWritingTo: session)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(turns.utf8))
        try handle.close()
        let segments = try scanner.scanChangedFiles([session.path])
        try require(segments.count == 3, "semantic bundle fixture has three completed turns")
        try scanner.recordRouteResult(
            segmentID: segments[0].id,
            route: RouteResult(
                action: "switch_project",
                projectId: "project",
                projectName: "",
                projectSummary: "",
                disposition: "carry",
                bundleId: "bundle-project-option-a",
                bundleTitle: "Option A",
                bundleSummary: "Option A is still being discussed.",
                signals: [
                    RouteSignal(type: "topic", authority: "assistant_proposal", summary: "Option A remains open")
                ],
                confidence: 1,
                reason: "Relevant but unresolved"
            )
        )
        try scanner.recordRouteResult(
            segmentID: segments[1].id,
            route: RouteResult(
                action: "switch_project",
                projectId: "project",
                projectName: "",
                projectSummary: "",
                disposition: "commit",
                bundleId: "bundle-project-option-a",
                bundleTitle: "Option A",
                bundleSummary: "Option A has been confirmed.",
                signals: [
                    RouteSignal(type: "decision", authority: "user_confirmed", summary: "Option A confirmed")
                ],
                confidence: 1,
                reason: "Confirmed"
            )
        )
        try scanner.recordRouteResult(
            segmentID: segments[2].id,
            route: RouteResult(
                action: "switch_project",
                projectId: "project",
                projectName: "",
                projectSummary: "",
                confidence: 1,
                reason: "Legacy route"
            )
        )
        let bundles = try scanner.openSemanticBundles()
        try require(
            bundles.count == 1
                && bundles[0].evidenceIDs == [segments[0].id, segments[1].id]
                && bundles[0].disposition == "commit",
            "carried and committed evidence remain visible in one pending semantic bundle"
        )
        let requeued = try scanner.requeueLegacyPendingRoutes()
        try require(requeued == 1, "legacy route is requeued once")
        let legacy = try scanner.processingRecord(segmentID: segments[2].id)
        try require(legacy.stage == .queued && legacy.route == nil, "legacy route returns to the Luna gate")
    }

    private static func interruptedProcessingRecoversWithoutRepeatingCompletedStages() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-processing-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let scanner = CodexSessionScanner(
            sessionsRoot: root.appendingPathComponent("sessions"),
            runtimeRoot: root
        )
        try scanner.replacePending(segmentIDs: ["routing", "stewarding", "applying"])

        try scanner.beginProcessing(segmentID: "routing", stage: .routing)

        try scanner.recordRouteResult(
            segmentID: "stewarding",
            route: RouteResult(
                action: "switch_project",
                projectId: "project",
                projectName: "Project",
                projectSummary: "Summary",
                confidence: 1,
                reason: "Matched"
            )
        )
        try scanner.beginProcessing(segmentID: "stewarding", stage: .stewarding)

        let route = RouteResult(
            action: "switch_project",
            projectId: "project",
            projectName: "Project",
            projectSummary: "Summary",
            confidence: 1,
            reason: "Matched"
        )
        try scanner.recordRouteResult(segmentID: "applying", route: route)
        try scanner.recordStewardResult(
            segmentID: "applying",
            steward: StewardResult(
                classification: "no_change",
                title: "",
                summary: "",
                worklineAction: "none",
                worklineId: "",
                worklineTitle: "",
                worklineObjective: "",
                branchFromWorklineId: "",
                kind: "contextUpdate",
                stage: "intake",
                delivery: "unchanged",
                facts: []
            )
        )
        try scanner.beginProcessing(segmentID: "applying", stage: .applying)

        let recovered = try scanner.recoverInterruptedProcessing()
        try require(recovered == 3, "all interrupted processing stages recover")
        let routingRecord = try scanner.processingRecord(segmentID: "routing")
        let stewardingRecord = try scanner.processingRecord(segmentID: "stewarding")
        let applyingRecord = try scanner.processingRecord(segmentID: "applying")
        try require(
            routingRecord.stage == .queued,
            "routing restarts before its missing model result"
        )
        try require(
            stewardingRecord.stage == .routed,
            "stewarding preserves the completed route"
        )
        try require(
            applyingRecord.stage == .stewarded,
            "applying preserves route and steward results"
        )
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

    private static func sessionWatcherReceivesNestedFileAppend() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-nested-watcher-check-\(UUID().uuidString)", isDirectory: true)
        let day = root.appendingPathComponent("2026/07/28", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let session = day.appendingPathComponent("rollout.jsonl")
        try Data("initial\n".utf8).write(to: session)

        let capture = WatcherCapture()
        let watcher = CodexSessionWatcher(root: root) { batch in
            capture.receive(batch)
        }
        try watcher.start()
        defer { watcher.stop() }

        let handle = try FileHandle(forWritingTo: session)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("appended\n".utf8))
        try handle.close()

        let result = capture.wait(timeout: 5)
        let canonicalSessionPath = session.resolvingSymlinksInPath().path
        try require(result != nil, "FSEvents watcher receives an append in a nested day directory")
        try require(
            result?.requiresFullScan == true
                || result?.paths.contains(where: {
                    URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == canonicalSessionPath
                }) == true,
            "FSEvents watcher identifies the nested appended session file"
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
            routeBindingHistory: [
                session.threadID: [
                    ThreadRouteBinding(
                        threadID: session.threadID,
                        turnID: session.turnID,
                        projectID: project.id,
                        updatedAt: session.updatedAt
                    )
                ]
            ]
        )

        try require(activities.count == 1, "known project thread creates live activity")
        try require(activities.first?.projectID == project.id, "live activity uses source-owned project")
        try require(activities.first?.title == session.userText, "live activity keeps current objective")
        try require(
            LiveActivityProjector().project(sessions: [session]).isEmpty,
            "unbound conversation does not appear in a project timeline"
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-live-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LiveActivityRepository(root: root)
        let snapshot = LiveActivitySnapshot(updatedAt: timelineDate(11), activities: activities)
        try repository.save(snapshot)
        let restored = try repository.load()
        try require(restored == snapshot, "live activity snapshot round trip")

        let scanner = CodexSessionScanner(
            sessionsRoot: root.appendingPathComponent("sessions", isDirectory: true),
            runtimeRoot: root
        )
        try scanner.recordRoute(threadID: "thread", turnID: "01900000-0000-7000-8000-000000000001", projectID: "project-a")
        try scanner.recordRoute(threadID: "thread", turnID: "01900000-0001-7000-8000-000000000002", projectID: "project-b")
        let history = try scanner.routeBindingHistory(threadID: "thread")
        try require(history.map(\.projectID) == ["project-a", "project-b"], "thread keeps ordered project binding history")
        let latestBinding = try scanner.routeBinding(threadID: "thread")
        try require(latestBinding?.projectID == "project-b", "latest project binding is current")
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
            try require(source.excerpt.isEmpty, "rebuild source does not copy conversation text")
            try require(
                source.startOffset == evidence.startOffset && source.endOffset == evidence.endOffset,
                "rebuild source keeps exact byte offsets"
            )
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
            topics: [],
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

    private static func contextSnapshotSelectsCurrentWork() throws {
        try withFixture { repository in
            let source = SourceReference(
                id: "source",
                kind: "codex",
                label: "Current discussion",
                locator: "/tmp/session.jsonl",
                threadID: "thread",
                turnIDs: ["turn"]
            )
            let activeTask = TaskRecord(
                id: "active",
                title: "Active work",
                objective: "Continue here",
                status: .active,
                currentStage: .implementation,
                branchedFromEventID: "start",
                sourceIDs: [source.id]
            )
            let completedTask = TaskRecord(
                id: "done",
                title: "Old work",
                objective: "Already done",
                status: .completed,
                currentStage: .completed,
                branchedFromEventID: "start"
            )
            let project = ProjectRecord(
                id: "project",
                name: "Project",
                summary: "Fallback",
                context: ProjectContext(
                    currentSummary: "Current project HEAD",
                    purpose: "Preserve context",
                    understanding: [
                        ContextStatement(text: "Confirmed understanding", status: .confirmed)
                    ],
                    acceptedDecisions: [
                        DecisionRecord(text: "Confirmed decision", status: .confirmed)
                    ],
                    forbiddenDirections: ["Do not replay old history"]
                ),
                tasks: [activeTask, completedTask],
                events: [
                    ProjectEvent(
                        id: "start",
                        timestamp: Date(timeIntervalSince1970: 100),
                        title: "Started",
                        summary: "Start",
                        kind: .taskStarted,
                        loopStage: .intake
                    ),
                    ProjectEvent(
                        id: "active-latest",
                        taskID: activeTask.id,
                        timestamp: Date(timeIntervalSince1970: 200),
                        title: "Implementation",
                        summary: "Current change",
                        kind: .implementation,
                        loopStage: .implementation,
                        facts: ["The implementation changed"],
                        sourceIDs: [source.id]
                    )
                ],
                sourceIDs: [source.id]
            )
            try repository.ensureInitialized(
                initial: WorkspaceSnapshot(projects: [project], sources: [source])
            )
            let snapshot = try WorkstateService(repository: repository).contextSnapshot(
                projectID: project.id,
                generatedAt: Date(timeIntervalSince1970: 300)
            )
            try require(snapshot.project.summary == "Current project HEAD", "handoff uses project HEAD")
            try require(snapshot.worklines.map(\.id) == [activeTask.id], "handoff excludes completed work")
            try require(snapshot.worklines[0].deltas.map(\.id) == ["active-latest"], "handoff keeps meaningful delta")
            try require(snapshot.sources.map(\.id) == [source.id], "handoff keeps source pointer")
            let markdown = ContextSnapshotMarkdownRenderer().render(snapshot)
            try require(markdown.contains("Confirmed decision"), "handoff renders decisions")
            try require(!markdown.contains("Old work"), "handoff omits completed work")
            let handoff = try ContextHandoffExporter(root: repository.paths.root).export(snapshot)
            try require(
                FileManager.default.fileExists(atPath: handoff.url.path),
                "handoff writes a durable project file"
            )
            try require(
                handoff.prompt.contains(handoff.url.path),
                "handoff prompt points another IDE to the durable file"
            )
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

    private static func ingestionBatchIsAtomicAndUpdatesProjectHead() throws {
        try withFixture { repository in
            let start = Date(timeIntervalSince1970: 100)
            let firstDate = Date(timeIntervalSince1970: 200)
            let secondDate = firstDate
            let project = ProjectRecord(
                id: "project",
                name: "Project",
                summary: "Old HEAD",
                createdAt: start,
                updatedAt: start,
                lastActivityAt: start,
                context: ProjectContext(
                    currentSummary: "Old HEAD",
                    purpose: "Keep project memory current"
                ),
                events: [
                    ProjectEvent(
                        id: "project-start",
                        timestamp: start,
                        title: "Project started",
                        summary: "Start",
                        kind: .projectStarted,
                        loopStage: .intake
                    )
                ]
            )
            try repository.ensureInitialized(
                initial: WorkspaceSnapshot(updatedAt: start, projects: [project])
            )
            let mutationLinesBefore = try Data(contentsOf: repository.paths.events)
                .split(separator: 0x0A)
                .count
            let firstSource = SourceReference(
                id: "source-first",
                kind: "conversation",
                label: "First",
                locator: "/tmp/first.jsonl"
            )
            let secondSource = SourceReference(
                id: "source-second",
                kind: "conversation",
                label: "Second",
                locator: "/tmp/second.jsonl"
            )
            let first = IngestionProjectChange(
                id: "z-delta-first",
                projectID: project.id,
                timestamp: firstDate,
                sources: [firstSource],
                title: "Implementation converged",
                summary: "The implementation now follows the confirmed model.",
                kind: .implementation,
                stage: .implementation,
                delivery: .changed,
                facts: ["Implementation changed"],
                operations: OperationalContext(cwd: "/tmp/project"),
                worklineAction: .startNew,
                worklineID: "project-core-workline",
                worklineTitle: "Core workline",
                worklineObjective: "Reach the confirmed result",
                branchFromWorklineID: "",
                isParallel: false,
                nextFocusedWorklineID: "",
                closureDisposition: .none,
                carryoverTitle: "",
                carryoverSummary: "",
                carryoverQuestions: [],
                taskStartEventID: "task-start-first",
                contextPatch: IngestionContextPatch(
                    currentSummary: "Current project HEAD",
                    revisionID: "context-revision-first",
                    revisionTitle: "Project understanding updated",
                    revisionSummary: "The confirmed product model is now current.",
                    revisionStatus: .confirmed,
                    changes: ["Replace the old HEAD"],
                    understandingUpserts: [
                        IngestionUnderstandingMutation(
                            id: "project-current-model",
                            text: "The confirmed product model is implemented.",
                            status: .confirmed
                        )
                    ],
                    decisionUpserts: [
                        IngestionDecisionMutation(
                            id: "project-use-confirmed-model",
                            text: "Use the confirmed product model.",
                            rationale: "Explicitly confirmed"
                        )
                    ]
                )
            )
            let second = IngestionProjectChange(
                id: "a-delta-second",
                projectID: project.id,
                timestamp: secondDate,
                sources: [secondSource],
                title: "Verification passed",
                summary: "The bounded workline is complete.",
                kind: .verification,
                stage: .verification,
                delivery: .checked,
                facts: ["Checks passed"],
                operations: OperationalContext(cwd: "/tmp/project"),
                worklineAction: .completeExisting,
                worklineID: "project-core-workline",
                worklineTitle: "",
                worklineObjective: "",
                branchFromWorklineID: "",
                isParallel: false,
                nextFocusedWorklineID: "",
                closureDisposition: .completed,
                carryoverTitle: "",
                carryoverSummary: "",
                carryoverQuestions: [],
                taskStartEventID: "",
                contextPatch: nil
            )

            _ = try WorkstateService(repository: repository).applyIngestionChanges(
                projectID: project.id,
                changes: [first, second]
            )
            let updated = try repository.load().project(id: project.id)
            try require(updated?.context.currentSummary == "Current project HEAD", "ingestion updates Project HEAD")
            try require(updated?.context.revisions.map(\.id) == ["context-revision-first"], "ingestion records one context revision")
            try require(updated?.context.understanding.first?.id == "project-current-model", "ingestion persists structured understanding")
            try require(updated?.context.acceptedDecisions.first?.id == "project-use-confirmed-model", "ingestion persists confirmed decisions")
            try require(updated?.task(id: "project-core-workline")?.status == .completed, "batch changes evolve one workline in order")
            try require(
                updated?.event(id: "z-delta-first") != nil
                    && updated?.event(id: "a-delta-second") != nil,
                "batch changes persist their deltas"
            )
            let mutationLinesAfter = try Data(contentsOf: repository.paths.events)
                .split(separator: 0x0A)
                .count
            try require(
                mutationLinesAfter == mutationLinesBefore + 1,
                "one ingestion batch writes one workspace mutation"
            )
            _ = try WorkstateService(repository: repository).applyIngestionChanges(
                projectID: project.id,
                changes: [first, second]
            )
            let mutationLinesAfterReplay = try Data(contentsOf: repository.paths.events)
                .split(separator: 0x0A)
                .count
            try require(
                mutationLinesAfterReplay == mutationLinesAfter,
                "replaying a committed ingestion batch performs no second write"
            )
        }
    }

    private static func ingestionBatchBranchesNewProjectFromHistoricalStart() throws {
        try withFixture { repository in
            try repository.ensureInitialized(initial: WorkspaceSnapshot())
            let evidenceTime = Date(timeIntervalSince1970: 200)
            let change = IngestionProjectChange(
                id: "historical-first-change",
                projectID: "historical-project",
                timestamp: evidenceTime,
                sources: [],
                title: "Historical work begins",
                summary: "The first imported change starts a bounded workline.",
                kind: .implementation,
                stage: .implementation,
                delivery: .changed,
                facts: [],
                operations: .init(),
                worklineAction: .startNew,
                worklineID: "historical-project-first-workline",
                worklineTitle: "First workline",
                worklineObjective: "Import historical work",
                branchFromWorklineID: "",
                isParallel: false,
                nextFocusedWorklineID: "historical-project-first-workline",
                closureDisposition: .none,
                carryoverTitle: "",
                carryoverSummary: "",
                carryoverQuestions: [],
                taskStartEventID: "historical-project-first-workline-start",
                contextPatch: nil
            )
            let input = ProjectCreateInput(
                id: "historical-project",
                name: "Historical Project",
                summary: "Imported from historical evidence",
                purpose: "Verify historical project creation",
                position: GraphPosition(x: 0, y: 0)
            )

            _ = try WorkstateService(repository: repository).applyIngestionBatch(
                [change],
                newProjects: [input]
            )
            let project = try repository.load().project(id: input.id)
            try require(
                project?.event(id: "project-start-historical-project")?.timestamp == evidenceTime,
                "new ingestion project starts at its earliest evidence"
            )
            try require(
                project?.task(id: "historical-project-first-workline")?.branchedFromEventID
                    == "project-start-historical-project",
                "historical first workline branches from the project start event"
            )
        }
    }

    private static func ingestionFocusSwitchDoesNotCompletePreviousWorkline() throws {
        try withFixture { repository in
            let start = Date(timeIntervalSince1970: 100)
            let firstTask = TaskRecord(
                id: "project-first",
                title: "First",
                objective: "Keep the first scope open",
                currentStage: .implementation,
                startedAt: start,
                updatedAt: start,
                branchedFromEventID: "project-start"
            )
            let project = ProjectRecord(
                id: "project",
                name: "Project",
                summary: "Summary",
                focusedTaskID: firstTask.id,
                tasks: [firstTask],
                events: [
                    ProjectEvent(
                        id: "project-start",
                        timestamp: start,
                        title: "Project started",
                        summary: "Start",
                        kind: .projectStarted,
                        loopStage: .intake
                    ),
                    ProjectEvent(
                        id: "first-progress",
                        taskID: firstTask.id,
                        timestamp: start,
                        title: "First progress",
                        summary: "The first scope remains unfinished",
                        kind: .implementation,
                        loopStage: .implementation
                    )
                ]
            )
            try repository.ensureInitialized(initial: WorkspaceSnapshot(projects: [project]))
            let change = IngestionProjectChange(
                id: "second-progress",
                projectID: project.id,
                timestamp: start.addingTimeInterval(60),
                sources: [],
                title: "Second scope started",
                summary: "Attention moved without completing the first scope.",
                kind: .implementation,
                stage: .implementation,
                delivery: .changed,
                facts: [],
                operations: .init(),
                worklineAction: .startNew,
                worklineID: "project-second",
                worklineTitle: "Second",
                worklineObjective: "Advance an independent scope",
                branchFromWorklineID: firstTask.id,
                isParallel: false,
                nextFocusedWorklineID: "",
                closureDisposition: .none,
                carryoverTitle: "",
                carryoverSummary: "",
                carryoverQuestions: [],
                taskStartEventID: "second-start",
                contextPatch: nil
            )
            _ = try WorkstateService(repository: repository).applyIngestionChanges(
                projectID: project.id,
                changes: [change]
            )
            let updated = try repository.load().project(id: project.id)
            try require(
                updated?.task(id: firstTask.id)?.status == .active,
                "focus switch does not complete the previous workline"
            )
            try require(
                updated?.focusedTaskID == "project-second",
                "focus switch selects the new workline"
            )
        }
    }

    private static func completedBatchMetadataIsPruned() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-batch-prune-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let scanner = CodexSessionScanner(
            sessionsRoot: root.appendingPathComponent("sessions"),
            runtimeRoot: root
        )
        let segmentIDs = ["segment-a", "segment-b"]
        try scanner.replacePending(segmentIDs: segmentIDs)
        let route = RouteResult(
            action: "switch_project",
            projectId: "project",
            projectName: "Project",
            projectSummary: "Summary",
            confidence: 1,
            reason: "Matched"
        )
        try scanner.recordRouteResults([
            segmentIDs[0]: route,
            segmentIDs[1]: route
        ])
        try scanner.beginProcessing(segmentIDs: segmentIDs, stage: .stewarding)
        try scanner.recordStewardBatch(
            id: "batch",
            projectID: "project",
            segmentIDs: segmentIDs,
            result: BatchStewardResult(changes: [])
        )
        let pending = try scanner.loadState()
        try require(pending.processingRecords?.count == 2, "active batch keeps recovery records")
        try require(pending.stewardBatches?.count == 1, "active batch result is stored once")

        do {
            try scanner.commitProcessed([
                ProcessedSegmentRoute(
                    segmentID: segmentIDs[0],
                    threadID: "thread",
                    turnID: "turn-a",
                    projectID: "project"
                )
            ])
            throw CheckFailure.failed("partial batch commit must fail")
        } catch let error as WorkstateStorageError {
            guard case .invalidState(let message) = error else { throw error }
            try require(message.contains("one unit"), "partial batch commit diagnostic")
        }

        try scanner.commitProcessed([
            ProcessedSegmentRoute(
                segmentID: segmentIDs[0],
                threadID: "thread",
                turnID: "turn-a",
                projectID: "project"
            ),
            ProcessedSegmentRoute(
                segmentID: segmentIDs[1],
                threadID: "thread",
                turnID: "turn-b",
                projectID: "project"
            )
        ])
        let completed = try scanner.loadState()
        try require(completed.pendingSegmentIDs.isEmpty, "completed batch leaves no pending ids")
        try require(completed.processingRecords?.isEmpty != false, "completed records are pruned")
        try require(completed.stewardBatches?.isEmpty != false, "completed batch payload is pruned")
    }

    private static func previousActivityDaySkipsCalendarGaps() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workstate-brief-day-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let friday = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 17, hour: 12)
        )!
        let monday = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 20, hour: 10)
        )!
        let project = ProjectRecord(
            id: "project",
            name: "Project",
            summary: "Summary",
            createdAt: friday,
            updatedAt: friday,
            lastActivityAt: friday,
            events: [
                ProjectEvent(
                    id: "friday-progress",
                    timestamp: friday,
                    title: "Friday progress",
                    summary: "A real workday",
                    kind: .implementation,
                    loopStage: .implementation
                )
            ]
        )
        let workspace = WorkspaceSnapshot(updatedAt: friday, projects: [project])
        let briefs = DailyBriefRepository(root: root)
        let fridayBrief = try briefs.brief(
            for: friday,
            workspace: workspace,
            calendar: calendar
        )
        _ = try briefs.applyNarrative(
            DailyBriefNarrative(
                sourceRevision: fridayBrief.sourceRevision,
                overview: "Friday summary",
                projectSummaries: [
                    DailyProjectNarrative(projectID: project.id, summary: "Friday progress")
                ],
                nextStep: ""
            ),
            to: fridayBrief.dateKey
        )
        let composer = BriefCompositionService(
            repository: briefs,
            runtime: AgentRuntimeClient(
                runtimeScript: root.appendingPathComponent("missing-runtime.js"),
                nodePath: "/missing/node",
                runtimeRoot: root
            ),
            scanner: CodexSessionScanner(
                sessionsRoot: root.appendingPathComponent("sessions"),
                runtimeRoot: root
            )
        )
        let result = try composer.refreshPreviousActivityDay(
            workspace: workspace,
            now: monday,
            calendar: calendar
        )
        try require(result?.dateKey == fridayBrief.dateKey, "daily brief selects the latest real activity day")
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

    private static func projectTimelineSequentialWorkStaysOnMainline() throws {
        let firstTask = timelineTask(id: "first", start: 1, update: 2, completion: 2)
        let secondTask = timelineTask(id: "second", start: 3, update: 4, completion: nil)
        let start = ProjectEvent(
            id: "project-start",
            timestamp: timelineDate(0),
            title: "Start",
            summary: "Start",
            kind: .projectStarted,
            loopStage: .intake
        )
        let first = ProjectEvent(
            id: "first-event",
            taskID: firstTask.id,
            timestamp: timelineDate(2),
            title: "First complete",
            summary: "First scope closed",
            kind: .completed,
            loopStage: .completed
        )
        let second = ProjectEvent(
            id: "second-event",
            taskID: secondTask.id,
            timestamp: timelineDate(4),
            title: "Second active",
            summary: "Second scope is current",
            kind: .implementation,
            loopStage: .implementation
        )
        let project = ProjectRecord(
            id: "project",
            name: "Project",
            summary: "Summary",
            lastActivityAt: timelineDate(4),
            focusedTaskID: secondTask.id,
            tasks: [firstTask, secondTask],
            events: [start, first, second]
        )

        let layout = ProjectTimelineLayout(project: project)
        try require(layout.primaryTaskID == secondTask.id, "explicit focus selects current mainline")
        try require(layout.branches.isEmpty, "sequential work does not create a branch")
        try require(
            layout.nodes.filter { $0.event.taskID != nil }.allSatisfy { $0.isOnMainline },
            "sequential task events remain on mainline"
        )
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

private struct TestBatchOutcomeRecord: Codable {
    var batchID: String
    var createdAt: Date
    var plan: ConversationBatchCommitPlan
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
