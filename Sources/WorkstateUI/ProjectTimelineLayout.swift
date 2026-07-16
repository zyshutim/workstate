import CoreGraphics
import Foundation
import WorkstateCore

package enum ProjectTimelineNodeContent {
    case projectEvent(ProjectEvent)
    case task(TaskRecord)
}

package struct ProjectTimelineNode: Identifiable {
    package let id: String
    package let timestamp: Date
    package let lane: Int
    package let content: ProjectTimelineNodeContent
}

package struct ProjectTimelineBranch {
    let task: TaskRecord
    let lane: Int
    let startPoint: CGPoint
    let taskPoint: CGPoint
    let mergePoint: CGPoint?
}

package struct ProjectTaskLaneAllocation {
    package let laneByTaskID: [String: Int]
    package let laneCount: Int

    package init(tasks: [TaskRecord]) {
        let orderedTasks = tasks.sorted {
            if $0.startedAt == $1.startedAt { return $0.id < $1.id }
            return $0.startedAt < $1.startedAt
        }
        var laneEndDates: [Date?] = []
        var assignments: [String: Int] = [:]

        for task in orderedTasks {
            let reusableLane = laneEndDates.firstIndex { endDate in
                guard let endDate else { return false }
                return endDate <= task.startedAt
            }
            let laneIndex: Int
            if let reusableLane {
                laneIndex = reusableLane
            } else {
                laneIndex = laneEndDates.count
                laneEndDates.append(nil)
            }
            assignments[task.id] = laneIndex + 1
            laneEndDates[laneIndex] = task.terminalDate
        }

        laneByTaskID = assignments
        laneCount = laneEndDates.count
    }
}

package struct ProjectTimelineLayout {
    package static let mainlineX: CGFloat = 72

    package let nodes: [ProjectTimelineNode]
    package let points: [String: CGPoint]
    package let branches: [ProjectTimelineBranch]
    package let taskLaneByID: [String: Int]
    package let contentSize: CGSize
    package let rowYs: [CGFloat]

    package init(
        project: ProjectRecord,
        viewportWidth: CGFloat = WorkstateTheme.projectWidth,
        laneWidth: CGFloat = WorkstateTheme.timelineLaneWidth,
        rowHeight: CGFloat = WorkstateTheme.timelineRowHeight
    ) {
        let projectEvents = project.events.filter { $0.taskID == nil }
        let laneAllocation = ProjectTaskLaneAllocation(tasks: project.tasks)
        taskLaneByID = laneAllocation.laneByTaskID

        var moments = projectEvents.map(\.timestamp)
        for task in project.tasks {
            moments.append(Self.branchStartDate(for: task))
            moments.append(Self.taskNodeDate(for: task, in: project))
            if let completedAt = task.terminalDate {
                moments.append(completedAt)
            }
        }
        let orderedMoments = Array(Set(moments)).sorted(by: >)
        let yByDate = Dictionary(uniqueKeysWithValues: orderedMoments.enumerated().map { index, date in
            (date, 66 + CGFloat(index) * rowHeight)
        })
        rowYs = orderedMoments.compactMap { yByDate[$0] }

        var timelineNodes = projectEvents.map { event in
            ProjectTimelineNode(
                id: Self.eventNodeID(event.id),
                timestamp: event.timestamp,
                lane: 0,
                content: .projectEvent(event)
            )
        }
        timelineNodes.append(contentsOf: project.tasks.map { task in
            ProjectTimelineNode(
                id: Self.taskNodeID(task.id),
                timestamp: Self.taskNodeDate(for: task, in: project),
                lane: laneAllocation.laneByTaskID[task.id]!,
                content: .task(task)
            )
        })
        timelineNodes.sort {
            if $0.timestamp == $1.timestamp { return $0.id < $1.id }
            return $0.timestamp > $1.timestamp
        }
        nodes = timelineNodes

        var nodePoints: [String: CGPoint] = [:]
        for node in timelineNodes {
            guard let y = yByDate[node.timestamp] else { continue }
            nodePoints[node.id] = CGPoint(
                x: Self.mainlineX + CGFloat(node.lane) * laneWidth,
                y: y
            )
        }
        points = nodePoints

        branches = project.tasks.compactMap { task in
            guard let lane = laneAllocation.laneByTaskID[task.id],
                  let taskPoint = nodePoints[Self.taskNodeID(task.id)],
                  let startY = yByDate[Self.branchStartDate(for: task)] else {
                return nil
            }
            let mergePoint = task.status == .completed
                ? task.terminalDate.flatMap { date in
                    yByDate[date].map { CGPoint(x: Self.mainlineX, y: $0) }
                }
                : nil
            return ProjectTimelineBranch(
                task: task,
                lane: lane,
                startPoint: CGPoint(x: Self.mainlineX, y: startY),
                taskPoint: taskPoint,
                mergePoint: mergePoint
            )
        }

        let lastLaneX = Self.mainlineX + CGFloat(laneAllocation.laneCount) * laneWidth
        contentSize = CGSize(
            width: max(viewportWidth, lastLaneX + 88),
            height: max(360, 108 + CGFloat(orderedMoments.count) * rowHeight)
        )
    }

    package static func taskNodeID(_ taskID: String) -> String {
        "task:\(taskID)"
    }

    package static func eventNodeID(_ eventID: String) -> String {
        "event:\(eventID)"
    }

    private static func branchStartDate(for task: TaskRecord) -> Date {
        task.startedAt
    }

    private static func taskNodeDate(for task: TaskRecord, in project: ProjectRecord) -> Date {
        project.events(for: task.id)
            .first(where: { $0.id != task.mergedByEventID })?
            .timestamp ?? task.updatedAt
    }
}

private extension TaskRecord {
    var terminalDate: Date? {
        switch status {
        case .completed, .abandoned:
            completedAt
        case .active, .waiting, .parked:
            nil
        }
    }
}
