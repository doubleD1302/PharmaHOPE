import Foundation
import SwiftData

public enum TaskSearchQuery {
    public static func descriptor(search: String, state: Int, priority: String, shiftID: String,
                                  start: Date, end: Date, now: Date) -> FetchDescriptor<TaskItem> {
        let search = TaskText.normalized(search)
        let future = Date.distantFuture
        let selectedShift: String? = shiftID == "__inbox__" ? nil : shiftID
        let restrictShift = !shiftID.isEmpty
        return FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { task in
            task.createdAt >= start && task.createdAt < end &&
            (search.isEmpty || task.searchText.contains(search)) &&
            (priority.isEmpty || task.priorityRaw == priority) &&
            (!restrictShift || task.shiftId == selectedShift) &&
            ((state == 0 && task.deletedAt == nil) ||
             (state == 1 && task.deletedAt == nil && !task.isCompleted) ||
             (state == 2 && task.deletedAt == nil && task.isCompleted) ||
             (state == 3 && task.deletedAt == nil && !task.isCompleted && (task.dueAt ?? future) < now) ||
             (state == 4 && task.deletedAt != nil))
        }, sortBy: [SortDescriptor(\TaskItem.createdAt, order: .reverse)])
    }
}
