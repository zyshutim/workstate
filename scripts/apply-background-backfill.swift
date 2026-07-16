import Foundation

private struct WorkspaceBackfill: Codable {
    var sources: [SourceReference]
    var projects: [ProjectRecord]
    var relations: [ProjectRelation]
}

@main
private struct ApplyBackgroundBackfill {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw BackfillError.usage
        }

        let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = try Data(contentsOf: inputURL)
        let backfill = try WorkstateCoding.makeDecoder().decode(WorkspaceBackfill.self, from: data)
        let repository = WorkstateRepository()
        let mutation = WorkspaceMutation(
            kind: "workspace.background-backfill",
            summary: "Backfilled Reframe project backgrounds and major milestones"
        )

        let snapshot = try repository.update(mutation: mutation) { snapshot in
            for source in backfill.sources {
                if let index = snapshot.sources.firstIndex(where: { $0.id == source.id }) {
                    snapshot.sources[index] = source
                } else {
                    snapshot.sources.append(source)
                }
            }

            for incoming in backfill.projects {
                guard let index = snapshot.projects.firstIndex(where: { $0.id == incoming.id }) else {
                    snapshot.projects.append(incoming)
                    continue
                }

                let preservedPosition = snapshot.projects[index].graphPosition
                var project = snapshot.projects[index]
                project.name = incoming.name
                project.summary = incoming.summary
                project.status = incoming.status
                project.accent = incoming.accent
                project.createdAt = incoming.createdAt
                project.updatedAt = incoming.updatedAt
                project.lastActivityAt = incoming.lastActivityAt
                project.graphPosition = preservedPosition
                project.context = incoming.context
                project.sourceIDs = incoming.sourceIDs
                upsert(incoming.tasks, into: &project.tasks)
                upsert(incoming.events, into: &project.events)
                snapshot.projects[index] = project
            }

            for relation in backfill.relations {
                if let index = snapshot.relations.firstIndex(where: { $0.id == relation.id }) {
                    snapshot.relations[index] = relation
                } else {
                    snapshot.relations.append(relation)
                }
            }
        }

        print("Applied Reframe background v1: \(snapshot.projects.count) projects, \(snapshot.sources.count) sources, \(snapshot.relations.count) relations")
    }

    private static func upsert(_ incoming: [TaskRecord], into current: inout [TaskRecord]) {
        for item in incoming {
            if let index = current.firstIndex(where: { $0.id == item.id }) {
                current[index] = item
            } else {
                current.append(item)
            }
        }
    }

    private static func upsert(_ incoming: [ProjectEvent], into current: inout [ProjectEvent]) {
        for item in incoming {
            if let index = current.firstIndex(where: { $0.id == item.id }) {
                current[index] = item
            } else {
                current.append(item)
            }
        }
    }
}

private enum BackfillError: LocalizedError {
    case usage

    var errorDescription: String? {
        "Usage: apply-background-backfill <backfill.json>"
    }
}
