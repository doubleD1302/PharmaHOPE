import Foundation
import UserNotifications

@MainActor
public final class NotificationScheduler {
    public static let shared = NotificationScheduler()
    public static let category = "HOPE_TASK"
    public static let completeAction = "HOPE_COMPLETE"
    public static let snooze10Action = "HOPE_SNOOZE_10"
    public static let snooze15Action = "HOPE_SNOOZE_15"
    private var generation = 0
    private init() {}

    public func registerActions() {
        let actions = [
            UNNotificationAction(identifier: Self.completeAction, title: "Hoàn thành", options: []),
            UNNotificationAction(identifier: Self.snooze10Action, title: "Nhắc sau 10 phút", options: []),
            UNNotificationAction(identifier: Self.snooze15Action, title: "Nhắc sau 15 phút", options: [])
        ]
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: actions, intentIdentifiers: [], options: [])
        ])
    }
    @discardableResult public func requestAuthorization() async -> Bool {
        do { return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { return false }
    }
    public func rebuild(tasks: [TaskItem], shiftEnd: Date?) async throws {
        generation += 1
        let current = generation
        let plan = TaskNotificationPlan.make(tasks: tasks, shiftEnd: shiftEnd)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        guard current == generation else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter(Self.owned))
        let delivered = await center.deliveredNotifications()
        guard current == generation else { return }
        let activeIDs = Set(tasks.filter { !$0.isCompleted && $0.deletedAt == nil && $0.reminderEnabled &&
            ($0.shiftId == nil || shiftEnd.map { $0 > .now } == true) }.map(\.id))
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
            guard Self.owned($0.request.identifier) else { return false }
            if let id = $0.request.content.userInfo["taskID"] as? String { return !activeIDs.contains(id) }
            return true // Summary messages from an earlier state must not linger after refresh.
        }.map { $0.request.identifier })
        for event in plan {
            guard current == generation else { return }
            let content = UNMutableNotificationContent()
            content.title = event.title; content.body = event.body; content.sound = .default
            content.interruptionLevel = .active
            if let taskID = event.taskID {
                content.categoryIdentifier = Self.category
                content.userInfo = ["taskID": taskID]
            }
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.date)
            try await center.add(UNNotificationRequest(identifier: event.id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }
    private static func owned(_ id: String) -> Bool {
        id.hasPrefix("hope.task.") || id.hasPrefix("hope.clockout.") || id.hasPrefix("clockout_alert_") || id.hasPrefix("interval_nagging_alert")
    }
}
