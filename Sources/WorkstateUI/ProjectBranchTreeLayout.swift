import CoreGraphics
import Foundation
import WorkstateCore

package struct ProjectBranchTreeNode: Identifiable {
    package let id: String
    package let event: ProjectEvent
    package let task: TaskRecord
    package let point: CGPoint
    package let isLatestInTask: Bool
}

package struct ProjectBranchTreeRow: Identifiable {
    package let id: String
    package let task: TaskRecord
    package let parentTaskID: String?
    package let depth: Int
    package let y: CGFloat
}

package struct ProjectBranchTreePath: Identifiable {
    package let id: String
    package let task: TaskRecord
    package let points: [CGPoint]
}

package struct ProjectBranchTreeLayout {
    package static let labelWidth: CGFloat = 240
    package static let graphStartX: CGFloat = 252
    package static let rowHeight: CGFloat = 72
    package static let eventSpacing: CGFloat = 20

    package let rows: [ProjectBranchTreeRow]
    package let nodes: [ProjectBranchTreeNode]
    package let paths: [ProjectBranchTreePath]
    package let primaryTaskID: String?
    package let contentSize: CGSize

    package init(
        project: ProjectRecord,
        includesHistory: Bool = false,
        viewportWidth: CGFloat = WorkstateTheme.projectWidth,
        topInset: CGFloat = 24
    ) {
        let includedTasks = project.tasks.filter { task in
            includesHistory || task.status == .active
        }
        let includedTaskIDs = Set(includedTasks.map(\.id))
        let taskByID = Dictionary(uniqueKeysWithValues: includedTasks.map { ($0.id, $0) })
        let eventByID = Dictionary(uniqueKeysWithValues: project.events.map { ($0.id, $0) })
        let taskByMergeEventID = includedTasks.reduce(into: [String: TaskRecord]()) { result, task in
            if let eventID = task.mergedByEventID {
                result[eventID] = task
            }
        }
        let syntheticMergeIDs = Set(includedTasks.compactMap(\.mergedByEventID))
        let visibleEvents = project.events.filter { event in
            event.kind != .taskStarted
                && event.taskID.map(includedTaskIDs.contains) == true
                && !syntheticMergeIDs.contains(event.id)
        }
        let branchOriginEventIDs = Set(includedTasks.map(\.branchedFromEventID))
        let allEventsByTaskID = Dictionary(grouping: visibleEvents, by: { $0.taskID! })
            .mapValues { events in
                events.sorted {
                    if $0.timestamp == $1.timestamp { return $0.id < $1.id }
                    return $0.timestamp < $1.timestamp
                }
            }
        let eventsByTaskID = allEventsByTaskID.mapValues { events in
            guard events.count > 6 else { return events }
            var selectedIDs = Set(events.filter { branchOriginEventIDs.contains($0.id) }.map(\.id))
            if let first = events.first { selectedIDs.insert(first.id) }
            if let last = events.last { selectedIDs.insert(last.id) }
            for event in events.reversed() where selectedIDs.count < 6 {
                selectedIDs.insert(event.id)
            }
            return events.filter { selectedIDs.contains($0.id) }
        }

        let parentByTaskID = includedTasks.reduce(into: [String: String]()) { result, task in
            let parentID = eventByID[task.branchedFromEventID]?.taskID
                ?? taskByMergeEventID[task.branchedFromEventID]?.id
            if let parentID, parentID != task.id, taskByID[parentID] != nil {
                result[task.id] = parentID
            }
        }
        let childrenByTaskID = Dictionary(grouping: includedTasks.compactMap { task -> TaskRecord? in
            parentByTaskID[task.id] == nil ? nil : task
        }, by: { parentByTaskID[$0.id]! })

        func sortedTasks(_ tasks: [TaskRecord]) -> [TaskRecord] {
            tasks.sorted {
                if $0.startedAt == $1.startedAt { return $0.id < $1.id }
                return $0.startedAt < $1.startedAt
            }
        }

        var orderedTasks: [(task: TaskRecord, depth: Int)] = []
        var visited = Set<String>()
        func appendTask(_ task: TaskRecord, depth: Int) {
            guard visited.insert(task.id).inserted else { return }
            orderedTasks.append((task, depth))
            for child in sortedTasks(childrenByTaskID[task.id] ?? []) {
                appendTask(child, depth: depth + 1)
            }
        }

        for root in sortedTasks(includedTasks.filter { parentByTaskID[$0.id] == nil }) {
            appendTask(root, depth: 0)
        }
        for task in sortedTasks(includedTasks) where !visited.contains(task.id) {
            appendTask(task, depth: 0)
        }

        var builtRows: [ProjectBranchTreeRow] = []
        var builtNodes: [ProjectBranchTreeNode] = []
        var builtPaths: [ProjectBranchTreePath] = []
        var pointByEventID: [String: CGPoint] = [:]
        var lastPointByTaskID: [String: CGPoint] = [:]
        var yByTaskID: [String: CGFloat] = [:]

        for (index, entry) in orderedTasks.enumerated() {
            let task = entry.task
            let y = topInset + CGFloat(index) * Self.rowHeight + Self.rowHeight / 2
            yByTaskID[task.id] = y
            builtRows.append(
                ProjectBranchTreeRow(
                    id: task.id,
                    task: task,
                    parentTaskID: parentByTaskID[task.id],
                    depth: entry.depth,
                    y: y
                )
            )

            let parentTaskID = parentByTaskID[task.id]
            let origin = pointByEventID[task.branchedFromEventID]
                ?? parentTaskID.flatMap { parentID in
                    guard let point = lastPointByTaskID[parentID] else { return nil }
                    return CGPoint(x: point.x, y: yByTaskID[parentID] ?? point.y)
                }
                ?? CGPoint(x: Self.graphStartX, y: y)

            let taskEvents = eventsByTaskID[task.id] ?? []
            guard !taskEvents.isEmpty else {
                builtPaths.append(
                    ProjectBranchTreePath(
                        id: "branch-tree-path:\(task.id)",
                        task: task,
                        points: [origin]
                    )
                )
                continue
            }

            let firstX = max(Self.graphStartX + Self.eventSpacing, origin.x + Self.eventSpacing)
            var pathPoints = [origin]
            for (eventIndex, event) in taskEvents.enumerated() {
                let point = CGPoint(
                    x: firstX + CGFloat(eventIndex) * Self.eventSpacing,
                    y: y
                )
                pointByEventID[event.id] = point
                pathPoints.append(point)
                builtNodes.append(
                    ProjectBranchTreeNode(
                        id: event.id,
                        event: event,
                        task: task,
                        point: point,
                        isLatestInTask: eventIndex == taskEvents.count - 1
                    )
                )
            }
            lastPointByTaskID[task.id] = pathPoints.last
            builtPaths.append(
                ProjectBranchTreePath(
                    id: "branch-tree-path:\(task.id)",
                    task: task,
                    points: pathPoints
                )
            )
        }

        let selectedPrimaryTaskID = project.focusedTaskID
            .flatMap { focusedID in includedTasks.first(where: { $0.id == focusedID })?.id }
            ?? includedTasks
            .filter { $0.status == .active }
            .sorted {
                if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
                return $0.updatedAt > $1.updatedAt
            }
            .first?.id
            ?? includedTasks.max { $0.updatedAt < $1.updatedAt }?.id

        rows = builtRows
        nodes = builtNodes
        paths = builtPaths
        primaryTaskID = selectedPrimaryTaskID
        contentSize = CGSize(
            width: max(viewportWidth, (builtNodes.map(\.point.x).max() ?? Self.graphStartX) + 72),
            height: max(360, topInset + CGFloat(orderedTasks.count) * Self.rowHeight + 28)
        )
    }
}
