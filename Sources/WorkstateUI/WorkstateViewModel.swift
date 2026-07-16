import Combine
import Foundation
import WorkstateCore

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

    public let repository: WorkstateRepository
    private let service: WorkstateService
    private var lastModificationDate: Date?

    public init(repository: WorkstateRepository = .init()) {
        self.repository = repository
        service = WorkstateService(repository: repository)
        do {
            try repository.ensureInitialized()
            workspace = try repository.load()
            lastModificationDate = repository.modificationDate()
        } catch {
            workspace = WorkspaceSnapshot()
            errorMessage = error.localizedDescription
        }
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

    public var selectedReview: ReviewItem? {
        guard let selectedReviewID else { return pendingReviews.first }
        return workspace.reviewInbox.first { $0.id == selectedReviewID }
    }

    public var preferredWidth: CGFloat {
        selectedProjectID == nil ? WorkstateTheme.graphWidth : WorkstateTheme.projectWidth
    }

    public var preferredHeight: CGFloat {
        selectedProjectID == nil ? WorkstateTheme.graphHeight : WorkstateTheme.projectHeight
    }

    public func selectProject(_ id: String) {
        selectedProjectID = id
        selectedTaskID = nil
        selectedEventID = nil
        isContextExpanded = false
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

    public func reload(force: Bool = false) {
        let modificationDate = repository.modificationDate()
        guard force || modificationDate != lastModificationDate else { return }
        do {
            workspace = try repository.load()
            lastModificationDate = modificationDate
            errorMessage = nil
            repairSelection()
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
