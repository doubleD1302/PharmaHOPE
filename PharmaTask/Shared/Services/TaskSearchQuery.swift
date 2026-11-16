import Foundation
import SwiftData

public enum TaskSearchQuery {
    /// Mỗi trạng thái có một biểu thức riêng và các điều kiện cố định (`state == …`) được tính trước ngoài biểu thức:
    /// một biểu thức khổng lồ làm trình biên dịch mới báo "unable to type-check this expression in reasonable time".
    public static func descriptor(search: String, state: Int, priority: String, shiftID: String,
                                  start: Date, end: Date, now: Date) -> FetchDescriptor<TaskItem> {
        let search = TaskText.normalized(search)
        let future = Date.distantFuture
        let selectedShift: String? = shiftID == "__inbox__" ? nil : shiftID
        let anySearch = search.isEmpty
        let anyPriority = priority.isEmpty
        let anyShift = shiftID.isEmpty
        let sort = [SortDescriptor(\TaskItem.createdAt, order: .reverse)]

        let predicate: Predicate<TaskItem>
        switch state {
        case 1: // chưa xong
            predicate = #Predicate<TaskItem> { task in
                task.createdAt >= start && task.createdAt < end &&
                (anySearch || task.searchText.contains(search)) &&
                (anyPriority || task.priorityRaw == priority) &&
                (anyShift || task.shiftId == selectedShift) &&
                task.deletedAt == nil && !task.isCompleted
            }
        case 2: // đã xong
            predicate = #Predicate<TaskItem> { task in
                task.createdAt >= start && task.createdAt < end &&
                (anySearch || task.searchText.contains(search)) &&
                (anyPriority || task.priorityRaw == priority) &&
                (anyShift || task.shiftId == selectedShift) &&
                task.deletedAt == nil && task.isCompleted
            }
        case 3: // quá hạn
            predicate = #Predicate<TaskItem> { task in
                task.createdAt >= start && task.createdAt < end &&
                (anySearch || task.searchText.contains(search)) &&
                (anyPriority || task.priorityRaw == priority) &&
                (anyShift || task.shiftId == selectedShift) &&
                task.deletedAt == nil && !task.isCompleted && (task.dueAt ?? future) < now
            }
        case 4: // đã xoá
            predicate = #Predicate<TaskItem> { task in
                task.createdAt >= start && task.createdAt < end &&
                (anySearch || task.searchText.contains(search)) &&
                (anyPriority || task.priorityRaw == priority) &&
                (anyShift || task.shiftId == selectedShift) &&
                task.deletedAt != nil
            }
        default: // tất cả việc chưa xoá
            predicate = #Predicate<TaskItem> { task in
                task.createdAt >= start && task.createdAt < end &&
                (anySearch || task.searchText.contains(search)) &&
                (anyPriority || task.priorityRaw == priority) &&
                (anyShift || task.shiftId == selectedShift) &&
                task.deletedAt == nil
            }
        }
        return FetchDescriptor<TaskItem>(predicate: predicate, sortBy: sort)
    }
}
