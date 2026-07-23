import CoreGraphics
import Foundation
import WorkstateCore

package struct ProjectTimelineNode: Identifiable {
    package let id: String
    package let event: ProjectEvent
    package let task: TaskRecord?
    package let point: CGPoint
    package let isOnMainline: Bool
}

package struct ProjectTimelineBranch: Identifiable {
    package let id: String
    package let eventID: String
    package let task: TaskRecord?
    package let points: [CGPoint]
}

package struct ProjectTimelineLayout {
    package static let mainlineX: CGFloat = 48
    package static let branchLaneSpacing: CGFloat = 24
    package static let minimumLabelStartX: CGFloat = 92

    package let nodes: [ProjectTimelineNode]
    package let branches: [ProjectTimelineBranch]
    package let primaryTaskID: String?
    package let contentSize: CGSize
    package let rowYs: [CGFloat]
    package let labelStartX: CGFloat

    package init(
        project: ProjectRecord,
        viewportWidth: CGFloat = WorkstateTheme.projectWidth,
        rowHeight: CGFloat = WorkstateTheme.timelineRowHeight,
        topInset: CGFloat = 0
    ) {
        let taskByID = Dictionary(uniqueKeysWithValues: project.tasks.map { ($0.id, $0) })
        let syntheticMergeIDs = Set(project.tasks.compactMap(\.mergedByEventID))
        let chronologicalEvents = project.events
            .filter { event in
                event.kind != .taskStarted
                    && !(syntheticMergeIDs.contains(event.id) && event.taskID == nil)
            }
            .sorted {
                if $0.timestamp == $1.timestamp { return $0.id < $1.id }
                return $0.timestamp < $1.timestamp
            }

        let openTasks = project.tasks
            .filter { $0.status == .active }
        let primaryTaskID = project.focusedTaskID
            .flatMap { focusedID in openTasks.first(where: { $0.id == focusedID })?.id }
            ?? openTasks
            .sorted {
                if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
                return $0.updatedAt > $1.updatedAt
            }
            .first?.id
            ?? project.tasks.max { $0.updatedAt < $1.updatedAt }?.id

        let eventIndex = Dictionary(uniqueKeysWithValues: chronologicalEvents.enumerated().map { ($0.element.id, $0.offset) })
        let taskEnd: (TaskRecord) -> Date = { task in
            if let completedAt = task.completedAt { return completedAt }
            if task.status == .waiting || task.status == .parked { return task.updatedAt }
            return max(task.updatedAt, project.lastActivityAt)
        }
        let overlaps: (TaskRecord, TaskRecord) -> Bool = { left, right in
            left.startedAt <= taskEnd(right) && right.startedAt <= taskEnd(left)
        }
        let primaryTask = primaryTaskID.flatMap { id in
            project.tasks.first(where: { $0.id == id })
        }
        let branchTasks = project.tasks
            .filter { task in
                guard task.id != primaryTaskID,
                      chronologicalEvents.contains(where: { $0.taskID == task.id }) else {
                    return false
                }
                if let primaryTask, overlaps(task, primaryTask) {
                    return true
                }
                return project.tasks.contains { other in
                    other.id != task.id
                        && other.startedAt < task.startedAt
                        && overlaps(task, other)
                }
            }
            .sorted {
                if $0.startedAt == $1.startedAt { return $0.id < $1.id }
                return $0.startedAt < $1.startedAt
            }

        var laneEndIndices: [Int] = []
        var laneByTaskID: [String: Int] = [:]
        for task in branchTasks {
            let indices = chronologicalEvents.enumerated().compactMap { index, event in
                event.taskID == task.id ? index : nil
            }
            guard let first = indices.first, let last = indices.last else { continue }
            let laneOffset = laneEndIndices.firstIndex(where: { $0 < first }) ?? laneEndIndices.count
            if laneOffset == laneEndIndices.count {
                laneEndIndices.append(last)
            } else {
                laneEndIndices[laneOffset] = last
            }
            laneByTaskID[task.id] = laneOffset + 1
        }

        let yByEventID = Dictionary(uniqueKeysWithValues: chronologicalEvents.enumerated().map { index, event in
            (event.id, 58 + topInset + CGFloat(chronologicalEvents.count - index - 1) * rowHeight)
        })

        let timelineNodes = chronologicalEvents.map { event -> ProjectTimelineNode in
            let task = event.taskID.flatMap { taskByID[$0] }
            let isMerge = task?.mergedByEventID == event.id
            let lane = isMerge ? 0 : event.taskID.flatMap { laneByTaskID[$0] } ?? 0
            return ProjectTimelineNode(
                id: event.id,
                event: event,
                task: task,
                point: CGPoint(
                    x: Self.mainlineX + CGFloat(lane) * Self.branchLaneSpacing,
                    y: yByEventID[event.id]!
                ),
                isOnMainline: lane == 0
            )
        }
        let nodeByEventID = Dictionary(uniqueKeysWithValues: timelineNodes.map { ($0.id, $0) })

        let timelineBranches = branchTasks.compactMap { task -> ProjectTimelineBranch? in
            guard let lane = laneByTaskID[task.id] else { return nil }
            let taskNodes = timelineNodes
                .filter { $0.event.taskID == task.id }
                .sorted { $0.event.timestamp < $1.event.timestamp }
            guard let firstTaskNode = taskNodes.first else { return nil }

            let branchY = nodeByEventID[task.branchedFromEventID]?.point.y
                ?? chronologicalEvents
                    .filter { $0.timestamp <= task.startedAt }
                    .last
                    .flatMap { yByEventID[$0.id] }
                ?? firstTaskNode.point.y
            let laneX = Self.mainlineX + CGFloat(lane) * Self.branchLaneSpacing
            var points = [
                CGPoint(x: Self.mainlineX, y: branchY),
                CGPoint(x: laneX, y: firstTaskNode.point.y)
            ]
            points.append(contentsOf: taskNodes.map(\.point).dropFirst())

            if let mergeID = task.mergedByEventID,
               let mergeIndex = eventIndex[mergeID],
               let mergeY = yByEventID[chronologicalEvents[mergeIndex].id],
               points.last?.x != Self.mainlineX {
                points.append(CGPoint(x: Self.mainlineX, y: mergeY))
            }
            return ProjectTimelineBranch(
                id: "branch:\(task.id)",
                eventID: firstTaskNode.id,
                task: task,
                points: points
            )
        }

        nodes = timelineNodes.sorted {
            if $0.point.y == $1.point.y { return $0.point.x < $1.point.x }
            return $0.point.y < $1.point.y
        }
        branches = timelineBranches
        self.primaryTaskID = primaryTaskID
        rowYs = chronologicalEvents.reversed().compactMap { yByEventID[$0.id] }
        let maximumLane = laneByTaskID.values.max() ?? 0
        labelStartX = max(
            Self.minimumLabelStartX,
            Self.mainlineX + CGFloat(maximumLane) * Self.branchLaneSpacing + 24
        )
        contentSize = CGSize(
            width: viewportWidth,
            height: max(360, 92 + topInset + CGFloat(chronologicalEvents.count) * rowHeight)
        )
    }
}
