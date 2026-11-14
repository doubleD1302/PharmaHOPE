import Foundation

/// A single partition per render; historical shifts never enter this snapshot's query.
public struct TaskDashboardSnapshot {
    public let pending: [TaskItem]
    public let completed: [TaskItem]
    public let urgentCount: Int
    public var total: Int { pending.count + completed.count }
    public var progress: Double { total == 0 ? 0 : Double(completed.count) / Double(total) }

    public init(tasks: [TaskItem]) {
        var pending: [TaskItem] = []
        var completed: [TaskItem] = []
        var urgent = 0
        for task in tasks {
            guard task.deletedAt == nil else { continue }
            if task.isCompleted { completed.append(task) }
            else {
                pending.append(task)
                if task.priority == .high { urgent += 1 }
            }
        }
        self.pending = pending.sorted {
            if $0.priority.sortOrder != $1.priority.sortOrder { return $0.priority.sortOrder < $1.priority.sortOrder }
            if $0.dueAt != $1.dueAt { return ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            if $0.dueTime != $1.dueTime { return ($0.dueTime ?? "99:99") < ($1.dueTime ?? "99:99") }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
        self.completed = completed.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id < $1.id
        }
        self.urgentCount = urgent
    }
}
