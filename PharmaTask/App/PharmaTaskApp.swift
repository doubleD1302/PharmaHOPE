import SwiftUI
import SwiftData

@main
@MainActor
struct PharmaTaskApp: App {
    @UIApplicationDelegateAdaptor(HopeAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    do {
                        let context = SharedModelContainer.shared.mainContext
                        let defaults = UserDefaults(suiteName: SharedModelContainer.appGroupID)
                        if defaults?.bool(forKey: "hope.taskMetadata.v2") != true {
                            try TaskCommands.prepareLegacyData(in: context)
                            defaults?.set(true, forKey: "hope.taskMetadata.v2")
                        }
                        try RoutineChecklistService.seedIfNeeded(context: context)
                        _ = await NotificationScheduler.shared.requestAuthorization()
                        try await ShiftTaskSync.refresh(using: context)
                    } catch {
                        SharedModelContainer.shared.mainContext.rollback()
                        UserDefaults(suiteName: SharedModelContainer.appGroupID)?.set(error.localizedDescription, forKey: "hope.notificationActionError")
                    }
                }
        }
        .modelContainer(SharedModelContainer.shared)
    }
}
