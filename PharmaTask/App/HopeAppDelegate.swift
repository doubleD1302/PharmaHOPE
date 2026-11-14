import UIKit
import UserNotifications
import SwiftData

@MainActor
final class HopeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationScheduler.shared.registerActions()
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["taskID"] as? String
        let action = response.actionIdentifier
        Task { @MainActor in
            defer { completionHandler() }
            guard let id = id else { return }
            let context = SharedModelContainer.shared.mainContext
            do {
                var query = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil })
                query.fetchLimit = 1
                guard let task = try context.fetch(query).first else { return }
                switch action {
                case NotificationScheduler.completeAction:
                    try TaskCommands.complete(task, completed: true, context: context)
                case NotificationScheduler.snooze10Action, NotificationScheduler.snooze15Action:
                    let shiftID = task.shiftId
                    let shift = try context.fetch(FetchDescriptor<ShiftConfig>(predicate: #Predicate { $0.id == shiftID })).first
                    try TaskCommands.snooze(task, minutes: action == NotificationScheduler.snooze10Action ? 10 : 15, shift: shift, context: context)
                default: return
                }
                try await ShiftTaskSync.refresh(using: context)
            } catch {
                context.rollback()
                // Surface action failure on the next foreground visit; never report a false success.
                UserDefaults(suiteName: SharedModelContainer.appGroupID)?.set(error.localizedDescription, forKey: "hope.notificationActionError")
            }
        }
    }
}
