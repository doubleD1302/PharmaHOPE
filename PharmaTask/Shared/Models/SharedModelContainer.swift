import Foundation
import SwiftData

public final class SharedModelContainer {
    public static let appGroupID = "group.com.pharmatask.app"
    public static let databaseFilename = "PharmaTask.sqlite"
    public static var schema: Schema { Schema([TaskItem.self, ShiftConfig.self, RoutineTemplate.self, PendingTaskImport.self]) }
    
    public static let shared: ModelContainer = {
        let schema = SharedModelContainer.schema
        
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        let storeURL: URL
        
        if let containerURL = containerURL {
            storeURL = containerURL.appendingPathComponent(databaseFilename)
        } else {
            // Dự phòng khi chạy trên simulator hoặc môi trường test chưa gắn App Group
            let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            storeURL = documentDir.appendingPathComponent(databaseFilename)
            print("⚠️ Warning: App Group container không khả dụng, sử dụng Document Directory: \(storeURL)")
        }
        
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("CRITICAL: Không thể khởi tạo ModelContainer: \(error.localizedDescription)")
        }
    }()
    
    // Khởi tạo ModelContext nền độc lập (thread-safe)
    @MainActor
    public static func mainContext() -> ModelContext {
        return shared.mainContext
    }
}
