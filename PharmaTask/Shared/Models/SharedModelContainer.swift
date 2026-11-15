import Foundation
import SwiftData

public final class SharedModelContainer {
    public static let appGroupID = "group.com.pharmatask.app"
    public static let databaseFilename = "PharmaTask.sqlite"
    public static var schema: Schema { Schema([TaskItem.self, ShiftConfig.self, RoutineTemplate.self,
                                        MoodCheckIn.self, JournalEntry.self, HealingVisit.self]) }
    
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
            // Không crash và không xoá gì: tệp dữ liệu cũ giữ nguyên trên máy. Tạm dùng kho trong bộ nhớ để app mở được,
            // ContentView báo cho người dùng biết và hướng dẫn cập nhật app hoặc liên hệ.
            SharedModelContainer.startupError = error.localizedDescription
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do { return try ModelContainer(for: schema, configurations: [memory]) }
            catch { fatalError("Không thể khởi tạo cả kho dữ liệu tạm: \(error.localizedDescription)") }
        }
    }()

    /// Có giá trị khi không mở được dữ liệu thật và app đang chạy bằng kho tạm. Chỉ đọc sau khi đã truy cập `shared`.
    public static var startupError: String?

    public static var isRunningOnTemporaryStore: Bool { _ = shared; return startupError != nil }
    
    // Khởi tạo ModelContext nền độc lập (thread-safe)
    @MainActor
    public static func mainContext() -> ModelContext {
        return shared.mainContext
    }
}
