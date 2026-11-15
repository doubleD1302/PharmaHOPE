import Foundation
import SwiftData
import ActivityKit
import WidgetKit

/// Shared by the app, intents and Share Extension. Call only after a successful save.
@MainActor
public enum ShiftTaskSync {
    public static func activeShift(in context: ModelContext) throws -> ShiftConfig? {
        var descriptor = FetchDescriptor<ShiftConfig>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\ShiftConfig.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public static func tasks(in context: ModelContext, shiftID: String?) throws -> [TaskItem] {
        let tasks = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.shiftId == shiftID && $0.deletedAt == nil }))
        return tasks.sorted {
            if $0.priority.sortOrder != $1.priority.sortOrder { return $0.priority.sortOrder < $1.priority.sortOrder }
            if $0.dueAt != $1.dueAt { return ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            if $0.dueTime != $1.dueTime { return ($0.dueTime ?? "99:99") < ($1.dueTime ?? "99:99") }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    public static func state(shift: ShiftConfig, tasks: [TaskItem]) -> ShiftActivityAttributes.ContentState {
        .init(shiftName: shift.name, completedCount: tasks.filter { $0.isCompleted }.count,
              totalCount: tasks.count, pendingTasks: tasks.filter { !$0.isCompleted }.prefix(3).map {
                  .init(id: $0.id, title: $0.title, priority: $0.priorityRaw)
              })
    }

    public static func refresh(using context: ModelContext) async throws {
        let shift = try activeShift(in: context)
        let currentTasks = try tasks(in: context, shiftID: shift?.id)
        WidgetCenter.shared.reloadAllTimelines()
        for activity in Activity<ShiftActivityAttributes>.activities {
            guard let shift = shift, activity.attributes.shiftId == shift.id,
                  activity.attributes.shiftEndTime == shift.endTime else {
                await activity.end(dismissalPolicy: .immediate)
                continue
            }
            await activity.update(ActivityContent(state: state(shift: shift, tasks: currentTasks), staleDate: shift.endTime))
        }
        let inbox = shift == nil ? [] : try tasks(in: context, shiftID: nil)
        try await NotificationScheduler.shared.rebuild(tasks: currentTasks + inbox, shiftEnd: shift?.endTime)
        let now = Date()
        let upcoming = try context.fetch(FetchDescriptor<ShiftConfig>(
            predicate: #Predicate { $0.startTime > now && !$0.isActive }, sortBy: [SortDescriptor(\ShiftConfig.startTime)]))
        try await NotificationScheduler.shared.rebuildShiftStarts(upcoming)
    }
}
